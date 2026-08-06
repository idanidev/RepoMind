import { parse as parseYaml, stringify as stringifyYaml } from "yaml";
import type { GitHubComment, GitHubIssue } from "./github.js";
import { labelNames } from "./github.js";

export type TaskStatus = "pending" | "in_progress" | "blocked" | "done";
export type TaskPriority = "now" | "next" | "someday";
export type TaskKind = "bug" | "feature" | "refactor" | "chore" | "question";

export interface ThreadEntry {
  author: "user" | "agent";
  text: string;
  createdAt: string;
}

export interface RepoMindTask {
  id: string;
  repo: string;
  branchHint?: string;
  title: string;
  /** The developer's original, unedited words. Source of truth for intent. */
  rawInput: string;
  intent: string;
  acceptanceCriteria: string[];
  priority: TaskPriority;
  kind: TaskKind;
  filesHint?: string[];
  status: TaskStatus;
  thread: ThreadEntry[];
  /** Kanban column the task sits in, when the app is mirroring one. */
  column?: string;
  githubIssueUrl?: string;
  prUrl?: string;
  createdAt: string;
  updatedAt: string;
}

export const LABEL_TASK = "repomind-task";
export const LABEL_IN_PROGRESS = "repomind:in-progress";
export const LABEL_BLOCKED = "repomind:blocked";
/** Appended to comments we write, so we can tell agent notes from the developer's replies. */
export const AGENT_MARKER = "<!--repomind:agent-->";

const META_OPEN = "<!--repomind:v1";
const META_CLOSE = "-->";
/** Marker the iOS app already writes today. */
const LEGACY_MARKER = /<!--\s*repomind-task:([0-9A-Fa-f-]+)\s*-->/;

export interface TaskMeta {
  taskId?: string;
  rawInput?: string;
  intent?: string;
  acceptanceCriteria?: string[];
  priority?: TaskPriority;
  kind?: TaskKind;
  filesHint?: string[];
  branchHint?: string;
  prUrl?: string;
}

/** Splits an issue body into its structured metadata and the human-readable part. */
export function extractMeta(body: string): { meta: TaskMeta; humanBody: string } {
  const start = body.indexOf(META_OPEN);
  const end = start === -1 ? -1 : body.indexOf(META_CLOSE, start);

  if (start === -1 || end === -1) {
    return { meta: {}, humanBody: body.replace(LEGACY_MARKER, "").trim() };
  }

  let meta: TaskMeta = {};
  try {
    meta = (parseYaml(body.slice(start + META_OPEN.length, end)) ?? {}) as TaskMeta;
  } catch {
    // A malformed block should degrade to "no metadata", never break the whole task.
    meta = {};
  }

  const humanBody = body.slice(0, start) + body.slice(end + META_CLOSE.length);
  return { meta, humanBody: humanBody.replace(LEGACY_MARKER, "").trim() };
}

export function serializeMeta(meta: TaskMeta): string {
  const clean = Object.fromEntries(
    Object.entries(meta).filter(([, v]) => v !== undefined && v !== null && v !== "")
  );
  return `${META_OPEN}\n${stringifyYaml(clean).trimEnd()}\n${META_CLOSE}`;
}

/** Replaces the metadata block in a body, appending it if not present. */
export function upsertMeta(body: string, patch: TaskMeta): string {
  const { meta, humanBody } = extractMeta(body);
  return `${humanBody}\n\n${serializeMeta({ ...meta, ...patch })}`.trim();
}

function statusFrom(issue: GitHubIssue, labels: string[]): TaskStatus {
  if (issue.state === "closed") return "done";
  if (labels.includes(LABEL_BLOCKED)) return "blocked";
  if (labels.includes(LABEL_IN_PROGRESS)) return "in_progress";
  return "pending";
}

/** Falls back to the severity labels the app already uses when no metadata block exists. */
function kindFrom(meta: TaskMeta, labels: string[]): TaskKind {
  if (meta.kind) return meta.kind;
  if (labels.some((l) => l.startsWith("bug:"))) return "bug";
  if (labels.includes("enhancement")) return "feature";
  return "chore";
}

function priorityFrom(meta: TaskMeta, labels: string[]): TaskPriority {
  if (meta.priority) return meta.priority;
  if (labels.includes("bug:critical")) return "now";
  return "next";
}

function columnFrom(labels: string[]): string | undefined {
  const col = labels.find((l) => l.startsWith("col:"));
  return col?.slice("col:".length);
}

function threadFrom(comments: GitHubComment[]): ThreadEntry[] {
  return comments.map((c) => {
    const text = (c.body ?? "").replace(AGENT_MARKER, "").trim();
    return {
      author: (c.body ?? "").includes(AGENT_MARKER) ? "agent" : "user",
      text,
      createdAt: c.created_at,
    };
  });
}

/**
 * Builds a task from an issue.
 *
 * Issues written before the enriched format exists carry no metadata block. In that case
 * the whole body is treated as `rawInput` — it is literally what the developer dictated —
 * and the richer fields degrade to sensible defaults rather than being fabricated.
 */
export function issueToTask(
  issue: GitHubIssue,
  repo: string,
  comments: GitHubComment[] = []
): RepoMindTask {
  const labels = labelNames(issue);
  const { meta, humanBody } = extractMeta(issue.body ?? "");

  return {
    id: String(issue.number),
    repo,
    branchHint: meta.branchHint,
    title: issue.title,
    rawInput: meta.rawInput?.trim() || humanBody || issue.title,
    intent: meta.intent?.trim() || "",
    acceptanceCriteria: meta.acceptanceCriteria ?? [],
    priority: priorityFrom(meta, labels),
    kind: kindFrom(meta, labels),
    filesHint: meta.filesHint,
    status: statusFrom(issue, labels),
    thread: threadFrom(comments),
    column: columnFrom(labels),
    githubIssueUrl: issue.html_url,
    prUrl: meta.prUrl,
    createdAt: issue.created_at,
    updatedAt: issue.updated_at,
  };
}

/** Compact shape returned by list_tasks, to keep the agent's context small. */
export function toSummary(task: RepoMindTask) {
  return {
    id: task.id,
    title: task.title,
    status: task.status,
    priority: task.priority,
    kind: task.kind,
    column: task.column,
    updatedAt: task.updatedAt,
    hasEnrichedContext: task.intent !== "" || task.acceptanceCriteria.length > 0,
  };
}
