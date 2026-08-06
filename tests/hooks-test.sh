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
  if echo "$2" | grep -qF -- "$3"; then
    echo "  PASS: $1"; PASS=$((PASS+1))
  else
    echo "  FAIL: $1 — output does not contain: $3"; FAIL=$((FAIL+1))
  fi
}
assert_not_contains() { # name, haystack, needle
  if echo "$2" | grep -qF -- "$3"; then
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
ok() { # name
  echo "  PASS: $1"; PASS=$((PASS+1))
}
no() { # name, detail
  echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1))
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
# missing-MAP fallback: points at /cortex-sync
rm "$TMP/single/.cortex/MAP.md"
run_hook "$SESSION_HOOK" "{\"cwd\":\"$TMP/single\"}" "$TMP/single"
assert_contains "session: missing MAP falls back to /cortex-sync hint" "$OUT" "cortex-sync"

echo ""
echo "── cortex-file-change.sh ──"
make_project "$TMP/fc"
# new unmapped file → silent (collector never emits reminders; the Stop hook decides)
echo "new" > "$TMP/fc/src/brandnew.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/src/brandnew.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_exit0    "filechange: new unmapped exits 0" "$RC"
assert_silent   "filechange: new unmapped file is silent (collector, not a reminder)" "$OUT"
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
# plain (local) rm of a MAP-documented file → silent (recorded as D, not reminded;
# the Stop hook — task 12 — is what evaluates the record)
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm src/mapped.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: plain rm of documented file is silent" "$OUT"
# plain rm with flags still detects the documented file
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -f src/mapped.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: plain rm -f of documented file is silent" "$OUT"
# plain rm of an undocumented/scratch file → silent (no noise for cleanup)
echo "scratch" > "$TMP/fc/src/scratch.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm src/scratch.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: plain rm of undocumented file is silent" "$OUT"
# local mv of a documented file → silent (both ends recorded: D for the source,
# T for the destination — the Stop hook decides what to do with the record)
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mv src/mapped.js src/renamed.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: local mv of documented file is silent" "$OUT"
# local mv creating a new undocumented path → silent (recorded as T for the
# destination — parity with how Write is recorded for a new file)
echo "s" > "$TMP/fc/src/scratchmv.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mv src/scratchmv.js src/scratchmv2.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: local mv to a new undocumented path is silent" "$OUT"
# git mv already asserted silent above (git ops not matched); local mv into an
# excluded dest must not nag about the excluded path itself
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"mv src/scratch.js node_modules/x.js\"},\"cwd\":\"$TMP/fc\"}" "$TMP/fc"
assert_silent "filechange: local mv of undocumented src into excluded dest is silent" "$OUT"
# malformed stdin → silent exit 0
OUT="$(echo "not json" | bash "$FILECHANGE_HOOK" 2>/dev/null)"; RC=$?
assert_exit0  "filechange: malformed stdin exits 0" "$RC"
assert_silent "filechange: malformed stdin is silent" "$OUT"

echo ""
echo "── cortex-file-change.sh: writes outside the project root ──"
# Critical regression: a Write to a path outside $PROJ (e.g. /tmp/scratch.js)
# must never be recorded verbatim. If it were, the Stop hook would surface it
# as a "folder" to --set, and --set "/tmp" would render a malformed empty
# root component via the ancestor-expansion awk, permanently breaking
# --validate with no sanctioned repair (MAP.md hand-editing is forbidden).
OUTSIDE_TARGET="/tmp/cortex-regression-outside-$$.js"
echo "x" > "$OUTSIDE_TARGET"
REC_OUT="$TMP/fc/.cortex/.touched-outsidetest"
rm -f "$REC_OUT"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$OUTSIDE_TARGET\"},\"cwd\":\"$TMP/fc\",\"session_id\":\"outsidetest\"}" "$TMP/fc"
assert_silent "filechange: write outside project root is silent" "$OUT"
[ ! -s "$REC_OUT" ] && ok "filechange: write outside project root is not recorded" \
  || no "filechange: write outside project root is not recorded" "$(cat "$REC_OUT" 2>/dev/null)"
rm -f "$OUTSIDE_TARGET"

# Defense in depth: even if such an entry ever reached the touch record (e.g.
# from a pre-fix session, or a future caller that bypasses the hook), the
# Stop hook must not turn it into a block — it must stay silent, and the
# only real fix is that cortex-map.sh itself now refuses the absolute-path
# --set the Stop hook would otherwise suggest (see map-test.sh).
printf 'T\t/tmp/x/y.js\n' > "$REC_OUT"
STOP_HOOK_FOR_OUTSIDE="$REPO_ROOT/.claude/hooks/cortex-stop.sh"
cp "$REPO_ROOT/.cortex/scripts/cortex-map.sh"  "$TMP/fc/.cortex/scripts/" 2>/dev/null || mkdir -p "$TMP/fc/.cortex/scripts"
cp "$REPO_ROOT/.cortex/scripts/cortex-map.sh"  "$TMP/fc/.cortex/scripts/"
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$TMP/fc/.cortex/scripts/"
stopout="$(printf '{"cwd":"%s","session_id":"outsidetest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_not_contains "stop: a stray absolute-path record never triggers a block on '/tmp'" "$stopout" '"decision":"block"'
rm -f "$REC_OUT"

REC_DOT="$TMP/fc/.cortex/.touched-dottest"
printf 'T\t./src/x.js\n' > "$REC_DOT"
dotstopout="$(printf '{"cwd":"%s","session_id":"dottest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_not_contains "stop: a stray dot-prefixed record never triggers a block" "$dotstopout" '"decision":"block"'
rm -f "$REC_DOT"

# A space in a folder name IS representable in MAP.md — map_parse ends a name at
# its slash — so reject_escaped() must pass it through and the Stop hook must
# surface it. Dropping it would leave the folder permanently unmappable with no
# signal that anything was skipped.
REC_WS="$TMP/fc/.cortex/.touched-wstest"
printf 'T\tmy docs/f.js\n' > "$REC_WS"
wsstopout="$(printf '{"cwd":"%s","session_id":"wstest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_contains "stop: a space-named folder is surfaced, not silently skipped" "$wsstopout" 'my docs'
rm -f "$REC_WS"

# A control character is the genuinely unrepresentable case, and it stays
# filtered: validate_target() refuses it, so surfacing one would hand the agent
# a --set that cannot succeed.
REC_CTL="$TMP/fc/.cortex/.touched-ctltest"
printf 'T\tsrc/a\rb/f.js\n' > "$REC_CTL"
ctlstopout="$(printf '{"cwd":"%s","session_id":"ctltest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_not_contains "stop: a stray control-character record never triggers a block" "$ctlstopout" '"decision":"block"'
rm -f "$REC_CTL"

# The suggested commands are meant to be run verbatim by an agent, so the folder
# has to be a single-quoted shell literal. Double quotes let a name like $(id)
# or one holding a backtick execute, and a name holding a double quote produces
# shell the agent simply cannot run. Neither is hypothetical: both shapes are
# legal folder names and both round-trip through MAP.md.
REC_INJ="$TMP/fc/.cortex/.touched-injtest"
printf 'T\t$(id)/f.js\n' > "$REC_INJ"
injout="$(printf '{"cwd":"%s","session_id":"injtest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_contains "stop: suggests a single-quoted target" "$injout" "--set '\$(id)'"
assert_not_contains "stop: never suggests a double-quoted target a shell would expand" "$injout" '--set \"$(id)\"'
rm -f "$REC_INJ"

REC_DQ="$TMP/fc/.cortex/.touched-dqtest"
printf 'T\tsay"hi/f.js\n' > "$REC_DQ"
dqout="$(printf '{"cwd":"%s","session_id":"dqtest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_contains "stop: a double-quote in a folder name stays inside single quotes" "$dqout" "--set 'say\\\"hi'"
rm -f "$REC_DQ"

# The hook must never suggest a command cortex-map.sh would refuse. It used to
# re-derive a subset of the representability rule in reject_escaped(), which is
# the same drift behind every earlier bug in this family — it now asks --check.
REC_UNREP="$TMP/fc/.cortex/.touched-unreptest"
printf 'T\t lead/f.js\nT\t#tmp/g.js\n' > "$REC_UNREP"
unrepout="$(printf '{"cwd":"%s","session_id":"unreptest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_not_contains "stop: never suggests --set for a leading-space folder" "$unrepout" "--set ' lead'"
assert_not_contains "stop: never suggests --set for a '#'-prefixed top-level folder" "$unrepout" "--set '#tmp'"
rm -f "$REC_UNREP"

REC_SQ="$TMP/fc/.cortex/.touched-sqtest"
printf "T\tit's/f.js\n" > "$REC_SQ"
sqout="$(printf '{"cwd":"%s","session_id":"sqtest","stop_hook_active":false}' "$TMP/fc" | bash "$STOP_HOOK_FOR_OUTSIDE" 2>/dev/null)"
assert_contains "stop: an apostrophe in a folder name is escaped, not left open" "$sqout" "'it'\\\\''s'"
rm -f "$REC_SQ"

echo ""
echo "── cortex-file-change.sh: embedded and leading '.'/'..' segments ──"
REC_NORM="$TMP/fc/.cortex/.touched-normtest"

rm -f "$REC_NORM"
echo x > "$TMP/fc/src/h.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/src/../src/h.js\"},\"cwd\":\"$TMP/fc\",\"session_id\":\"normtest\"}" "$TMP/fc"
assert_contains "embedded ../ normalizes to the real path" "$(cat "$REC_NORM" 2>/dev/null)" "T	src/h.js"

rm -f "$REC_NORM"
echo x > "$TMP/fc/src/g.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/./src/g.js\"},\"cwd\":\"$TMP/fc\",\"session_id\":\"normtest\"}" "$TMP/fc"
assert_contains "leading ./ normalizes away" "$(cat "$REC_NORM" 2>/dev/null)" "T	src/g.js"

rm -f "$REC_NORM"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/src/api/../../../outside.js\"},\"cwd\":\"$TMP/fc\",\"session_id\":\"normtest\"}" "$TMP/fc"
[ ! -s "$REC_NORM" ] && ok "path escaping above the project via three .. segments is not recorded" \
  || no "path escaping above the project via three .. segments is not recorded" "$(cat "$REC_NORM")"

# A space round-trips through MAP.md, so record() must keep it: dropping it here
# would hide the folder from the Stop hook and leave it silently unmapped. Only
# a control character is refused — a literal tab inside the path would be
# mistaken for the record's own mark/path delimiter by every consumer. Same
# [[:cntrl:]] rule as validate_target() in cortex-map.sh.
rm -f "$REC_NORM"
mkdir -p "$TMP/fc/my docs"
echo x > "$TMP/fc/my docs/f.js"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMP/fc/my docs/f.js\"},\"cwd\":\"$TMP/fc\",\"session_id\":\"normtest\"}" "$TMP/fc"
assert_contains "a path containing a space is recorded verbatim" "$(cat "$REC_NORM" 2>/dev/null)" "T	my docs/f.js"

rm -f "$REC_NORM"
TABPATH="$TMP/fc/src/a$(printf '\t')b/f.js"
mkdir -p "$(dirname "$TABPATH")"
echo x > "$TABPATH"
run_hook "$FILECHANGE_HOOK" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TABPATH\"},\"cwd\":\"$TMP/fc\",\"session_id\":\"normtest\"}" "$TMP/fc"
[ ! -s "$REC_NORM" ] && ok "a path containing a literal tab is not recorded" \
  || no "a path containing a literal tab is not recorded" "$(cat "$REC_NORM")"

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
echo "== session: injects all three files =="
SESS="$REPO_ROOT/.claude/hooks/cortex-session.sh"
SP="$TMP/sessproj"; mkdir -p "$SP/.cortex"
printf 'SYSTEM MARKER\n' > "$SP/.cortex/SYSTEM.md"
printf 'PROJECT MARKER\n' > "$SP/.cortex/PROJECT.md"
printf 'MAP MARKER\n'     > "$SP/.cortex/MAP.md"
sout="$(printf '{"cwd":"%s"}' "$SP" | bash "$SESS")"
assert_contains "session injects SYSTEM.md" "$sout" "SYSTEM MARKER"
assert_contains "session injects PROJECT.md" "$sout" "PROJECT MARKER"
assert_contains "session injects MAP.md" "$sout" "MAP MARKER"

echo "== session: no drift check, no script execution =="
assert_not_contains "session does not mention drift" "$sout" "drift"
assert_not_contains "session does not run cortex-map" "$sout" "cortex-map.sh --"

echo "== session: missing MAP.md points at cortex-sync =="
SP2="$TMP/sessproj2"; mkdir -p "$SP2/.cortex"
printf 'SYSTEM MARKER\n' > "$SP2/.cortex/SYSTEM.md"
sout2="$(printf '{"cwd":"%s"}' "$SP2" | bash "$SESS")"
assert_contains "suggests cortex-sync when map absent" "$sout2" "/cortex-sync"
assert_not_contains "does not mention cortex-init" "$sout2" "cortex-init"

echo "== session: non-CORTEX dir is silent =="
SP3="$TMP/notcortex"; mkdir -p "$SP3"
sout3="$(printf '{"cwd":"%s"}' "$SP3" | bash "$SESS")"
assert_silent "non-CORTEX dir silent" "$sout3"

echo ""
echo "== subagent: gets the same full context as session start =="
SUB="$REPO_ROOT/.claude/hooks/cortex-subagent.sh"
SP="$TMP/subproj"; mkdir -p "$SP/.cortex"
printf 'SYSTEM MARKER\n' > "$SP/.cortex/SYSTEM.md"
printf 'PROJECT MARKER\n' > "$SP/.cortex/PROJECT.md"
printf 'MAP MARKER\n'     > "$SP/.cortex/MAP.md"
subout="$(printf '{"cwd":"%s"}' "$SP" | bash "$SUB")"
assert_contains "subagent gets SYSTEM.md" "$subout" "SYSTEM MARKER"
assert_contains "subagent gets PROJECT.md" "$subout" "PROJECT MARKER"
assert_contains "subagent gets MAP.md" "$subout" "MAP MARKER"
assert_contains "declares SubagentStart event" "$subout" "SubagentStart"

echo "== subagent: non-CORTEX dir is silent =="
SP3="$TMP/notcortex2"; mkdir -p "$SP3"
subout2="$(printf '{"cwd":"%s"}' "$SP3" | bash "$SUB")"
assert_silent "subagent silent outside CORTEX" "$subout2"

echo "== collector: records writes and edits identically as T =="
FC="$REPO_ROOT/.claude/hooks/cortex-file-change.sh"
CP="$TMP/collproj"; mkdir -p "$CP/.cortex/scripts" "$CP/src/api"
printf 'x\n' > "$CP/.cortex/SYSTEM.md"
REC="$CP/.cortex/.touched-sess1"
rm -f "$REC"
wout="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/api/h.js"},"cwd":"%s","session_id":"sess1"}' "$CP" "$CP" | bash "$FC")"
eout="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/api/g.js"},"cwd":"%s","session_id":"sess1"}' "$CP" "$CP" | bash "$FC")"
assert_silent "collector emits nothing on Write" "$wout"
assert_silent "collector emits nothing on Edit" "$eout"
assert_contains "Write recorded as T" "$(cat "$REC")" "T	src/api/h.js"
assert_contains "Edit recorded as T" "$(cat "$REC")" "T	src/api/g.js"

echo "== collector: manifests marked M, not T =="
rm -f "$REC"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/package.json"},"cwd":"%s","session_id":"sess1"}' "$CP" "$CP" | bash "$FC" >/dev/null
assert_contains "manifest recorded as M" "$(cat "$REC")" "M	package.json"
assert_not_contains "manifest not recorded as T" "$(cat "$REC")" "T	package.json"

echo "== collector: rm recorded as D, multiple args =="
rm -f "$REC"
printf '{"tool_name":"Bash","tool_input":{"command":"rm -f src/api/a.js src/api/b.js"},"cwd":"%s","session_id":"sess1"}' "$CP" | bash "$FC" >/dev/null
assert_contains "first rm arg recorded" "$(cat "$REC")" "D	src/api/a.js"
assert_contains "second rm arg recorded" "$(cat "$REC")" "D	src/api/b.js"

echo "== collector: mv records source as D and destination as T =="
rm -f "$REC"
printf '{"tool_name":"Bash","tool_input":{"command":"mv src/api/old.js src/core/new.js"},"cwd":"%s","session_id":"sess1"}' "$CP" | bash "$FC" >/dev/null
assert_contains "mv source recorded as D" "$(cat "$REC")" "D	src/api/old.js"
assert_contains "mv destination recorded as T" "$(cat "$REC")" "T	src/core/new.js"

echo "== collector: excluded paths ignored =="
rm -f "$REC"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.cortex/MAP.md"},"cwd":"%s","session_id":"sess1"}' "$CP" "$CP" | bash "$FC" >/dev/null
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/node_modules/x/i.js"},"cwd":"%s","session_id":"sess1"}' "$CP" "$CP" | bash "$FC" >/dev/null
[ ! -s "$REC" ] && ok "excluded paths produce no record" || no "excluded paths produce no record" "$(cat "$REC")"

echo "== collector: records are per-session =="
rm -f "$REC" "$CP/.cortex/.touched-sess2"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/api/s1.js"},"cwd":"%s","session_id":"sess1"}' "$CP" "$CP" | bash "$FC" >/dev/null
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/api/s2.js"},"cwd":"%s","session_id":"sess2"}' "$CP" "$CP" | bash "$FC" >/dev/null
assert_contains "sess1 has its own file" "$(cat "$REC")" "s1.js"
assert_not_contains "sess1 does not see sess2" "$(cat "$REC")" "s2.js"

echo "== collector: non-CORTEX project ignored =="
NC="$TMP/nocortex"; mkdir -p "$NC/src"
nout="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/x.js"},"cwd":"%s","session_id":"sess1"}' "$NC" "$NC" | bash "$FC")"
assert_silent "non-CORTEX silent" "$nout"
[ ! -f "$NC/.cortex/.touched-sess1" ] && ok "no record outside CORTEX" || no "no record outside CORTEX" "record created"

echo "== stop: silent when the record is empty =="
STOP="$REPO_ROOT/.claude/hooks/cortex-stop.sh"
STP="$TMP/stopproj"; mkdir -p "$STP/.cortex/scripts" "$STP/src/api"
cp "$REPO_ROOT/.cortex/scripts/cortex-map.sh"  "$STP/.cortex/scripts/"
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$STP/.cortex/scripts/"
printf 'x\n' > "$STP/.cortex/SYSTEM.md"
printf '# Knowledge Map\n\n> map\n\nsrc/  Application source.\n  api/  HTTP handlers.\n' > "$STP/.cortex/MAP.md"
SREC="$STP/.cortex/.touched-s1"
rm -f "$SREC"
o1="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_silent "empty record is silent" "$o1"

echo "== stop: blocks and names a missing folder =="
printf 'T\tsrc/billing/invoice.js\n' > "$SREC"
o2="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_contains "blocks" "$o2" '"decision":"block"'
assert_contains "names the missing folder" "$o2" "src/billing"
assert_contains "tells it to use --set" "$o2" "--set"
[ ! -s "$SREC" ] && ok "record truncated after blocking" || no "record truncated after blocking" "record still populated"

echo "== stop: reports a mapped folder for review with its description =="
printf 'T\tsrc/api/new.js\n' > "$SREC"
o3="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_contains "quotes the current description" "$o3" "HTTP handlers."
assert_contains "names the folder" "$o3" "src/api"

echo "== stop: reports an emptied folder for removal =="
mkdir -p "$STP/src/gone"
printf '# Knowledge Map\n\n> map\n\nsrc/  Application source.\n  api/  HTTP handlers.\n  gone/  Old module.\n' > "$STP/.cortex/MAP.md"
printf 'D\tsrc/gone/old.js\n' > "$SREC"
o4="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_contains "suggests --remove for the emptied folder" "$o4" "--remove"
assert_contains "names the emptied folder" "$o4" "src/gone"

echo "== stop: manifest routes to PROJECT.md =="
printf 'M\tpackage.json\n' > "$SREC"
o5="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_contains "mentions PROJECT.md" "$o5" "PROJECT.md"
assert_contains "mentions Tech Stack" "$o5" "Tech Stack"

echo "== stop: does not block twice in a turn =="
printf 'T\tsrc/billing/invoice.js\n' > "$SREC"
o6="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":true}' "$STP" | bash "$STOP")"
assert_silent "stop_hook_active suppresses a second block" "$o6"

echo "== stop: is stateless — same folder reported again on a later turn =="
printf 'T\tsrc/api/another.js\n' > "$SREC"
o7="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_contains "same folder reported again (statelessness is the contract)" "$o7" "src/api"

echo "== stop: takes no action when the map is malformed =="
BADP="$TMP/badmap"; mkdir -p "$BADP/.cortex/scripts"
cp "$REPO_ROOT/.cortex/scripts/cortex-map.sh" "$BADP/.cortex/scripts/"
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$BADP/.cortex/scripts/"
printf 'x\n' > "$BADP/.cortex/SYSTEM.md"
printf '# m\n\nsrc/  Source.\n   api/  Odd indent.\n' > "$BADP/.cortex/MAP.md"
printf 'T\tsrc/api/x.js\n' > "$BADP/.cortex/.touched-s1"
o8="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$BADP" | bash "$STOP")"
assert_not_contains "does not block on a malformed map" "$o8" '"decision":"block"'
assert_contains "reports the format problem" "$o8" "validate"

echo "== stop: reports all missing ancestors at once =="
printf 'T\tlib/vendor/acme/client.js\n' > "$SREC"
o9="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_contains "reports lib" "$o9" "lib"
assert_contains "reports lib/vendor" "$o9" "lib/vendor"
assert_contains "reports lib/vendor/acme" "$o9" "lib/vendor/acme"

echo "== stop: opt-out env var =="
printf 'T\tsrc/billing/invoice.js\n' > "$SREC"
o10="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | CORTEX_STOP_HOOK=0 bash "$STOP")"
assert_silent "CORTEX_STOP_HOOK=0 disables the hook" "$o10"

echo "== stop: root-level file touch is silent (no bogus folder) =="
printf 'T\tREADME.md\n' > "$SREC"
o11="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_silent "root-level file does not surface a folder report" "$o11"

echo "== stop: malformed map does not discard the turn's record =="
printf 'T\tsrc/api/x.js\n' > "$BADP/.cortex/.touched-s1"
o12="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$BADP" | bash "$STOP")"
[ -s "$BADP/.cortex/.touched-s1" ] && ok "record survives the malformed-map turn" \
  || no "record survives the malformed-map turn" "record was truncated"

echo "== stop: rm -rf of a whole mapped directory suggests --remove for it =="
mkdir -p "$STP/src/full"
printf '# Knowledge Map\n\n> map\n\nsrc/  Application source.\n  api/  HTTP handlers.\n  gone/  Old module.\n  full/  Fully removed module.\n' > "$STP/.cortex/MAP.md"
rmdir "$STP/src/full"
printf 'D\tsrc/full\n' > "$SREC"
o13="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_contains "suggests --remove for the deleted directory itself" "$o13" '--remove'
assert_contains "names the deleted directory itself" "$o13" "src/full"

echo "== stop: partial deletion (folder still has other files) suggests nothing =="
mkdir -p "$STP/src/keep"
printf '# Knowledge Map\n\n> map\n\nsrc/  Application source.\n  api/  HTTP handlers.\n  gone/  Old module.\n  keep/  Partially cleaned module.\n' > "$STP/.cortex/MAP.md"
printf 'one\n' > "$STP/src/keep/one.js"
printf 'two\n' > "$STP/src/keep/two.js"
rm "$STP/src/keep/one.js"
printf 'D\tsrc/keep/one.js\n' > "$SREC"
o14="$(printf '{"cwd":"%s","session_id":"s1","stop_hook_active":false}' "$STP" | bash "$STOP")"
assert_not_contains "no removal suggestion while other files remain" "$o14" "src/keep — no longer holds files"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
