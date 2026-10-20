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

# git ls-files --cached keeps listing a committed file after a plain `rm`/`mv`
# until the change is staged. The scan must report the disk, not the index.
echo "== scan: a file deleted from disk but still in the index is not listed =="
DG="$TMP/delgit"; mkdir -p "$DG/ghost" "$DG/live" "$DG/old"
( cd "$DG" && git init -q && git config user.email t@t && git config user.name t )
printf 'x\n' > "$DG/ghost/f.js"; printf 'x\n' > "$DG/live/g.js"; printf 'x\n' > "$DG/old/h.js"
( cd "$DG" && git add -A && git commit -qm init )
rm -rf "$DG/ghost"; mv "$DG/old" "$DG/new"
dgfiles="$(bash "$SCAN" --files "$DG")"
assert_eq "deleted-but-indexed files are not listed" "$dgfiles" "$(printf 'live/g.js\nnew/h.js')"
assert_eq "deleted-but-indexed folders are not listed" "$(bash "$SCAN" --dirs "$DG")" "$(printf 'live\nnew')"


MAPSH="$REPO_ROOT/.cortex/scripts/cortex-map.sh"
# --- v6 map storage: one sibling .cortex file per folder ---
mk_project() { # $1 = dir, $2 = git|plain
  mkdir -p "$1/.cortex/map"
  if [ "$2" = git ]; then
    ( cd "$1" && git init -q && git config user.email t@t && git config user.name t )
  fi
}

for MODE in git plain; do
P="$TMP/proj-$MODE"; mk_project "$P" "$MODE"

echo "== [$MODE] set: writes one-line sibling file =="
mkdir -p "$P/src/api"; printf 'x\n' > "$P/src/api/a.js"
CORTEX_ROOT="$P" bash "$MAPSH" --set src "Application source."
CORTEX_ROOT="$P" bash "$MAPSH" --set src/api "HTTP handlers."
assert_eq "[$MODE] src.cortex content" "$(cat "$P/.cortex/map/src.cortex")" "Application source."
assert_eq "[$MODE] api file is sibling of mirror dir" "$(cat "$P/.cortex/map/src/api.cortex")" "HTTP handlers."
CORTEX_ROOT="$P" bash "$MAPSH" --set src/api "Request handlers."
assert_eq "[$MODE] set replaces" "$(cat "$P/.cortex/map/src/api.cortex")" "Request handlers."

echo "== [$MODE] set: rejects invalid input with exit 2 =="
for bad in "" "/abs" "a/../b" "./a" ".git/x" ".cortex/map" "x.cortex" "src/y.cortex/z" "nope"; do
  CORTEX_ROOT="$P" bash "$MAPSH" --set "$bad" "Desc." 2>/dev/null; assert_eq "[$MODE] rejects dir [$bad]" "$?" "2"
done
long="$(printf 'a%.0s' $(seq 121))"; ok120="$(printf 'á%.0s' $(seq 120))"; bad121="$(printf 'á%.0s' $(seq 121))"
CORTEX_ROOT="$P" bash "$MAPSH" --set src "$long" 2>/dev/null; assert_eq "[$MODE] rejects 121 ascii" "$?" "2"
CORTEX_ROOT="$P" bash "$MAPSH" --set src "$ok120";              assert_eq "[$MODE] [RF 2] accepts 120 accented" "$?" "0"
CORTEX_ROOT="$P" bash "$MAPSH" --set src "$bad121" 2>/dev/null; assert_eq "[$MODE] [RF 2] rejects 121 accented" "$?" "2"
CORTEX_ROOT="$P" bash "$MAPSH" --set src "$(printf 'two\nlines')" 2>/dev/null; assert_eq "[$MODE] rejects multiline" "$?" "2"
CORTEX_ROOT="$P" bash "$MAPSH" --set src "   " 2>/dev/null; assert_eq "[$MODE] rejects blank" "$?" "2"
CORTEX_ROOT="$P" bash "$MAPSH" --set src "Application source."

echo "== [$MODE] check: read-only representability =="
CORTEX_ROOT="$P" bash "$MAPSH" --check "src/api/" 2>/dev/null; assert_eq "[$MODE] check accepts trailing slash" "$?" "0"
CORTEX_ROOT="$P" bash "$MAPSH" --check "a//b" 2>/dev/null; assert_eq "[$MODE] check rejects empty segment" "$?" "2"
CORTEX_ROOT="$P" bash "$MAPSH" --check "$(printf 'a\tb')" 2>/dev/null; assert_eq "[$MODE] check rejects control char" "$?" "2"
CORTEX_ROOT="$P" bash "$MAPSH" --bogus 2>/dev/null; assert_eq "[$MODE] unknown mode exits 2" "$?" "2"
assert_has "[$MODE] usage line" "$(CORTEX_ROOT="$P" bash "$MAPSH" 2>&1)" "usage:"

echo "== [$MODE] set: odd but valid names =="
mkdir -p "$P/my folder/it's" "$P/documentación"; printf 'x\n' > "$P/my folder/it's/f.js"; printf 'x\n' > "$P/documentación/g.md"
CORTEX_ROOT="$P" bash "$MAPSH" --set "my folder/it's" "Quoted name."; assert_eq "[$MODE] apostrophe+space" "$?" "0"
CORTEX_ROOT="$P" bash "$MAPSH" --set "documentación" "Docs."; assert_eq "[$MODE] accented name" "$?" "0"

echo "== [$MODE] drift: + for undescribed, - for gone =="
mkdir -p "$P/lib"; printf 'x\n' > "$P/lib/z.py"
printf 'Old.\n' > "$P/.cortex/map/gone.cortex"
d="$(CORTEX_ROOT="$P" bash "$MAPSH" --drift)"
assert_has "[$MODE] drift + lib" "$d" "+ lib"
assert_has "[$MODE] drift - gone" "$d" "- gone"
assert_no  "[$MODE] drift no + for described src" "$d" "+ src"
assert_eq  "[$MODE] drift + before -" "$(printf '%s\n' "$d" | tail -1)" "- gone"

if [ "$MODE" = git ]; then
  echo "== [git] drift: gitignored folder is not proposed =="
  mkdir -p "$P/build-out"; printf 'x\n' > "$P/build-out/o.js"; printf 'build-out/\n' > "$P/.gitignore"
  d="$(CORTEX_ROOT="$P" bash "$MAPSH" --drift)"
  assert_no "[git] drift ignores gitignored dir" "$d" "build-out"
fi

echo "== [$MODE] [RF 3] project path containing a space =="
S="$TMP/with space/$MODE"; mk_project "$S" "$MODE"; mkdir -p "$S/lib"; printf 'x\n' > "$S/lib/z.py"
CORTEX_ROOT="$S" bash "$MAPSH" --set lib "Libraries."; assert_eq "[$MODE] set in spaced root" "$?" "0"
assert_eq "[$MODE] spaced root file written" "$(cat "$S/.cortex/map/lib.cortex")" "Libraries."
mkdir -p "$S/app"; printf 'x\n' > "$S/app/a.js"
assert_eq "[$MODE] drift in spaced root" "$(CORTEX_ROOT="$S" bash "$MAPSH" --drift)" "+ app"

echo "== [$MODE] find: relevance, AND, cap =="
F="$TMP/find-$MODE"; mk_project "$F" "$MODE"
for d in rsrc/modules/incidents rsrc/shared/state/Incidents rsrc/shared/state rsrc/modules/control-map/CaseManager; do mkdir -p "$F/$d"; printf 'x\n' > "$F/$d/f.js"; done
CORTEX_ROOT="$F" bash "$MAPSH" --set rsrc/modules/control-map/CaseManager "Incident and case panels."
CORTEX_ROOT="$F" bash "$MAPSH" --set rsrc/modules/incidents "Incident manager tab."
CORTEX_ROOT="$F" bash "$MAPSH" --set rsrc/shared/state "Redux store setup."
CORTEX_ROOT="$F" bash "$MAPSH" --set rsrc/shared/state/Incidents "Redux store for the incident manager."
o="$(CORTEX_ROOT="$F" bash "$MAPSH" --find INCIDENT)"
assert_eq "[$MODE] name matches first, alphabetical" "$(printf '%s\n' "$o" | sed -n '1p;2p' | cut -d' ' -f1 | tr '\n' ' ')" "rsrc/modules/incidents/ rsrc/shared/state/Incidents/ "
assert_eq "[$MODE] description-only match last" "$(printf '%s\n' "$o" | tail -1 | cut -d' ' -f1)" "rsrc/modules/control-map/CaseManager/"
o2="$(CORTEX_ROOT="$F" bash "$MAPSH" --find incident state)"
assert_eq "[$MODE] AND narrows" "$(printf '%s\n' "$o2" | wc -l | tr -d ' ')" "1"
assert_has "[$MODE] no match message" "$(CORTEX_ROOT="$F" bash "$MAPSH" --find zzz)" "No folder matches: zzz"
CORTEX_ROOT="$F" bash "$MAPSH" --find >/dev/null 2>&1; assert_eq "[$MODE] find without terms exits 2" "$?" "2"
for blank in "" "   " "$(printf '\t')"; do
  fo="$(CORTEX_ROOT="$F" bash "$MAPSH" --find incident "$blank" 2>"$TMP/fe-$MODE")"; frc=$?
  assert_eq "[$MODE] find rejects blank term [$blank] with exit 2" "$frc" "2"
  assert_eq "[$MODE] find blank term prints no matches" "$fo" ""
  assert_has "[$MODE] find blank term prints usage" "$(cat "$TMP/fe-$MODE")" "usage:"
done
assert_has "[$MODE] backslash term is literal in no-match message" "$(CORTEX_ROOT="$F" bash "$MAPSH" --find 'a\b')" 'No folder matches: a\b'
mkdir -p "$F/re/x"; printf 'x\n' > "$F/re/x/f"
CORTEX_ROOT="$F" bash "$MAPSH" --set re/x "Handles a.b literally; axb is different."
assert_eq "[$MODE] regex chars are literal" "$(CORTEX_ROOT="$F" bash "$MAPSH" --find 'a.b' | cut -d' ' -f1)" "re/x/"
assert_has "[$MODE] literal dot does not match axb" "$(CORTEX_ROOT="$F" bash "$MAPSH" --find 'q.b')" "No folder matches: q.b"
for i in $(seq 1 45); do mkdir -p "$F/many/m$i"; printf 'x\n' > "$F/many/m$i/f"; CORTEX_ROOT="$F" bash "$MAPSH" --set "many/m$i" "Widget $i."; done
o3="$(CORTEX_ROOT="$F" bash "$MAPSH" --find widget)"
assert_eq "[$MODE] cap 40 + overflow line" "$(printf '%s\n' "$o3" | wc -l | tr -d ' ')" "41"
assert_has "[$MODE] overflow text" "$o3" "… 5 more — add another term to narrow"
echo "== [$MODE] [RF 3] find in a project path containing a space =="
mkdir -p "$S/pay/api"; printf 'x\n' > "$S/pay/api/f"
CORTEX_ROOT="$S" bash "$MAPSH" --set pay/api "Payment endpoints."
assert_eq "[$MODE] find in spaced root" "$(CORTEX_ROOT="$S" bash "$MAPSH" --find payment)" "pay/api/  Payment endpoints."

rc(){ CORTEX_ROOT="$1" bash "$MAPSH" --reconcile; }
TAB="$(printf '\t')"
echo "== [$MODE] reconcile: simple rename keeps description =="
Q="$TMP/rn-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/old/sub"; printf 'x\n' > "$Q/old/a.js"; printf 'x\n' > "$Q/old/sub/b.js"
CORTEX_ROOT="$Q" bash "$MAPSH" --set old "Old module."; CORTEX_ROOT="$Q" bash "$MAPSH" --set old/sub "Sub."
rc "$Q" >/dev/null; mv "$Q/old" "$Q/new"
o="$(rc "$Q")"
assert_has "[$MODE] reports move" "$o" "$(printf 'moved\told\tnew')"
assert_eq  "[$MODE] description moved" "$(cat "$Q/.cortex/map/new.cortex")" "Old module."
assert_eq  "[$MODE] subtree moved" "$(cat "$Q/.cortex/map/new/sub.cortex")" "Sub."
assert_eq  "[$MODE] old gone" "$([ -e "$Q/.cortex/map/old.cortex" ] && echo y || echo n)" "n"
assert_no  "[$MODE] nothing pending" "$o" "pending"
assert_eq  "[$MODE] old mirror dir pruned" "$([ -d "$Q/.cortex/map/old" ] && echo y || echo n)" "n"
assert_eq  "[$MODE] snapshot written" "$(cat "$Q/.cortex/.state/tree")" "$(printf 'new/a.js\nnew/sub/b.js')"
assert_eq  "[$MODE] reconcile is idempotent" "$(rc "$Q")" ""

echo "== [$MODE] reconcile: clean stderr and no temp dir left behind =="
Q="$TMP/tmpd-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/a" "$TMP/tmpdir-$MODE"; printf 'x\n' > "$Q/a/f"
o="$(TMPDIR="$TMP/tmpdir-$MODE" CORTEX_ROOT="$Q" bash "$MAPSH" --reconcile 2>"$TMP/err-$MODE")"
assert_eq "[$MODE] tmp: output" "$o" "$(printf 'pending\ta')"
assert_eq "[$MODE] tmp: stderr empty" "$(cat "$TMP/err-$MODE")" ""
assert_eq "[$MODE] tmp: no temp dir left" "$(ls -A "$TMP/tmpdir-$MODE")" ""

echo "== [$MODE] reconcile: move to another branch of the tree =="
Q="$TMP/mv-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/src/x" "$Q/lib"; printf 'x\n' > "$Q/src/x/a.js"; printf 'x\n' > "$Q/src/y.js"; printf 'x\n' > "$Q/lib/l.js"
for d in src src/x lib; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; mv "$Q/src/x" "$Q/lib/x"
o="$(rc "$Q")"
assert_eq  "[$MODE] cross-branch move output" "$o" "$(printf 'moved\tsrc/x\tlib/x')"
assert_eq  "[$MODE] cross-branch description" "$(cat "$Q/.cortex/map/lib/x.cortex")" "D src/x."

echo "== [$MODE] reconcile: rename while renaming files =="
Q="$TMP/ed-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/p" "$Q/q"; for f in a b c; do printf 'x\n' > "$Q/p/$f.js"; printf 'x\n' > "$Q/q/$f.js"; done
CORTEX_ROOT="$Q" bash "$MAPSH" --set p "P."; CORTEX_ROOT="$Q" bash "$MAPSH" --set q "Q."
rc "$Q" >/dev/null
mv "$Q/p" "$Q/p2"; mv "$Q/p2/a.js" "$Q/p2/z.js"
mv "$Q/q" "$Q/q2"; mv "$Q/q2/a.js" "$Q/q2/y.js"; mv "$Q/q2/b.js" "$Q/q2/w.js"
o="$(rc "$Q")"
assert_has "[$MODE] 2 of 3 kept -> moved" "$o" "$(printf 'moved\tp\tp2')"
assert_has "[$MODE] 1 of 3 kept -> removed" "$o" "$(printf 'removed\tq')"
assert_has "[$MODE] 1 of 3 kept -> pending" "$o" "$(printf 'pending\tq2')"
assert_eq  "[$MODE] output order moved, removed, pending" "$(printf '%s\n' "$o" | cut -f1 | tr '\n' ' ')" "moved removed pending "

echo "== [$MODE] reconcile: no snapshot means remove + pending =="
Q="$TMP/ns-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/old"; printf 'x\n' > "$Q/old/a.js"
CORTEX_ROOT="$Q" bash "$MAPSH" --set old "Old."
rc "$Q" >/dev/null; rm -rf "$Q/.cortex/.state"; mv "$Q/old" "$Q/new"
o="$(rc "$Q")"
assert_eq  "[$MODE] no snapshot output" "$o" "$(printf 'removed\told\npending\tnew')"
assert_eq  "[$MODE] snapshot recreated" "$(cat "$Q/.cortex/.state/tree")" "new/a.js"

echo "== [$MODE] reconcile: deleted folder without a pair =="
Q="$TMP/del-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/gone/deep/er" "$Q/stay"; printf 'x\n' > "$Q/gone/deep/er/a.js"; printf 'x\n' > "$Q/stay/s.js"
for d in gone gone/deep gone/deep/er stay; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D."; done
rc "$Q" >/dev/null; rm -rf "$Q/gone"
o="$(rc "$Q")"
assert_eq  "[$MODE] only top-level removed reported" "$o" "$(printf 'removed\tgone')"
assert_eq  "[$MODE] subtree descriptions deleted" "$(find "$Q/.cortex/map" -name '*.cortex' | sed "s|^$Q/.cortex/map/||" | sort)" "stay.cortex"
assert_eq  "[$MODE] mirror dir pruned" "$([ -e "$Q/.cortex/map/gone" ] && echo y || echo n)" "n"

echo "== [$MODE] reconcile: new folders pending by depth =="
Q="$TMP/new-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/a/b" "$Q/z"; printf 'x\n' > "$Q/a/b/f.js"; printf 'x\n' > "$Q/z/f.js"
o="$(rc "$Q")"
assert_eq  "[$MODE] pending depth then C order" "$o" "$(printf 'pending\ta\npending\tz\npending\ta/b')"

echo "== [$MODE] [RF 1] reconcile: rename across odd names =="
Q="$TMP/odd-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/my folder/inner"; printf 'x\n' > "$Q/my folder/a.js"; printf 'x\n' > "$Q/my folder/inner/b.js"
CORTEX_ROOT="$Q" bash "$MAPSH" --set "my folder" "Spaced."; CORTEX_ROOT="$Q" bash "$MAPSH" --set "my folder/inner" "Inner."
rc "$Q" >/dev/null; mv "$Q/my folder" "$Q/it's here"
o="$(rc "$Q")"
assert_eq  "[$MODE] odd-name move output" "$o" "$(printf "moved\tmy folder\tit's here")"
assert_eq  "[$MODE] odd-name description" "$(cat "$Q/.cortex/map/it's here.cortex")" "Spaced."
assert_eq  "[$MODE] odd-name subtree" "$(cat "$Q/.cortex/map/it's here/inner.cortex")" "Inner."

echo "== [$MODE] [RF 4] reconcile: folder with only subfolders =="
Q="$TMP/top-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/top/inner"; printf 'x\n' > "$Q/top/inner/f.js"
CORTEX_ROOT="$Q" bash "$MAPSH" --set top "Top."; CORTEX_ROOT="$Q" bash "$MAPSH" --set top/inner "Inner."
rc "$Q" >/dev/null; mv "$Q/top" "$Q/top2"
o="$(rc "$Q")"
assert_eq  "[$MODE] subfolder-only move" "$o" "$(printf 'moved\ttop\ttop2')"
assert_eq  "[$MODE] subfolder-only description" "$(cat "$Q/.cortex/map/top2.cortex")" "Top."

echo "== [$MODE] [RF 5] reconcile: copy is not a rename =="
Q="$TMP/cp-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/a"; printf 'x\n' > "$Q/a/f.js"
CORTEX_ROOT="$Q" bash "$MAPSH" --set a "A."
rc "$Q" >/dev/null; cp -r "$Q/a" "$Q/b"
o="$(rc "$Q")"
assert_no  "[$MODE] copy: no move" "$o" "moved"
assert_eq  "[$MODE] copy: b pending" "$o" "$(printf 'pending\tb')"
assert_eq  "[$MODE] copy: a intact" "$(cat "$Q/.cortex/map/a.cortex")" "A."

if [ "$MODE" = git ]; then
  echo "== [git] reconcile: gitignored new folder is not pending =="
  Q="$TMP/gi-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/out" "$Q/src"; printf 'x\n' > "$Q/out/o.js"; printf 'x\n' > "$Q/src/s.js"; printf 'out/\n' > "$Q/.gitignore"
  o="$(rc "$Q")"
  assert_eq "[git] gitignored not pending" "$o" "$(printf 'pending\tsrc')"
fi

if [ "$MODE" = git ]; then
  echo "== [git] reconcile: committed folders moved or removed without staging =="
  Q="$TMP/cm-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/src/sub" "$Q/ghost" "$Q/keep"
  printf 'x\n' > "$Q/src/a.js"; printf 'x\n' > "$Q/src/sub/b.js"; printf 'x\n' > "$Q/ghost/g.js"; printf 'x\n' > "$Q/keep/k.js"
  for d in src src/sub ghost keep; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
  ( cd "$Q" && git add -A && git commit -qm init )
  rc "$Q" >/dev/null
  mv "$Q/src" "$Q/source"; rm -rf "$Q/ghost"
  o="$(rc "$Q")"
  assert_eq  "[git] committed: moved + removed, nothing pending" "$o" "$(printf 'moved\tsrc\tsource\nremoved\tghost')"
  assert_no  "[git] committed: old path never pending" "$o" "pending"
  assert_eq  "[git] committed: description followed the rename" "$(cat "$Q/.cortex/map/source/sub.cortex")" "D src/sub."
  assert_eq  "[git] committed: drift empty afterwards" "$(CORTEX_ROOT="$Q" bash "$MAPSH" --drift)" ""
  assert_eq  "[git] committed: snapshot has no stale index paths" "$(cat "$Q/.cortex/.state/tree")" "$(printf 'keep/k.js\nsource/a.js\nsource/sub/b.js')"
  assert_eq  "[git] committed: idempotent" "$(rc "$Q")" ""
  mkdir -p "$Q/staged"; printf 'x\n' > "$Q/staged/s.js"; ( cd "$Q" && git add staged ); rm -rf "$Q/staged"
  assert_eq  "[git] staged-then-deleted folder is not pending" "$(rc "$Q")" ""
  assert_eq  "[git] staged-then-deleted folder not in drift" "$(CORTEX_ROOT="$Q" bash "$MAPSH" --drift)" ""
fi

echo "== [$MODE] reconcile: a failing or missing scan changes nothing =="
for how in fail missing; do
  Q="$TMP/sf-$how-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/.cortex/scripts" "$Q/keep"; printf 'x\n' > "$Q/keep/k.js"
  cp "$MAPSH" "$Q/.cortex/scripts/cortex-map.sh"
  CORTEX_ROOT="$Q" bash "$Q/.cortex/scripts/cortex-map.sh" --set keep "Keep."
  printf 'Gone.\n' > "$Q/.cortex/map/gone.cortex"
  if [ "$how" = fail ]; then printf '#!/usr/bin/env bash\nexit 1\n' > "$Q/.cortex/scripts/cortex-scan.sh"; fi
  CORTEX_ROOT="$Q" bash "$Q/.cortex/scripts/cortex-map.sh" --reconcile >/dev/null 2>&1; rcode=$?
  assert_eq "[$MODE] scan $how: non-zero exit" "$([ "$rcode" -ne 0 ] && echo y || echo n)" "y"
  assert_eq "[$MODE] scan $how: keep intact" "$(cat "$Q/.cortex/map/keep.cortex")" "Keep."
  assert_eq "[$MODE] scan $how: nothing removed" "$(cat "$Q/.cortex/map/gone.cortex")" "Gone."
  assert_eq "[$MODE] scan $how: no snapshot" "$([ -e "$Q/.cortex/.state/tree" ] && echo y || echo n)" "n"
done

echo "== [$MODE] reconcile: 1000 folders, rename 5 =="
Q="$TMP/perf-$MODE"; mk_project "$Q" "$MODE"
for i in $(seq 1 1000); do d="$Q/pkg/m$i"; mkdir -p "$d"; printf 'x\n' > "$d/a.js"; printf 'x\n' > "$d/b.js"; printf 'x\n' > "$d/c.js"; mkdir -p "$Q/.cortex/map/pkg"; printf 'Module %s.\n' "$i" > "$Q/.cortex/map/pkg/m$i.cortex"; done
printf 'Packages.\n' > "$Q/.cortex/map/pkg.cortex"
rc "$Q" >/dev/null
for i in 1 200 400 600 800; do mv "$Q/pkg/m$i" "$Q/pkg/r$i"; done
start=$(date +%s.%N); o="$(rc "$Q")"; end=$(date +%s.%N)
echo "  time: [$MODE] reconcile 1000 folders: $(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.2fs", e-s}')"
assert_eq "[$MODE] perf: 5 moved" "$(printf '%s\n' "$o" | grep -c '^moved')" "5"
assert_eq "[$MODE] perf: only moves" "$(printf '%s\n' "$o" | grep -vc '^moved')" "0"
assert_eq "[$MODE] perf: moved description" "$(cat "$Q/.cortex/map/pkg/r200.cortex")" "Module 200."
done

echo ""; echo "map-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
