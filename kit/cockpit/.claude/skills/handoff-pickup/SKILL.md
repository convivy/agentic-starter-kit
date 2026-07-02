---
name: handoff-pickup
description: The operator invokes /handoff-pickup at the start of a fresh session to resume a prior session's work; pairs with /handoff-leave. `co -r` runs it automatically.
---

# /handoff-pickup — resume from the most recent handoff

1. Determine the context name: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.
2. Find the newest handoff for this context from the last 48 hours:
   `ls -t $AGENTIC_ROOT/agent-runs/*/co-<context>-*/handoff.md 2>/dev/null | head -5` (default root `~/agentic`), filtering by the date directory.
3. **Found:** read it and surface a brief structured ack — State / In-flight / Recommended next move — with the handoff's full path. Then act on the recommended next move unless the operator redirects. Do not re-litigate the prior session's decisions.
4. **Not found:** say plainly "No handoff found for `<context>` in the last 48 hours. Starting fresh — what would you like to do?" Do not search older history or other contexts unasked.

The world may have moved while the prior session was closed — if the handoff references an in-flight artifact (a PR, a running job), check its current state before proceeding. The handoff is the last-known state, not the current reality. Leave the handoff file in place; it is an audit trail.
