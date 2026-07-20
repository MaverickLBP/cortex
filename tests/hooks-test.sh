#!/usr/bin/env bash
# CORTEX — hook test harness. Pipe-tests every hook script with synthetic
# Claude Code hook payloads. No Claude session needed. Requires: bash, jq, git.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ── Assertion helpers ─────────────────────────────────
assert_contains() { # name, haystack, needle
  if echo "$2" | grep -qF "$3"; then
    echo "  PASS: $1"; PASS=$((PASS+1))
  else
    echo "  FAIL: $1 — output does not contain: $3"; FAIL=$((FAIL+1))
  fi
}
assert_not_contains() { # name, haystack, needle
  if echo "$2" | grep -qF "$3"; then
    echo "  FAIL: $1 — output unexpectedly contains: $3"; FAIL=$((FAIL+1))
  else
    echo "  PASS: $1"; PASS=$((PASS+1))
  fi
}
assert_silent() { # name, output
  if [ -z "$2" ]; then
    echo "  PASS: $1"; PASS=$((PASS+1))
  else
    echo "  FAIL: $1 — expected no output, got: $2"; FAIL=$((FAIL+1))
  fi
}
assert_exit0() { # name, exit_code
  if [ "$2" -eq 0 ]; then
    echo "  PASS: $1"; PASS=$((PASS+1))
  else
    echo "  FAIL: $1 — exit code $2"; FAIL=$((FAIL+1))
  fi
}

# ── Fixture builders ──────────────────────────────────
# make_project DIR — git repo with .cortex/{SYSTEM.md,MAP.md} and one mapped file
make_project() {
  local dir="$1"
  mkdir -p "$dir/.cortex" "$dir/src"
  echo "# SYSTEM sentinel-system-content" > "$dir/.cortex/SYSTEM.md"
  cat > "$dir/.cortex/MAP.md" << 'EOM'
# Knowledge Map — fixture
sentinel-map-content
- `src/mapped.js` → already documented file
EOM
  echo "x" > "$dir/src/mapped.js"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm init
}

# make_workspace DIR — workspace marker + two CORTEX projects (alpha, beta)
make_workspace() {
  local dir="$1"
  mkdir -p "$dir"
  echo '{"cortex": true}' > "$dir/.cortex-workspace.json"
  make_project "$dir/alpha"
  make_project "$dir/beta"
  # distinguish the two maps
  sed -i 's/sentinel-map-content/sentinel-map-alpha/' "$dir/alpha/.cortex/MAP.md"
  sed -i 's/sentinel-map-content/sentinel-map-beta/' "$dir/beta/.cortex/MAP.md"
}

run_hook() { # script, payload, cwd  → sets OUT and RC
  local script="$1" payload="$2" cwd="$3"
  OUT="$(cd "$cwd" && echo "$payload" | timeout 5 bash "$script" 2>/dev/null)"
  RC=$?
}

SESSION_HOOK="$REPO_ROOT/.claude/hooks/cortex-session.sh"
FILECHANGE_HOOK="$REPO_ROOT/.claude/hooks/cortex-file-change.sh"
SUBAGENT_HOOK="$REPO_ROOT/.claude/hooks/cortex-subagent.sh"

echo "── cortex-session.sh ──"
make_project "$TMP/single"
run_hook "$SESSION_HOOK" "{\"cwd\":\"$TMP/single\"}" "$TMP/single"
OUT_SINGLE="$OUT"
assert_exit0   "session: single mode exits 0" "$RC"
assert_contains "session: single mode injects SYSTEM.md content" "$OUT" "sentinel-system-content"

make_workspace "$TMP/ws"
run_hook "$SESSION_HOOK" "{\"cwd\":\"$TMP/ws/alpha\"}" "$TMP/ws/alpha"
assert_exit0   "session: workspace mode exits 0" "$RC"
assert_contains "session: workspace mode lists projects" "$OUT" "alpha"

assert_contains "session: single mode injects MAP.md content" "$OUT_SINGLE" "sentinel-map-content"
run_hook "$SESSION_HOOK" "{\"cwd\":\"$TMP/ws/alpha\"}" "$TMP/ws/alpha"
assert_contains     "session: workspace mode injects cwd project MAP" "$OUT" "sentinel-map-alpha"
assert_not_contains "session: workspace mode does NOT inject other projects' MAPs" "$OUT" "sentinel-map-beta"
# missing-MAP fallback: still points at /cortex-init
rm "$TMP/single/.cortex/MAP.md"
run_hook "$SESSION_HOOK" "{\"cwd\":\"$TMP/single\"}" "$TMP/single"
assert_contains "session: missing MAP falls back to /cortex-init hint" "$OUT" "cortex-init"

echo ""
echo "── cortex-file-change.sh ──"
make_project "$TMP/fc"
# new unmapped file → reminder
echo "new" > "$TMP/fc/src/brandnew.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/src/brandnew.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_exit0    "filechange: new unmapped exits 0" "$RC"
assert_contains "filechange: new unmapped file triggers reminder" "$OUT" "MAP.md"
# file already in MAP → silent
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/src/mapped.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: mapped file is silent" "$OUT"
# tracked, pre-existing file (overwrite) → silent
echo "tracked" > "$TMP/fc/src/tracked.js"
git -C "$TMP/fc" add src/tracked.js && git -C "$TMP/fc" -c user.email=t@t -c user.name=t commit -qm t
echo "edited" > "$TMP/fc/src/tracked.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/src/tracked.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: tracked overwrite is silent" "$OUT"
# excluded path → silent
mkdir -p "$TMP/fc/node_modules/x" && echo x > "$TMP/fc/node_modules/x/a.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/node_modules/x/a.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: excluded path is silent" "$OUT"
# outside any CORTEX project → silent
mkdir -p "$TMP/plain" && echo x > "$TMP/plain/a.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/plain/a.js\"},\"cwd\":\"$TMP/plain\"}" "$TMP/plain"
assert_silent "filechange: outside CORTEX project is silent" "$OUT"
# git operations are NOT matched — detection is local ops only (rm / mv)
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git rm src/mapped.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: git rm is silent (git ops not matched)" "$OUT"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git mv src/mapped.js src/renamed.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: git mv is silent (git ops not matched)" "$OUT"
# non-matching bash command → silent
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: unrelated bash command is silent" "$OUT"
# plain (local) rm of a MAP-documented file → reminder, so the actor who
# deletes it keeps MAP.md accurate at that moment. MAP reflects what exists.
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm src/mapped.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_contains "filechange: plain rm of documented file triggers reminder" "$OUT" "MAP.md"
# plain rm with flags still detects the documented file
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -f src/mapped.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_contains "filechange: plain rm -f of documented file triggers reminder" "$OUT" "MAP.md"
# plain rm of an undocumented/scratch file → silent (no noise for cleanup)
echo "scratch" > "$TMP/fc/src/scratch.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm src/scratch.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: plain rm of undocumented file is silent" "$OUT"
# local mv of a documented file → reminder covering BOTH ends: the old entry is
# now stale, and the new path is not yet in MAP.md. The map must track reality.
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mv src/mapped.js src/renamed.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_contains "filechange: local mv of documented file triggers reminder" "$OUT" "MAP.md"
assert_contains "filechange: mv reminder names the source path" "$OUT" "src/mapped.js"
assert_contains "filechange: mv reminder names the dest path" "$OUT" "src/renamed.js"
# local mv creating a new undocumented path → reminder (the new file now exists,
# the map should reflect it — parity with how Write treats a new file)
echo "s" > "$TMP/fc/src/scratchmv.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mv src/scratchmv.js src/scratchmv2.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_contains "filechange: local mv to a new undocumented path reminds" "$OUT" "MAP.md"
# git mv already asserted silent above (git ops not matched); local mv into an
# excluded dest must not nag about the excluded path itself
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mv src/scratch.js node_modules/x.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: local mv of undocumented src into excluded dest is silent" "$OUT"
# malformed stdin → silent exit 0
OUT="$(echo "not json" | bash "$FILECHANGE_HOOK" 2>/dev/null)"; RC=$?
assert_exit0  "filechange: malformed stdin exits 0" "$RC"
assert_silent "filechange: malformed stdin is silent" "$OUT"

echo ""
echo "── cortex-subagent.sh ──"
run_hook "$SUBAGENT_HOOK" "{\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_exit0    "subagent: inside project exits 0" "$RC"
assert_contains "subagent: inside project injects CORTEX note" "$OUT" "MAP.md"
run_hook "$SUBAGENT_HOOK" "{\"cwd\":\"$TMP/plain\"}" "$TMP/plain"
assert_silent "subagent: outside CORTEX project is silent" "$OUT"
OUT="$(echo "garbage" | bash "$SUBAGENT_HOOK" 2>/dev/null)"; RC=$?
assert_exit0 "subagent: malformed stdin exits 0" "$RC"

echo ""
echo "── install.sh ──"
mkdir -p "$TMP/install-target"
bash "$REPO_ROOT/install.sh" --source "$REPO_ROOT" --agent claude "$TMP/install-target" >/dev/null 2>&1
SETTINGS="$TMP/install-target/.claude/settings.json"
OUT="$(jq -r '.hooks.PostToolUse[]?.hooks[]?.command' "$SETTINGS" 2>/dev/null)"
assert_contains "install: PostToolUse registered" "$OUT" "cortex-file-change.sh"
OUT="$(jq -r '.hooks.SubagentStart[]?.hooks[]?.command' "$SETTINGS" 2>/dev/null)"
assert_contains "install: SubagentStart registered" "$OUT" "cortex-subagent.sh"
OUT="$(jq -r '.hooks.PostToolUse[]? | select(.matcher=="Bash") | .hooks[]?.if' "$SETTINGS" 2>/dev/null)"
assert_contains     "install: Bash entry carries local rm if-filter" "$OUT" "Bash(rm *)"
assert_contains     "install: Bash entry carries local mv if-filter" "$OUT" "Bash(mv *)"
assert_not_contains "install: no git rm/git mv if-filter (local ops only)" "$OUT" "git"
[ -x "$TMP/install-target/.claude/hooks/cortex-file-change.sh" ] && OUT=ok || OUT=""
assert_contains "install: file-change script copied+executable" "$OUT" "ok"
# idempotence: run again, counts must not grow
bash "$REPO_ROOT/install.sh" --source "$REPO_ROOT" --agent claude "$TMP/install-target" >/dev/null 2>&1
N_POST="$(jq '[.hooks.PostToolUse[]?.hooks[]?] | length' "$SETTINGS")"
N_SUB="$(jq '[.hooks.SubagentStart[]?.hooks[]?] | length' "$SETTINGS")"
[ "$N_POST" -eq 3 ] && OUT=ok || OUT="PostToolUse count=$N_POST"
assert_contains "install: idempotent PostToolUse (3 entries)" "$OUT" "ok"
[ "$N_SUB" -eq 1 ] && OUT=ok || OUT="SubagentStart count=$N_SUB"
assert_contains "install: idempotent SubagentStart (1 entry)" "$OUT" "ok"
# OpenCode path byte-identical to v4.0 behavior
mkdir -p "$TMP/oc-target"
bash "$REPO_ROOT/install.sh" --source "$REPO_ROOT" --agent opencode "$TMP/oc-target" >/dev/null 2>&1
OUT="$(cat "$TMP/oc-target/opencode.json")"
assert_contains     "install: opencode instructions include MAP" "$OUT" ".cortex/MAP.md"
# SYSTEM.md is the file carrying the agent-agnostic §2.3 update-triggers table
# (create/rename/remove) — OpenCode's only parity mechanism for the same use
# cases Claude Code covers via active hooks. Must be loaded every session too.
assert_contains     "install: opencode instructions include SYSTEM.md" "$OUT" ".cortex/SYSTEM.md"
[ -d "$TMP/oc-target/.claude" ] && OUT="claude-dir-created" || OUT="ok"
assert_contains "install: opencode run does not create .claude/" "$OUT" "ok"

echo ""
echo "── walk-up loop termination (relative paths, no .cortex ancestor) ──"
# Regression for the reviewer-reported hang: dirname on a relative path
# (or ".") never reaches "/" or empty, so a naive walk-up loop spins
# forever. run_hook already wraps invocations in `timeout 5`, so a
# regression here fails fast (RC=124) instead of hanging the suite.
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"relative/foo.js\"},\"cwd\":\"$TMP\"}" "$TMP"
assert_exit0  "filechange: relative file_path with no .cortex ancestor returns promptly" "$RC"
assert_silent "filechange: relative file_path with no .cortex ancestor is silent" "$OUT"
run_hook "$SUBAGENT_HOOK" "{\"cwd\":\"relative\"}" "$TMP"
assert_exit0  "subagent: relative cwd with no .cortex ancestor returns promptly" "$RC"
assert_silent "subagent: relative cwd with no .cortex ancestor is silent" "$OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
