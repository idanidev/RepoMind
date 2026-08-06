import { execFileSync } from "node:child_process";

let cached: string | null | undefined;

/**
 * Resolves a GitHub token.
 *
 * Prefers `GITHUB_TOKEN`, but falls back to the GitHub CLI's own credentials so the token never
 * has to be written into an MCP config file in plain text — the machine is already authenticated
 * for `gh`, and that store is a safer place for it to live.
 *
 * Returns null when neither is available; callers decide whether that is fatal.
 */
export function resolveToken(): string | null {
  if (cached !== undefined) return cached;

  const fromEnv = process.env.GITHUB_TOKEN?.trim();
  if (fromEnv) {
    cached = fromEnv;
    return cached;
  }

  try {
    const fromCli = execFileSync("gh", ["auth", "token"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    cached = fromCli || null;
  } catch {
    cached = null;
  }
  return cached;
}

export function requireToken(): string {
  const token = resolveToken();
  if (!token) {
    throw new Error(
      "No GitHub token available. Either set GITHUB_TOKEN, or sign in once with `gh auth login` " +
        "and this server will use those credentials."
    );
  }
  return token;
}
