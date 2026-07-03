---
name: handoff-leave
description: The operator invokes /handoff-leave when ending a session that has work in flight or context worth preserving; writes a dated handoff doc the next session resumes from.
---

# /handoff-leave — save this session's state before exit

Write a handoff so the next session picks up cleanly. Steps:

1. Determine the context name: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.
2. Create `$AGENTIC_ROOT/agent-runs/$(date +%F)/co-<context>-$(date +%H%M)/` (default root `~/agentic`) and write `handoff.md` in it with these sections:
   - **State summary** — one paragraph: where things stand right now.
   - **In-flight items** — bullets, each with enough detail to resume without this conversation.
   - **Decisions made this session** — what was decided and why, briefly.
   - **Open questions / blockers** — anything waiting on the operator or the world.
   - **Recommended next move** — a verbatim instruction the next session can act on.
3. Tell the operator the full absolute path where it landed.

The handoff is an audit trail. Never delete or rewrite an old one; a new break point gets a new directory.
