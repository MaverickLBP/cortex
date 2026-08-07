#!/usr/bin/env bash
# CORTEX — map core test harness (scan + folder map).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); }
assert_eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$3] got [$2]"; }
assert_has(){ echo "$2" | grep -qF -- "$3" && ok "$1" || no "$1" "missing [$3]"; }
assert_no(){ echo "$2" | grep -qF -- "$3" && no "$1" "unexpected [$3]" || ok "$1"; }

SCAN="$REPO_ROOT/.cortex/scripts/cortex-scan.sh"

# --- Fixture: a git repo with a .gitignore ---
G="$TMP/gitrepo"; mkdir -p "$G/src/a" "$G/src/b" "$G/dist" "$G/.cortex"
( cd "$G" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$G/src/a/one.js"
printf 'x\n' > "$G/src/b/two.js"
printf 'x\n' > "$G/dist/bundle.js"
printf 'x\n' > "$G/.cortex/MAP.md"
printf 'x\n' > "$G/README.md"
( cd "$G" && git add README.md )
printf 'dist/\n' > "$G/.gitignore"

echo "== scan: gitignored dir excluded =="
out="$(bash "$SCAN" --files "$G")"
assert_has "includes src/a/one.js" "$out" "src/a/one.js"
assert_no  "excludes dist (gitignored)" "$out" "dist/bundle.js"
assert_no  "excludes .cortex (floor)"   "$out" ".cortex/MAP.md"

echo "== scan: dirs mode emits ancestors =="
mkdir -p "$G/deep/nested/leaf"
printf 'x\n' > "$G/deep/nested/leaf/f.js"
dirs="$(bash "$SCAN" --dirs "$G")"
assert_has "dirs includes src/a" "$dirs" "src/a"
assert_has "dirs includes leaf dir" "$dirs" "deep/nested/leaf"
assert_has "dirs includes intermediate ancestor" "$dirs" "deep/nested"
assert_has "dirs includes top ancestor" "$dirs" "deep"
assert_no "dirs excludes root-level file (no parent dir)" "$dirs" "README.md"
assert_no "dirs excludes gitignored tree" "$dirs" "dist"

echo "== scan: non-ASCII folder names are emitted verbatim, not git-quoted =="
U="$TMP/utf8repo"; mkdir -p "$U/documentación/api" "$U/diseño"
( cd "$U" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$U/documentación/api/f.js"; printf 'x\n' > "$U/diseño/g.js"
udirs="$(bash "$SCAN" --dirs "$U")"
assert_has "dirs emits an accented name verbatim" "$udirs" "documentación/api"
assert_has "dirs emits an n-tilde name verbatim" "$udirs" "diseño"
assert_no "dirs never emits a git-quoted octal escape" "$udirs" '\303'
assert_no "dirs never emits a git quoting wrapper" "$udirs" '"'

echo "== scan: non-git fallback still runs =="
N="$TMP/plain"; mkdir -p "$N/lib"; printf 'x\n' > "$N/lib/z.py"
outn="$(bash "$SCAN" --files "$N")"
assert_has "non-git includes lib/z.py" "$outn" "lib/z.py"

# A newline in a folder name is the one control character a line-based filter
# can never catch: it has already split the record before any grep sees it, so
# the real folder is lost AND a fragment of it is emitted as a folder that does
# not exist. Both scan branches must be NUL-delimited to close this, and the
# fallback branch is the one no test covered.
echo "== scan: a newline in a folder name yields no phantom folder (both branches) =="
NL="$TMP/nlplain"; mkdir -p "$NL/$(printf 'a\nb')" "$NL/real"
printf 'x\n' > "$NL/$(printf 'a\nb')/f.js"; printf 'x\n' > "$NL/real/g.js"
nldirs="$(bash "$SCAN" --dirs "$NL")"
assert_has "non-git fallback still emits the sane folder" "$nldirs" "real"
assert_eq "non-git fallback emits no phantom fragment" "$nldirs" "real"

NLG="$TMP/nlgit"; mkdir -p "$NLG/$(printf 'a\nb')" "$NLG/real"
( cd "$NLG" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$NLG/$(printf 'a\nb')/f.js"; printf 'x\n' > "$NLG/real/g.js"
nlgdirs="$(bash "$SCAN" --dirs "$NLG")"
assert_eq "git branch emits no phantom fragment either" "$nlgdirs" "real"

MAPSH="$REPO_ROOT/.cortex/scripts/cortex-map.sh"

mk_map() { # $1 = target file, stdin = tree body
  mkdir -p "$(dirname "$1")"
  { printf '# Knowledge Map — test\n\n> Folder-level map.\n\n'; cat; } > "$1"
}

echo "== map: validate accepts a well-formed tree =="
VM="$TMP/vmap/.cortex/MAP.md"
mk_map "$VM" <<'EOF'
e2e/  End-to-end suites.
  api/  Contract tests.
rsrc/  Application source.
  modules/  Business features.
    detours/  Detour handling.
EOF
CORTEX_MAP_FILE="$VM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && ok "validate accepts well-formed tree" || no "validate accepts well-formed tree" "exit non-zero"

echo "== map: validate rejects odd indentation =="
OM="$TMP/omap/.cortex/MAP.md"
mk_map "$OM" <<'EOF'
rsrc/  Application source.
   modules/  Three spaces is invalid.
EOF
CORTEX_MAP_FILE="$OM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && no "validate rejects odd indentation" "exited 0" || ok "validate rejects odd indentation"

echo "== map: validate rejects tab indentation =="
TM="$TMP/tmap/.cortex/MAP.md"
printf '# m\n\nrsrc/  Source.\n\tmodules/  Tab indented.\n' > "$TM" 2>/dev/null || mkdir -p "$(dirname "$TM")"
printf '# m\n\nrsrc/  Source.\n\tmodules/  Tab indented.\n' > "$TM"
CORTEX_MAP_FILE="$TM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && no "validate rejects tab indentation" "exited 0" || ok "validate rejects tab indentation"

echo "== map: validate rejects a level skip =="
SM="$TMP/smap/.cortex/MAP.md"
mk_map "$SM" <<'EOF'
rsrc/  Application source.
    deep/  Skipped a level.
EOF
CORTEX_MAP_FILE="$SM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && no "validate rejects level skip" "exited 0" || ok "validate rejects level skip"

echo "== map: validate reports the offending line number =="
verr="$(CORTEX_MAP_FILE="$OM" bash "$MAPSH" --validate 2>&1 >/dev/null || true)"
assert_has "diagnostic names the line" "$verr" "line 6"

echo "== map: validate rejects indented first node =="
FM="$TMP/fmap/.cortex/MAP.md"
mk_map "$FM" <<'EOF'
  child/  Indented first node.
EOF
CORTEX_MAP_FILE="$FM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && no "validate rejects indented first node" "exited 0" || ok "validate rejects indented first node"

echo "== install: claude agent =="
I="$TMP/installtarget"; mkdir -p "$I"; ( cd "$I" && git init -q && git config user.email t@t && git config user.name t )
bash "$REPO_ROOT/install.sh" --agent claude --source "$REPO_ROOT" "$I" >/dev/null 2>&1
[ -f "$I/.cortex/scripts/cortex-scan.sh" ] && ok "scan installed" || no "scan installed" "missing"
[ -f "$I/.cortex/scripts/cortex-map.sh" ]  && ok "map script installed" || no "map script installed" "missing"
[ -f "$I/.cortex/PROJECT.md" ]             && ok "PROJECT.md installed" || no "PROJECT.md installed" "missing"
[ -f "$I/.claude/hooks/cortex-stop.sh" ]   && ok "stop hook installed" || no "stop hook installed" "missing"
[ -f "$I/.claude/commands/cortex-sync.md" ] && ok "sync command installed" || no "sync command installed" "missing"
[ ! -f "$I/.cortex/scripts/cortex-areas.sh" ] && ok "areas not installed" || no "areas not installed" "still present"
[ ! -f "$I/.cortex/scripts/cortex-init.sh" ]  && ok "init script not installed" || no "init script not installed" "still present"
[ ! -f "$I/.claude/hooks/cortex-map-load.sh" ] && ok "map-load not installed" || no "map-load not installed" "still present"

echo "== install: Stop hook registered, PreToolUse gone =="
sreg="$(jq -r '.hooks.Stop[]?.hooks[]?.command' "$I/.claude/settings.json" 2>/dev/null | grep -c 'cortex-stop.sh' || true)"
[ "$sreg" -ge 1 ] && ok "Stop registered" || no "Stop registered" "not found"
preg="$(jq -r '.hooks.PreToolUse[]?.hooks[]?.command' "$I/.claude/settings.json" 2>/dev/null | grep -c 'cortex' || true)"
assert_eq "PreToolUse no longer registered" "$preg" "0"
sstop="$(jq -r '.hooks.SubagentStop[]?.hooks[]?.command' "$I/.claude/settings.json" 2>/dev/null | grep -c 'cortex' || true)"
assert_eq "SubagentStop deliberately not registered" "$sstop" "0"

echo "== install: idempotent =="
bash "$REPO_ROOT/install.sh" --agent claude --source "$REPO_ROOT" "$I" >/dev/null 2>&1
sreg2="$(jq -r '.hooks.Stop[]?.hooks[]?.command' "$I/.claude/settings.json" 2>/dev/null | grep -c 'cortex-stop.sh' || true)"
assert_eq "Stop not duplicated" "$sreg2" "$sreg"

echo "== install: gitignores the touch record but not the knowledge files =="
gi="$(cat "$I/.gitignore" 2>/dev/null || true)"
assert_has "touch record ignored" "$gi" ".cortex/.touched/"
assert_no "MAP.md not ignored" "$gi" ".cortex/MAP.md"
assert_no "PROJECT.md not ignored" "$gi" ".cortex/PROJECT.md"

echo "== install: PROJECT.md is never overwritten =="
printf '# Project — mine\n\n## Conventions\n- do not clobber me\n' > "$I/.cortex/PROJECT.md"
bash "$REPO_ROOT/install.sh" --agent claude --source "$REPO_ROOT" "$I" >/dev/null 2>&1
assert_has "existing PROJECT.md preserved" "$(cat "$I/.cortex/PROJECT.md")" "do not clobber me"

echo "== cortex-sync.md: procedure present =="
SYNC="$REPO_ROOT/.cortex/commands/cortex-sync.md"
syncc="$(cat "$SYNC")"
assert_has "runs validate first" "$syncc" "--validate"
assert_has "runs drift" "$syncc" "--drift"
assert_has "uses --set for new folders" "$syncc" "--set"
assert_has "uses --remove for gone folders" "$syncc" "--remove"
assert_has "refreshes tech stack" "$syncc" "Tech Stack"
assert_has "asks before touching conventions" "$syncc" "ask"
assert_has "states it is idempotent" "$syncc" "Idempotent"
assert_no "no init/update split" "$syncc" "cortex-update"

echo "== SYSTEM.md: v5 model =="
SYS="$REPO_ROOT/.cortex/SYSTEM.md"
sysc="$(cat "$SYS")"
assert_has "documents folder granularity" "$sysc" "folder"
assert_has "instructs to use cortex-map.sh --set" "$sysc" "cortex-map.sh --set"
assert_has "forbids hand-editing MAP.md" "$sysc" "never edit"
assert_has "never name files rule" "$sysc" "never name"
assert_has "ask before editing conventions" "$sysc" "ask"
assert_has "end-of-task review instruction" "$sysc" "When you finish a task"
assert_has "staleness caveat" "$sysc" "may be stale"
assert_has "mentions OpenCode" "$sysc" "OpenCode"
assert_no "no hierarchical leftovers" "$sysc" "index.json"
assert_no "no sub-map leftovers" "$sysc" "sub-map"
assert_no "no cortex-init leftovers" "$sysc" "cortex-init"

echo "== PROJECT.md: template shape =="
PRJ="$REPO_ROOT/.cortex/PROJECT.md"
prjc="$(cat "$PRJ")"
assert_has "has Tech Stack section" "$prjc" "## Tech Stack"
assert_has "has Conventions section" "$prjc" "## Conventions"
assert_has "has Notes section" "$prjc" "## Notes"

echo "== install: opencode agent =="
O="$TMP/octarget"; mkdir -p "$O"
bash "$REPO_ROOT/install.sh" --agent opencode --source "$REPO_ROOT" "$O" >/dev/null 2>&1
instr="$(jq -r '.instructions[]?' "$O/opencode.json" 2>/dev/null)"
assert_has "opencode loads SYSTEM.md"  "$instr" ".cortex/SYSTEM.md"
assert_has "opencode loads PROJECT.md" "$instr" ".cortex/PROJECT.md"
assert_has "opencode loads MAP.md"     "$instr" ".cortex/MAP.md"
[ -f "$O/.opencode/commands/cortex-sync.md" ] && ok "opencode sync command installed" || no "opencode sync command installed" "missing"
[ ! -d "$O/.claude/hooks" ] && ok "no claude hooks for opencode-only install" || no "no claude hooks for opencode-only install" "hooks dir present"

echo "== map: lookup resolves by full path, not basename =="
LM="$TMP/lmap/.cortex/MAP.md"
mk_map "$LM" <<'EOF'
rsrc/  Application source.
  modules/  Business features.
    detours/  Detour handling.
      styles/  Detour-specific styling.
    billing/  Billing.
      styles/  Billing-specific styling.
EOF
d1="$(CORTEX_MAP_FILE="$LM" bash "$MAPSH" --lookup rsrc/modules/detours/styles)"
d2="$(CORTEX_MAP_FILE="$LM" bash "$MAPSH" --lookup rsrc/modules/billing/styles)"
assert_eq "lookup disambiguates homonym styles (detours)" "$d1" "Detour-specific styling."
assert_eq "lookup disambiguates homonym styles (billing)" "$d2" "Billing-specific styling."

echo "== map: lookup of a nested path =="
d3="$(CORTEX_MAP_FILE="$LM" bash "$MAPSH" --lookup rsrc/modules)"
assert_eq "lookup nested path" "$d3" "Business features."

echo "== map: lookup MISSING =="
d4="$(CORTEX_MAP_FILE="$LM" bash "$MAPSH" --lookup rsrc/modules/invoicing || true)"
assert_eq "lookup absent folder prints MISSING" "$d4" "MISSING"
CORTEX_MAP_FILE="$LM" bash "$MAPSH" --lookup rsrc/modules/invoicing >/dev/null 2>&1 \
  && no "lookup MISSING exits non-zero" "exited 0" || ok "lookup MISSING exits non-zero"

echo "== map: lookup does not match a bare basename =="
d5="$(CORTEX_MAP_FILE="$LM" bash "$MAPSH" --lookup styles || true)"
assert_eq "bare basename does not resolve" "$d5" "MISSING"

echo "== map: set inserts in tree order =="
SETM="$TMP/setmap/.cortex/MAP.md"
mk_map "$SETM" <<'EOF'
rsrc/  Application source.
  modules/  Business features.
tests/  Test suites.
EOF
CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --set "rsrc/modules/billing" "Billing: invoice issuing."
body="$(grep -v '^#' "$SETM" | grep -v '^>' | grep -v '^[[:space:]]*$' | grep -vF '```')"
assert_eq "billing inserted under modules with 4-space indent" \
  "$(echo "$body" | sed -n '3p')" "    billing/  Billing: invoice issuing."
assert_eq "tests stays last" "$(echo "$body" | sed -n '4p')" "tests/  Test suites."

echo "== map: set updates an existing description in place =="
CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --set "rsrc/modules" "Business features, one folder per feature."
assert_eq "description replaced" \
  "$(CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --lookup rsrc/modules)" \
  "Business features, one folder per feature."
assert_eq "no duplicate node created" "$(grep -c '  modules/  ' "$SETM")" "1"

echo "== map: set creates missing ancestors =="
CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --set "lib/vendor/acme" "Vendored acme client."
assert_eq "ancestor lib created" "$(CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --lookup lib)" "(undescribed)"
assert_eq "ancestor lib/vendor created" "$(CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --lookup lib/vendor)" "(undescribed)"
assert_eq "leaf keeps its description" "$(CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --lookup lib/vendor/acme)" "Vendored acme client."

echo "== map: set output still validates =="
CORTEX_MAP_FILE="$SETM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && ok "map still valid after sets" || no "map still valid after sets" "validate failed"

echo "== map: set preserves the header =="
assert_has "header preserved" "$(cat "$SETM")" "# Knowledge Map — test"

echo "== map: sibling ordering does not corrupt nesting (hyphen vs slash) =="
HM="$TMP/hyphmap/.cortex/MAP.md"
mk_map "$HM" <<'EOF'
a/  Folder a.
EOF
CORTEX_MAP_FILE="$HM" bash "$MAPSH" --set "a-b" "Sibling with a hyphen."
CORTEX_MAP_FILE="$HM" bash "$MAPSH" --set "a/b" "Child of a."
assert_eq "a/b resolves as a child of a" "$(CORTEX_MAP_FILE="$HM" bash "$MAPSH" --lookup a/b)" "Child of a."
assert_eq "a-b resolves as a top-level sibling" "$(CORTEX_MAP_FILE="$HM" bash "$MAPSH" --lookup a-b)" "Sibling with a hyphen."
CORTEX_MAP_FILE="$HM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && ok "hyphen/slash tree valid" || no "hyphen/slash tree valid" "validate failed"

echo "== map: set is atomic (temp file cleaned up) =="
assert_eq "no temp files left behind" "$(find "$TMP/setmap/.cortex" -name '.MAP.md.*' | wc -l)" "0"

echo "== map: remove drops the folder and its subtree =="
RM="$TMP/rmmap/.cortex/MAP.md"
mk_map "$RM" <<'EOF'
rsrc/  Application source.
  modules/  Business features.
    billing/  Billing.
      styles/  Billing styling.
    detours/  Detours.
tests/  Test suites.
EOF
CORTEX_MAP_FILE="$RM" bash "$MAPSH" --remove "rsrc/modules/billing"
assert_eq "billing gone" "$(CORTEX_MAP_FILE="$RM" bash "$MAPSH" --lookup rsrc/modules/billing || true)" "MISSING"
assert_eq "billing subtree gone" "$(CORTEX_MAP_FILE="$RM" bash "$MAPSH" --lookup rsrc/modules/billing/styles || true)" "MISSING"
assert_eq "sibling survives" "$(CORTEX_MAP_FILE="$RM" bash "$MAPSH" --lookup rsrc/modules/detours)" "Detours."
assert_eq "described ancestor survives" "$(CORTEX_MAP_FILE="$RM" bash "$MAPSH" --lookup rsrc/modules)" "Business features."

echo "== map: remove prunes undescribed orphan ancestors =="
ORM="$TMP/ormap/.cortex/MAP.md"
mk_map "$ORM" <<'EOF'
keep/  Kept.
EOF
CORTEX_MAP_FILE="$ORM" bash "$MAPSH" --set "lib/vendor/acme" "Vendored acme."
CORTEX_MAP_FILE="$ORM" bash "$MAPSH" --remove "lib/vendor/acme"
assert_eq "undescribed ancestor lib/vendor pruned" "$(CORTEX_MAP_FILE="$ORM" bash "$MAPSH" --lookup lib/vendor || true)" "MISSING"
assert_eq "undescribed ancestor lib pruned" "$(CORTEX_MAP_FILE="$ORM" bash "$MAPSH" --lookup lib || true)" "MISSING"
assert_eq "unrelated folder untouched" "$(CORTEX_MAP_FILE="$ORM" bash "$MAPSH" --lookup keep)" "Kept."

echo "== map: remove is idempotent =="
CORTEX_MAP_FILE="$ORM" bash "$MAPSH" --remove "lib/vendor/acme" >/dev/null 2>&1 \
  && ok "removing an absent folder exits 0" || no "removing an absent folder exits 0" "non-zero exit"

echo "== map: remove output still validates =="
CORTEX_MAP_FILE="$RM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && ok "map valid after removes" || no "map valid after removes" "validate failed"

echo "== map: drift on a virgin repo reports everything as + =="
DR="$TMP/driftrepo"
mkdir -p "$DR/.cortex" "$DR/src/api" "$DR/tests"
( cd "$DR" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$DR/src/api/h.js"; printf 'x\n' > "$DR/tests/t.js"
printf '# Knowledge Map\n\n> empty\n' > "$DR/.cortex/MAP.md"
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$DR/.cortex/scripts/" 2>/dev/null || \
  { mkdir -p "$DR/.cortex/scripts"; cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$DR/.cortex/scripts/"; }
dout="$(CORTEX_ROOT="$DR" bash "$MAPSH" --drift "$DR")"
assert_has "drift reports + src" "$dout" "+ src"
assert_has "drift reports + src/api" "$dout" "+ src/api"
assert_has "drift reports + tests" "$dout" "+ tests"
# An empty map on one side and folders on the other is the fresh-install case:
# `printf '%s\n' "$EMPTY_VAR"` still emits one blank line, so comm reports it as
# a difference and it renders as a marker with no folder name.
echo "$dout" | grep -qE '^[+-][[:space:]]*$' \
  && no "drift on a virgin repo emits no marker with an empty folder name" "got [$dout]" \
  || ok "drift on a virgin repo emits no marker with an empty folder name"

echo "== map: drift reports - for folders only in the map =="
CORTEX_ROOT="$DR" bash "$MAPSH" --set "src" "Source."
CORTEX_ROOT="$DR" bash "$MAPSH" --set "src/api" "HTTP handlers."
CORTEX_ROOT="$DR" bash "$MAPSH" --set "tests" "Test suites."
CORTEX_ROOT="$DR" bash "$MAPSH" --set "gone" "No longer on disk."
dout2="$(CORTEX_ROOT="$DR" bash "$MAPSH" --drift "$DR")"
assert_has "drift reports - gone" "$dout2" "- gone"
assert_no "drift no longer reports + src" "$dout2" "+ src"

echo "== map: drift is silent when in sync =="
CORTEX_ROOT="$DR" bash "$MAPSH" --remove "gone"
dout3="$(CORTEX_ROOT="$DR" bash "$MAPSH" --drift "$DR")"
assert_eq "drift silent when in sync" "$dout3" ""

echo "== map: --set rejects an absolute path =="
AM="$TMP/absmap/.cortex/MAP.md"
mk_map "$AM" <<'EOF'
keep/  Kept.
EOF
before="$(cat "$AM")"
CORTEX_MAP_FILE="$AM" bash "$MAPSH" --set "/tmp/x" "Should not be written." >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "--set absolute path exits non-zero" || no "--set absolute path exits non-zero" "exited 0"
assert_eq "--set absolute path leaves MAP.md unchanged" "$(cat "$AM")" "$before"

echo "== map: --remove rejects an absolute path =="
CORTEX_MAP_FILE="$AM" bash "$MAPSH" --remove "/tmp/x" >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "--remove absolute path exits non-zero" || no "--remove absolute path exits non-zero" "exited 0"
assert_eq "--remove absolute path leaves MAP.md unchanged" "$(cat "$AM")" "$before"

echo "== map: --set rejects a '..' path segment =="
CORTEX_MAP_FILE="$AM" bash "$MAPSH" --set "src/../etc" "Should not be written." >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "--set '..' segment exits non-zero" || no "--set '..' segment exits non-zero" "exited 0"
assert_eq "--set '..' segment leaves MAP.md unchanged" "$(cat "$AM")" "$before"

echo "== map: --set rejects a bare '..' target =="
CORTEX_MAP_FILE="$AM" bash "$MAPSH" --set ".." "Should not be written." >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "--set bare '..' exits non-zero" || no "--set bare '..' exits non-zero" "exited 0"
assert_eq "--set bare '..' leaves MAP.md unchanged" "$(cat "$AM")" "$before"

echo "== map: a write that would not parse back is refused, not applied =="
# The safety net under every other rule: map_write re-parses what it is about to
# install and refuses the mv unless it round-trips to the exact records it was
# given. A tab in the DESCRIPTION is the shape validate_target cannot see (it
# only inspects the target), and it makes map_parse report tab indentation —
# i.e. it would brick the map with no sanctioned repair.
GRD="$TMP/guardmap/.cortex/MAP.md"
mk_map "$GRD" <<'EOF'
src/  Source.
EOF
grdbefore="$(cat "$GRD")"
CORTEX_MAP_FILE="$GRD" bash "$MAPSH" --set "docs" "$(printf 'a\tb')" >/dev/null 2>&1 \
  && no "--set with a tab in the description exits non-zero" "exited 0" \
  || ok "--set with a tab in the description exits non-zero"
assert_eq "a refused write leaves MAP.md byte-identical" "$(cat "$GRD")" "$grdbefore"
CORTEX_MAP_FILE="$GRD" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && ok "the map still validates after a refused write" || no "the map still validates after a refused write" "validate failed"
# A newline in the description would silently truncate it: the second line is
# read back as a continuation, so --lookup would return something other than
# what was set. Refusing is the only honest outcome.
CORTEX_MAP_FILE="$GRD" bash "$MAPSH" --set "docs" "$(printf 'a\nb')" >/dev/null 2>&1 \
  && no "--set with a newline in the description exits non-zero" "exited 0" \
  || ok "--set with a newline in the description exits non-zero"
assert_eq "the truncating write was not applied" "$(cat "$GRD")" "$grdbefore"

echo "== map: --set rejects a leading space in any path segment =="
# A leading space collides with MAP.md's OTHER positional channel: indentation.
# ` docs/  Docs.` reads back as indent=1 (odd) and every command that runs
# map_parse first — set, remove, lookup, drift — then fails, with hand-editing
# the only escape (which SYSTEM.md §2.1 forbids).
LSM="$TMP/leadspacemap/.cortex/MAP.md"
mk_map "$LSM" <<'EOF'
src/  Source.
EOF
lsbefore="$(cat "$LSM")"
for bad in " docs" "  docs" "src/ x" "src/  x"; do
  CORTEX_MAP_FILE="$LSM" bash "$MAPSH" --set "$bad" "Should not be written." >/dev/null 2>&1 \
    && no "--set rejects a leading space [$bad]" "exited 0" || ok "--set rejects a leading space [$bad]"
done
assert_eq "--set with a leading space leaves MAP.md unchanged" "$(cat "$LSM")" "$lsbefore"
CORTEX_MAP_FILE="$LSM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && ok "the map is still parseable after rejected leading-space sets" \
  || no "the map is still parseable after rejected leading-space sets" "validate failed"
lserr="$(CORTEX_MAP_FILE="$LSM" bash "$MAPSH" --set " docs" "d" 2>&1 >/dev/null || true)"
assert_has "leading-space diagnostic explains itself" "$lserr" "start with a space"

echo "== map: --set accepts a folder name containing a space and round-trips it =="
SPM="$TMP/spacemap/.cortex/MAP.md"
mk_map "$SPM" <<'EOF'
src/  Source.
EOF
CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --set "design assets" "Brand assets." >/dev/null 2>&1 \
  && ok "--set with a space exits 0" || no "--set with a space exits 0" "exited non-zero"
assert_eq "--lookup round-trips a space name" \
  "$(CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --lookup "design assets")" "Brand assets."
CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --validate >/dev/null 2>&1 \
  && ok "a map holding a space name still validates" || no "a map holding a space name still validates" "validate failed"
CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --set "src/my docs" "Written docs." >/dev/null 2>&1
assert_eq "--lookup round-trips a nested space name" \
  "$(CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --lookup "src/my docs")" "Written docs."
assert_eq "the space name's parent is untouched" \
  "$(CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --lookup "src")" "Source."
# The never-converging duplication is what the old blanket rejection existed to
# prevent: an unreadable node means --lookup misses it and every --set appends
# another copy. Prove the round-trip closes that.
CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --set "design assets" "Brand assets, revised." >/dev/null 2>&1
assert_eq "--set on an existing space name updates in place" \
  "$(CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --lookup "design assets")" "Brand assets, revised."
assert_eq "--set on an existing space name appends no duplicate" \
  "$(grep -c 'design assets/' "$SPM")" "1"

echo "== map: --set still rejects a folder name containing a newline =="
CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --set "$(printf 'a\nb')" "desc" >/dev/null 2>&1 \
  && no "--set with a newline exits non-zero" "exited 0" || ok "--set with a newline exits non-zero"

echo "== map: --set rejects a folder name containing a tab =="
TABM="$TMP/tabmap/.cortex/MAP.md"
mk_map "$TABM" <<'EOF'
src/  Source.
EOF
tabbefore="$(md5sum "$TABM" | awk '{print $1}')"
CORTEX_MAP_FILE="$TABM" bash "$MAPSH" --set "$(printf 'ta\tb')" "desc" >/dev/null 2>&1 \
  && no "--set with tab exits non-zero" "exited 0" || ok "--set with tab exits non-zero"
tabafter="$(md5sum "$TABM" | awk '{print $1}')"
assert_eq "--set with tab leaves MAP.md unchanged" "$tabafter" "$tabbefore"

echo "== map: --set diagnostic distinguishes '.' from '..' =="
DOTM="$TMP/dotmap/.cortex/MAP.md"
mk_map "$DOTM" <<'EOF'
src/  Source.
EOF
doterr="$(CORTEX_MAP_FILE="$DOTM" bash "$MAPSH" --set "./src" "desc" 2>&1 >/dev/null || true)"
assert_has "single-dot diagnostic mentions '.'" "$doterr" "'.' path segments"
assert_no "single-dot diagnostic does not claim '..'" "$doterr" "'..' path segments"
dotdoterr="$(CORTEX_MAP_FILE="$DOTM" bash "$MAPSH" --set "../src" "desc" 2>&1 >/dev/null || true)"
assert_has "double-dot diagnostic mentions '..'" "$dotdoterr" "'..' path segments"

echo "== map: --remove accepts a folder name containing a space =="
CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --remove "design assets" >/dev/null 2>&1 \
  && ok "--remove with a space exits 0" || no "--remove with a space exits 0" "exited non-zero"
assert_eq "--remove actually dropped the space name" \
  "$(CORTEX_MAP_FILE="$SPM" bash "$MAPSH" --lookup "design assets")" "MISSING"

echo "== map: drift never proposes a folder --set would reject =="
TABD="$TMP/tabdriftrepo"
mkdir -p "$TABD/.cortex/scripts" "$TABD/ok" "$TABD/$(printf 'ta\tb')"
( cd "$TABD" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$TABD/ok/f.js"; printf 'x\n' > "$TABD/$(printf 'ta\tb')/f.js"
printf '# Knowledge Map\n\n> empty\n' > "$TABD/.cortex/MAP.md"
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$TABD/.cortex/scripts/"
# A leading space is the shape validate_target refuses for indentation reasons;
# it must be filtered by the same rule, not by a second approximation of it.
mkdir -p "$TABD/ lead"; printf 'x\n' > "$TABD/ lead/f.js"
tdout="$(CORTEX_ROOT="$TABD" bash "$MAPSH" --drift "$TABD")"
assert_has "drift still reports the representable folder" "$tdout" "+ ok"
assert_no "drift omits the tab-named folder it could not map" "$tdout" "$(printf 'ta\tb')"
assert_no "drift omits the leading-space folder it could not map" "$tdout" "+  lead"
# Convergence: everything drift proposed must be applicable, leaving it silent.
CORTEX_ROOT="$TABD" bash "$MAPSH" --set "ok" "Fine." >/dev/null 2>&1
assert_eq "drift converges to silence after applying its own proposals" \
  "$(CORTEX_ROOT="$TABD" bash "$MAPSH" --drift "$TABD")" ""

# The regression net for "representable". Rather than enumerating which shapes
# are legal — a list that has now been wrong in both directions — assert the
# INVARIANT: whatever --set accepts must leave a map that reads back, and
# whatever --drift proposes must be exactly what --set accepts. Both halves have
# been violated in this codebase; the second is what let a leading-space name
# corrupt a map through the normal /cortex-sync path.
# awk's -v assignment runs escape processing over the VALUE, so a folder name
# holding a backslash reached the awk comparisons mangled ("d\bs" arrives as
# "d<BS>s"). Every record filter then failed to match the node it was meant to
# replace or drop: --set appended a fresh duplicate on each call and --remove
# reported success while removing nothing. Path data must reach awk through
# ENVIRON, which does no escape processing.
echo "== map: a backslash in a folder name round-trips and does not duplicate =="
BSM="$TMP/bsmap/.cortex/MAP.md"
mk_map "$BSM" <<'EOF'
src/  Source.
EOF
CORTEX_MAP_FILE="$BSM" bash "$MAPSH" --set 'd\bs' "First." >/dev/null 2>&1
assert_eq "--lookup finds a backslash name" \
  "$(CORTEX_MAP_FILE="$BSM" bash "$MAPSH" --lookup 'd\bs' 2>/dev/null)" "First."
CORTEX_MAP_FILE="$BSM" bash "$MAPSH" --set 'd\bs' "Second." >/dev/null 2>&1
CORTEX_MAP_FILE="$BSM" bash "$MAPSH" --set 'd\bs' "Third." >/dev/null 2>&1
assert_eq "repeated --set on a backslash name appends no duplicate" \
  "$(grep -c 'd\\bs/' "$BSM")" "1"
assert_eq "the last --set won" \
  "$(CORTEX_MAP_FILE="$BSM" bash "$MAPSH" --lookup 'd\bs' 2>/dev/null)" "Third."
CORTEX_MAP_FILE="$BSM" bash "$MAPSH" --remove 'd\bs' >/dev/null 2>&1
assert_eq "--remove actually drops a backslash name" \
  "$(CORTEX_MAP_FILE="$BSM" bash "$MAPSH" --lookup 'd\bs' 2>/dev/null)" "MISSING"

# The representability rule has to be askable from outside this script, or every
# other component re-derives a subset of it by hand — which is what caused every
# bug in this family. --check is that seam: read-only, no output, exit status only.
echo "== map: --check exposes the representability rule without writing =="
CHKM="$TMP/chkmap/.cortex/MAP.md"
mk_map "$CHKM" <<'EOF'
src/  Source.
EOF
chk_before="$(cat "$CHKM")"
CORTEX_MAP_FILE="$CHKM" bash "$MAPSH" --check "ok/name" >/dev/null 2>&1 \
  && ok "--check accepts a representable name" || no "--check accepts a representable name" "exited non-zero"
CORTEX_MAP_FILE="$CHKM" bash "$MAPSH" --check " lead" >/dev/null 2>&1 \
  && no "--check rejects a leading-space name" "exited 0" || ok "--check rejects a leading-space name"
CORTEX_MAP_FILE="$CHKM" bash "$MAPSH" --check "#hash" >/dev/null 2>&1 \
  && no "--check rejects a '#' top-level name" "exited 0" || ok "--check rejects a '#' top-level name"
CORTEX_MAP_FILE="$CHKM" bash "$MAPSH" --check "$(printf 'a\tb')" >/dev/null 2>&1 \
  && no "--check rejects a control character" "exited 0" || ok "--check rejects a control character"
assert_eq "--check leaves MAP.md untouched" "$(cat "$CHKM")" "$chk_before"

# --set already does this; --remove dropped it, so a failed write was reported
# as success by the sole writer of MAP.md.
echo "== map: --remove propagates a failed write =="
if [ "$(id -u)" -ne 0 ]; then
  ROM="$TMP/roremove"; mkdir -p "$ROM"
  printf '# K\n\n> h\ndocs/  Docs.\n' > "$ROM/MAP.md"
  chmod a-w "$ROM"
  CORTEX_MAP_FILE="$ROM/MAP.md" bash "$MAPSH" --remove docs >/dev/null 2>&1 \
    && no "--remove reports failure when the write fails" "exited 0" \
    || ok "--remove reports failure when the write fails"
  chmod u+w "$ROM"
else
  ok "--remove failed-write check skipped (running as root)"
fi

echo "== map: property — --set either refuses a name or leaves a readable map =="
PROP="$TMP/propmap"; mkdir -p "$PROP/.cortex/scripts"
( cd "$PROP" && git init -q && git config user.email t@t && git config user.name t )
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$PROP/.cortex/scripts/"
prop_fail=0; prop_accepted=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  printf '# Knowledge Map\n\n> empty\n' > "$PROP/.cortex/MAP.md"
  if CORTEX_ROOT="$PROP" bash "$MAPSH" --set "$name" "Desc." >/dev/null 2>&1; then
    prop_accepted=$((prop_accepted+1))
    # Accepted → the map must validate AND the name must round-trip.
    CORTEX_ROOT="$PROP" bash "$MAPSH" --validate >/dev/null 2>&1 || {
      echo "      violated by [$name]: --set accepted it but the map no longer validates"
      prop_fail=$((prop_fail+1)); continue; }
    [ "$(CORTEX_ROOT="$PROP" bash "$MAPSH" --lookup "$name" 2>/dev/null)" = "Desc." ] || {
      echo "      violated by [$name]: --set accepted it but --lookup cannot find it"
      prop_fail=$((prop_fail+1)); }
  fi
done <<EOF
 leading
trailing
in ter ior
  two
a/ nested
#hash
>gt
d"quote
d\\backslash
d\$dollar
ñ
$(printf 'a\tb')
EOF
[ "$prop_fail" -eq 0 ] && ok "every accepted name leaves a readable, round-tripping map" \
  || no "every accepted name leaves a readable, round-tripping map" "$prop_fail violation(s)"
# Without this the property above passes vacuously if the rule ever regresses to
# rejecting everything — which is exactly one of the two states this branch was in.
[ "$prop_accepted" -ge 5 ] && ok "the property is load-bearing (>=5 of the adversarial names accepted)" \
  || no "the property is load-bearing (>=5 of the adversarial names accepted)" "only $prop_accepted accepted"

echo "== map: property — drift proposes exactly what --set accepts =="
PROP2="$TMP/propdrift"; mkdir -p "$PROP2/.cortex/scripts"
( cd "$PROP2" && git init -q && git config user.email t@t && git config user.name t )
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$PROP2/.cortex/scripts/"
printf '# Knowledge Map\n\n> empty\n' > "$PROP2/.cortex/MAP.md"
for n in " leading" "trailing " "in ter ior" "ok" "d\"quote" "ñ"; do
  mkdir -p "$PROP2/$n" 2>/dev/null && printf 'x\n' > "$PROP2/$n/f.js" 2>/dev/null
done
driftout="$(CORTEX_ROOT="$PROP2" bash "$MAPSH" --drift "$PROP2")"
[ -n "$driftout" ] && ok "drift actually proposed something to check against" \
  || no "drift actually proposed something to check against" "drift was empty"
drift_fail=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in "+ "*) d="${line#+ }" ;; *) continue ;; esac
  CORTEX_ROOT="$PROP2" bash "$MAPSH" --set "$d" "Desc." >/dev/null 2>&1 || {
    echo "      violated: drift proposed [$d] but --set refuses it"
    drift_fail=$((drift_fail+1)); }
done < <(CORTEX_ROOT="$PROP2" bash "$MAPSH" --drift "$PROP2")
[ "$drift_fail" -eq 0 ] && ok "every folder drift proposes is one --set accepts" \
  || no "every folder drift proposes is one --set accepts" "$drift_fail violation(s)"
assert_eq "applying drift's own proposals converges to silence" \
  "$(CORTEX_ROOT="$PROP2" bash "$MAPSH" --drift "$PROP2")" ""

echo "== map: drift on an empty map does not emit a spurious blank '-' line =="
EMD="$TMP/emptydriftrepo"
mkdir -p "$EMD/.cortex/scripts"
( cd "$EMD" && git init -q && git config user.email t@t && git config user.name t )
printf '# Knowledge Map\n\n> empty\n' > "$EMD/.cortex/MAP.md"
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$EMD/.cortex/scripts/"
edout="$(CORTEX_ROOT="$EMD" bash "$MAPSH" --drift "$EMD")"
assert_eq "drift on virgin empty repo is silent (no spurious blank '-' entry)" "$edout" ""

# The mirror of the fresh-install case: the map holds nodes but nothing on disk
# does, so the on-disk side is the empty one.
echo "== map: drift with a populated map and no folders on disk emits no spurious blank '+' line =="
NOD="$TMP/nodirsrepo"
mkdir -p "$NOD/.cortex/scripts"
( cd "$NOD" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$NOD/README.md"
printf '# Knowledge Map\n\n> empty\n' > "$NOD/.cortex/MAP.md"
cp "$REPO_ROOT/.cortex/scripts/cortex-scan.sh" "$NOD/.cortex/scripts/"
CORTEX_ROOT="$NOD" bash "$MAPSH" --set "gone" "Only in the map."
ndout="$(CORTEX_ROOT="$NOD" bash "$MAPSH" --drift "$NOD")"
assert_eq "drift reports only the stale mapped folder, with no blank '+' entry" "$ndout" "- gone"

echo "== install: fresh MAP.md is header-only, no folder nodes, no foreign project name =="
IT="$TMP/my-other-project"; mkdir -p "$IT"
( cd "$IT" && git init -q && git config user.email t@t && git config user.name t )
bash "$REPO_ROOT/install.sh" --agent claude --source "$REPO_ROOT" "$IT" >/dev/null 2>&1
itmap="$IT/.cortex/MAP.md"
[ -f "$itmap" ] && ok "fresh install creates MAP.md" || no "fresh install creates MAP.md" "missing"
nodecount="$(grep -cE '^ *[^ ]+/  ' "$itmap" 2>/dev/null || true)"
assert_eq "fresh MAP.md has no folder nodes" "${nodecount:-0}" "0"
assert_has "fresh MAP.md header names the target project" "$(cat "$itmap")" "my-other-project"
assert_no "fresh MAP.md does not describe the CORTEX source project" "$(cat "$itmap")" "Knowledge Map — CORTEX"
assert_no "fresh MAP.md header has no transient cortex-sync instruction" "$(cat "$itmap")" "Run \`/cortex-sync\`"

echo ""; echo "map-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
