#!/usr/bin/env bash
# CORTEX — hook test harness. Pipe-tests every hook script with synthetic
# Claude Code hook payloads. No Claude session needed. Requires: bash, jq.
# Every block runs twice: in a git repo (MODE=git) and in a plain folder (MODE=plain).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ── Assertion helpers ─────────────────────────────────
assert_contains() { # name, haystack, needle
  if printf '%s\n' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1" "output does not contain: $3"; fi
}
assert_not_contains() { # name, haystack, needle
  if printf '%s\n' "$2" | grep -qF -- "$3"; then no "$1" "output unexpectedly contains: $3"; else ok "$1"; fi
}
assert_silent() { # name, output
  if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi
}
assert_eq() { # name, got, want
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "got [$2], want [$3]"; fi
}
assert_lt() { # name, num, limit — passes if num < limit
  if [ "$2" -lt "$3" ]; then ok "$1"; else no "$1" "$2 is not < $3"; fi
}
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
no() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# ── Fixture builder ───────────────────────────────────
# make_project DIR MODE — CORTEX project (git repo when MODE=git, plain folder otherwise)
make_project() {
  local dir="$1" mode="$2"
  mkdir -p "$dir/.cortex/map" "$dir/.cortex/scripts"
  [ "$mode" = git ] && git -C "$dir" init -q
  cp "$REPO_ROOT/.cortex/LOOKUP.md" "$REPO_ROOT/.cortex/MAINTAIN.md" "$dir/.cortex/"
  cp "$REPO_ROOT/.cortex/scripts/"*.sh "$dir/.cortex/scripts/"
}

# run_bounded CMD... — run with a time limit where `timeout` exists (exit 124 on expiry).
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 10 "$@"; else "$@"; fi
}

for MODE in git plain; do
  echo "── mode: $MODE ──"

  echo "SubagentStart"
  P="$TMP/sub-$MODE"; make_project "$P" "$MODE"
  SUB="$REPO_ROOT/.claude/hooks/cortex-subagent.sh"
  mkdir -p "$P/src"; out="$(printf '{"cwd":"%s/src"}' "$P" | bash "$SUB")"
  assert_contains "[$MODE] injects LOOKUP" "$out" "CORTEX — Finding things"
  assert_not_contains "[$MODE] no MAINTAIN in subagent" "$out" "Maintaining the map"
  assert_lt "[$MODE] subagent output < 2000 chars" "$(printf '%s' "$out" | wc -c)" 2000
  assert_silent "[$MODE] silent outside a CORTEX project" "$(printf '{"cwd":"%s"}' "$TMP/nowhere" | bash "$SUB")"

  # [RF 3] project root containing a space
  PS="$TMP/My Projects-$MODE/app"; make_project "$PS" "$MODE"; mkdir -p "$PS/src"
  out="$(printf '{"cwd":"%s/src"}' "$PS" | bash "$SUB")"
  assert_contains "[$MODE][RF3] injects LOOKUP under a path with spaces" "$out" "CORTEX — Finding things"

  # ── Error paths, both hooks ─────────────────────────
  # Garbage on stdin, or a relative cwd with no CORTEX ancestor: exit 0, no output, promptly.
  STOP="$REPO_ROOT/.claude/hooks/cortex-stop.sh"
  NOWHERE="$TMP/nowhere-$MODE"; mkdir -p "$NOWHERE"
  for H in "$SUB" "$STOP"; do
    hn="$(basename "$H")"
    o="$(cd "$NOWHERE" && printf 'not json {{{' | run_bounded bash "$H")"; rc=$?
    assert_eq "[$MODE] $hn: garbage stdin → exit 0" "$rc" 0
    assert_silent "[$MODE] $hn: garbage stdin → no output" "$o"
    o="$(cd "$NOWHERE" && printf '{"cwd":"relative"}' | run_bounded bash "$H")"; rc=$?
    assert_eq "[$MODE] $hn: relative cwd, no project → exit 0 promptly" "$rc" 0
    assert_silent "[$MODE] $hn: relative cwd, no project → no output" "$o"
  done

  echo "Stop"
  run_stop(){ printf '{"cwd":"%s","session_id":"s","stop_hook_active":%s}' "$1" "${2:-false}" | bash "$STOP"; }
  reason_of(){ printf '%s' "$1" | jq -r '.reason // empty'; }
  S="$TMP/stop-$MODE"; make_project "$S" "$MODE"; mkdir -p "$S/src"; printf 'x\n' > "$S/src/a.js"
  assert_silent "[$MODE] empty map → silent" "$(run_stop "$S")"
  CORTEX_ROOT="$S" bash "$S/.cortex/scripts/cortex-map.sh" --set src "Source."
  assert_silent "[$MODE] in sync → silent" "$(run_stop "$S")"
  mkdir -p "$S/src/new"; printf 'x\n' > "$S/src/new/b.js"
  o="$(run_stop "$S")"
  assert_contains "[$MODE] blocks on new folder" "$o" '"decision":"block"'
  assert_contains "[$MODE] suggests --set" "$o" "--set 'src/new'"
  r="$(reason_of "$o")"
  assert_contains "[$MODE] reason header" "$r" "CORTEX — describe the new folders before finishing this turn:"
  assert_contains "[$MODE] reason bullet" "$r" "• src/new"
  assert_contains "[$MODE] reason command" "$r" "    bash .cortex/scripts/cortex-map.sh --set 'src/new' '<role of this folder>'"
  assert_contains "[$MODE] reason closing rule" "$r" "Describe the folder's role in one line (max 120 chars). Never name files or list contents."
  assert_not_contains "[$MODE] nothing done automatically → no Done line" "$r" "Done automatically"
  assert_silent "[$MODE] stop_hook_active → silent" "$(run_stop "$S" true)"
  assert_silent "[$MODE] CORTEX_STOP_HOOK=0 → silent" "$(printf '{"cwd":"%s"}' "$S" | CORTEX_STOP_HOOK=0 bash "$STOP")"
  o="$(printf '{"cwd":"%s/src/new"}' "$S" | bash "$STOP")"
  assert_contains "[$MODE] finds the project walking up from a subfolder" "$o" "--set 'src/new'"

  # Rename and delete of described folders: reported, never blocking.
  R="$TMP/stop-mv-$MODE"; make_project "$R" "$MODE"
  mkdir -p "$R/keep" "$R/lib"; printf 'x\n' > "$R/keep/k.js"; printf 'x\n' > "$R/lib/a.js"; printf 'y\n' > "$R/lib/b.js"
  CORTEX_ROOT="$R" bash "$R/.cortex/scripts/cortex-map.sh" --set keep "Kept."
  CORTEX_ROOT="$R" bash "$R/.cortex/scripts/cortex-map.sh" --set lib "Library."
  assert_silent "[$MODE] snapshot run → silent" "$(run_stop "$R")"
  mv "$R/lib" "$R/core"
  o="$(run_stop "$R")"
  assert_eq "[$MODE] rename → systemMessage" "$(printf '%s' "$o" | jq -r '.systemMessage // empty')" "CORTEX map updated: moved lib → core"
  assert_not_contains "[$MODE] rename → no decision" "$o" '"decision"'
  rm -rf "$R/core"
  o="$(run_stop "$R")"
  assert_eq "[$MODE] delete → systemMessage" "$(printf '%s' "$o" | jq -r '.systemMessage // empty')" "CORTEX map updated: removed core"
  assert_not_contains "[$MODE] delete → no decision" "$o" '"decision"'
  # A rename alongside a new folder: blocks, and reports what was done.
  mkdir -p "$R/old" "$R/fresh"; printf 'x\n' > "$R/old/o.js"; printf 'x\n' > "$R/fresh/f.js"
  CORTEX_ROOT="$R" bash "$R/.cortex/scripts/cortex-map.sh" --set old "Old."
  CORTEX_ROOT="$R" bash "$R/.cortex/scripts/cortex-map.sh" --set fresh "Fresh."
  run_stop "$R" >/dev/null
  mv "$R/old" "$R/renamed"; rm -rf "$R/fresh"; mkdir -p "$R/added"; printf 'x\n' > "$R/added/x.js"
  r="$(reason_of "$(run_stop "$R")")"
  assert_contains "[$MODE] block lists the new folder" "$r" "• added"
  assert_contains "[$MODE] block reports what was done" "$r" "Done automatically: moved old → renamed; removed fresh"

  # More than 20 pending: capped, shallowest first.
  N="$TMP/stop-many-$MODE"; make_project "$N" "$MODE"
  mkdir -p "$N/src/a"; printf 'x\n' > "$N/src/a/x.js"
  CORTEX_ROOT="$N" bash "$N/.cortex/scripts/cortex-map.sh" --set src "Source."
  CORTEX_ROOT="$N" bash "$N/.cortex/scripts/cortex-map.sh" --set src/a "A."
  for i in $(seq -w 1 22); do mkdir -p "$N/src/a/x/y/c$i"; printf 'x\n' > "$N/src/a/x/y/c$i/f.js"; done
  mkdir -p "$N/src/z"; printf 'x\n' > "$N/src/z/f.js"
  r="$(reason_of "$(run_stop "$N")")"
  assert_eq "[$MODE] at most 20 folders listed" "$(printf '%s\n' "$r" | grep -c '^• ')" 20
  assert_eq "[$MODE] shallowest folder first" "$(printf '%s\n' "$r" | grep -m1 '^• ')" "• src/z"
  assert_contains "[$MODE] overflow line" "$r" "…and 5 more — run /cortex-sync"

  # More than 20 automatic changes: the Done list is capped the same way.
  D="$TMP/stop-done-$MODE"; make_project "$D" "$MODE"
  for i in $(seq -w 1 23); do mkdir -p "$D/d$i"; printf 'x\n' > "$D/d$i/f.js"; CORTEX_ROOT="$D" bash "$D/.cortex/scripts/cortex-map.sh" --set "d$i" "D."; done
  run_stop "$D" >/dev/null
  for i in $(seq -w 1 23); do rm -rf "$D/d$i"; done
  m="$(run_stop "$D" | jq -r '.systemMessage // empty')"
  assert_eq "[$MODE] done list capped at 20" "$(printf '%s\n' "$m" | grep -o 'removed d' | wc -l | tr -d ' ')" 20
  assert_contains "[$MODE] done overflow" "$m" "…and 3 more"
  mkdir -p "$D/e"; printf 'x\n' > "$D/e/f"; CORTEX_ROOT="$D" bash "$D/.cortex/scripts/cortex-map.sh" --set e "E."
  for i in $(seq -w 1 23); do mkdir -p "$D/d$i"; printf 'x\n' > "$D/d$i/f.js"; CORTEX_ROOT="$D" bash "$D/.cortex/scripts/cortex-map.sh" --set "d$i" "D."; done
  run_stop "$D" >/dev/null
  for i in $(seq -w 1 23); do rm -rf "$D/d$i"; done; mkdir -p "$D/e/new"; printf 'x\n' > "$D/e/new/f"
  r="$(reason_of "$(run_stop "$D")")"
  assert_eq "[$MODE] block done list capped at 20" "$(printf '%s\n' "$r" | grep -o 'removed d' | wc -l | tr -d ' ')" 20
  assert_contains "[$MODE] block done overflow" "$r" "…and 3 more"

  # [RF 1] hostile folder name: the suggested command is valid shell, $(id) stays literal.
  Q="$TMP/stop-q-$MODE"; make_project "$Q" "$MODE"; mkdir -p "$Q/src"; printf 'x\n' > "$Q/src/a.js"
  CORTEX_ROOT="$Q" bash "$Q/.cortex/scripts/cortex-map.sh" --set src "Source."
  mkdir -p "$Q/src/it's \$(id)"; printf 'x\n' > "$Q/src/it's \$(id)/f.js"
  line="$(reason_of "$(run_stop "$Q")" | grep -F -- '--set')"
  if [ -n "$line" ] && bash -n -c "$line" 2>/dev/null; then ok "[$MODE][RF1] suggested line is valid shell"; else no "[$MODE][RF1] suggested line is valid shell" "[$line]"; fi
  assert_contains "[$MODE][RF1] \$(id) appears literally" "$line" '$(id)'
  eval "set -- $line"
  assert_eq "[$MODE][RF1] the folder argument round-trips" "${4:-}" "src/it's \$(id)"

  if [ "$MODE" = git ]; then
    G="$TMP/stop-ign-$MODE"; make_project "$G" "$MODE"; mkdir -p "$G/src"; printf 'x\n' > "$G/src/a.js"
    CORTEX_ROOT="$G" bash "$G/.cortex/scripts/cortex-map.sh" --set src "Source."
    printf 'ignored/\n' > "$G/.gitignore"; mkdir -p "$G/ignored"; printf 'x\n' > "$G/ignored/f.js"
    assert_silent "[$MODE] new gitignored folder → silent" "$(run_stop "$G")"
  fi

  if [ "$MODE" = git ]; then
    # Committed folders renamed or deleted with plain mv/rm (nothing staged):
    # the index still lists the old paths, which must never be pending.
    C="$TMP/stop-commit-$MODE"; make_project "$C" "$MODE"; mkdir -p "$C/src" "$C/ghost" "$C/keep"
    printf 'x\n' > "$C/src/a.js"; printf 'x\n' > "$C/ghost/g.js"; printf 'x\n' > "$C/keep/k.js"
    for d in src ghost keep; do CORTEX_ROOT="$C" bash "$C/.cortex/scripts/cortex-map.sh" --set "$d" "D $d."; done
    git -C "$C" add -A; git -C "$C" -c user.email=t@t -c user.name=t commit -qm init
    assert_silent "[$MODE] committed: snapshot run → silent" "$(run_stop "$C")"
    mv "$C/src" "$C/source"; rm -rf "$C/ghost"
    o="$(run_stop "$C")"
    assert_eq "[$MODE] committed: rename + removal reported" "$(printf '%s' "$o" | jq -r '.systemMessage // empty')" "CORTEX map updated: moved src → source; removed ghost"
    assert_not_contains "[$MODE] committed: no block" "$o" '"decision"'
    assert_not_contains "[$MODE] committed: old path not suggested" "$o" "--set 'src'"
    assert_silent "[$MODE] committed: next turn silent" "$(run_stop "$C")"
    assert_eq "[$MODE] committed: drift empty" "$(CORTEX_ROOT="$C" bash "$C/.cortex/scripts/cortex-map.sh" --drift)" ""
    mkdir -p "$C/staged"; printf 'x\n' > "$C/staged/f"; git -C "$C" add staged; rm -rf "$C/staged"
    assert_silent "[$MODE] staged-then-deleted folder → silent" "$(run_stop "$C")"
  fi

  # [RF 3] project root containing a space
  SP="$TMP/My Projects-stop-$MODE/app"; make_project "$SP" "$MODE"; mkdir -p "$SP/src"; printf 'x\n' > "$SP/src/a.js"
  CORTEX_ROOT="$SP" bash "$SP/.cortex/scripts/cortex-map.sh" --set src "Source."
  mkdir -p "$SP/src/new"; printf 'x\n' > "$SP/src/new/b.js"
  o="$(run_stop "$SP")"
  assert_contains "[$MODE][RF3] blocks under a path with spaces" "$o" '"decision":"block"'
  assert_contains "[$MODE][RF3] lists the new folder" "$o" "--set 'src/new'"
done

echo "Settings"
SET="$REPO_ROOT/.claude/settings.json"
assert_eq "settings: only Stop and SubagentStart hooks" "$(jq -r '.hooks|keys|join(",")' "$SET")" "Stop,SubagentStart"
cmds="$(jq -r '.. | .command? // empty' "$SET")"
assert_not_contains "settings: no cortex-session hook" "$cmds" "cortex-session"
assert_not_contains "settings: no cortex-file-change hook" "$cmds" "cortex-file-change"
assert_contains "settings: Stop runs cortex-stop.sh" "$(jq -r '.hooks.Stop[].hooks[].command' "$SET")" "bash .claude/hooks/cortex-stop.sh"
assert_contains "settings: SubagentStart runs cortex-subagent.sh" "$(jq -r '.hooks.SubagentStart[].hooks[].command' "$SET")" "bash .claude/hooks/cortex-subagent.sh"

echo "Rule and template"
for f in $(sed 's/^@//' "$REPO_ROOT/.claude/rules/cortex.md"); do
  [ -f "$REPO_ROOT/.claude/rules/$f" ] && ok "rule import resolves: $f" || no "rule import resolves: $f" "missing"
done
assert_contains "template conventions placeholder" "$(cat "$REPO_ROOT/templates/PROJECT.md")" "_None yet._"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] && echo "0 failed"
exit "$FAIL"
