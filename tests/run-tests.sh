#!/usr/bin/env bash
# run-tests.sh — the kit's test suite. CI runs exactly this; run it locally
# with:  ./tests/run-tests.sh
#
# Installs the kit into a scratch HOME (with a recording `claude` shim),
# then exercises every launch path, both guards, the knowledge tools, and
# the team site. Zero network access needed except `pip install mcp`
# (skipped if pip is offline; the mcp package is not needed by anything
# tested here).
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(mktemp -d)"
H="$SCRATCH/home"
R="$H/agentic"
mkdir -p "$H/bin"
trap 'rm -rf "$SCRATCH"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   $*"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL $*"; }
expect() { # expect <want-exit> <label> <cmd...>
  want="$1"; label="$2"; shift 2
  set +e; "$@" >/dev/null 2>&1; got=$?; set -e
  [ "$got" -eq "$want" ] && ok "$label" || bad "$label (exit $got, wanted $want)"
}

echo "== syntax =="
for f in install.sh kit/bin/co kit/bin/agentic-guard kit/bin/model-pin-guard tests/run-tests.sh; do
  expect 0 "bash -n $f" bash -n "$REPO/$f"
done
for f in kit/bin/kb-index kit/bin/kb-watch kit/bin/agentic-site kit/lib/agentic/mcp_kb.py kit/knowledge/scripts/validate.py; do
  expect 0 "py_compile $f" python3 -m py_compile "$REPO/$f"
done

echo "== install (scratch HOME, claude shim) =="
cat > "$H/bin/claude" <<'EOF'
#!/bin/bash
echo "ARGS: $*" >> "$HOME/claude-shim.log"
exit 0
EOF
chmod +x "$H/bin/claude"
export ORIG_PATH="$PATH"
kit_env() { env HOME="$H" AGENTIC_ROOT="$R" PATH="$H/bin:$H/.local/bin:$ORIG_PATH" "$@"; }

kit_env bash "$REPO/install.sh" --yes >/dev/null 2>&1 || bad "install.sh --yes"
[ -x "$H/.local/bin/co" ] && ok "binaries installed" || bad "binaries installed"
[ -f "$R/substrate/CLAUDE.md" ] && ok "cockpit seeded" || bad "cockpit seeded"
[ -f "$R/.model-pin" ] && ok "model pin written" || bad "model pin written"
grep -q '"model": "claude-sonnet-5"' "$H/.claude/settings.json" && ok "settings pin" || bad "settings pin"

kit_env bash "$REPO/install.sh" --yes >/dev/null 2>&1 || bad "install.sh rerun"
n_guard=$(grep -c 'agentic-guard' "$H/.claude/settings.json" || true)
[ "$n_guard" -eq 1 ] && ok "idempotent hook registration" || bad "idempotent hook registration ($n_guard entries)"

echo "== co launch paths =="
rm -f "$H/claude-shim.log"
(cd "$R/substrate" && kit_env bash "$H/.local/bin/co")
grep -q 'ARGS: --model claude-sonnet-5$' "$H/claude-shim.log" && ok "co pins the model" || bad "co pins the model"
(cd "$R/substrate" && kit_env bash "$H/.local/bin/co" -m other-model)
grep -q 'ARGS: --model other-model' "$H/claude-shim.log" && ok "co -m overrides" || bad "co -m overrides"
(cd "$R/substrate" && kit_env bash "$H/.local/bin/co" -r)
grep -q 'ARGS: --model claude-sonnet-5 /handoff-pickup' "$H/claude-shim.log" && ok "co -r resumes" || bad "co -r resumes"
(cd "$R/substrate" && kit_env bash "$H/.local/bin/co" researcher)
grep -q 'append-system-prompt' "$H/claude-shim.log" && ok "co <role> loads role" || bad "co <role> loads role"
expect 1 "co unknown role errors" env HOME="$H" AGENTIC_ROOT="$R" PATH="$H/bin:$ORIG_PATH" bash "$H/.local/bin/co" nosuchrole

echo "== agentic-guard =="
guard() { printf '{"tool_input":{"command":"%s"}}' "$1" | kit_env bash "$H/.local/bin/agentic-guard"; }
expect 2 "blocks pr merge"            guard 'gh pr merge 42'
expect 2 "blocks pr merge in chain"   guard 'cd /x && gh pr merge 42 --squash'
expect 2 "blocks quoted pr merge (bash -c)" guard 'bash -c \"gh pr merge 42\"'
expect 2 "blocks quoted pr merge (eval)"    guard "eval 'gh pr merge 42'"
expect 2 "blocks force-push main"     guard 'git push --force origin main'
expect 2 "blocks -f master"           guard 'git push -f origin master'
expect 2 "blocks force-with-lease main" guard 'git push --force-with-lease origin main'
expect 2 "blocks bare force-push"     guard 'git push -f'
expect 2 "blocks force-push remote-only" guard 'git push --force origin'
expect 0 "allows force-push feature"  guard 'git push --force origin feature-x'
expect 0 "allows plain push main"     guard 'git push origin main'
expect 0 "allows mention in echo"     guard 'echo the merge command is dangerous'
expect 0 "allows pr view"             guard 'gh pr view 42'

echo "== model-pin-guard =="
python3 - "$H/.claude/settings.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["model"] = "drifted-model"
json.dump(d, open(p, "w"), indent=2)
EOF
kit_env bash "$H/.local/bin/model-pin-guard" >/dev/null 2>&1
grep -q '"model": "claude-sonnet-5"' "$H/.claude/settings.json" && ok "restores drifted pin" || bad "restores drifted pin"
out=$(kit_env bash "$H/.local/bin/model-pin-guard" 2>&1)
[ -z "$out" ] && ok "silent when pinned" || bad "silent when pinned"

echo "== knowledge layer =="
kit_env python3 "$R/knowledge/scripts/validate.py" >/dev/null && ok "validate.py seed docs" || bad "validate.py seed docs"
kit_env python3 "$H/.local/bin/kb-index" | grep -q 'indexed 2 docs' && ok "kb-index" || bad "kb-index"

echo "== team site =="
mkdir -p "$R/agent-runs/2026-01-15/co-demo-1830"
printf '%s\n' '# Handoff' '' '- item one' '' '[link](https://example.com/"onmouseover="alert(1))' \
  > "$R/agent-runs/2026-01-15/co-demo-1830/handoff.md"
cat > "$R/knowledge/projects/shared/runbooks/xss-probe.md" <<'EOF'
---
id: shared/runbooks/xss-probe
kind: runbook
status: draft
title: xss probe fixture
---

<script>alert("frontmatter probe")</script> searchable-marker-word
EOF
kit_env python3 "$H/.local/bin/kb-index" >/dev/null
PORT=8399
kit_env env AGENTIC_SITE_PORT=$PORT python3 "$H/.local/bin/agentic-site" >/dev/null 2>&1 &
SITE=$!
i=0
until curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1; do
  i=$((i+1)); [ $i -gt 50 ] && break; sleep 0.2
done
for p in / /activity /kb "/kb?q=frontmatter" /cockpit; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$p")
  [ "$code" = "200" ] && ok "GET $p" || bad "GET $p ($code)"
done
curl -s "http://127.0.0.1:$PORT/handoff?p=/etc/hosts" | grep -q 'Not a handoff path' \
  && ok "handoff path traversal rejected" || bad "handoff path traversal rejected"
hf_page=$(curl -s "http://127.0.0.1:$PORT/handoff?p=$R/agent-runs/2026-01-15/co-demo-1830/handoff.md")
printf '%s' "$hf_page" | grep -q 'onmouseover="alert' \
  && bad "href XSS escaped" || ok "href XSS escaped"
kb_page=$(curl -s "http://127.0.0.1:$PORT/kb?q=searchable-marker-word")
printf '%s' "$kb_page" | grep -q '<script>alert' \
  && bad "snippet XSS escaped" || ok "snippet XSS escaped"
printf '%s' "$kb_page" | grep -q '<b>' \
  && ok "snippet highlight kept" || bad "snippet highlight kept"
curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/kb?q=%22broken(syntax" | grep -q 200 \
  && ok "bad FTS query survives" || bad "bad FTS query survives"
kill $SITE 2>/dev/null || true
wait $SITE 2>/dev/null || true

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
