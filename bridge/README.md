# RepoMind Bridge

An MCP server that gives coding agents access to the tasks you capture in RepoMind —
including the words you actually dictated, not just a tidy title.

Tasks travel as **GitHub issues** labelled `repomind-task`, which the iOS app already
creates. There is no server to deploy and nothing to pay for: GitHub is the postbox.

```
phone (dictate) ──> RepoMind ──> GitHub issue ──> this bridge ──> your agent
```

## Install

**1. Build it**

```bash
npm --prefix bridge install
npm --prefix bridge run build
```

**2. Give it a GitHub token**

A classic token with `repo` scope, from https://github.com/settings/tokens

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx   # add to ~/.zshrc to make it stick
```

**3. Point your agent at it**

Claude Code picks up `.mcp.json` in this repo automatically — nothing to do.
For other agents, register the server as:

```json
{
  "command": "node",
  "args": ["bridge/dist/index.js"],
  "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" }
}
```

## Tools

| Tool | When the agent should reach for it |
|---|---|
| `list_tasks` | Start of a session, to find out what you already asked for |
| `get_task` | Read one task in full, including `rawInput` and the thread |
| `start_task` | Beginning work — marks it picked up on your phone and returns full context |
| `add_note` | A decision or finding worth pushing to your phone |
| `ask_user` | Genuinely blocked; marks the task blocked and asks one question |
| `complete_task` | Work finished and verified; closes the issue, attaches the PR |

Repository is resolved from the `repo` argument, else `REPOMIND_REPO`, else the `origin`
remote of the working directory.

## Session start

`bridge/dist/brief.js` prints a short briefing and is wired as a `SessionStart` hook in
`.claude/settings.json`. It stays silent when there is no token, no network or no tasks,
so it can never get in the way of starting work.

Run `/repomind` to ask for the same thing on demand.

## Task format

The agent-facing fields live in a block inside the issue body — invisible on GitHub, easy
to parse:

```markdown
Refresh the GitHub token when it expires

<!--repomind:v1
rawInput: |
  en RepoMind el login peta cuando el token de GitHub expira,
  hay que refrescarlo automáticamente
intent: The user should never see the error screen
acceptanceCriteria:
  - No error screen when the token expires
priority: now
kind: bug
filesHint: [RepoMind/GitHubService.swift]
-->
```

Issues **without** that block still work: the whole body is taken as `rawInput` and the
richer fields fall back to defaults derived from the labels, rather than being invented.

`status` maps to `repomind:in-progress` / `repomind:blocked` labels plus the issue's
open/closed state. The `thread` is the issue's comments; the ones the agent writes carry a
hidden marker so replies can be told apart from notes.

## Tests

```bash
npm --prefix bridge test
```
