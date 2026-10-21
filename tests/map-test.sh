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

echo "== [$MODE] find: accented capitals fold (Latin-1 in UTF-8) =="
Z="$TMP/fold-$MODE"; mk_project "$Z" "$MODE"
mkdir -p "$Z/ordenes" "$Z/Ñandú"; printf 'x\n' > "$Z/ordenes/a.js"; printf 'x\n' > "$Z/Ñandú/b.js"
CORTEX_ROOT="$Z" bash "$MAPSH" --set ordenes "Gestión de Órdenes."
CORTEX_ROOT="$Z" bash "$MAPSH" --set "Ñandú" "Birds."
assert_has "[$MODE] find lower accented term" "$(CORTEX_ROOT="$Z" bash "$MAPSH" --find órdenes)" "ordenes/"
assert_has "[$MODE] find upper accented term" "$(CORTEX_ROOT="$Z" bash "$MAPSH" --find ÓRDENES)" "ordenes/"
assert_has "[$MODE] find folder name Ñandú by ñandú" "$(CORTEX_ROOT="$Z" bash "$MAPSH" --find ñandú)" "Ñandú/"
assert_no  "[$MODE] multiplication sign is not folded" "$(CORTEX_ROOT="$Z" bash "$MAPSH" --find 'gestión de ÷rdenes')" "ordenes/"

echo "== [$MODE] check: invalid UTF-8 names are unrepresentable =="
BADN="$(printf 'bad\377name')"
mkdir -p "$Z/$BADN" 2>/dev/null; printf 'x\n' > "$Z/$BADN/f.js" 2>/dev/null
CORTEX_ROOT="$Z" bash "$MAPSH" --check "$BADN" 2>/dev/null; assert_eq "[$MODE] check rejects 0xFF byte" "$?" "2"
assert_no "[$MODE] drift never lists invalid UTF-8" "$(CORTEX_ROOT="$Z" bash "$MAPSH" --drift 2>/dev/null | od -c)" "377"
assert_no "[$MODE] reconcile never lists invalid UTF-8 as pending" "$(CORTEX_ROOT="$Z" bash "$MAPSH" --reconcile 2>/dev/null | od -c)" "377"
CORTEX_ROOT="$Z" bash "$MAPSH" --check "documentación/Ñandú"; assert_eq "[$MODE] check accepts valid accented name" "$?" "0"

echo "== [$MODE] set: trims whitespace; rejected set leaves nothing behind =="
CORTEX_ROOT="$Z" bash "$MAPSH" --set ordenes "  Source.  "
assert_eq "[$MODE] set trims" "$(cat "$Z/.cortex/map/ordenes.cortex")" "Source."
CORTEX_ROOT="$Z" bash "$MAPSH" --set ordenes "$(printf ' \t ')" 2>/dev/null; assert_eq "[$MODE] blank still rejected" "$?" "2"
mkdir -p "$Z/fresh"
CORTEX_ROOT="$Z" bash "$MAPSH" --set fresh "$(printf 'a\nb')" 2>/dev/null
assert_eq "[$MODE] invalid desc leaves no file" "$([ -e "$Z/.cortex/map/fresh.cortex" ] && echo y || echo n)" "n"
CORTEX_ROOT="$Z" bash "$MAPSH" --set nodir/sub "Desc." 2>/dev/null
assert_eq "[$MODE] missing dir leaves no file" "$([ -e "$Z/.cortex/map/nodir.cortex" ] || [ -e "$Z/.cortex/map/nodir" ] && echo y || echo n)" "n"
CORTEX_ROOT="$Z" bash "$MAPSH" --set ".git/x" "Desc." 2>/dev/null
assert_eq "[$MODE] invalid dir leaves no file" "$([ -e "$Z/.cortex/map/.git" ] && echo y || echo n)" "n"

echo "== [$MODE] check: direct cases =="
for bad in ".git/x" ".cortex/x" "a.cortex" "a/b.cortex/c"; do
  CORTEX_ROOT="$Z" bash "$MAPSH" --check "$bad" 2>/dev/null; assert_eq "[$MODE] check rejects [$bad]" "$?" "2"
done
CORTEX_ROOT="$Z" bash "$MAPSH" --check "src/ok" 2>/dev/null; assert_eq "[$MODE] check accepts [src/ok]" "$?" "0"

echo "== [$MODE] drift: round trip for spaces, apostrophes, accents =="
Y="$TMP/rt-$MODE"; mk_project "$Y" "$MODE"
mkdir -p "$Y/my dir/it's" "$Y/año/ñu"; printf 'x\n' > "$Y/my dir/it's/f"; printf 'x\n' > "$Y/año/ñu/f"
assert_eq "[$MODE] round trip: all listed exactly" "$(CORTEX_ROOT="$Y" bash "$MAPSH" --drift)" "$(printf '+ año\n+ año/ñu\n+ my dir\n+ my dir/it'"'"'s')"
for dd in "my dir" "my dir/it's" "año" "año/ñu"; do CORTEX_ROOT="$Y" bash "$MAPSH" --set "$dd" "D."; done
assert_eq "[$MODE] round trip: described are not listed" "$(CORTEX_ROOT="$Y" bash "$MAPSH" --drift)" ""

echo "== guard: unresolvable script dir with CORTEX_ROOT unset =="
g_out="$(env -u CORTEX_ROOT bash -c "$(cat "$MAPSH")" "$TMP/no-such-dir/cortex-map.sh" --check x 2>&1)"; g_rc=$?
assert_eq "root guard: exit 2" "$g_rc" "2"
assert_has "root guard: clear message" "$g_out" "cannot resolve"

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

echo "== [$MODE] dirs: every representable scanned folder, described or not =="
DR="$TMP/dirs-$MODE"; mk_project "$DR" "$MODE"
mkdir -p "$DR/src/a" "$DR/src/b" "$DR/my dir/it's" "$DR/ignored-out"
for d in src/a src/b "my dir/it's" ignored-out; do printf 'x\n' > "$DR/$d/f.js"; done
[ "$MODE" = git ] && printf 'ignored-out/\n' > "$DR/.gitignore"
CORTEX_ROOT="$DR" bash "$MAPSH" --set src/a "Alpha service."
before="$(find "$DR/.cortex/map" -type f | sort | xargs cat | md5sum)"
want="$(printf "my dir\nmy dir/it's\nsrc\nsrc/a\nsrc/b")"
[ "$MODE" = plain ] && want="$(printf "ignored-out\nmy dir\nmy dir/it's\nsrc\nsrc/a\nsrc/b")"
assert_eq "[$MODE] dirs lists described and undescribed folders" "$(CORTEX_ROOT="$DR" bash "$MAPSH" --dirs)" "$want"
CORTEX_ROOT="$DR" bash "$MAPSH" --dirs extra 2>/dev/null; assert_eq "[$MODE] dirs rejects extra args" "$?" "2"
assert_eq "[$MODE] dirs changes nothing" "$(find "$DR/.cortex/map" -type f | sort | xargs cat | md5sum)" "$before"


if [ "$MODE" = git ]; then
echo "== [git] map files must never be git-ignored =="
GI="$TMP/gitign-git"; mk_project "$GI" git
printf 'reports\n' > "$GI/.gitignore"
mkdir -p "$GI/src/reports/sub"; printf 'x\n' > "$GI/src/reports/a.js"; printf 'x\n' > "$GI/src/reports/sub/b.js"
( cd "$GI" && git add -f src/reports/a.js src/reports/sub/b.js )
gm() { CORTEX_ROOT="$GI" bash "$MAPSH" "$@"; }
gm --set src "Source area." 2>/dev/null; gm --set src/reports "Report screens." 2>/dev/null
gm --set src/reports/sub "Report sub-widgets." 2>"$TMP/gi-err"
assert_eq "[git] --set creates the map .gitignore" "$([ -f "$GI/.cortex/map/.gitignore" ] && echo y || echo n)" "y"
assert_eq "[git] a folder under an ignored name is not ignored" "$(cd "$GI" && git check-ignore -q .cortex/map/src/reports/sub.cortex && echo ignored || echo ok)" "ok"
assert_has "[git] git would add the nested map file" "$(cd "$GI" && git add -A -n)" "src/reports/sub.cortex"
assert_eq "[git] --set stays quiet when nothing is ignored" "$(cat "$TMP/gi-err")" ""
assert_eq "[git] --ignored is empty and exits 0" "$(gm --ignored; echo "rc=$?")" "rc=0"
rm -f "$GI/.cortex/map/.gitignore"
assert_eq "[git] --ignored lists the map files git would drop" "$(gm --ignored)" "src/reports/sub"
gm --reconcile >/dev/null
assert_eq "[git] --reconcile restores the map .gitignore" "$([ -f "$GI/.cortex/map/.gitignore" ] && echo y || echo n)" "y"
assert_eq "[git] --ignored is empty after reconcile" "$(gm --ignored)" ""
printf '.cortex/map/\n' > "$GI/.gitignore"
gm --set src/reports "Report screens, revised." 2>"$TMP/gi-err"; assert_eq "[git] --set still succeeds when the map itself is ignored" "$?" "0"
assert_has "[git] --set warns when git ignores the file it wrote" "$(cat "$TMP/gi-err")" "git ignores"
assert_has "[git] --ignored lists them when the project ignores the map" "$(gm --ignored)" "src/reports"
fi
if [ "$MODE" = plain ]; then
echo "== [plain] no git, no map .gitignore =="
PI="$TMP/gitign-plain"; mk_project "$PI" plain; mkdir -p "$PI/lib"; printf 'x\n' > "$PI/lib/a.js"
CORTEX_ROOT="$PI" bash "$MAPSH" --set lib "Libraries."
assert_eq "[plain] no map .gitignore outside git" "$([ -e "$PI/.cortex/map/.gitignore" ] && echo y || echo n)" "n"
assert_eq "[plain] --ignored is empty and exits 0" "$(CORTEX_ROOT="$PI" bash "$MAPSH" --ignored; echo "rc=$?")" "rc=0"
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
echo "== [$MODE] find: inherited path matches fold into their listed ancestor =="
FG="$TMP/findgroup-$MODE"; mk_project "$FG" "$MODE"
for d in mod/incidents/components/new-incident mod/incidents/hooks/deep mod/incidents/views app/x; do mkdir -p "$FG/$d"; printf 'x\n' > "$FG/$d/f.js"; done
CORTEX_ROOT="$FG" bash "$MAPSH" --set mod/incidents "Incident manager tab."
CORTEX_ROOT="$FG" bash "$MAPSH" --set mod/incidents/components "UI pieces."
CORTEX_ROOT="$FG" bash "$MAPSH" --set mod/incidents/components/new-incident "Creation modal."
CORTEX_ROOT="$FG" bash "$MAPSH" --set mod/incidents/hooks "Data hooks."
CORTEX_ROOT="$FG" bash "$MAPSH" --set mod/incidents/hooks/deep "Polling helpers."
CORTEX_ROOT="$FG" bash "$MAPSH" --set mod/incidents/views "Pages."
CORTEX_ROOT="$FG" bash "$MAPSH" --set app "Incident app root."
CORTEX_ROOT="$FG" bash "$MAPSH" --set app/x "Incident widgets."
og="$(CORTEX_ROOT="$FG" bash "$MAPSH" --find incident)"
assert_has "[$MODE] ancestor line counts its folded subfolders" "$og" "mod/incidents/  Incident manager tab. (+4 subfolders match)"
assert_no  "[$MODE] inherited child is folded" "$og" "mod/incidents/components/  "
assert_no  "[$MODE] inherited grandchild is folded" "$og" "mod/incidents/hooks/deep/"
assert_has "[$MODE] child matching by its own name stays listed" "$og" "mod/incidents/components/new-incident/  Creation modal."
assert_has "[$MODE] description-only ancestor folds nothing" "$og" "app/x/  Incident widgets."
assert_eq  "[$MODE] folded output line count" "$(printf '%s\n' "$og" | wc -l | tr -d ' ')" "4"
mkdir -p "$FG/solo/incidents/one"; printf 'x\n' > "$FG/solo/incidents/one/f.js"
CORTEX_ROOT="$FG" bash "$MAPSH" --set solo/incidents "Solo incidents."
CORTEX_ROOT="$FG" bash "$MAPSH" --set solo/incidents/one "Only child."
assert_has "[$MODE] a single folded subfolder is singular" "$(CORTEX_ROOT="$FG" bash "$MAPSH" --find solo incident)" "solo/incidents/  Solo incidents. (+1 subfolder matches)"
mkdir -p "$FG/wide/incidents/a"; printf 'x\n' > "$FG/wide/incidents/a/f.js"
CORTEX_ROOT="$FG" bash "$MAPSH" --set wide "Incident everything."
CORTEX_ROOT="$FG" bash "$MAPSH" --set wide/incidents/a "Area a."
ow="$(CORTEX_ROOT="$FG" bash "$MAPSH" --find incident)"
assert_has "[$MODE] description-only ancestor never hosts a fold" "$ow" "wide/  Incident everything."
assert_no  "[$MODE] description-only ancestor shows no count" "$ow" "Incident everything. (+"
assert_has "[$MODE] match under a description-only ancestor stays" "$ow" "wide/incidents/a/  Area a."
mkdir -p "$FG/loose/incidents/b"; printf 'x\n' > "$FG/loose/incidents/b/f.js"
CORTEX_ROOT="$FG" bash "$MAPSH" --set loose/incidents/b "Area b."
assert_has "[$MODE] inherited match without a listed ancestor stays" "$(CORTEX_ROOT="$FG" bash "$MAPSH" --find incident)" "loose/incidents/b/  Area b."
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

echo "== [$MODE] reconcile: nested rename, parent scores low on its own =="
# Most of p's files live in p/c, which is renamed too: p alone matches q on 2
# of 5 paths, so p is only recognised once p/c -> q/d is folded into its score.
Q="$TMP/nest-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/p/c" "$Q/p/z"
printf 'x\n' > "$Q/p/a.js"; for f in b e h; do printf 'x\n' > "$Q/p/c/$f.js"; done; printf 'x\n' > "$Q/p/z/g.js"
for d in p p/c p/z; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; mv "$Q/p" "$Q/q"; mv "$Q/q/c" "$Q/q/d"
o="$(rc "$Q")"
assert_eq  "[$MODE] nested low: output" "$o" "$(printf 'moved\tp\tq\nmoved\tp/c\tq/d')"
assert_eq  "[$MODE] nested low: parent description" "$(cat "$Q/.cortex/map/q.cortex" 2>/dev/null)" "D p."
assert_eq  "[$MODE] nested low: child description" "$(cat "$Q/.cortex/map/q/d.cortex" 2>/dev/null)" "D p/c."
assert_eq  "[$MODE] nested low: carried sibling" "$(cat "$Q/.cortex/map/q/z.cortex" 2>/dev/null)" "D p/z."
assert_eq  "[$MODE] nested low: drift empty" "$(CORTEX_ROOT="$Q" bash "$MAPSH" --drift)" ""
assert_eq  "[$MODE] nested low: idempotent" "$(rc "$Q")" ""

echo "== [$MODE] reconcile: nested rename, parent matches on its own =="
# p matches q directly; its subfolder p/c no longer sits at q/c and must be
# matched on its own instead of following p to a folder that does not exist.
Q="$TMP/nest2-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/p/c" "$Q/p/z"
for f in a y w; do printf 'x\n' > "$Q/p/$f.js"; done; printf 'x\n' > "$Q/p/c/b.js"; printf 'x\n' > "$Q/p/z/g.js"
for d in p p/c p/z; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; mv "$Q/p" "$Q/q"; mv "$Q/q/c" "$Q/q/d"
o="$(rc "$Q")"
assert_eq  "[$MODE] nested high: output" "$o" "$(printf 'moved\tp\tq\nmoved\tp/c\tq/d')"
assert_eq  "[$MODE] nested high: parent description" "$(cat "$Q/.cortex/map/q.cortex" 2>/dev/null)" "D p."
assert_eq  "[$MODE] nested high: child description" "$(cat "$Q/.cortex/map/q/d.cortex" 2>/dev/null)" "D p/c."
assert_eq  "[$MODE] nested high: carried sibling" "$(cat "$Q/.cortex/map/q/z.cortex" 2>/dev/null)" "D p/z."
assert_eq  "[$MODE] nested high: drift empty" "$(CORTEX_ROOT="$Q" bash "$MAPSH" --drift)" ""

echo "== [$MODE] reconcile: ties prefer the same name, then the same parent =="
# Equal scores everywhere. By name alone b/one would go to a/sub/dos and
# src/util to src/aaa; location must win instead.
Q="$TMP/tie-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/x/one" "$Q/y/two" "$Q/b/one" "$Q/a/sub/two" "$Q/src/util"
for d in x/one y/two b/one a/sub/two src/util; do printf 'x\n' > "$Q/$d/index.js"; CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
printf 'x\n' > "$Q/src/keep.js"
for d in src x y b a a/sub; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null
mv "$Q/x/one" "$Q/x/uno"; mv "$Q/y/two" "$Q/y/dos"; mv "$Q/b/one" "$Q/b/uno"; mv "$Q/a/sub/two" "$Q/a/sub/dos"
mkdir -p "$Q/zz"; mv "$Q/src/util" "$Q/zz/util"; mkdir -p "$Q/src/aaa"; printf 'x\n' > "$Q/src/aaa/index.js"
o="$(rc "$Q")"
assert_has "[$MODE] tie: x/one -> x/uno" "$o" "$(printf 'moved\tx/one\tx/uno')"
assert_has "[$MODE] tie: y/two -> y/dos" "$o" "$(printf 'moved\ty/two\ty/dos')"
assert_has "[$MODE] tie: b/one -> b/uno (same parent beats lower name)" "$o" "$(printf 'moved\tb/one\tb/uno')"
assert_has "[$MODE] tie: a/sub/two -> a/sub/dos" "$o" "$(printf 'moved\ta/sub/two\ta/sub/dos')"
assert_has "[$MODE] tie: src/util -> zz/util (same name beats same parent)" "$o" "$(printf 'moved\tsrc/util\tzz/util')"
assert_has "[$MODE] tie: src/aaa pending" "$o" "$(printf 'pending\tsrc/aaa')"

echo "== [$MODE] reconcile: every level of single-file folders renamed =="
# a, a/b and a/b/c each hold one f.js. All scores tie at every level, so only
# the shape of each folder (file depths inside it) and its depth tell them apart.
Q="$TMP/chain-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/a/b/c"
for d in a a/b a/b/c; do printf 'x\n' > "$Q/$d/f.js"; CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; mv "$Q/a" "$Q/x"; mv "$Q/x/b" "$Q/x/y"; mv "$Q/x/y/c" "$Q/x/y/z"
o="$(rc "$Q")"
assert_eq  "[$MODE] chain: output" "$o" "$(printf 'moved\ta\tx\nmoved\ta/b\tx/y\nmoved\ta/b/c\tx/y/z')"
assert_eq  "[$MODE] chain: a kept" "$(cat "$Q/.cortex/map/x.cortex" 2>/dev/null)" "D a."
assert_eq  "[$MODE] chain: a/b kept" "$(cat "$Q/.cortex/map/x/y.cortex" 2>/dev/null)" "D a/b."
assert_eq  "[$MODE] chain: a/b/c kept" "$(cat "$Q/.cortex/map/x/y/z.cortex" 2>/dev/null)" "D a/b/c."
assert_eq  "[$MODE] chain: drift empty" "$(CORTEX_ROOT="$Q" bash "$MAPSH" --drift)" ""
assert_eq  "[$MODE] chain: idempotent" "$(rc "$Q")" ""

echo "== [$MODE] reconcile: equal shape, the same depth beats the lower name =="
Q="$TMP/dep-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/a/b"; printf 'x\n' > "$Q/a/keep.js"; printf 'x\n' > "$Q/a/b/g.js"
for d in a a/b; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; mkdir -p "$Q/zz"; mv "$Q/a/b" "$Q/zz/q"; mkdir -p "$Q/e"; printf 'x\n' > "$Q/e/g.js"
o="$(rc "$Q")"
assert_has "[$MODE] depth: a/b -> zz/q" "$o" "$(printf 'moved\ta/b\tzz/q')"
assert_has "[$MODE] depth: e pending" "$o" "$(printf 'pending\te')"

echo "== [$MODE] reconcile: equal depth, the same shape beats the lower name =="
Q="$TMP/shp-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/m/k"; printf 'x\n' > "$Q/m/keep.js"; printf 'x\n' > "$Q/m/k/f.js"
for d in m m/k; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; mkdir -p "$Q/n/aa/other"; mv "$Q/m/k" "$Q/n/zz"; printf 'x\n' > "$Q/n/aa/f.js"; printf 'x\n' > "$Q/n/aa/other/x.js"
o="$(rc "$Q")"
assert_has "[$MODE] shape: m/k -> n/zz" "$o" "$(printf 'moved\tm/k\tn/zz')"
assert_has "[$MODE] shape: n/aa pending" "$o" "$(printf 'pending\tn/aa')"

echo "== [$MODE] reconcile: a removed subfolder of a moved parent is reported by its old path =="
Q="$TMP/rmsub-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/p/c"
printf 'x\n' > "$Q/p/a.js"; printf 'x\n' > "$Q/p/b.js"; printf 'x\n' > "$Q/p/c/k.js"
for d in p p/c; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; mv "$Q/p" "$Q/q"; rm -rf "$Q/q/c"
o="$(rc "$Q")"
assert_eq  "[$MODE] rmsub: output" "$o" "$(printf 'moved\tp\tq\nremoved\tp/c')"
assert_no  "[$MODE] rmsub: never the new path" "$o" "q/c"
assert_eq  "[$MODE] rmsub: description gone" "$([ -e "$Q/.cortex/map/q/c.cortex" ] && echo y || echo n)" "n"
assert_eq  "[$MODE] rmsub: parent kept" "$(cat "$Q/.cortex/map/q.cortex" 2>/dev/null)" "D p."
assert_eq  "[$MODE] rmsub: drift empty" "$(CORTEX_ROOT="$Q" bash "$MAPSH" --drift)" ""

echo "== [$MODE] reconcile: a failing step reports what was done, then the error =="
# The map destination of the second move is blocked by a plain file where its
# mirror directory must go: mkdir fails even for root, unlike chmod.
Q="$TMP/pf-$MODE"; mk_project "$Q" "$MODE"; mkdir -p "$Q/a" "$Q/b" "$Q/x" "$Q/gone"
printf 'x\n' > "$Q/a/f.js"; printf 'x\n' > "$Q/b/g.js"; printf 'x\n' > "$Q/x/h.js"; printf 'x\n' > "$Q/gone/k.js"
for d in a b x gone; do CORTEX_ROOT="$Q" bash "$MAPSH" --set "$d" "D $d."; done
rc "$Q" >/dev/null; cp "$Q/.cortex/.state/tree" "$TMP/pf-tree-$MODE"
mv "$Q/a" "$Q/a2"; mv "$Q/b" "$Q/x/b"; rm -rf "$Q/gone"; printf 'blocker\n' > "$Q/.cortex/map/x"
o="$(rc "$Q" 2>/dev/null)"; prc=$?
assert_eq  "[$MODE] partial: non-zero exit" "$([ "$prc" -ne 0 ] && echo y || echo n)" "y"
assert_eq  "[$MODE] partial: done line then error line" "$(printf '%s\n' "$o" | cut -f1 | tr '\n' ' ')" "moved error "
assert_eq  "[$MODE] partial: first line is the move" "$(printf '%s\n' "$o" | sed -n 1p)" "$(printf 'moved\ta\ta2')"
assert_has "[$MODE] partial: error names the folder" "$(printf '%s\n' "$o" | sed -n 2p)" "b"
assert_eq  "[$MODE] partial: the move happened" "$(cat "$Q/.cortex/map/a2.cortex" 2>/dev/null)" "D a."
assert_eq  "[$MODE] partial: snapshot not written" "$(cat "$Q/.cortex/.state/tree")" "$(cat "$TMP/pf-tree-$MODE")"
rm -f "$Q/.cortex/map/x"

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
