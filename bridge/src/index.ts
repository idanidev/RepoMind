#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readTaskImage, storeIsAvailable, taskHasImage, taskUUIDFromBody } from "./attachments.js";
import { GitHubClient } from "./github.js";
import { resolveRepo } from "./repo.js";
import { requireToken } from "./token.js";
import {
  AGENT_MARKER,
  LABEL_BLOCKED,
  LABEL_IN_PROGRESS,
  LABEL_TASK,
  issueToTask,
  toSummary,
  upsertMeta,
  type RepoMindTask,
  type TaskStatus,
} from "./task.js";

const github = new GitHubClient(requireToken());
const server = new McpServer({ name: "repomind-bridge", version: "0.1.0" });

const ok = (payload: unknown) => ({
  content: [{ type: "text" as const, text: JSON.stringify(payload, null, 2) }],
});

/** Never let an exception escape as an opaque failure — the agent should be able to act on it. */
async function guard<T>(fn: () => Promise<T>) {
  try {
    return (await fn()) as ReturnType<typeof ok>;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      isError: true as const,
      content: [{ type: "text" as const, text: message }],
    };
  }
}

async function loadTask(repo: string, id: number, withThread: boolean) {
  const issue = await github.getIssue(repo, id);
  const comments = withThread ? await github.listComments(repo, id) : [];
  const task: RepoMindTask = issueToTask(issue, repo, comments);

  // Screenshots never leave the machine, so their existence has to be reported separately —
  // there is nothing in the issue itself to reveal it.
  const taskUUID = taskUUIDFromBody(issue.body);
  const hasScreenshot = taskUUID ? taskHasImage(taskUUID) : false;
  return { ...task, hasScreenshot };
}

const repoArg = z
  .string()
  .optional()
  .describe('Repository as "owner/name". Omit to use the repo of the current working directory.');

const taskIdArg = z.string().describe("Task id, as returned by list_tasks (the GitHub issue number).");

// ---------------------------------------------------------------------------

server.registerTool(
  "list_tasks",
  {
    title: "List RepoMind tasks",
    description:
      "Lists the developer's captured tasks for a repository. These are their own notes — usually " +
      "dictated by voice from their phone away from the keyboard — not generic GitHub issues.\n\n" +
      "Call this at the start of a working session, before asking the developer what to do: they " +
      "have probably already told you. Returns a compact summary only; use start_task to get the " +
      "full context of the one you are about to work on.",
    inputSchema: {
      repo: repoArg,
      status: z
        .enum(["pending", "in_progress", "blocked", "done", "all"])
        .optional()
        .describe("Filter by status. Defaults to everything still open (pending, in_progress, blocked)."),
    },
  },
  async ({ repo, status }) =>
    guard(async () => {
      const target = resolveRepo(repo);
      const wantsClosed = status === "done" || status === "all";
      const issues = await github.listIssues(target, {
        labels: [LABEL_TASK],
        state: wantsClosed ? (status === "done" ? "closed" : "all") : "open",
      });

      let tasks = issues.map((i) => issueToTask(i, target));
      if (status && status !== "all") tasks = tasks.filter((t) => t.status === status);

      const order: Record<string, number> = { now: 0, next: 1, someday: 2 };
      tasks.sort((a, b) => order[a.priority] - order[b.priority]);

      return ok({ repo: target, count: tasks.length, tasks: tasks.map(toSummary) });
    })
);

server.registerTool(
  "get_task",
  {
    title: "Get full task context",
    description:
      "Returns one task in full, including `rawInput` and the conversation thread.\n\n" +
      "`rawInput` is the developer's original, unedited words and is the source of truth for what " +
      "they want. The `title` is a cleaned-up label — when the two seem to disagree, trust " +
      "`rawInput`. Read this before implementing anything, and prefer start_task if you are " +
      "actually about to begin work.",
    inputSchema: { repo: repoArg, id: taskIdArg },
  },
  async ({ repo, id }) =>
    guard(async () => ok(await loadTask(resolveRepo(repo), Number(id), true)))
);

server.registerTool(
  "start_task",
  {
    title: "Start working on a task",
    description:
      "Marks a task as in_progress and returns its full context in a single call.\n\n" +
      "Use this instead of get_task when you are actually beginning the work: it lets the developer " +
      "see on their phone that you picked the task up. Read the returned `rawInput` carefully — it " +
      "is what they actually said, and outranks the tidied-up title.",
    inputSchema: { repo: repoArg, id: taskIdArg },
  },
  async ({ repo, id }) =>
    guard(async () => {
      const target = resolveRepo(repo);
      const number = Number(id);
      await github.addLabels(target, number, [LABEL_IN_PROGRESS]);
      await github.removeLabel(target, number, LABEL_BLOCKED);
      return ok(await loadTask(target, number, true));
    })
);

server.registerTool(
  "add_note",
  {
    title: "Post a note to the task thread",
    description:
      "Writes a note into the task's thread, which reaches the developer on their phone.\n\n" +
      "Use it for things worth interrupting someone for: a decision you had to make, something " +
      "surprising you found, or a summary when you finish a chunk of work. Do not narrate every " +
      "step — a stream of notifications is worse than none. If you need an answer before you can " +
      "continue, use ask_user instead.",
    inputSchema: {
      repo: repoArg,
      id: taskIdArg,
      note: z.string().min(1).describe("The note, in the developer's language. Plain prose beats bullet soup."),
    },
  },
  async ({ repo, id, note }) =>
    guard(async () => {
      const target = resolveRepo(repo);
      await github.createComment(target, Number(id), `${note}\n\n${AGENT_MARKER}`);
      return ok({ posted: true, repo: target, id });
    })
);

server.registerTool(
  "ask_user",
  {
    title: "Ask the developer a question",
    description:
      "Marks the task as blocked and sends a question to the developer's phone.\n\n" +
      "Only use this when you genuinely cannot proceed: you have already checked the code and " +
      "`rawInput`, and the answer is a judgement call only they can make. Ask one specific question, " +
      "and say what you would do by default if they don't reply.\n\n" +
      "After calling this, do not wait — move on to another task, or stop cleanly.",
    inputSchema: {
      repo: repoArg,
      id: taskIdArg,
      question: z
        .string()
        .min(1)
        .describe("One specific question, plus the default you'll assume if they don't answer."),
    },
  },
  async ({ repo, id, question }) =>
    guard(async () => {
      const target = resolveRepo(repo);
      const number = Number(id);
      await github.createComment(target, number, `${question}\n\n${AGENT_MARKER}`);
      await github.addLabels(target, number, [LABEL_BLOCKED]);
      await github.removeLabel(target, number, LABEL_IN_PROGRESS);
      return ok({ asked: true, repo: target, id, status: "blocked" as TaskStatus });
    })
);

server.registerTool(
  "complete_task",
  {
    title: "Mark a task done",
    description:
      "Marks the task done and closes its GitHub issue.\n\n" +
      "Only call this once the work is actually finished and verified — the developer treats a " +
      "closed task as done and will not look at it again. Attach `prUrl` if you opened a pull " +
      "request, and use `summary` to say what you changed.",
    inputSchema: {
      repo: repoArg,
      id: taskIdArg,
      summary: z.string().optional().describe("Short note on what you did. Posted to the thread."),
      prUrl: z.string().url().optional().describe("Pull request URL, if there is one."),
    },
  },
  async ({ repo, id, summary, prUrl }) =>
    guard(async () => {
      const target = resolveRepo(repo);
      const number = Number(id);

      if (summary || prUrl) {
        const parts = [summary, prUrl ? `PR: ${prUrl}` : undefined].filter(Boolean);
        await github.createComment(target, number, `${parts.join("\n\n")}\n\n${AGENT_MARKER}`);
      }
      if (prUrl) {
        const issue = await github.getIssue(target, number);
        await github.updateIssue(target, number, { body: upsertMeta(issue.body ?? "", { prUrl }) });
      }

      await github.removeLabel(target, number, LABEL_IN_PROGRESS);
      await github.removeLabel(target, number, LABEL_BLOCKED);
      await github.updateIssue(target, number, { state: "closed", state_reason: "completed" });

      return ok({ completed: true, repo: target, id, prUrl });
    })
);

server.registerTool(
  "get_task_image",
  {
    title: "View the screenshot attached to a task",
    description:
      "Returns the screenshot the developer attached when they captured the task, as an image " +
      "you can actually look at.\n\n" +
      "`get_task` and `start_task` report `hasScreenshot` — whenever that is true, fetch the " +
      "image before deciding what the bug is. A screenshot of the broken screen usually settles " +
      "in one look what a written description leaves ambiguous.\n\n" +
      "The image is read from the RepoMind app's local database on this machine; it is never " +
      "uploaded to GitHub, so it is only available where the Mac app is installed and synced.",
    inputSchema: { repo: repoArg, id: taskIdArg },
  },
  async ({ repo, id }) =>
    guard(async () => {
      const target = resolveRepo(repo);
      const issue = await github.getIssue(target, Number(id));
      const taskUUID = taskUUIDFromBody(issue.body);

      if (!taskUUID) {
        throw new Error(
          `Issue #${id} carries no RepoMind task marker, so it has no attachment to look up. ` +
            "Only issues created by the app do."
        );
      }
      if (!storeIsAvailable()) {
        throw new Error(
          "The RepoMind local database is not on this machine, so attachments cannot be read here. " +
            "Screenshots stay on device by design — run this from the Mac that has the app installed."
        );
      }

      const image = readTaskImage(taskUUID);
      if (!image) {
        throw new Error(`Task ${taskUUID} has no screenshot attached.`);
      }

      return {
        content: [
          {
            type: "image" as const,
            data: image.base64,
            mimeType: image.mimeType,
          },
        ],
      };
    })
);

// ---------------------------------------------------------------------------

const transport = new StdioServerTransport();
await server.connect(transport);
