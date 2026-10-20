#!/usr/bin/env bash
# CORTEX — installer test harness (installs only into temp dirs).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); }
assert_eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$3] got [$2]"; }
assert_has(){ echo "$2" | grep -qF -- "$3" && ok "$1" || no "$1" "missing [$3]"; }
assert_no(){ echo "$2" | grep -qF -- "$3" && no "$1" "unexpected [$3]" || ok "$1"; }

I="$REPO_ROOT/install.sh"

for MODE in git plain; do
  echo "== install: $MODE =="
  T="$TMP/app-$MODE"; mkdir -p "$T"; [ "$MODE" = git ] && git -C "$T" init -q
  bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1
  assert_eq "[$MODE] PROJECT title from template" "$(head -1 "$T/.cortex/PROJECT.md")" "# Project — app-$MODE"
  assert_has "[$MODE] conventions empty" "$(cat "$T/.cortex/PROJECT.md")" "_None yet._"
  assert_eq "[$MODE] no source map copied" "$(find "$T/.cortex/map" -type f | wc -l | tr -d ' ')" "0"
  assert_eq "[$MODE] no state copied" "$([ -e "$T/.cortex/.state" ] && echo y || echo n)" "n"
  assert_eq "[$MODE] describe script is executable" "$([ -x "$T/.cortex/scripts/cortex-describe.sh" ] && echo y || echo n)" "y"
  assert_has "[$MODE] claude sync command drives the queue" "$(cat "$T/.claude/commands/cortex-sync.md")" "cortex-describe.sh --status"
  assert_has "[$MODE] opencode sync command drives the queue" "$(cat "$T/.opencode/commands/cortex-sync.md")" "cortex-describe.sh --status"
  assert_eq "[$MODE] hooks" "$(jq -r '.hooks|keys|join(",")' "$T/.claude/settings.json")" "Stop,SubagentStart"
  assert_has "[$MODE] rule" "$(cat "$T/.claude/rules/cortex.md")" "@../../.cortex/LOOKUP.md"
  assert_has "[$MODE] opencode" "$(jq -r '.instructions|join(",")' "$T/opencode.json")" ".cortex/MAINTAIN.md"
  assert_eq "[$MODE] no v5 files" "$(ls "$T/.cortex/SYSTEM.md" "$T/.cortex/MAP.md" "$T/.claude/hooks/cortex-session.sh" 2>/dev/null | wc -l | tr -d ' ')" "0"
  assert_eq "[$MODE] no .touched" "$([ -e "$T/.cortex/.touched" ] && echo y || echo n)" "n"
  assert_eq "[$MODE] scripts + hooks installed" "$(ls "$T/.cortex/LOOKUP.md" "$T/.cortex/MAINTAIN.md" "$T/.cortex/scripts/cortex-scan.sh" "$T/.cortex/scripts/cortex-map.sh" "$T/.cortex/scripts/cortex-describe.sh" "$T/.claude/hooks/cortex-stop.sh" "$T/.claude/hooks/cortex-subagent.sh" "$T/.claude/commands/cortex-sync.md" "$T/.opencode/commands/cortex-sync.md" | wc -l | tr -d ' ')" "9"
done
assert_has "git: .state ignored" "$(cat "$TMP/app-git/.gitignore")" ".cortex/.state/"
assert_eq "plain: no .gitignore entry for state" "$(grep -qF '.cortex/.state/' "$TMP/app-plain/.gitignore" 2>/dev/null && echo 1 || echo 0)" "0"

echo "== idempotence =="
T="$TMP/app-git"
before="$(cat "$T/.claude/settings.json" "$T/.gitignore" "$T/opencode.json")"
bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_eq "second run changes nothing" "$(cat "$T/.claude/settings.json" "$T/.gitignore" "$T/opencode.json")" "$before"
assert_eq "state entry once" "$(grep -cF '.cortex/.state/' "$T/.gitignore")" "1"

echo "== foreign hook + existing PROJECT.md =="
T="$TMP/foreign"; mkdir -p "$T/.claude" "$T/.cortex"
cat > "$T/.claude/settings.json" <<'J'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]},"other":1}
J
printf 'MY PROJECT\n' > "$T/.cortex/PROJECT.md"
bash "$I" --agent claude --source "$REPO_ROOT" "$T" >/dev/null 2>&1
bash "$I" --agent claude --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_has "foreign hook kept" "$(jq -r '[.hooks.Stop[].hooks[].command]|join("|")' "$T/.claude/settings.json")" "echo mine"
assert_eq "cortex stop once" "$(jq -r '[.hooks.Stop[].hooks[].command]|map(select(test("cortex-stop")))|length' "$T/.claude/settings.json")" "1"
assert_eq "unrelated key kept" "$(jq -r '.other' "$T/.claude/settings.json")" "1"
assert_eq "PROJECT.md untouched" "$(cat "$T/.cortex/PROJECT.md")" "MY PROJECT"

echo "== v5 leftovers =="
T="$TMP/v5"; mkdir -p "$T/.cortex" "$T/.claude/hooks"
echo old > "$T/.cortex/SYSTEM.md"; echo old > "$T/.cortex/MAP.md"
echo old > "$T/.claude/hooks/cortex-session.sh"; echo old > "$T/.claude/hooks/cortex-file-change.sh"
cat > "$T/.claude/settings.json" <<'J'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash .claude/hooks/cortex-session.sh"}]}]}}
J
out="$(bash "$I" --agent claude --source "$REPO_ROOT" "$T" 2>&1)"
assert_has "warns upgrade" "$out" "Upgrading from v5"
assert_has "lists SYSTEM.md" "$out" ".cortex/SYSTEM.md"
assert_has "lists session hook" "$out" "cortex-session.sh"
assert_eq "v5 files remain" "$(ls "$T/.cortex/SYSTEM.md" "$T/.cortex/MAP.md" "$T/.claude/hooks/cortex-session.sh" "$T/.claude/hooks/cortex-file-change.sh" | wc -l | tr -d ' ')" "4"
assert_has "v5 settings entry kept" "$(cat "$T/.claude/settings.json")" "cortex-session.sh"
T="$TMP/v5b"; mkdir -p "$T/.claude"
cat > "$T/.claude/settings.json" <<'J'
{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"bash .claude/hooks/cortex-file-change.sh"}]}]}}
J
out="$(bash "$I" --agent claude --source "$REPO_ROOT" "$T" 2>&1)"
assert_has "settings-only leftover warns" "$out" "Upgrading from v5"
T="$TMP/v5c"; mkdir -p "$T"
printf '{"instructions":[".cortex/SYSTEM.md",".cortex/MAP.md","AGENTS.md"]}\n' > "$T/opencode.json"
cp "$T/opencode.json" "$TMP/v5c-opencode.json"
out="$(bash "$I" --agent claude --source "$REPO_ROOT" "$T" 2>&1)"
assert_has "opencode instructions leftover warns" "$out" "Upgrading from v5"
assert_has "lists opencode.json instructions" "$out" "opencode.json (instructions entries for .cortex/SYSTEM.md / .cortex/MAP.md)"
assert_eq "opencode.json untouched" "$(cat "$T/opencode.json")" "$(cat "$TMP/v5c-opencode.json")"
T="$TMP/v5d"; mkdir -p "$T"; printf 'node_modules/\n.cortex/.touched/\n' > "$T/.gitignore"
out="$(bash "$I" --agent claude --source "$REPO_ROOT" "$T" 2>&1)"
assert_has "gitignore .touched leftover warns" "$out" "Upgrading from v5"
assert_has "lists .gitignore entry" "$out" ".gitignore (entry for .cortex/.touched/)"
assert_has ".gitignore entry kept" "$(cat "$T/.gitignore")" ".cortex/.touched/"
T="$TMP/clean"; mkdir -p "$T"
out="$(bash "$I" --agent claude --source "$REPO_ROOT" "$T" 2>&1)"
assert_no "no warning when clean" "$out" "Upgrading from v5"
assert_has "final message" "$out" "Run /cortex-sync to generate the folder map."

echo "== invalid JSON in target config =="
for CASE in settings opencode; do
  T="$TMP/badjson-$CASE"; mkdir -p "$T/.claude"
  if [ "$CASE" = settings ]; then BADF="$T/.claude/settings.json"; else BADF="$T/opencode.json"; fi
  printf '{ "broken": [1, 2,\n' > "$BADF"; cp "$BADF" "$TMP/bad-$CASE.orig"
  mkdir -p "$TMP/tmpdir-$CASE"
  out="$(TMPDIR="$TMP/tmpdir-$CASE" bash "$I" --agent both --source "$REPO_ROOT" "$T" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && ok "[$CASE] exit non-zero" || no "[$CASE] exit non-zero" "got 0"
  assert_has "[$CASE] error names the file" "$out" "$(basename "$BADF")"
  assert_eq "[$CASE] file byte-identical" "$(cmp -s "$BADF" "$TMP/bad-$CASE.orig" && echo y || echo n)" "y"
  assert_eq "[$CASE] other artifacts installed" "$(ls "$T/.cortex/LOOKUP.md" "$T/.claude/rules/cortex.md" "$T/.claude/hooks/cortex-stop.sh" "$T/.opencode/commands/cortex-sync.md" 2>/dev/null | wc -l | tr -d ' ')" "4"
  assert_eq "[$CASE] no temp files left" "$(ls -A "$TMP/tmpdir-$CASE" | wc -l | tr -d ' ')" "0"
done

echo "== .gitignore handling =="
T="$TMP/gi-plain"; mkdir -p "$T"
bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_eq "plain: no .gitignore created" "$([ -e "$T/.gitignore" ] && echo y || echo n)" "n"
T="$TMP/gi-plain2"; mkdir -p "$T"; printf 'node_modules/\nfoo' > "$T/.gitignore"; cp "$T/.gitignore" "$TMP/gi.orig"
bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_eq "plain: existing .gitignore byte-identical" "$(cmp -s "$T/.gitignore" "$TMP/gi.orig" && echo y || echo n)" "y"
T="$TMP/gi-git"; mkdir -p "$T"; git -C "$T" init -q
bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1
bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_eq "git: state entry once" "$(grep -cxF '.cortex/.state/' "$T/.gitignore")" "1"
assert_eq "git: settings.local entry once" "$(grep -cxF '.claude/settings.local.json' "$T/.gitignore")" "1"
assert_eq "git: fresh .gitignore has no leading blank line" "$(head -1 "$T/.gitignore" | grep -c '^$' | tr -d ' ')" "0"

echo "== non-object, empty and multi-document config files =="
for CASE in settings opencode; do
  for KIND in array string multi; do
    T="$TMP/odd-$CASE-$KIND"; mkdir -p "$T/.claude"
    if [ "$CASE" = settings ]; then F="$T/.claude/settings.json"; else F="$T/opencode.json"; fi
    case "$KIND" in array) printf '[]\n' > "$F" ;; string) printf '"x"\n' > "$F" ;; multi) printf '{"a":1}{"b":2}\n' > "$F" ;; esac
    cp "$F" "$TMP/odd.orig"
    out="$(bash "$I" --agent both --source "$REPO_ROOT" "$T" 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && ok "[$CASE/$KIND] exit non-zero" || no "[$CASE/$KIND] exit non-zero" "got 0"
    assert_has "[$CASE/$KIND] reports invalid JSON" "$out" "not valid JSON"
    assert_eq "[$CASE/$KIND] file byte-identical" "$(cmp -s "$F" "$TMP/odd.orig" && echo y || echo n)" "y"
    assert_eq "[$CASE/$KIND] other artifacts installed" "$(ls "$T/.cortex/LOOKUP.md" "$T/.claude/rules/cortex.md" "$T/.claude/hooks/cortex-stop.sh" "$T/.opencode/commands/cortex-sync.md" 2>/dev/null | wc -l | tr -d ' ')" "4"
  done
  for KIND in zero blank; do
    T="$TMP/empty-$CASE-$KIND"; mkdir -p "$T/.claude"
    if [ "$CASE" = settings ]; then F="$T/.claude/settings.json"; else F="$T/opencode.json"; fi
    case "$KIND" in zero) : > "$F" ;; blank) printf ' \n\n' > "$F" ;; esac
    bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1; rc=$?
    assert_eq "[$CASE/$KIND] exit 0" "$rc" "0"
  done
  if [ "$CASE" = settings ]; then
    assert_eq "[settings/zero] hooks merged" "$(jq -r '.hooks|keys|join(",")' "$TMP/empty-settings-zero/.claude/settings.json")" "Stop,SubagentStart"
    assert_eq "[settings/blank] hooks merged" "$(jq -r '.hooks|keys|join(",")' "$TMP/empty-settings-blank/.claude/settings.json")" "Stop,SubagentStart"
  else
    assert_has "[opencode/zero] instructions merged" "$(jq -r '.instructions|join(",")' "$TMP/empty-opencode-zero/opencode.json")" ".cortex/LOOKUP.md"
    assert_has "[opencode/blank] instructions merged" "$(jq -r '.instructions|join(",")' "$TMP/empty-opencode-blank/opencode.json")" ".cortex/LOOKUP.md"
  fi
done

echo "== .gitignore separators =="
T="$TMP/gi-nonl"; mkdir -p "$T"; git -C "$T" init -q; printf 'node_modules/' > "$T/.gitignore"
bash "$I" --agent claude --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_eq "no trailing newline: exact content" "$(cat "$T/.gitignore")" "node_modules/

# CORTEX local tree snapshot
.cortex/.state/
.claude/settings.local.json"
T="$TMP/gi-nl"; mkdir -p "$T"; git -C "$T" init -q; printf 'node_modules/\n' > "$T/.gitignore"
bash "$I" --agent claude --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_eq "trailing newline: exact content" "$(cat "$T/.gitignore")" "node_modules/

# CORTEX local tree snapshot
.cortex/.state/
.claude/settings.local.json"

echo "== self-install =="
S="$TMP/self"; cp -R "$REPO_ROOT" "$S"; rm -rf "$S/.git"
cp "$S/.cortex/PROJECT.md" "$TMP/self-project.md"
bash "$I" --agent both --source "$S" "$S" >/dev/null 2>&1; rc=$?
assert_eq "self-install exit 0" "$rc" "0"
assert_eq "self PROJECT.md intact" "$(cat "$S/.cortex/PROJECT.md")" "$(cat "$TMP/self-project.md")"

echo "== [RF 3] path with space =="
T="$TMP/My Projects/app"; mkdir -p "$T"; git -C "$T" init -q
bash "$I" --agent both --source "$REPO_ROOT" "$T" >/dev/null 2>&1; rc=$?
assert_eq "space path exit 0" "$rc" "0"
assert_eq "space path title" "$(head -1 "$T/.cortex/PROJECT.md")" "# Project — app"
assert_eq "space path hooks" "$(jq -r '.hooks|keys|join(",")' "$T/.claude/settings.json")" "Stop,SubagentStart"
assert_has "space path state ignored" "$(cat "$T/.gitignore")" ".cortex/.state/"

echo "== ampersand in project name =="
T="$TMP/a&b"; mkdir -p "$T"
bash "$I" --agent claude --source "$REPO_ROOT" "$T" >/dev/null 2>&1
assert_eq "ampersand literal in title" "$(head -1 "$T/.cortex/PROJECT.md")" "# Project — a&b"

for CV in 32 42; do
  for NM in "a&b" "plain"; do
    T="$TMP/compat$CV/$NM"; mkdir -p "$T"
    BASH_COMPAT=$CV bash "$I" --agent claude --source "$REPO_ROOT" "$T" >/dev/null 2>&1
    assert_eq "BASH_COMPAT=$CV [$NM] title" "$(head -1 "$T/.cortex/PROJECT.md")" "# Project — $NM"
  done
done

echo "== /cortex-sync keeps large output out of the Bash tool =="
SYNC="$REPO_ROOT/.cortex/commands/cortex-sync.md"
assert_eq "claude copy byte-identical" "$(cmp -s "$SYNC" "$REPO_ROOT/.claude/commands/cortex-sync.md" && echo y || echo n)" "y"
sync="$(cat "$SYNC")"
assert_has "reconcile redirected to a state file" "$sync" "--reconcile > .cortex/.state/reconcile.txt"
assert_has "completion is gated by the queue status" "$sync" "cortex-describe.sh --status"
assert_has "read in chunks with awk" "$sync" "awk 'NR>=1 && NR<=200' .cortex/.state/reconcile.txt"

echo "== documented bash floor matches the scripts (3.2, macOS) =="
assert_has "PROJECT.md Tech Stack says Bash 3.2+" "$(cat "$REPO_ROOT/.cortex/PROJECT.md")" "| Bash | 3.2+ |"

echo "== no stale v5 references in shipped files =="
# install.sh is excluded on purpose: its v5-leftover warning must name the v5 files it detects.
stale="$(cd "$REPO_ROOT" && grep -rn --exclude-dir=.state --exclude-dir=map -E 'SYSTEM\.md|MAP\.md|--validate|--lookup|--remove|--move|cortex-session|cortex-file-change|\.touched|cortex-workspace|workspace-bridge|[Ww]orkspace mode' \
  .cortex .claude README.md CONTRIBUTING.md docs/index.html templates 2>/dev/null)"
assert_eq "no stale references" "$stale" ""

echo ""
echo "install-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
