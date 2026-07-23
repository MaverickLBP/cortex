#!/usr/bin/env bash
# CORTEX — map core test harness (scan + areas + map-load hook).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); }
assert_eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$3] got [$2]"; }
assert_has(){ echo "$2" | grep -qF "$3" && ok "$1" || no "$1" "missing [$3]"; }
assert_no(){ echo "$2" | grep -qF "$3" && no "$1" "unexpected [$3]" || ok "$1"; }

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

echo "== scan: dirs mode =="
dirs="$(bash "$SCAN" --dirs "$G")"
assert_has "dirs includes src/a" "$dirs" "src/a"
assert_no "dirs excludes root-level file (no parent dir)" "$dirs" "README.md"

echo "== scan: non-git fallback still runs =="
N="$TMP/plain"; mkdir -p "$N/lib"; printf 'x\n' > "$N/lib/z.py"
outn="$(bash "$SCAN" --files "$N")"
assert_has "non-git includes lib/z.py" "$outn" "lib/z.py"

AREAS="$REPO_ROOT/.cortex/scripts/cortex-areas.sh"

echo "== areas: small repo → flat =="
S="$TMP/small"; mkdir -p "$S/src"; ( cd "$S" && git init -q && git config user.email t@t && git config user.name t )
for i in $(seq 1 5); do printf 'x\n' > "$S/src/f$i.js"; done
sumS="$(CORTEX_FLAT_CAP=150 bash "$AREAS" "$S")"
assert_has "small repo reports FLAT" "$sumS" "FLAT"
assert_eq  "small repo flat flag" "$(jq -r '.flat' "$S/.cortex/maps/index.json")" "true"

echo "== areas: large repo → partitioned by subtree =="
L="$TMP/large"; ( mkdir -p "$L" && cd "$L" && git init -q && git config user.email t@t && git config user.name t )
# mod-a: 12 files, mod-b: 12 files, tiny: 1 file
for m in a b; do mkdir -p "$L/src/mod-$m"; for i in $(seq 1 12); do printf 'x\n' > "$L/src/mod-$m/f$i.js"; done; done
mkdir -p "$L/src/tiny"; printf 'x\n' > "$L/src/tiny/z.js"
sumL="$(CORTEX_FLAT_CAP=10 CORTEX_AREA_CAP=15 CORTEX_MERGE_MIN=5 bash "$AREAS" "$L")"
assert_no  "large repo not flat" "$sumL" "FLAT"
assert_has "area for mod-a" "$sumL" "src/mod-a"
assert_has "area for mod-b" "$sumL" "src/mod-b"
# tiny (1 file < MERGE_MIN) must NOT be its own area
assert_no  "tiny not promoted" "$sumL" "AREA src/tiny"
# manifest: longest-prefix resolves a mod-a file to the mod-a area
ma="$(jq -r '.areas[].root' "$L/.cortex/maps/index.json" | grep -x 'src/mod-a')"
assert_eq "mod-a is an area root" "$ma" "src/mod-a"

echo "== areas: top-level tiny dir not promoted =="
TT="$TMP/toptiny"; ( mkdir -p "$TT" && cd "$TT" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TT/small" "$TT/big"
for i in 1 2; do printf 'x\n' > "$TT/small/f$i.js"; done
for i in $(seq 1 20); do printf 'x\n' > "$TT/big/f$i.js"; done
sumTT="$(CORTEX_FLAT_CAP=5 CORTEX_AREA_CAP=15 CORTEX_MERGE_MIN=5 bash "$AREAS" "$TT")"
assert_has "area for big" "$sumTT" "AREA big"
# small (2 files < MERGE_MIN) is top-level; must NOT be promoted to its own area
assert_no  "small top-level dir not promoted" "$sumTT" "AREA small"
assert_has "small top-level dir rolled into _misc" "$sumTT" "AREA . 2"

echo "== areas: single-child chain collapses =="
C="$TMP/chain"; ( mkdir -p "$C" && cd "$C" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$C/a/b/c/pkg"; for i in $(seq 1 20); do printf 'x\n' > "$C/a/b/c/pkg/f$i.js"; done
sumC="$(CORTEX_FLAT_CAP=10 CORTEX_AREA_CAP=15 CORTEX_MERGE_MIN=5 bash "$AREAS" "$C")"
# The area root should be the collapsed deep dir, not the pass-through 'a'
assert_has "chain collapses to a/b/c/pkg" "$sumC" "a/b/c/pkg"

LOAD="$REPO_ROOT/.claude/hooks/cortex-map-load.sh"

# Build a hierarchical fixture with a manifest + sub-map file.
H="$TMP/hier"; mkdir -p "$H/.cortex/maps" "$H/src/mod-a"
printf 'x\n' > "$H/src/mod-a/a.js"
cat > "$H/.cortex/maps/index.json" <<'JSON'
{"version":1,"flat":false,"areas":[{"root":"src/mod-a","map":"maps/src__mod-a.md","files":12}]}
JSON
printf '# map\n' > "$H/.cortex/maps/src__mod-a.md"

echo "== map-load: Grep in an area → reminder =="
gout="$(printf '{"tool_name":"Grep","tool_input":{"pattern":"foo","path":"src/mod-a"},"cwd":"%s"}' "$H" | bash "$LOAD")"
assert_has "grep reminder names sub-map" "$gout" "maps/src__mod-a.md"

echo "== map-load: Write into area → placement note =="
wout="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/mod-a/new.js"},"cwd":"%s"}' "$H" "$H" | bash "$LOAD")"
assert_has "write note names sub-map" "$wout" "maps/src__mod-a.md"

echo "== map-load: flat repo → silent =="
F="$TMP/flatrepo"; mkdir -p "$F/.cortex/maps"
echo '{"version":1,"flat":true,"areas":[]}' > "$F/.cortex/maps/index.json"
fout="$(printf '{"tool_name":"Grep","tool_input":{"pattern":"foo","path":"src"},"cwd":"%s"}' "$F" | bash "$LOAD")"
assert_eq "flat repo silent" "$fout" ""

echo "== map-load: no manifest → silent =="
P="$TMP/nomani"; mkdir -p "$P/src"
pout="$(printf '{"tool_name":"Grep","tool_input":{"pattern":"foo","path":"src"},"cwd":"%s"}' "$P" | bash "$LOAD")"
assert_eq "no manifest silent" "$pout" ""

echo ""; echo "map-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
