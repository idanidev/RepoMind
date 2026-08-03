#!/usr/bin/env node
/**
 * Prints a short briefing of pending RepoMind tasks, for SessionStart hooks.
 *
 * Deliberately fails silently: a missing token, no network or no tasks should never
 * interrupt or delay the start of a coding session.
 */
import { GitHubClient } from "./github.js";
import { resolveRepo } from "./repo.js";
import { LABEL_TASK, issueToTask } from "./task.js";
import { resolveToken } from "./token.js";

const PRIORITY_ORDER: Record<string, number> = { now: 0, next: 1, someday: 2 };
const MAX_LISTED = 5;

async function main(): Promise<void> {
  const token = resolveToken();
  if (!token) return;

  const repo = resolveRepo();
  const issues = await new GitHubClient(token).listIssues(repo, {
    labels: [LABEL_TASK],
    state: "open",
  });
  if (issues.length === 0) return;

  const tasks = issues
    .map((i) => issueToTask(i, repo))
    .sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]);

  const lines = [`RepoMind — ${tasks.length} task(s) captured by the developer in ${repo}:`];
  for (const t of tasks.slice(0, MAX_LISTED)) {
    const flag = t.status === "blocked" ? " BLOCKED" : t.status === "in_progress" ? " in progress" : "";
    const title = t.title.length > 90 ? `${t.title.slice(0, 89)}…` : t.title;
    lines.push(`  #${t.id} [${t.priority}]${flag} ${title}`);
  }
  if (tasks.length > MAX_LISTED) lines.push(`  …and ${tasks.length - MAX_LISTED} more.`);

  const next = tasks.find((t) => t.status === "pending" && t.priority === "now") ?? tasks[0];
  lines.push(
    `Mention these to the developer before asking what to work on. ` +
      `Call start_task with id ${next.id} to begin — it returns their original words (rawInput), which is the real spec.`
  );

  console.log(lines.join("\n"));
}

main().catch(() => process.exit(0));
