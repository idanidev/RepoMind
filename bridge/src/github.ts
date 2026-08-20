import { invalidateToken } from "./token.js";

const API = "https://api.github.com";

export class GitHubError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly hint?: string
  ) {
    super(hint ? `${message}\n\n${hint}` : message);
    this.name = "GitHubError";
  }
}

export interface GitHubIssue {
  number: number;
  title: string;
  body: string | null;
  state: "open" | "closed";
  html_url: string;
  labels: Array<{ name: string } | string>;
  created_at: string;
  updated_at: string;
  /** Present when the "issue" is actually a pull request — those are filtered out. */
  pull_request?: unknown;
}

export interface GitHubComment {
  id: number;
  body: string | null;
  created_at: string;
  user: { login: string } | null;
}

export function labelNames(issue: GitHubIssue): string[] {
  return issue.labels.map((l) => (typeof l === "string" ? l : l.name));
}

/**
 * Minimal GitHub REST client.
 *
 * Rate limiting is deliberately simple: this server is single-user and local, so the
 * only realistic risk is a runaway loop hammering the API. We serialise requests with a
 * small floor between them and surface GitHub's own limit headers when we do get throttled.
 */
export class GitHubClient {
  private queue: Promise<unknown> = Promise.resolve();
  private static readonly MIN_INTERVAL_MS = 80;
  private lastRequestAt = 0;

  private readonly resolve: () => string | null;

  /**
   * Takes a token *provider*, not a token.
   *
   * It used to capture one string at startup and keep it for the life of the process. An MCP
   * server runs for days, `gh` rotates its OAuth token underneath it, and from that moment every
   * call 401'd with no way back short of restarting the server.
   */
  constructor(token: string | (() => string | null)) {
    this.resolve = typeof token === "function" ? token : () => token;
    if (!this.resolve()) {
      throw new Error(
        "Missing GitHub token. Set GITHUB_TOKEN in the MCP server config to a token with `repo` scope."
      );
    }
  }

  private async throttle(): Promise<void> {
    const elapsed = Date.now() - this.lastRequestAt;
    const wait = GitHubClient.MIN_INTERVAL_MS - elapsed;
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    this.lastRequestAt = Date.now();
  }

  private request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const attempt = async (): Promise<Response> => {
      await this.throttle();
      return fetch(`${API}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${this.resolve() ?? ""}`,
          Accept: "application/vnd.github+json",
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": "repomind-bridge",
          ...(body ? { "Content-Type": "application/json" } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      });
    };

    const run = async (): Promise<T> => {
      let res = await attempt();

      // One retry on 401 with a freshly resolved token. The stale-cache case is the common one,
      // and it is indistinguishable from a genuinely revoked token until you try again.
      if (res.status === 401) {
        invalidateToken();
        if (this.resolve()) res = await attempt();
      }

      if (!res.ok) throw await this.toError(res, method, path);
      if (res.status === 204) return undefined as T;
      return (await res.json()) as T;
    };

    // Chain onto the queue so requests never overlap, but don't let one failure
    // poison the chain for subsequent calls.
    const result = this.queue.then(run, run);
    this.queue = result.catch(() => undefined);
    return result;
  }

  private async toError(res: Response, method: string, path: string): Promise<GitHubError> {
    const text = await res.text().catch(() => "");
    const target = `${method} ${path}`;

    if (res.status === 401) {
      return new GitHubError(
        `GitHub rejected the token (401) on ${target}.`,
        401,
        "The token is invalid or expired. Generate a new one at https://github.com/settings/tokens with `repo` scope and update GITHUB_TOKEN."
      );
    }
    if (res.status === 404) {
      return new GitHubError(
        `Not found (404) on ${target}.`,
        404,
        "Either the repository/issue does not exist or the token cannot see it. Private repos need the `repo` scope."
      );
    }
    const remaining = res.headers.get("x-ratelimit-remaining");
    if ((res.status === 403 || res.status === 429) && remaining === "0") {
      const reset = Number(res.headers.get("x-ratelimit-reset") ?? 0) * 1000;
      const mins = reset ? Math.max(1, Math.ceil((reset - Date.now()) / 60000)) : undefined;
      return new GitHubError(
        `GitHub rate limit exhausted on ${target}.`,
        res.status,
        mins ? `Retry in about ${mins} minute(s).` : "Retry shortly."
      );
    }
    if (res.status === 403) {
      return new GitHubError(
        `Forbidden (403) on ${target}.`,
        403,
        "The token lacks permission to write here. Check it has `repo` scope and that the repository is not archived."
      );
    }
    return new GitHubError(`GitHub returned ${res.status} on ${target}. ${text.slice(0, 300)}`, res.status);
  }

  async listIssues(
    repo: string,
    opts: { labels?: string[]; state?: "open" | "closed" | "all"; perPage?: number } = {}
  ): Promise<GitHubIssue[]> {
    const params = new URLSearchParams({
      state: opts.state ?? "open",
      per_page: String(opts.perPage ?? 100),
      sort: "updated",
      direction: "desc",
    });
    if (opts.labels?.length) params.set("labels", opts.labels.join(","));
    const issues = await this.request<GitHubIssue[]>("GET", `/repos/${repo}/issues?${params}`);
    return issues.filter((i) => !i.pull_request);
  }

  getIssue(repo: string, number: number): Promise<GitHubIssue> {
    return this.request<GitHubIssue>("GET", `/repos/${repo}/issues/${number}`);
  }

  listComments(repo: string, number: number): Promise<GitHubComment[]> {
    return this.request<GitHubComment[]>("GET", `/repos/${repo}/issues/${number}/comments?per_page=100`);
  }

  createComment(repo: string, number: number, body: string): Promise<GitHubComment> {
    return this.request<GitHubComment>("POST", `/repos/${repo}/issues/${number}/comments`, { body });
  }

  updateIssue(
    repo: string,
    number: number,
    patch: { state?: "open" | "closed"; state_reason?: string; body?: string; title?: string }
  ): Promise<GitHubIssue> {
    return this.request<GitHubIssue>("PATCH", `/repos/${repo}/issues/${number}`, patch);
  }

  addLabels(repo: string, number: number, labels: string[]): Promise<unknown> {
    return this.request("POST", `/repos/${repo}/issues/${number}/labels`, { labels });
  }

  async removeLabel(repo: string, number: number, label: string): Promise<void> {
    try {
      await this.request("DELETE", `/repos/${repo}/issues/${number}/labels/${encodeURIComponent(label)}`);
    } catch (err) {
      // Removing a label that isn't there is not a failure worth surfacing.
      if (err instanceof GitHubError && err.status === 404) return;
      throw err;
    }
  }
}
