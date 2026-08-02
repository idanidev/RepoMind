---
description: Show the tasks captured in RepoMind for this repo and offer to start one
---

Call the `list_tasks` tool from the `repomind` MCP server for this repository.

Present the result as a short list the developer can scan — id, priority, title — with
anything `blocked` or `in_progress` called out first. Do not dump the raw JSON.

Then offer to start the highest-priority pending one. If they agree, call `start_task`
(not `get_task`) so it is marked as picked up on their phone, and treat the returned
`rawInput` as the specification: it is what they actually dictated, and it outranks the
tidied-up title.
