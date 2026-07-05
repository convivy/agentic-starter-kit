> **What this is.** The spec-driven path: hand this whole document to a fresh Claude Code session on an empty machine (`claude` in an empty directory, then "read docs/llm-bootstrap.md and follow it") and it builds the system from scratch — confirming the choices that are yours to make, then becoming the system's steward. If you used `install.sh`, you don't need to run this; it's here because watching it happen is the fastest way to understand both the system and what you can reasonably ask a session to do. The kit's prebuilt files differ from this spec in small deliberate ways (the index lives at `<root>/.index/`, the watcher is a zero-dependency poller, `co` never auto-starts tmux); where they differ, the kit's files are the maintained version.

# Bootstrapping an agentic substrate on this VM

**Read this fully before you touch anything.** You are the first Claude Code session on a fresh
machine, and your job is to stand up a small, durable agentic system here, then *become its
steward*. This document is the spec and the build order. Work top to bottom. Stop at the points
marked **CONFIRM** and ask the human (referred to here as "the operator") before proceeding.

The design mirrors a working setup the operator runs elsewhere. You are building the distilled
core, not a 1:1 clone of years of accreted machinery. Build the foundation that makes the
ergonomics good and the knowledge durable; add the heavier layers later, only when a real,
repeated pain demonstrates the need. That restraint is part of the design, not a shortcut.

---

## 0. The mental model

The "substrate" is everything the work is built *from*, as opposed to the work products
(business workflows, code repos) that run *on* it. It has three layers:

- **Knowledge** — a local git repo of markdown docs (decisions, runbooks, references, agent
  role definitions), a SQLite full-text index over them, a watcher that reindexes on save, and
  an MCP server that lets any Claude session search and read the KB through `kb_*` tools.
- **Orchestration** — the `co` launcher, the tmux/ssh ergonomics, the safety hooks, and (later,
  on demand) worker dispatch, worktrees, and scheduled jobs.
- **Daily operation** — how the operator opens a session each day, hands off between sessions,
  and keeps the whole thing healthy.

One directory, the **cockpit**, holds the *meta*: the steward's charter, an intake backlog, a
decision log, and session handoffs. The cockpit holds the map; the rest of the system is the
territory. Never move real machinery (KB data, binaries, run artifacts) *into* the cockpit; each
of those has its own home, defined below.

**A "co"** is simply one Claude Code session opened in a particular context (a directory with its
own `CLAUDE.md`, and optionally a KB profile and an agent role). A *steward* co watches the
substrate. A *business-workflow* co runs a recurring operational task. A *coding* co works in a
source repo. They are the same tool pointed at different contexts.

---

## 1. CONFIRM the environment with the operator

Before building, establish these facts. Run the checks, then ask the operator to confirm the
choices. Do not guess past this gate.

```bash
uname -s -r            # OS + kernel (expect Linux; macOS is supported with noted deltas)
echo "$SHELL"          # login shell
claude --version       # confirm Claude Code is on PATH
tmux -V                # confirm tmux
python3 --version      # the KB tooling below is Python; need 3.10+
echo "$PATH" | tr ':' '\n' | grep -q "$HOME/.local/bin" && echo "local bin on PATH" || echo "ADD ~/.local/bin TO PATH"
```

Then confirm with the operator:

1. **Root directory name.** Everything lives under one root. This document uses `~/agentic`.
   Pick the operator's preferred name (it doubles as the ssh alias, e.g. `ssh agentic`).
2. **Short system name / KB namespace.** A one-word handle (this doc uses `acme`) used in the
   KB index filename and doc paths. Use the operator's org or project name.
3. **Pinned model.** The default model every `co` launches on. This doc pins `claude-opus-4-8`.
   The hard rule: **always pin an explicit, known model; never let a session inherit the CLI
   default.** (An unpinned default once silently switched to an expensive model and burned a
   subscription plus real money in a day. Pinning is cheap insurance.)
4. **Scope for v1.** Default: local-only, Claude-only, no external comms. Confirm the operator
   does *not* want Slack/email notifications or a multi-provider gateway yet — those are
   deferred to Phase 3 and only added on demand.
5. **Scheduler.** Linux → `systemd --user` units (preferred) or cron. macOS → launchd. Confirm
   which is available (`systemctl --user` responds on Linux with user lingering enabled).

Record the answers; you will reference them throughout. If the operator wants names other than
`~/agentic` / `acme` / `claude-opus-4-8`, substitute consistently everywhere below.

---

## 2. Directory layout

Create this skeleton. Each path has a single purpose; keep them separate.

```
~/agentic/
  substrate/                 # THE COCKPIT — the steward's home (this is meta, not machinery)
    CLAUDE.md                # the steward charter (§5)
    backlog.md               # durable intake of flagged work
    decisions.md             # the design-decision log
    .claude/
      skills/
        handoff-leave/SKILL.md
        handoff-pickup/SKILL.md
  knowledge/                 # THE KB git repo (§4) — canonical docs
    projects/
      shared/
        agents/              # agent role definitions (markdown + frontmatter)
        runbooks/
      acme/                  # per-project docs (decisions, runbooks, reference)
    scripts/
      validate.py            # frontmatter schema check
  agent-runs/                # run + handoff artifacts (per-day subdirs)

~/.local/bin/                # binaries on PATH
  co                         # the session launcher (§3b)
  agentic-guard              # the safety hook (§3d)
  kb-index                   # KB indexer (§4b)
  kb-watch                   # KB watcher (§4c)
~/.local/lib/agentic/
  mcp_kb.py                  # the MCP knowledge server (§4d)
~/.acme-index/
  index.db                  # the SQLite KB index (§4b)
~/.claude/
  settings.json             # model pin + hook registration (§3a, §3d)
```

```bash
mkdir -p ~/agentic/substrate/.claude/skills/handoff-leave \
         ~/agentic/substrate/.claude/skills/handoff-pickup \
         ~/agentic/knowledge/projects/shared/agents \
         ~/agentic/knowledge/projects/shared/runbooks \
         ~/agentic/knowledge/projects/acme \
         ~/agentic/knowledge/scripts \
         ~/agentic/agent-runs \
         ~/.local/bin ~/.local/lib/agentic ~/.acme-index
git -C ~/agentic/knowledge init -q
```

---

## 3. Phase 0 — Ergonomics (ssh, tmux, co, colors, model pin, safety)

This phase delivers the daily feel: ssh in, launch colored `co` sessions on a pinned model,
hand off between them, and have a guardrail that stops an agent from doing something
irreversible. Build this first; it is usable on its own.

### 3a. Pin the model (`~/.claude/settings.json`)

```json
{
  "model": "claude-opus-4-8"
}
```

This is the machine-wide default for a bare `claude`. The `co` wrapper pins it again at launch
so the two cannot drift. (We add a `hooks` block to this same file in §3d.)

### 3b. The `co` launcher (`~/.local/bin/co`)

`co` opens a Claude Code session inside a named, colored tmux window, on the pinned model,
optionally pre-loaded with an agent role. `co -r` re-materializes the current context's KB
profile before launching (a no-op until Phase 1's `knowledge-ctx` exists, then meaningful).

```bash
#!/usr/bin/env bash
# co — launch a Claude Code session ("a co") in a colored tmux window on a pinned model.
set -euo pipefail

MODEL="${CO_DEFAULT_MODEL:-claude-opus-4-8}"   # never an inherited default; always explicit
ROOT="${AGENTIC_ROOT:-$HOME/agentic}"

# First non-flag word is an optional role. Extend this map as you add roles.
role=""
case "${1:-}" in
  -*|"") : ;;                       # a flag or nothing → plain session, no role
  steward) role="steward"; shift ;;
  *) role="$1"; shift ;;            # any other word is treated as a role name
esac

reload=0
while [ $# -gt 0 ]; do
  case "$1" in
    -r|--reload)  reload=1; shift ;;
    -m|--model)   MODEL="$2"; shift 2 ;;
    --model=*)    MODEL="${1#--model=}"; shift ;;
    *) break ;;
  esac
done

# Deterministic color per role/dir so each co is visually distinct.
name="${role:-$(basename "$PWD")}"
palette=(colour39 colour208 colour46 colour201 colour226 colour51 colour129 colour160)
idx=$(( $(printf '%s' "$name" | cksum | cut -d' ' -f1) % ${#palette[@]} ))
color="${palette[$idx]}"

# If inside tmux, color this window+pane; else start a tmux session named for the role.
if [ -n "${TMUX:-}" ]; then
  tmux select-pane -P "fg=$color"
  tmux set -w window-active-style "fg=$color" 2>/dev/null || true
  tmux rename-window "$name" 2>/dev/null || true
  tmux set -w window-status-current-style "fg=black,bg=$color" 2>/dev/null || true
else
  exec tmux new-session -s "$name" "CO_DEFAULT_MODEL='$MODEL' co ${role} $([ $reload -eq 1 ] && echo -r)"
fi

# Re-materialize the KB profile for this context (Phase 1; harmless if absent).
if [ "$reload" -eq 1 ] && command -v knowledge-ctx >/dev/null 2>&1; then
  knowledge-ctx use --force || true
fi

# Compose the launch. A role preloads its system prompt from the KB-materialized agent file.
args=(--model "$MODEL")
role_file="$ROOT/knowledge/projects/shared/agents/${role}.md"
if [ -n "$role" ] && [ -f "$role_file" ]; then
  args+=(--append-system-prompt "$(sed '1{/^---$/,/^---$/d}' "$role_file")")
fi

exec claude "${args[@]}"
```

```bash
chmod +x ~/.local/bin/co
```

Notes for you to relay to the operator: `co` with no argument launches a plain session in the
current directory; `co steward` launches the steward role; `co <role>` launches any role you
later define in `knowledge/projects/shared/agents/`. `co -r` reloads the KB profile. `co -m
<model>` overrides the model for one session (use this, with the operator in the loop, when a
task genuinely needs a different tier).

### 3c. ssh + tmux attach, with one alias per system

The operator wants `ssh agentic` to drop straight into the running tmux on this VM. That alias
lives on the operator's **laptop**, not here. Generate the snippet for them to paste into their
local `~/.ssh/config`:

```
Host agentic
    HostName <this-vm-hostname-or-ip>
    User <operator-username>
    RequestTTY yes
    RemoteCommand tmux attach -t main || tmux new -s main
```

With that, `ssh agentic` attaches to (or creates) a tmux session named `main` here. Inside it,
each `co` opens its own colored window, so the operator switches co's with tmux's window keys
(`Ctrl-b n/p/<number>`). Fill in the hostname/user from this VM (`hostname -f`, `whoami`).

Install the operator's personal tmux bindings on this VM (`~/.tmux.conf`) so it feels identical
to their other machines: prefix `C-a`, `|`/`-` splits that keep the current path, `r` to reload,
vi copy-mode, and clipboard routed over OSC 52 so a copy in the remote tmux lands on the laptop's
clipboard. The title-map is genericized here (it referenced project names that won't exist on
this VM); extend it with the operator's real systems.

```tmux
# Prefix: C-a instead of the default C-b
unbind C-b
set -g prefix C-a
bind C-a send-prefix

set -g mouse on
set -g base-index 1
setw -g pane-base-index 1

# Reload config
bind r source-file ~/.tmux.conf \; display "Reloaded ~/.tmux.conf"

# Split panes with | and -, keeping the current path
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
unbind '"'
unbind %

# vi copy-mode; route copies to the LOCAL terminal clipboard over OSC 52. Works over ssh through
# any OSC52-capable terminal: copy in the remote tmux, paste on your laptop. Sidesteps the
# pasteboard isolation that bites a long-lived tmux server.
setw -g mode-keys vi
set -g set-clipboard on
bind-key -T copy-mode-vi y                 send-keys -X copy-pipe-and-cancel
bind-key -T copy-mode-vi Enter             send-keys -X copy-pipe-and-cancel
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel

# Label the terminal tab/window by session name (extend the map with your project names;
# falls back to the raw session name).
set -g set-titles on
set -g set-titles-string "#{?#{==:#S,steward},Steward,#S}"

# Highlight the active co window (pairs with the per-co colors `co` sets in §3b).
setw -g automatic-rename off
set -g window-status-current-format "#[bold]#W"
```

### 3d. The safety guard (`~/.local/bin/agentic-guard`)

A `PreToolUse` hook the harness runs before every Bash command. It blocks the two
irreversible, outward actions no agent should ever take autonomously: merging a PR and
force-pushing to the main branch. The human stays in the loop for both.

```bash
#!/usr/bin/env bash
# agentic-guard — PreToolUse hook. Reads the tool call on stdin; exit 2 blocks it.
input="$(cat)"
cmd="$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

block() { echo "BLOCKED by agentic-guard: $1 Ask the operator to do this manually." >&2; exit 2; }

# Force-push to main/master.
printf '%s' "$cmd" | grep -Eq 'git +push.*(-f\b|--force)' \
  && printf '%s' "$cmd" | grep -Eq '\b(main|master)\b' \
  && block "force-push to a protected branch."

# PR merge via gh.
printf '%s' "$cmd" | grep -Eq '\bgh +pr +merge\b' && block "merging a pull request."

exit 0
```

```bash
chmod +x ~/.local/bin/agentic-guard
```

Register it in `~/.claude/settings.json` (merge with the model pin from §3a):

```json
{
  "model": "claude-opus-4-8",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/home/<operator>/.local/bin/agentic-guard" }
        ]
      }
    ]
  }
}
```

Use the absolute path (hooks do not expand `~`). After editing, verify in a session with `/hooks`
and test that a `gh pr merge` attempt is refused. Extend the guard over time as you discover
other actions that warrant a human gate; harden the guard rather than weakening it.

### 3e. Handoff skills

These let a session save its state on exit and the next session resume it, so the steward role
spans days. Create both files.

`~/agentic/substrate/.claude/skills/handoff-leave/SKILL.md`:

```markdown
---
name: handoff-leave
description: Save the current session's state to a dated handoff doc before exiting.
---

# /handoff-leave

Write a handoff so the next session resumes cleanly. Steps:

1. Determine the context name: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.
2. Create `~/agentic/agent-runs/$(date +%F)/co-<context>-$(date +%H%M)/` and write `handoff.md`
   with: **State summary** (one paragraph), **In-flight items** (bullets, each with enough to
   resume), **Decisions made this session**, **Open questions / blockers**, and a
   **Recommended next move** (verbatim instruction for the next session).
3. Tell the operator where it landed (full absolute path).

The handoff is an audit trail. Never delete or rewrite an old one.
```

`~/agentic/substrate/.claude/skills/handoff-pickup/SKILL.md`:

```markdown
---
name: handoff-pickup
description: Resume from the most recent handoff for this context.
---

# /handoff-pickup

1. Context name: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.
2. Find the newest handoff in the last 48h:
   `ls -t ~/agentic/agent-runs/*/co-<context>-*/handoff.md 2>/dev/null | head -1`.
3. If found, read it and surface a brief ack: State / In-flight / Recommended next move. Then
   act on the recommended next move unless the operator redirects. If none found, say so and
   start fresh. Do not move or delete the handoff.
```

**Phase 0 is now usable.** `ssh agentic` → colored `co` windows on a pinned model, a working
safety gate, and handoff continuity. Verify with §7 before moving on.

---

## 4. Phase 1 — The knowledge layer

A local KB that any session can search through `kb_*` MCP tools, kept current by a watcher.

### 4a. The doc format

Every KB doc is markdown with YAML frontmatter:

```markdown
---
id: acme/runbooks/deploy
kind: runbook            # runbook | decision | reference | agent | profile
status: active           # active | draft | deprecated
title: How to deploy the billing service
audience: shared         # shared, or a project name
---

Body in plain markdown. Link related docs with [[acme/runbooks/rollback]].
```

`scripts/validate.py` enforces the schema so a malformed doc is caught at save time rather than
discovered missing from the index later:

```python
#!/usr/bin/env python3
import sys, pathlib, yaml
KINDS = {"runbook", "decision", "reference", "agent", "profile"}
STATUS = {"active", "draft", "deprecated"}
root = pathlib.Path(__file__).resolve().parent.parent / "projects"
errs = 0
for md in root.rglob("*.md"):
    text = md.read_text(encoding="utf-8")
    if not text.startswith("---"):
        print(f"ERROR {md}: missing frontmatter"); errs += 1; continue
    fm = yaml.safe_load(text.split("---", 2)[1])
    for key in ("id", "kind", "status", "title"):
        if key not in fm:
            print(f"ERROR {md}: missing '{key}'"); errs += 1
    if fm.get("kind") not in KINDS:
        print(f"ERROR {md}: bad kind {fm.get('kind')!r}"); errs += 1
    if fm.get("status") not in STATUS:
        print(f"ERROR {md}: bad status {fm.get('status')!r}"); errs += 1
print(f"checked, {errs} error(s)")
sys.exit(1 if errs else 0)
```

### 4b. The index + indexer (`~/.local/bin/kb-index`)

A SQLite FTS5 index over every doc. Rebuild is fast; run it on demand and from the watcher.

```python
#!/usr/bin/env python3
"""kb-index — (re)build the SQLite FTS index over the knowledge repo."""
import sqlite3, pathlib, yaml, os
ROOT = pathlib.Path(os.environ.get("AGENTIC_ROOT", pathlib.Path.home() / "agentic"))
DOCS = ROOT / "knowledge" / "projects"
DB = pathlib.Path.home() / ".acme-index" / "index.db"
DB.parent.mkdir(parents=True, exist_ok=True)
con = sqlite3.connect(DB)
con.executescript("""
DROP TABLE IF EXISTS docs;
CREATE VIRTUAL TABLE docs USING fts5(id, kind, status, title, audience, path, body);
""")
n = 0
for md in DOCS.rglob("*.md"):
    text = md.read_text(encoding="utf-8")
    if not text.startswith("---"):
        continue
    _, fm_raw, body = text.split("---", 2)
    fm = yaml.safe_load(fm_raw) or {}
    con.execute("INSERT INTO docs VALUES (?,?,?,?,?,?,?)", (
        fm.get("id", str(md)), fm.get("kind", ""), fm.get("status", ""),
        fm.get("title", ""), fm.get("audience", "shared"), str(md), body.strip()))
    n += 1
con.commit(); con.close()
print(f"indexed {n} docs into {DB}")
```

```bash
chmod +x ~/.local/bin/kb-index && kb-index
```

### 4c. The watcher (`~/.local/bin/kb-watch`)

Reindex whenever a doc changes, so the KB is always current without a manual rebuild.

```python
#!/usr/bin/env python3
"""kb-watch — reindex on any change under knowledge/projects."""
import time, subprocess, os, pathlib
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
ROOT = pathlib.Path(os.environ.get("AGENTIC_ROOT", pathlib.Path.home() / "agentic"))
WATCH = ROOT / "knowledge" / "projects"

class H(FileSystemEventHandler):
    def on_any_event(self, e):
        if str(e.src_path).endswith(".md"):
            subprocess.run(["kb-index"], check=False)

obs = Observer(); obs.schedule(H(), str(WATCH), recursive=True); obs.start()
try:
    while True: time.sleep(2)
except KeyboardInterrupt:
    obs.stop()
obs.join()
```

```bash
pip install --user watchdog pyyaml mcp
chmod +x ~/.local/bin/kb-watch
```

Run it as a background service so it survives logout. **Linux (`systemd --user`)** —
`~/.config/systemd/user/kb-watch.service`:

```ini
[Unit]
Description=Knowledge base watcher
[Service]
ExecStart=%h/.local/bin/kb-watch
Restart=always
[Install]
WantedBy=default.target
```

```bash
loginctl enable-linger "$USER"          # so the unit runs without an active login
systemctl --user daemon-reload
systemctl --user enable --now kb-watch
```

**macOS** — wrap `kb-watch` in a launchd `~/Library/LaunchAgents/*.plist` with `RunAtLoad` and
`KeepAlive`, then `launchctl bootstrap gui/$(id -u) <plist>`.

### 4d. The MCP knowledge server (`~/.local/lib/agentic/mcp_kb.py`)

Exposes `kb_search`, `kb_get`, `kb_list_topics` to every Claude session.

```python
#!/usr/bin/env python3
"""mcp_kb — serve the KB index to Claude sessions over MCP (stdio)."""
import sqlite3, pathlib
from mcp.server.fastmcp import FastMCP
DB = pathlib.Path.home() / ".acme-index" / "index.db"
mcp = FastMCP("kb")

def _con():
    return sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

@mcp.tool()
def kb_search(query: str, limit: int = 8) -> list[dict]:
    """Full-text search the knowledge base. Returns id, title, kind, and a snippet."""
    con = _con()
    rows = con.execute(
        "SELECT id, title, kind, snippet(docs, 6, '[', ']', ' … ', 12) "
        "FROM docs WHERE docs MATCH ? ORDER BY rank LIMIT ?", (query, limit)).fetchall()
    con.close()
    return [{"id": r[0], "title": r[1], "kind": r[2], "snippet": r[3]} for r in rows]

@mcp.tool()
def kb_get(id: str) -> dict:
    """Fetch one doc's full body by its frontmatter id."""
    con = _con()
    r = con.execute("SELECT id, title, kind, status, body FROM docs WHERE id = ?", (id,)).fetchone()
    con.close()
    if not r:
        return {"error": f"no doc with id {id!r}"}
    return {"id": r[0], "title": r[1], "kind": r[2], "status": r[3], "body": r[4]}

@mcp.tool()
def kb_list_topics() -> list[dict]:
    """List every doc id + title + kind, for browsing."""
    con = _con()
    rows = con.execute("SELECT id, title, kind FROM docs ORDER BY id").fetchall()
    con.close()
    return [{"id": r[0], "title": r[1], "kind": r[2]} for r in rows]

if __name__ == "__main__":
    mcp.run()
```

Register it with Claude Code, then confirm it loaded:

```bash
claude mcp add kb -- python3 ~/.local/lib/agentic/mcp_kb.py
claude mcp list          # kb should appear; in a session, /mcp shows its tools
```

The tools surface as `mcp__kb__kb_search`, `mcp__kb__kb_get`, `mcp__kb__kb_list_topics`. Confirm
the exact registration syntax with `claude mcp --help` on this Claude Code version if the above
differs.

### 4e. `knowledge-ctx` (profile materialization) — defer until you have agent roles

In the full system, `knowledge-ctx use` reads the index and writes a context's agent files and a
local `CLAUDE.md` overlay into the working directory, so `co -r` refreshes a co's role and KB
view. You do not need it until you define agent roles and dispatch workers (Phase 3). For now,
`co -r` is a harmless no-op. Note this as a known stub; build it when the roster justifies it.

---

## 5. Phase 2 — Become the steward

Now stand up the cockpit and adopt the role.

### 5a. The charter (`~/agentic/substrate/CLAUDE.md`)

```markdown
# Substrate steward

You are a Claude Code session opened in `~/agentic/substrate/`. This directory is the home of a
*role*, not a codebase: you are the keeper and improver of this machine's agentic substrate.

## What the substrate is
- **Knowledge** — `~/agentic/knowledge/` (git), the index at `~/.acme-index/index.db`, the
  `kb-watch` service, the `mcp_kb` server (`mcp__kb__*` tools).
- **Orchestration** — the `co` launcher, the tmux/ssh ergonomics, the `agentic-guard` safety
  hook, and (later, on demand) worker dispatch and scheduled jobs.
- **Daily operation** — how the operator opens a session, hands off, and keeps things healthy.

## Cockpit, not engine
This directory holds the meta: this charter, the backlog, the decision log, handoffs. The real
machinery lives in its homes (`~/.local/bin`, `~/.local/lib/agentic`, `~/agentic/knowledge`,
`~/agentic/agent-runs`). Edit machinery in place; never relocate it into `substrate/`.

## How the role works
1. **Intake.** The moment the operator flags friction, capture it in `backlog.md` — an
   unrecorded flag is a lost flag.
2. **Triage.** Sort each item: do-now / queue / needs-operator-decision / won't-do. Surface
   real decisions as "approve option B or redirect," with the legwork already done.
3. **Implement directly** in the real homes; test; record meaningful choices.
4. **Record.** Append to `decisions.md` for any non-trivial choice; mint runbooks in the KB.
5. **Continuity.** Use `/handoff-leave` before exit, `/handoff-pickup` to resume.

## Boundaries
- Never merge a PR or force-push to a protected branch autonomously (the guard enforces this).
- Don't silently work around a recorded decision; if one seems wrong, surface it as a question.
- Coordinate before churning another co's working context.

## Spawning more co's
- A **business-workflow co**: a directory with its own `CLAUDE.md` describing the task, plus any
  KB docs it relies on. Launch with `co` from that directory.
- A **coding co**: open `co` inside a source repo. Its `CLAUDE.md` (the repo's own) scopes it.
- A **role**: drop a `<name>.md` (frontmatter + system prompt) into
  `knowledge/projects/shared/agents/`, let the watcher index it, then `co <name>`.
```

### 5b. Seed the backlog and decision log

`~/agentic/substrate/backlog.md`:

```markdown
# Substrate backlog

Durable intake. Every flagged item lands here the moment it's raised. States: now · next ·
decide · someday · verify.

---
(empty — first entries land as the operator flags friction)
```

`~/agentic/substrate/decisions.md`:

```markdown
# Decision log

Append an entry for any non-trivial design choice. Newest at the bottom.

## DEC-001 — Substrate bootstrapped
**Date:** <today>
**Status:** Live.
Stood up Phase 0 (co launcher, tmux/ssh ergonomics, colors, model pin, safety guard, handoff
skills) and Phase 1 (knowledge repo + index + watcher + mcp_kb). Orchestration and comms layers
deferred until a real need appears. Model pinned to claude-opus-4-8 machine-wide.
```

### 5c. Commit and hand off

```bash
git -C ~/agentic/knowledge add -A && git -C ~/agentic/knowledge commit -qm "knowledge: seed repo + schema"
git -C ~/agentic/substrate init -q && git -C ~/agentic/substrate add -A \
  && git -C ~/agentic/substrate commit -qm "substrate: charter, backlog, decisions, handoff skills"
```

Then, as the steward, run `/handoff-leave` so the next session resumes cleanly. From here, the
operator opens the steward with `co steward` (in `~/agentic/substrate`) and grows the system by
flagging work.

---

## 6. Phase 3+ — Deferred layers (build only when a real need appears)

Do not build these speculatively. Each earns its place when a concrete, repeated friction
demands it. When that happens, the steward designs it, records the decision, and adds it.

- **Worker dispatch (`agentctl`) + worktrees.** When a task is large, mechanical, and
  parallelizable, spawn dedicated worker sessions in isolated git worktrees rather than doing it
  inline. This is the point of `knowledge-ctx` (§4e): materialize a worker's role + KB into its
  worktree. Build `agentctl spawn/status/logs` as a thin wrapper over `claude -p` plus run-dir
  bookkeeping.
- **Scheduled jobs.** Recurring maintenance (an overnight health scan, a KB validation sweep) as
  `systemd --user` timers. Add when a manual habit proves worth automating.
- **Comms / notifications.** If the day job wants run summaries in chat or email, wire one
  outbound channel. Keep it one-way and explicit; never let an agent post as the operator.
- **Multi-provider gateway.** Only if cost or availability forces routing some work to non-Claude
  models. Until then, Claude-only is simpler and fine.

The discipline is a lean core that works, grown deliberately. That is the whole philosophy.

---

## 7. Verification checklist

Run these before declaring each phase done.

- **Phase 0:** `ssh agentic` (from the laptop) attaches to tmux; `co` opens a colored window on
  `claude-opus-4-8` (check the model line in-session); `co -r` runs without error; a `gh pr
  merge` attempt is refused by the guard; `/handoff-leave` then `/handoff-pickup` round-trips.
- **Phase 1:** `kb-index` reports a doc count; editing a KB doc auto-reindexes (watch `kb-watch`
  logs / `systemctl --user status kb-watch`); in a session, `mcp__kb__kb_search` returns a hit
  and `kb_get` returns a full body.
- **Phase 2:** `co steward` launches with the charter loaded; the backlog and decision log exist
  and are committed; the first handoff is written.

---

## 8. The lessons baked in (so you don't relearn them the hard way)

- **Always pin the model.** An inherited default once silently became expensive and burned a
  subscription in a day. Pin it in `settings.json` and in `co`.
- **The human merges.** No agent merges a PR or force-pushes a protected branch. The guard
  enforces it; keep it that way.
- **Cockpit, not engine.** Keep the meta (charter, backlog, decisions, handoffs) separate from
  the machinery. The temptation to dump real data into `substrate/` is a signal it belongs
  elsewhere.
- **Capture every flag immediately.** Context windows compact and sessions close; an unrecorded
  flag is lost. The backlog is the durable memory.
- **Surface decisions, don't bury them.** Bring the operator "approve B or redirect," with the
  legwork done, not a menu of unresearched options.
- **Grow on demand.** Add scheduled jobs, workers, and comms only when real, repeated pain
  justifies them. A small system that works beats a large one that mostly idles.
- **Write plainly.** In every doc, runbook, and message, say each thing once, precisely, and
  stop. Lead with the point; cut restatement.

---

*This is the seed. The system is meant to grow from here, one deliberately-added piece at a time,
as the steward and operator discover what this particular machine actually needs.*
