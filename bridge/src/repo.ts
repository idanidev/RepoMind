import { execFileSync } from "node:child_process";

/** Normalises anything that identifies a repo into the canonical `owner/name`. */
export function normalizeRepo(input: string): string {
  const trimmed = input.trim().replace(/\.git$/, "");
  const url = trimmed.match(/github\.com[:/]([^/]+)\/([^/]+)/);
  if (url) return `${url[1]}/${url[2]}`;
  const plain = trimmed.match(/^([\w.-]+)\/([\w.-]+)$/);
  if (plain) return `${plain[1]}/${plain[2]}`;
  throw new Error(
    `"${input}" is not a valid repository. Use the "owner/name" form, for example "idanidev/RepoMind".`
  );
}

function detectFromGit(cwd: string): string | undefined {
  try {
    const remote = execFileSync("git", ["remote", "get-url", "origin"], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return remote ? normalizeRepo(remote) : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Resolves which repository a tool call refers to.
 * Precedence: explicit argument > REPOMIND_REPO env var > `origin` remote of the working directory.
 */
export function resolveRepo(explicit?: string): string {
  if (explicit) return normalizeRepo(explicit);
  if (process.env.REPOMIND_REPO) return normalizeRepo(process.env.REPOMIND_REPO);

  const detected = detectFromGit(process.env.REPOMIND_CWD ?? process.cwd());
  if (detected) return detected;

  throw new Error(
    "Could not work out which repository to use. Pass `repo` explicitly (\"owner/name\"), " +
      "or set REPOMIND_REPO, or run the agent from a directory whose git `origin` points at GitHub."
  );
}
