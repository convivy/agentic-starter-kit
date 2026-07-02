---
id: shared/runbooks/adding-a-doc
kind: runbook
status: active
title: How to add a doc to the knowledge base
audience: shared
---

Every knowledge doc is markdown with flat `key: value` frontmatter. Required keys: `id` (path-like, unique), `kind` (`runbook` | `decision` | `reference` | `agent` | `profile`), `status` (`active` | `draft` | `deprecated`), `title`. Optional: `audience` (`shared`, or a project name).

Steps:

1. Create the file under `knowledge/projects/<audience>/` — shared docs under `projects/shared/`, project docs under `projects/<project>/`.
2. Run `python3 knowledge/scripts/validate.py` to check the schema.
3. If `kb-watch` is running, the index updates within seconds; otherwise run `kb-index`.
4. Verify in any session: `mcp__kb__kb_search` should find it.

Commit the doc to the knowledge repo. Docs are the durable memory your agents share; a fact that lives only in a conversation is lost when the session closes.
