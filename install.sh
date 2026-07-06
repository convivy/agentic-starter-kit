#!/usr/bin/env bash
# install.sh — install the agentic starter kit onto this machine.
#
# What it does (idempotent; re-running refreshes kit binaries and leaves your
# data alone):
#   1. checks prerequisites (claude, git, python3; tmux optional)
#   2. creates the root layout (default ~/agentic; override with --root)
#   3. installs binaries to ~/.local/bin and the MCP server to ~/.local/lib/agentic
#   4. seeds the cockpit, the knowledge repo, and the product template
#      (never overwrites an existing cockpit or knowledge repo)
#   5. pins the model: writes <root>/.model-pin and sets it in ~/.claude/settings.json
#   6. registers the safety hooks in ~/.claude/settings.json (backs it up first)
#   7. installs the one Python dependency (mcp), registers the kb MCP server,
#      and builds the first index
#
# Usage:  ./install.sh [--root DIR] [--model MODEL] [--yes]
#   --root   install root (default: ~/agentic)
#   --model  pinned default model (default: claude-sonnet-5)
#   --yes    non-interactive; accept all defaults
#
# Works on macOS (bash 3.2) and Linux.
set -eu

KIT="$(cd "$(dirname "$0")" && pwd)/kit"
ROOT="$HOME/agentic"
MODEL="claude-sonnet-5"
YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)   ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --model)  MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#--model=}"; shift ;;
    --yes|-y) YES=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

confirm() {
  # confirm "question" "default-value" -> echoes the chosen value
  q="$1"; d="$2"
  if [ "$YES" -eq 1 ]; then
    printf '%s' "$d"; return
  fi
  printf '%s [%s]: ' "$q" "$d" >&2
  read -r ans || ans=""
  printf '%s' "${ans:-$d}"
}

# ---- 1. prerequisites -------------------------------------------------------
say "== checking prerequisites"
command -v claude  >/dev/null 2>&1 || fail "claude not found — install Claude Code first: https://code.claude.com/docs"
command -v git     >/dev/null 2>&1 || fail "git not found"
command -v python3 >/dev/null 2>&1 || fail "python3 not found (3.10+ required)"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
  || fail "python3 is older than 3.10 (the mcp package needs 3.10+) — install a newer one, e.g. 'brew install python3' on macOS"
command -v tmux >/dev/null 2>&1 || say "   note: tmux not found — optional, but persistent sessions want it (see IDEAS.md)"

ROOT="$(confirm 'Install root' "$ROOT")"
MODEL="$(confirm 'Pinned default model' "$MODEL")"
case "$ROOT" in
  "~")   ROOT="$HOME" ;;
  "~/"*) ROOT="$HOME/${ROOT#\~/}" ;;
esac
case "$ROOT" in
  /*) : ;;
  *) fail "install root must be an absolute path (got '$ROOT')" ;;
esac
say "   root:  $ROOT"
say "   model: $MODEL"

# ---- 2. layout --------------------------------------------------------------
say "== creating layout"
mkdir -p "$ROOT" "$ROOT/agent-runs" "$ROOT/.index" "$HOME/.local/bin" "$HOME/.local/lib/agentic"

# ---- 3. binaries + lib (always refreshed — these are the kit's code) --------
say "== installing binaries to ~/.local/bin"
for f in co co-session-health agentic-guard model-pin-guard kb-index kb-watch agentic-site; do
  cp "$KIT/bin/$f" "$HOME/.local/bin/$f"
  chmod +x "$HOME/.local/bin/$f"
done
cp "$KIT/lib/agentic/mcp_kb.py" "$HOME/.local/lib/agentic/mcp_kb.py"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) say "   note: add ~/.local/bin to PATH in your shell profile:"
     say "         export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ---- 4. cockpit, knowledge, product template (seed once, never clobber) -----
say "== seeding cockpit + knowledge + product template"
if [ -d "$ROOT/substrate" ]; then
  say "   substrate/ exists — leaving your cockpit alone"
else
  cp -R "$KIT/cockpit" "$ROOT/substrate"
fi
if [ -d "$ROOT/knowledge" ]; then
  say "   knowledge/ exists — leaving your knowledge repo alone"
else
  cp -R "$KIT/knowledge" "$ROOT/knowledge"
  git -C "$ROOT/knowledge" init -q
  git -C "$ROOT/knowledge" add -A
  git -C "$ROOT/knowledge" commit -qm "knowledge: seed from agentic-starter-kit" || true
fi
if [ -d "$ROOT/product-template" ]; then
  say "   product-template/ exists — leaving it alone (delete it and re-run to refresh)"
else
  cp -R "$KIT/product-template" "$ROOT/product-template"
fi

# ---- 5 + 6. model pin + settings.json (pin + hooks), with backup ------------
say "== pinning the model + registering hooks in ~/.claude/settings.json"
printf '%s\n' "$MODEL" > "$ROOT/.model-pin"

SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.pre-agentic-kit.bak"
  say "   backed up existing settings to $SETTINGS.pre-agentic-kit.bak"
fi
python3 - "$SETTINGS" "$MODEL" "$HOME/.local/bin" <<'PY'
import json, os, sys

path, model, bindir = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)   # invalid JSON aborts the install loudly — fix it first

data["model"] = model
# Status line: model + context gauge (with handoff warnings) + live dispatched runs.
data["statusLine"] = {"type": "command", "command": f"{bindir}/co-session-health"}
hooks = data.setdefault("hooks", {})

def ensure(event, matcher, command):
    entries = hooks.setdefault(event, [])
    for e in entries:
        for h in e.get("hooks", []):
            if h.get("command") == command:
                return
    entry = {"hooks": [{"type": "command", "command": command}]}
    if matcher:
        entry["matcher"] = matcher
    entries.append(entry)

ensure("PreToolUse", "Bash", f"{bindir}/agentic-guard")
ensure("SessionStart", None, f"{bindir}/model-pin-guard")

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"   model pinned to {model}; status line + agentic-guard + model-pin-guard registered")
PY

# ---- 7. python dep, MCP registration, first index ----------------------------
say "== installing the mcp package (the kit's one Python dependency)"
python3 -m pip install --user --quiet mcp 2>/dev/null \
  || python3 -m pip install --user --quiet --break-system-packages mcp \
  || say "   warning: pip install mcp failed — kb tools won't load until you install it (python3 -m pip install --user mcp)"

say "== registering the kb MCP server with Claude Code"
if claude mcp list 2>/dev/null | grep -q '^kb\b\|^kb:'; then
  say "   kb already registered"
else
  claude mcp add --scope user kb -e "AGENTIC_ROOT=$ROOT" -- python3 "$HOME/.local/lib/agentic/mcp_kb.py" \
    || say "   warning: 'claude mcp add' failed — register manually (see BOOTSTRAP.md §5)"
fi

say "== building the first knowledge index"
AGENTIC_ROOT="$ROOT" python3 "$HOME/.local/bin/kb-index"

# ---- done --------------------------------------------------------------------
say ""
say "Installed. Verify:"
say "  1. cd $ROOT/substrate && co        # steward session on $MODEL (check /status)"
say "  2. in that session, ask: 'search the kb for adding a doc'   # tests mcp__kb__kb_search"
say "  3. ask it to run: gh pr merge 1    # agentic-guard must refuse"
say "  4. agentic-site &                  # then open http://127.0.0.1:8321"
say ""
say "Then read BOOTSTRAP.md end to end — it explains the daily loop."
case "$ROOT" in
  "$HOME/agentic") : ;;
  *) say "note: you chose a non-default root — export AGENTIC_ROOT=\"$ROOT\" in your shell profile so co, the hooks, and the site all find it." ;;
esac
