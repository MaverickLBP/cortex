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
printf 'dist/\n' > "$G/.gitignore"

echo "== scan: gitignored dir excluded =="
out="$(bash "$SCAN" --files "$G")"
assert_has "includes src/a/one.js" "$out" "src/a/one.js"
assert_no  "excludes dist (gitignored)" "$out" "dist/bundle.js"
assert_no  "excludes .cortex (floor)"   "$out" ".cortex/MAP.md"

echo "== scan: dirs mode =="
dirs="$(bash "$SCAN" --dirs "$G")"
assert_has "dirs includes src/a" "$dirs" "src/a"

echo "== scan: non-git fallback still runs =="
N="$TMP/plain"; mkdir -p "$N/lib"; printf 'x\n' > "$N/lib/z.py"
outn="$(bash "$SCAN" --files "$N")"
assert_has "non-git includes lib/z.py" "$outn" "lib/z.py"

echo ""; echo "map-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
