import { describe, expect, it } from "vitest";
import type { GitHubComment, GitHubIssue } from "../src/github.js";
import { extractMeta, issueToTask, serializeMeta, toSummary, upsertMeta } from "../src/task.js";
import { normalizeRepo } from "../src/repo.js";

function issue(overrides: Partial<GitHubIssue> = {}): GitHubIssue {
  return {
    number: 42,
    title: "Refrescar el token al expirar",
    body: "El login peta cuando el token de GitHub expira.",
    state: "open",
    html_url: "https://github.com/idanidev/RepoMind/issues/42",
    labels: [{ name: "repomind-task" }],
    created_at: "2026-07-01T10:00:00Z",
    updated_at: "2026-07-02T10:00:00Z",
    ...overrides,
  };
}

describe("issues written by the app today (no metadata block)", () => {
  it("treats the whole body as rawInput rather than inventing structure", () => {
    const task = issueToTask(issue(), "idanidev/RepoMind");
    expect(task.rawInput).toBe("El login peta cuando el token de GitHub expira.");
    expect(task.intent).toBe("");
    expect(task.acceptanceCriteria).toEqual([]);
  });

  it("strips the marker the iOS app appends", () => {
    const task = issueToTask(
      issue({ body: "Arreglar el login\n\n<!-- repomind-task:4F2A1C3D-0000-0000-0000-000000000001 -->" }),
      "idanidev/RepoMind"
    );
    expect(task.rawInput).toBe("Arreglar el login");
  });

  it("falls back to the title when the body is empty", () => {
    expect(issueToTask(issue({ body: null }), "r/x").rawInput).toBe("Refrescar el token al expirar");
  });

  it("derives kind and priority from the severity labels already in use", () => {
    const critical = issueToTask(
      issue({ labels: [{ name: "repomind-task" }, { name: "bug:critical" }] }),
      "r/x"
    );
    expect(critical.kind).toBe("bug");
    expect(critical.priority).toBe("now");

    const feature = issueToTask(
      issue({ labels: [{ name: "repomind-task" }, { name: "enhancement" }] }),
      "r/x"
    );
    expect(feature.kind).toBe("feature");
    expect(feature.priority).toBe("next");
  });
});

describe("status", () => {
  it("maps closed issues to done", () => {
    expect(issueToTask(issue({ state: "closed" }), "r/x").status).toBe("done");
  });

  it("reads in_progress and blocked from labels, with blocked winning", () => {
    const inProgress = issue({ labels: [{ name: "repomind:in-progress" }] });
    expect(issueToTask(inProgress, "r/x").status).toBe("in_progress");

    const both = issue({ labels: [{ name: "repomind:in-progress" }, { name: "repomind:blocked" }] });
    expect(issueToTask(both, "r/x").status).toBe("blocked");
  });

  it("defaults to pending", () => {
    expect(issueToTask(issue(), "r/x").status).toBe("pending");
  });

  it("exposes the Kanban column when the app mirrors one", () => {
    const withColumn = issue({ labels: [{ name: "repomind-task" }, { name: "col:pendiente" }] });
    expect(issueToTask(withColumn, "r/x").column).toBe("pendiente");
  });
});

describe("metadata block", () => {
  const body = `Refrescar el token

**Intención**
Que no salte la pantalla de error.

<!--repomind:v1
taskId: 4F2A
rawInput: |
  en RepoMind el login peta cuando el token de GitHub expira,
  hay que refrescarlo automáticamente
intent: Que el usuario no vea la pantalla de error
acceptanceCriteria:
  - No aparece pantalla de error al expirar
  - Se reintenta en silencio
priority: now
kind: bug
filesHint:
  - RepoMind/GitHubService.swift
branchHint: fix/token-refresh
-->`;

  it("parses the structured fields", () => {
    const task = issueToTask(issue({ body }), "idanidev/RepoMind");
    expect(task.rawInput).toContain("hay que refrescarlo automáticamente");
    expect(task.intent).toBe("Que el usuario no vea la pantalla de error");
    expect(task.acceptanceCriteria).toHaveLength(2);
    expect(task.priority).toBe("now");
    expect(task.kind).toBe("bug");
    expect(task.filesHint).toEqual(["RepoMind/GitHubService.swift"]);
    expect(task.branchHint).toBe("fix/token-refresh");
  });

  it("keeps the block out of the human-readable part", () => {
    const { humanBody } = extractMeta(body);
    expect(humanBody).not.toContain("repomind:v1");
    expect(humanBody).toContain("**Intención**");
  });

  it("degrades to no metadata when the block is malformed instead of throwing", () => {
    const broken = "Texto\n\n<!--repomind:v1\n  : : not yaml : :\n -->";
    expect(() => extractMeta(broken)).not.toThrow();
    expect(extractMeta(broken).meta).toEqual({});
  });

  it("round-trips through upsertMeta and preserves existing values", () => {
    const updated = upsertMeta(body, { prUrl: "https://github.com/idanidev/RepoMind/pull/7" });
    const task = issueToTask(issue({ body: updated }), "r/x");
    expect(task.prUrl).toBe("https://github.com/idanidev/RepoMind/pull/7");
    expect(task.kind).toBe("bug");
    expect(task.rawInput).toContain("hay que refrescarlo");
  });

  it("omits empty values when serialising", () => {
    expect(serializeMeta({ kind: "bug", intent: undefined, branchHint: "" })).not.toContain("branchHint");
  });
});

describe("thread", () => {
  const comment = (body: string, id = 1): GitHubComment => ({
    id,
    body,
    created_at: "2026-07-02T11:00:00Z",
    user: { login: "idanidev" },
  });

  it("distinguishes agent notes from the developer's replies", () => {
    const task = issueToTask(issue(), "r/x", [
      comment("Empiezo por el refresh silencioso.\n\n<!--repomind:agent-->", 1),
      comment("Vale, pero no cierres sesión si falla.", 2),
    ]);
    expect(task.thread[0]).toMatchObject({ author: "agent", text: "Empiezo por el refresh silencioso." });
    expect(task.thread[1]).toMatchObject({ author: "user" });
  });
});

describe("summary", () => {
  it("stays compact and flags whether enriched context exists", () => {
    const bare = toSummary(issueToTask(issue(), "r/x"));
    expect(bare.hasEnrichedContext).toBe(false);
    expect(Object.keys(bare)).not.toContain("rawInput");
    expect(Object.keys(bare)).not.toContain("thread");
  });
});

describe("repo normalisation", () => {
  it("accepts the shapes a git remote can take", () => {
    expect(normalizeRepo("idanidev/RepoMind")).toBe("idanidev/RepoMind");
    expect(normalizeRepo("git@github.com:idanidev/RepoMind.git")).toBe("idanidev/RepoMind");
    expect(normalizeRepo("https://github.com/idanidev/RepoMind")).toBe("idanidev/RepoMind");
  });

  it("rejects nonsense with a message that says what to do", () => {
    expect(() => normalizeRepo("nope")).toThrow(/owner\/name/);
  });
});
