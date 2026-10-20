#!/usr/bin/env bash
# CORTEX — describe-queue test harness (cortex-describe.sh). No Claude session needed.
# Every block runs twice: in a git repo (MODE=git) and in a plain folder (MODE=plain).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); }
assert_eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$3] got [$2]"; }
assert_has(){ printf '%s\n' "$2" | grep -qF -- "$3" && ok "$1" || no "$1" "missing [$3] in [$2]"; }
assert_no(){ printf '%s\n' "$2" | grep -qF -- "$3" && no "$1" "unexpected [$3]" || ok "$1"; }

MAPSH="$REPO_ROOT/.cortex/scripts/cortex-map.sh"
DESCSH="$REPO_ROOT/.cortex/scripts/cortex-describe.sh"

# mk_project DIR MODE — a CORTEX project (git repo when MODE=git, plain folder otherwise)
mk_project() {
  mkdir -p "$1/.cortex/map" "$1/.cortex/scripts"
  cp "$REPO_ROOT/.cortex/scripts/"*.sh "$1/.cortex/scripts/"
  [ "$2" = git ] && ( cd "$1" && git init -q && git config user.email t@t && git config user.name t )
  return 0
}
# mkf PROJECT PATH... — create each folder with one small file
mkf() { local p="$1" d; shift; for d in "$@"; do mkdir -p "$p/$d"; printf 'x\n' > "$p/$d/f.js"; done; }

for MODE in git plain; do
P="$TMP/show-$MODE"; mk_project "$P" "$MODE"
dsc() { CORTEX_ROOT="$P" bash "$DESCSH" "$@"; }

echo "== [$MODE] show: content digest =="
mkdir -p "$P/src/api/v1" "$P/my dir/it's" "$P/documentación" "$P/blobs" "$P/100%" "$P/empty-leaf-parent/child" "$P/many" "$P/big"
printf 'x\n' > "$P/src/api/a.js"; printf 'yy\n' > "$P/src/api/b.js"; printf 'x\n' > "$P/src/api/v1/c.py"
printf 'x\n' > "$P/my dir/it's/f.txt"; printf 'x\n' > "$P/documentación/léeme.md"
printf '\0\1\2' > "$P/blobs/blob.bin"; printf 'x\n' > "$P/100%/y.js"; printf 'x\n' > "$P/empty-leaf-parent/child/x.js"
for i in $(seq -w 1 70); do printf 'x\n' > "$P/many/f$i.txt"; done
for i in $(seq 1 100); do printf '%0500d\n' 7; done > "$P/big/long.txt"

out="$(dsc --show src/api)"
assert_eq "[$MODE] show header" "$(printf '%s\n' "$out" | head -1)" "== CONTENTS of src/api =="
assert_has "[$MODE] show file a.js" "$out" "FILE a.js 2"
assert_has "[$MODE] show file b.js" "$out" "FILE b.js 3"
assert_has "[$MODE] show subfolder not described" "$out" "DIR v1: (not yet described)"
assert_has "[$MODE] show extension histogram" "$out" "EXT js 2"
assert_has "[$MODE] show excerpt" "$out" "== EXCERPT a.js =="
assert_eq "[$MODE] show ends with END" "$(printf '%s\n' "$out" | tail -1)" "== END =="
assert_has "[$MODE] show odd name (space+apostrophe)" "$(dsc --show "my dir/it's")" "FILE f.txt 2"
assert_has "[$MODE] show accented name" "$(dsc --show documentación)" "FILE léeme.md 2"
assert_has "[$MODE] show percent name" "$(dsc --show '100%')" "FILE y.js 2"
bo="$(dsc --show blobs)"
assert_has "[$MODE] show binary listed" "$bo" "FILE blob.bin 3"
assert_no  "[$MODE] show binary has no excerpt" "$bo" "== EXCERPT blob.bin =="
eo="$(dsc --show empty-leaf-parent)"
assert_has "[$MODE] show NOFILES" "$eo" "NOFILES"
assert_has "[$MODE] show lists child" "$eo" "DIR child:"
mo="$(dsc --show many)"
assert_eq "[$MODE] show caps file list at 60" "$(printf '%s\n' "$mo" | grep -c '^FILE ')" "60"
assert_has "[$MODE] show reports the rest" "$mo" "… 10 more"
bg="$(dsc --show big)"
block="$(printf '%s\n' "$bg" | sed -n '/^== EXCERPT long.txt ==$/,/^== END ==$/p' | sed '1d;$d')"
assert_eq "[$MODE] excerpt is at most 30 lines" "$([ "$(printf '%s\n' "$block" | wc -l)" -le 30 ] && echo y || echo n)" "y"
assert_eq "[$MODE] excerpt lines are cut at 200 chars" "$(printf '%s\n' "$block" | awk '{ if (length($0) > m) m = length($0) } END { print (m <= 200) ? "y" : "n" }')" "y"
assert_eq "[$MODE] excerpt is at most 6000 bytes" "$([ "$(printf '%s' "$block" | wc -c)" -le 6000 ] && echo y || echo n)" "y"
dsc --show nope 2>/dev/null; assert_eq "[$MODE] show of a missing folder exits 2" "$?" "2"
dsc 2>/dev/null; assert_eq "[$MODE] no subcommand exits 2" "$?" "2"
dsc --bogus 2>/dev/null; assert_eq "[$MODE] unknown subcommand exits 2" "$?" "2"
assert_eq "[$MODE] show does not create the marker" "$([ -e "$P/.cortex/.state/describe/active" ] && echo y || echo n)" "n"
done

# Hand-set a folder state / read a state file (white-box helpers for the tests).
enc_t() { local x="${1//%/%25}"; printf '%s' "${x//\//%2F}"; }
setst() { mkdir -p "$1/.cortex/.state/describe/f/$(enc_t "$2")"; printf '%s\n' "$3" > "$1/.cortex/.state/describe/f/$(enc_t "$2")/state"; }
getst() { cat "$1/.cortex/.state/describe/f/$(enc_t "$2")/state" 2>/dev/null; }
mapsum() { find "$1/.cortex/map" -type f | sort | xargs cat 2>/dev/null | md5sum; }

for MODE in git plain; do
echo "== [$MODE] init: pending folders only, nothing touched =="
Q="$TMP/init-$MODE"; mk_project "$Q" "$MODE"; mkf "$Q" src/a src/b lib
CORTEX_ROOT="$Q" bash "$MAPSH" --set lib "Library of utilities."
qs() { CORTEX_ROOT="$Q" bash "$DESCSH" "$@"; }
before="$(mapsum "$Q")"
qs --init >/dev/null; assert_eq "[$MODE] init exits 0" "$?" "0"
assert_eq "[$MODE] scope is the undescribed folders" "$(cat "$Q/.cortex/.state/describe/scope")" "$(printf 'src\nsrc/a\nsrc/b')"
assert_eq "[$MODE] mode is pending" "$(cat "$Q/.cortex/.state/describe/mode")" "pending"
assert_eq "[$MODE] every folder starts todo" "$(for d in src src/a src/b; do getst "$Q" "$d"; done | sort -u)" "todo"
assert_eq "[$MODE] marker created" "$([ -e "$Q/.cortex/.state/describe/active" ] && echo y || echo n)" "y"
assert_eq "[$MODE] init leaves the map untouched" "$(mapsum "$Q")" "$before"
so="$(qs --status)"; rc=$?
assert_eq "[$MODE] status counts" "$(printf '%s\n' "$so" | head -1)" "todo=3 claimed=0 written=0 verified=0 needs-human=0"
assert_eq "[$MODE] status is incomplete" "$rc" "1"
assert_has "[$MODE] status lists blockers" "$so" "$(printf 'BLOCKED\tsrc/a\ttodo')"

echo "== [$MODE] init --all: everything queued, no description deleted =="
A="$TMP/initall-$MODE"; mk_project "$A" "$MODE"; mkf "$A" one two three
CORTEX_ROOT="$A" bash "$MAPSH" --set one "First area."; CORTEX_ROOT="$A" bash "$MAPSH" --set two "Second area."
before="$(mapsum "$A")"
CORTEX_ROOT="$A" bash "$DESCSH" --init --all >/dev/null
assert_eq "[$MODE] all: scope has every folder" "$(cat "$A/.cortex/.state/describe/scope")" "$(printf 'one\nthree\ntwo')"
assert_eq "[$MODE] all: mode recorded" "$(cat "$A/.cortex/.state/describe/mode")" "all"
assert_eq "[$MODE] all: no description deleted at init" "$(mapsum "$A")" "$before"

echo "== [$MODE] init: resumes a queue in progress =="
setst "$Q" src/a verified; setst "$Q" src/b claimed-write; setst "$Q" src claimed-verify
rm -rf "$Q/src/b"; mkf "$Q" docs
qs --init >/dev/null; assert_eq "[$MODE] resume exits 0" "$?" "0"
assert_eq "[$MODE] resume: scope follows the tree" "$(cat "$Q/.cortex/.state/describe/scope")" "$(printf 'docs\nsrc\nsrc/a')"
assert_eq "[$MODE] resume keeps verified work" "$(getst "$Q" src/a)" "verified"
assert_eq "[$MODE] resume: unfinished verification goes back to written" "$(getst "$Q" src)" "written"
assert_eq "[$MODE] resume: new folder is todo" "$(getst "$Q" docs)" "todo"
assert_eq "[$MODE] resume: vanished folder state removed" "$([ -e "$Q/.cortex/.state/describe/f/$(enc_t src/b)" ] && echo y || echo n)" "n"
setst "$Q" docs claimed-write; qs --init >/dev/null
assert_eq "[$MODE] resume: unfinished write goes back to todo" "$(getst "$Q" docs)" "todo"
qs --init --all >/dev/null 2>"$TMP/err"; assert_eq "[$MODE] --all on an existing queue is refused" "$?" "2"
assert_has "[$MODE] refusal points to --restart" "$(cat "$TMP/err")" "--restart"
qs --init --restart >/dev/null
assert_eq "[$MODE] restart rebuilds from scratch" "$(for d in docs src src/a; do getst "$Q" "$d"; done | sort -u)" "todo"

echo "== [$MODE] init: reconcile runs first =="
R="$TMP/initrec-$MODE"; mk_project "$R" "$MODE"; mkf "$R" old
CORTEX_ROOT="$R" bash "$MAPSH" --set old "Legacy billing."
CORTEX_ROOT="$R" bash "$MAPSH" --reconcile >/dev/null
mv "$R/old" "$R/new"
CORTEX_ROOT="$R" bash "$DESCSH" --init --all >/dev/null
assert_eq "[$MODE] renamed folder kept its description" "$(cat "$R/.cortex/map/new.cortex" 2>/dev/null)" "Legacy billing."
assert_eq "[$MODE] renamed folder is in scope, old path is not" "$(cat "$R/.cortex/.state/describe/scope")" "new"
done

for MODE in git plain; do
echo "== [$MODE] next/submit: order, dependencies, exit codes =="
W="$TMP/write-$MODE"; mk_project "$W" "$MODE"; mkf "$W" src/api/v1
wd() { CORTEX_ROOT="$W" bash "$DESCSH" "$@"; }
wd --init >/dev/null
o="$(wd --next --role write --worker w1)"; rc=$?
assert_eq "[$MODE] next exits 0" "$rc" "0"
assert_eq "[$MODE] deepest folder first" "$(printf '%s\n' "$o" | head -1)" "TASK write src/api/v1"
assert_has "[$MODE] next carries the digest" "$o" "== CONTENTS of src/api/v1 =="
assert_eq "[$MODE] claimed for the worker" "$(getst "$W" src/api/v1) $(cat "$W/.cortex/.state/describe/f/$(enc_t src/api/v1)/worker")" "claimed-write w1"
wd --next --role write --worker w2 >/dev/null; assert_eq "[$MODE] parents wait for their children (exit 3)" "$?" "3"
wd --submit src/api/v1 "Migration scripts for the v1 API" --worker w2 2>/dev/null; assert_eq "[$MODE] submit by another worker is refused" "$?" "1"
wd --submit src/api "Early guess" --worker w1 2>/dev/null; assert_eq "[$MODE] submit of an unclaimed folder is refused" "$?" "1"
wd --submit src/api/v1 "$(printf 'z%.0s' $(seq 121))" --worker w1 2>/dev/null; assert_eq "[$MODE] a description the map rejects is refused" "$?" "1"
assert_eq "[$MODE] refused submit leaves state and map alone" "$(getst "$W" src/api/v1) $([ -e "$W/.cortex/map/src/api/v1.cortex" ] && echo map || echo nomap)" "claimed-write nomap"
wd --submit src/api/v1 "Migration scripts for the v1 API" --worker w1 >/dev/null; assert_eq "[$MODE] submit exits 0" "$?" "0"
assert_eq "[$MODE] description is in the map" "$(cat "$W/.cortex/map/src/api/v1.cortex")" "Migration scripts for the v1 API"
assert_eq "[$MODE] state is written, writer recorded" "$(getst "$W" src/api/v1) $(cat "$W/.cortex/.state/describe/f/$(enc_t src/api/v1)/writer")" "written w1"
assert_eq "[$MODE] hash recorded" "$(cat "$W/.cortex/.state/describe/f/$(enc_t src/api/v1)/hash")" "$(cksum < "$W/.cortex/map/src/api/v1.cortex")"
wd --next --role write --worker w2 >/dev/null; assert_eq "[$MODE] child written but unverified still blocks the parent (exit 3)" "$?" "3"
setst "$W" src/api/v1 verified
assert_eq "[$MODE] verified child unblocks the parent" "$(wd --next --role write --worker w2 | head -1)" "TASK write src/api"
setst "$W" src/api verified; setst "$W" src verified
wd --next --role write --worker w2 >/dev/null; assert_eq "[$MODE] nothing left for write (exit 4)" "$?" "4"
wd --next --role write 2>/dev/null; assert_eq "[$MODE] next without a worker exits 2" "$?" "2"
wd --next --role bogus --worker w1 2>/dev/null; assert_eq "[$MODE] next with a bad role exits 2" "$?" "2"

echo "== [$MODE] next: previous rejection is shown to the next writer =="
setst "$W" src todo; setst "$W" src/api todo
printf '%s\n' 2 > "$W/.cortex/.state/describe/f/$(enc_t src/api)/rejects"; printf '%s\n' "too vague" > "$W/.cortex/.state/describe/f/$(enc_t src/api)/reason"
assert_has "[$MODE] REJECTED line" "$(wd --next --role write --worker w3)" "REJECTED: too vague"

echo "== [$MODE] next/submit: odd folder names =="
O="$TMP/odd-$MODE"; mk_project "$O" "$MODE"; mkf "$O" "my dir/it's" documentación
od() { CORTEX_ROOT="$O" bash "$DESCSH" "$@"; }
od --init >/dev/null
for want in "my dir/it's" documentación; do
  got="$(od --next --role write --worker w1 | head -1 | sed 's/^TASK write //')"
  assert_eq "[$MODE] served $want" "$got" "$want"
  od --submit "$got" "Notes about $RANDOM things" --worker w1 >/dev/null; assert_eq "[$MODE] submitted $want" "$?" "0"
  assert_eq "[$MODE] written $want" "$(getst "$O" "$got")" "written"
done

echo "== [$MODE] next: concurrent workers never share a folder =="
C="$TMP/conc-$MODE"; mk_project "$C" "$MODE"; mkf "$C" $(seq -f 'c%02g' 1 12)
cd_() { CORTEX_ROOT="$C" bash "$DESCSH" "$@"; }
cd_ --init >/dev/null
: > "$TMP/served-$MODE"
worker_loop() {
  local id="$1" o rc dir
  while true; do
    o="$(cd_ --next --role write --worker "$id")"; rc=$?
    case "$rc" in
      0) dir="$(printf '%s\n' "$o" | head -1 | sed 's/^TASK write //')"
         printf '%s\n' "$dir" >> "$TMP/served-$MODE"
         cd_ --submit "$dir" "Description of the $dir area" --worker "$id" >/dev/null ;;
      3) sleep 0.05 ;;
      *) break ;;
    esac
  done
}
for i in 1 2 3 4 5 6; do worker_loop "cw$i" & done; wait
assert_eq "[$MODE] every folder served exactly once" "$(sort "$TMP/served-$MODE" | uniq -d | wc -l | tr -d ' ') $(sort -u "$TMP/served-$MODE" | wc -l | tr -d ' ')" "0 12"
assert_eq "[$MODE] every folder is written" "$(for i in $(seq -f 'c%02g' 1 12); do getst "$C" "$i"; done | sort -u)" "written"
done

for MODE in git plain; do
echo "== [$MODE] verify: independent verifier, evidence, rejection cycle =="
V="$TMP/verify-$MODE"; mk_project "$V" "$MODE"; mkf "$V" p r g/h; mkdir -p "$V/tiny"; printf 'x\n' > "$V/tiny/a"
vd() { CORTEX_ROOT="$V" bash "$DESCSH" "$@"; }
sdir() { echo "$V/.cortex/.state/describe/f/$(enc_t "$1")"; }
vd --init >/dev/null
wr() { local d; d="$(vd --next --role write --worker "$1" | head -1 | sed 's/^TASK write //')"; vd --submit "$d" "$2" --worker "$1" >/dev/null; echo "$d"; }
vd --next --role verify --worker v1 >/dev/null; assert_eq "[$MODE] nothing to verify yet waits (exit 3: writers still working)" "$?" "3"
d1="$(wr w1 'Parcel handling service')"
vo="$(vd --next --role verify --worker w1)"; rc=$?
assert_eq "[$MODE] a writer never verifies its own folder" "$rc" "3"
vo="$(vd --next --role verify --worker v1)"; rc=$?
assert_eq "[$MODE] verifier is served" "$rc" "0"
assert_eq "[$MODE] verify task line" "$(printf '%s\n' "$vo" | head -1)" "TASK verify $d1"
assert_has "[$MODE] verify shows the description" "$vo" "DESCRIPTION: Parcel handling service"
assert_has "[$MODE] verify shows the digest" "$vo" "== CONTENTS of $d1 =="
assert_eq "[$MODE] state is claimed-verify" "$(getst "$V" "$d1")" "claimed-verify"
vd --verdict "$d1" ok "looks fine" --worker v1 2>/dev/null; assert_eq "[$MODE] ok without evidence is refused" "$?" "2"
assert_eq "[$MODE] refused verdict leaves the state" "$(getst "$V" "$d1")" "claimed-verify"
vd --verdict "$d1" ok "matches f.js" --worker v2 2>/dev/null; assert_eq "[$MODE] verdict by another worker is refused" "$?" "1"
vd --verdict "$d1" ok "matches f.js" --worker v1 >/dev/null; assert_eq "[$MODE] ok with evidence" "$?" "0"
assert_eq "[$MODE] state is verified" "$(getst "$V" "$d1")" "verified"
vd --verdict "$d1" ok "matches f.js" --worker v1 2>/dev/null; assert_eq "[$MODE] verdict on a folder not under verification is refused" "$?" "1"

echo "== [$MODE] verify: evidence rule with only short names =="
setst "$V" tiny written; printf 'w9\n' > "$(sdir tiny)/writer"
vd --next --role verify --worker v1 | head -1 | grep -q "tiny" || { for x in g/h r; do setst "$V" "$x" verified; done; vd --next --role verify --worker v1 >/dev/null; }
vd --verdict tiny ok "reads fine" --worker v1 >/dev/null; assert_eq "[$MODE] short names: any evidence accepted" "$?" "0"

echo "== [$MODE] verify: rejection cycle ends in needs-human =="
setst "$V" p verified; setst "$V" g verified; setst "$V" r todo; rm -f "$(sdir r)/rejects" "$(sdir r)/reason"
for round in 1 2 3; do
  w="$(vd --next --role write --worker w1 | head -1)"; assert_eq "[$MODE] round $round: r is served for writing" "$w" "TASK write r"
  vd --submit r "Attempt $round at describing r" --worker w1 >/dev/null
  vd --next --role verify --worker v1 >/dev/null
  vd --verdict r reject "" --worker v1 2>/dev/null; assert_eq "[$MODE] round $round: reject without a reason is refused" "$?" "2"
  vd --verdict r reject "too vague, round $round" --worker v1 >/dev/null; assert_eq "[$MODE] round $round: reject accepted" "$?" "0"
  assert_eq "[$MODE] round $round: reject count" "$(cat "$(sdir r)/rejects")" "$round"
  [ "$round" -lt 3 ] && assert_has "[$MODE] round $round: next writer sees the reason" "$(vd --next --role write --worker w1; vd --requeue-claimed >/dev/null)" "REJECTED: too vague, round $round"
done
assert_eq "[$MODE] third rejection escalates" "$(getst "$V" r)" "needs-human"
assert_eq "[$MODE] the description stays in the map until replaced" "$(cat "$V/.cortex/map/r.cortex")" "Attempt 3 at describing r"
vd --next --role write --worker w1 >/dev/null; assert_eq "[$MODE] needs-human is never served (exit 4)" "$?" "4"
assert_has "[$MODE] status counts needs-human" "$(vd --status | head -1)" "needs-human=1"
vd --reset r >/dev/null; assert_eq "[$MODE] reset exits 0" "$?" "0"
assert_eq "[$MODE] reset returns it to todo with a clean counter" "$(getst "$V" r) $(cat "$(sdir r)/rejects")" "todo 0"
vd --reset r 2>/dev/null; assert_eq "[$MODE] reset of a non-stuck folder is refused" "$?" "2"

echo "== [$MODE] verify: requeue-claimed =="
setst "$V" p claimed-write; setst "$V" r claimed-verify; setst "$V" g written; setst "$V" g/h verified; setst "$V" tiny verified
n="$(vd --requeue-claimed)"
assert_eq "[$MODE] requeue reports the count" "$n" "2"
assert_eq "[$MODE] requeue states" "$(getst "$V" p) $(getst "$V" r) $(getst "$V" g) $(getst "$V" g/h)" "todo written written verified"

echo "== [$MODE] verify: a parent waits for its verified children =="
G="$TMP/gate-$MODE"; mk_project "$G" "$MODE"; mkf "$G" top/kid
gd() { CORTEX_ROOT="$G" bash "$DESCSH" "$@"; }
gd --init >/dev/null
gd --next --role write --worker w1 >/dev/null; gd --submit top/kid "First draft of kid" --worker w1 >/dev/null
gd --next --role verify --worker v1 >/dev/null; gd --verdict top/kid reject "wrong" --worker v1 >/dev/null
assert_eq "[$MODE] rejected child, parent still waits" "$(gd --next --role write --worker w2 | head -1)" "TASK write top/kid"
gd --submit top/kid "Second draft of kid" --worker w2 >/dev/null
gd --next --role write --worker w3 >/dev/null; assert_eq "[$MODE] rewritten but unverified child still blocks the parent" "$?" "3"
gd --next --role verify --worker v1 >/dev/null; gd --verdict top/kid ok "describes f.js" --worker v1 >/dev/null
assert_eq "[$MODE] verified child releases the parent" "$(gd --next --role write --worker w3 | head -1)" "TASK write top"
done

# run_to_completion DIR: drive writers and verifiers until --status stops improving.
run_to_completion() {
  local P="$1" i o rc dir name
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    while true; do
      o="$(CORTEX_ROOT="$P" bash "$DESCSH" --next --role write --worker wk)"; rc=$?
      [ "$rc" -eq 0 ] || break
      dir="$(printf '%s\n' "$o" | head -1 | sed 's/^TASK write //')"
      CORTEX_ROOT="$P" bash "$DESCSH" --submit "$dir" "Area description for ${dir##*/}" --worker wk >/dev/null
    done
    while true; do
      o="$(CORTEX_ROOT="$P" bash "$DESCSH" --next --role verify --worker vk)"; rc=$?
      [ "$rc" -eq 0 ] || break
      dir="$(printf '%s\n' "$o" | head -1 | sed 's/^TASK verify //')"
      name="$(printf '%s\n' "$o" | sed -n 's/^FILE \(.*\) [0-9]*$/\1/p; s/^DIR \([^:]*\): .*$/\1/p' | awk 'length($0) >= 3 { print; exit }')"
      CORTEX_ROOT="$P" bash "$DESCSH" --verdict "$dir" ok "cites $name" --worker vk >/dev/null
    done
  done
}

for MODE in git plain; do
echo "== [$MODE] status: the completion gate =="
T="$TMP/gate2-$MODE"; mk_project "$T" "$MODE"; mkf "$T" top/kid other
td() { CORTEX_ROOT="$T" bash "$DESCSH" "$@"; }
td --init >/dev/null
o="$(td --status)"; rc=$?; assert_eq "[$MODE] fresh queue is incomplete" "$rc" "1"
assert_has "[$MODE] reason todo" "$o" "$(printf 'BLOCKED\tother\ttodo')"
td --next --role write --worker w1 >/dev/null
assert_has "[$MODE] reason claimed" "$(td --status)" "claimed"
setst "$T" top/kid written
assert_has "[$MODE] reason written" "$(td --status)" "$(printf 'BLOCKED\ttop/kid\twritten')"
setst "$T" top/kid needs-human
assert_has "[$MODE] reason needs-human" "$(td --status)" "$(printf 'BLOCKED\ttop/kid\tneeds-human')"
td --init --restart >/dev/null
run_to_completion "$T"
td --status >/dev/null; assert_eq "[$MODE] a fully verified queue completes (exit 0)" "$?" "0"
assert_eq "[$MODE] completion removes the marker" "$([ -e "$T/.cortex/.state/describe/active" ] && echo y || echo n)" "n"
assert_eq "[$MODE] descriptions really are in the map" "$(cat "$T/.cortex/map/top/kid.cortex")" "Area description for kid"

echo "== [$MODE] status: a later direct --set invalidates the verification =="
CORTEX_ROOT="$T" bash "$MAPSH" --set other "Something else entirely"
o="$(td --status)"; rc=$?
assert_eq "[$MODE] changed description blocks completion" "$rc" "1"
assert_has "[$MODE] reason changed" "$o" "$(printf 'BLOCKED\tother\tdescription changed after verification')"

echo "== [$MODE] status: a folder created after init =="
td --init --restart --all >/dev/null; run_to_completion "$T"
mkf "$T" extra
o="$(td --status)"; rc=$?
assert_eq "[$MODE] new folder blocks completion" "$rc" "1"
assert_has "[$MODE] reason new folder" "$o" "$(printf 'BLOCKED\textra\tnew folder not in the queue')"
td --init >/dev/null; run_to_completion "$T"
td --status >/dev/null; assert_eq "[$MODE] resume + finish completes again" "$?" "0"

echo "== [$MODE] marker: refreshed by activity while incomplete =="
td --init --restart --all >/dev/null
touch -d '3 hours ago' "$T/.cortex/.state/describe/active" 2>/dev/null || touch -t "$(date -d '3 hours ago' +%Y%m%d%H%M 2>/dev/null)" "$T/.cortex/.state/describe/active"
td --next --role write --worker w1 >/dev/null
assert_eq "[$MODE] --next refreshes the marker" "$([ -n "$(find "$T/.cortex/.state/describe/active" -mmin -1 2>/dev/null)" ] && echo y || echo n)" "y"
touch -d '3 hours ago' "$T/.cortex/.state/describe/active" 2>/dev/null
td --status >/dev/null
assert_eq "[$MODE] --status refreshes the marker while incomplete" "$([ -n "$(find "$T/.cortex/.state/describe/active" -mmin -1 2>/dev/null)" ] && echo y || echo n)" "y"
done

echo "== performance: 1000 folders =="
PF="$TMP/perf"; mk_project "$PF" plain
for i in $(seq -w 1 1000); do mkdir -p "$PF/pkg/m$i"; printf 'x\n' > "$PF/pkg/m$i/a.js"; done
start=$(date +%s)
CORTEX_ROOT="$PF" bash "$DESCSH" --init >/dev/null
for k in $(seq 1 30); do
  d="$(CORTEX_ROOT="$PF" bash "$DESCSH" --next --role write --worker w1 | head -1 | sed 's/^TASK write //')"
  CORTEX_ROOT="$PF" bash "$DESCSH" --submit "$d" "Package $k handler" --worker w1 >/dev/null
  CORTEX_ROOT="$PF" bash "$DESCSH" --next --role verify --worker v1 >/dev/null
  CORTEX_ROOT="$PF" bash "$DESCSH" --verdict "$d" ok "cites a.js" --worker v1 >/dev/null
done
CORTEX_ROOT="$PF" bash "$DESCSH" --status >/dev/null
end=$(date +%s)
echo "  time: init + 30 cycles + status over 1000 folders: $((end - start))s"
assert_eq "performance: under 60 s" "$([ $((end - start)) -lt 60 ] && echo y || echo n)" "y"

for MODE in git plain; do
echo "== [$MODE] review fixes: a renamed unverified folder stays in the queue =="
RN="$TMP/rn-$MODE"; mk_project "$RN" "$MODE"; mkf "$RN" src/foo
rd() { CORTEX_ROOT="$RN" bash "$DESCSH" "$@"; }
rd --init >/dev/null
rd --next --role write --worker w1 >/dev/null; rd --submit src/foo "Unverified filler text." --worker w1 >/dev/null
mv "$RN/src/foo" "$RN/src/bar"
rd --init >/dev/null
assert_eq "[$MODE] rename: scope follows the folder" "$(cat "$RN/.cortex/.state/describe/scope")" "$(printf 'src\nsrc/bar')"
assert_eq "[$MODE] rename: unverified work is still unverified" "$(getst "$RN" src/bar)" "written"
rd --status >/dev/null; assert_eq "[$MODE] rename: status is not complete" "$?" "1"
run_to_completion "$RN"
rd --status >/dev/null; assert_eq "[$MODE] rename: finishing the queue completes it" "$?" "0"

echo "== [$MODE] review fixes: a finished queue does not haunt the next sync =="
rd --next --role write --worker late >/dev/null; assert_eq "[$MODE] finished queue serves nothing (exit 4)" "$?" "4"
assert_eq "[$MODE] a late worker does not revive the marker" "$([ -e "$RN/.cortex/.state/describe/active" ] && echo y || echo n)" "n"
CORTEX_ROOT="$RN" bash "$MAPSH" --set src/bar "Edited later through the normal path"
mkf "$RN" lib
rd --init >/dev/null
assert_eq "[$MODE] next init after completion starts a fresh queue" "$(cat "$RN/.cortex/.state/describe/scope")" "lib"
run_to_completion "$RN"
rd --status >/dev/null; assert_eq "[$MODE] the new sync can finish" "$?" "0"

echo "== [$MODE] review fixes: very long folder paths =="
LP="$TMP/long-$MODE"; mk_project "$LP" "$MODE"
lp=""; for i in 1 2 3 4 5 6 7 8 9; do lp="$lp/seg$i-$(printf 'x%.0s' $(seq 1 24))"; done; lp="${lp#/}"
mkf "$LP" "$lp"
ld() { CORTEX_ROOT="$LP" bash "$DESCSH" "$@"; }
ld --init >/dev/null
assert_has "[$MODE] long path: all nine levels queued" "$(ld --status | head -1)" "todo=9"
run_to_completion "$LP"
ld --status >/dev/null; assert_eq "[$MODE] long path: the sync completes" "$?" "0"
assert_eq "[$MODE] long path: the deepest folder is described" "$(cat "$LP/.cortex/map/$lp.cortex" 2>/dev/null)" "Area description for ${lp##*/}"

echo "== [$MODE] review fixes: a stale lock does not stall the queue =="
SL="$TMP/stale-$MODE"; mk_project "$SL" "$MODE"; mkf "$SL" alpha
sd() { CORTEX_ROOT="$SL" bash "$DESCSH" "$@"; }
sd --init >/dev/null
mkdir "$SL/.cortex/.state/describe/f/alpha/.lock"
touch -d '10 minutes ago' "$SL/.cortex/.state/describe/f/alpha/.lock" 2>/dev/null || touch -t "$(date -v-10M +%Y%m%d%H%M)" "$SL/.cortex/.state/describe/f/alpha/.lock"
assert_eq "[$MODE] stale lock: the folder is served" "$(sd --next --role write --worker w1 | head -1)" "TASK write alpha"

echo "== [$MODE] review fixes: needs-human shows why =="
NH="$TMP/nh-$MODE"; mk_project "$NH" "$MODE"; mkf "$NH" solo
nd() { CORTEX_ROOT="$NH" bash "$DESCSH" "$@"; }
nd --init >/dev/null
for r in 1 2 3; do nd --next --role write --worker w1 >/dev/null; nd --submit solo "Try number $r of solo" --worker w1 >/dev/null; nd --next --role verify --worker v1 >/dev/null; nd --verdict solo reject "vague on round $r" --worker v1 >/dev/null; done
assert_has "[$MODE] status prints the last rejection reason" "$(nd --status)" "vague on round 3"
done

for MODE in git plain; do
echo "== [$MODE] 6.1.2: guide lines travel with the task =="
GD="$TMP/guide-$MODE"; mk_project "$GD" "$MODE"; mkf "$GD" alpha
gdd() { CORTEX_ROOT="$GD" bash "$DESCSH" "$@"; }
gdd --init >/dev/null
assert_has "[$MODE] writer gets a guide" "$(gdd --next --role write --worker w1)" "GUIDE: Say what this folder is FOR"
gdd --submit alpha "Billing invoice rendering" --worker w1 >/dev/null
assert_has "[$MODE] verifier gets a guide" "$(gdd --next --role verify --worker v1)" "GUIDE: Approve only if"

echo "== [$MODE] 6.1.2: expired claims return to the queue =="
LS="$TMP/lease-$MODE"; mk_project "$LS" "$MODE"; mkf "$LS" one two
ld2() { CORTEX_ROOT="$LS" bash "$DESCSH" "$@"; }
age() { touch -d "$2 minutes ago" "$1" 2>/dev/null || touch -t "$(date -v-"$2"M +%Y%m%d%H%M)" "$1"; }
ld2 --init >/dev/null
ld2 --next --role write --worker dead >/dev/null
assert_eq "[$MODE] a fresh claim is not taken" "$(ld2 --next --role write --worker w2 | head -1)" "TASK write two"
age "$LS/.cortex/.state/describe/f/one/worker" 30
assert_eq "[$MODE] a claim older than the lease is served again" "$(ld2 --next --role write --worker w3 | head -1)" "TASK write one"
assert_eq "[$MODE] and now belongs to the new worker" "$(cat "$LS/.cortex/.state/describe/f/one/worker")" "w3"
ld2 --submit one "First of two areas" --worker w3 >/dev/null; ld2 --next --role verify --worker v1 >/dev/null
age "$LS/.cortex/.state/describe/f/one/worker" 30
ld2 --submit two "Second of two areas" --worker w2 >/dev/null
assert_eq "[$MODE] an expired verification goes back to written and is re-served" "$(ld2 --next --role verify --worker v2 | head -1)" "TASK verify one"

echo "== [$MODE] 6.1.2: report =="
RP="$TMP/report-$MODE"; mk_project "$RP" "$MODE"; mkf "$RP" a1 b1
rpd() { CORTEX_ROOT="$RP" bash "$DESCSH" "$@"; }
rpd --init >/dev/null
for d in a1 b1; do rpd --next --role write --worker w1 >/dev/null; rpd --submit "$d" "Description of $d" --worker w1 >/dev/null; done
rpd --next --role verify --worker v1 >/dev/null; rpd --verdict a1 ok "matches f.js" --worker v1 >/dev/null
rpd --next --role verify --worker v1 >/dev/null; rpd --verdict b1 reject "too vague" --worker v1 >/dev/null
ro="$(rpd --report)"; rc=$?
assert_eq "[$MODE] report exits 0" "$rc" "0"
assert_has "[$MODE] report totals" "$ro" "submissions=2 approved=1 rejected=1"
assert_has "[$MODE] report writers" "$ro" "WRITER w1: 2"
assert_has "[$MODE] report verifiers" "$ro" "VERIFIER v1: ok=1 rejected=1"
assert_no  "[$MODE] a rejection suppresses the no-rejection warning" "$ro" "WARNING"
SW="$TMP/warn-$MODE"; mk_project "$SW" "$MODE"; mkf "$SW" $(seq -f 'k%02g' 1 12)
swd() { CORTEX_ROOT="$SW" bash "$DESCSH" "$@"; }
swd --init >/dev/null; run_to_completion "$SW"
assert_has "[$MODE] no rejections among many verdicts is flagged" "$(swd --report)" "WARNING: no folder was rejected out of 12 verdicts"
DU="$TMP/dual-$MODE"; mk_project "$DU" "$MODE"; mkf "$DU" p1 p2
dud() { CORTEX_ROOT="$DU" bash "$DESCSH" "$@"; }
dud --init >/dev/null
dud --next --role write --worker dual >/dev/null; dud --submit p1 "Area p1 handling" --worker dual >/dev/null
dud --next --role write --worker w2 >/dev/null; dud --submit p2 "Area p2 handling" --worker w2 >/dev/null
dud --next --role verify --worker dual >/dev/null; dud --verdict p2 ok "cites f.js" --worker dual >/dev/null
assert_has "[$MODE] a worker acting in both roles is flagged" "$(dud --report)" "WARNING: worker dual acted as both writer and verifier"
CORTEX_ROOT="$TMP/none-$MODE" bash "$DESCSH" --report 2>/dev/null; assert_eq "[$MODE] report without a queue fails" "$?" "1"
done

echo ""; echo "describe-test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
