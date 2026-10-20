#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — cortex-map: sole owner of the folder map.
# The map is a mirror tree under .cortex/map/: each described folder <dir>
# has a one-line sibling file .cortex/map/<dir>.cortex holding its description
# (the file sits NEXT TO the mirror directory of its children, not inside it):
#     .cortex/map/src.cortex        -> "Application source."
#     .cortex/map/src/api.cortex    -> "HTTP handlers."
# Nothing else may write these files.
# Usage: cortex-map.sh --check <dir> | --set <dir> <desc> | --drift | --reconcile | --find <term>...
# ──────────────────────────────────────────────────────
set -uo pipefail

# Character classification and the length count below must not depend on the
# ambient locale (8-bit locales classify UTF-8 continuation bytes as control).
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -z "${CORTEX_ROOT:-}" ] && [ -z "$SCRIPT_DIR" ]; then
  echo "cortex-map: cannot resolve the script directory and CORTEX_ROOT is not set" >&2
  exit 2
fi
ROOT="${CORTEX_ROOT:-$SCRIPT_DIR/../..}"
MAPDIR="$ROOT/.cortex/map"
SCAN="$SCRIPT_DIR/cortex-scan.sh"

usage() {
  echo "usage: cortex-map.sh --check <dir> | --set <dir> <desc> | --drift | --reconcile | --find <term>..." >&2
  exit 2
}

# Strict UTF-8 (no overlongs, no surrogates, max U+10FFFF), built from octal
# escapes so no grep needs to understand \x.
UTF8_RE="$(printf '^([\001-\177]|[\302-\337][\200-\277]|\340[\240-\277][\200-\277]|[\341-\354\356\357][\200-\277][\200-\277]|\355[\200-\237][\200-\277]|\360[\220-\277][\200-\277][\200-\277]|[\361-\363][\200-\277][\200-\277][\200-\277]|\364[\200-\217][\200-\277][\200-\277])*$')"

# validate_target <dir>: exit 0 if <dir> can be stored as a map entry, else 2.
validate_target() {
  local t="${1%/}" seg rest
  if [ -z "$t" ]; then
    echo "cortex-map: empty folder path" >&2; return 2
  fi
  case "$t" in
    /*) echo "cortex-map: absolute paths are not allowed: $t" >&2; return 2 ;;
    *[[:cntrl:]]*) echo "cortex-map: folder names may not contain tabs, newlines or other control characters: $t" >&2; return 2 ;;
    *//*) echo "cortex-map: empty path segments are not allowed: $t" >&2; return 2 ;;
  esac
  # Names that are not valid UTF-8 cannot be carried faithfully through JSON or
  # hook output. Pure-ASCII names (the common case) skip the check.
  case "$t" in
    *[!\ -~]*)
      if grep -qvE "$UTF8_RE" <<< "$t"; then
        echo "cortex-map: folder name is not valid UTF-8: $t" >&2; return 2
      fi ;;
  esac
  rest="$t/"
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"; rest="${rest#*/}"
    case "$seg" in
      .) echo "cortex-map: '.' path segments are not allowed: $t" >&2; return 2 ;;
      ..) echo "cortex-map: '..' path segments are not allowed: $t" >&2; return 2 ;;
      *.cortex) echo "cortex-map: a folder name may not end in .cortex — it would collide with a map file: $t" >&2; return 2 ;;
    esac
  done
  case "${t%%/*}" in
    .git|.cortex|.claude|.opencode)
      echo "cortex-map: ${t%%/*} is excluded from the map: $t" >&2; return 2 ;;
  esac
  return 0
}

# validate_desc <desc>: exit 0 if usable as a one-line description, else 2.
validate_desc() {
  local d="$1" n
  case "$d" in
    *[[:cntrl:]]*) echo "cortex-map: a description may not contain newlines or control characters" >&2; return 2 ;;
    *[![:space:]]*) ;;
    *) echo "cortex-map: a description may not be empty" >&2; return 2 ;;
  esac
  # Count characters, not bytes: UTF-8 continuation bytes (0x80-0xBF) are skipped.
  n="$(printf '%s' "$d" | awk '{ n=0; for (i=1;i<=length($0);i++) { c=substr($0,i,1); if (c < "\200" || c > "\277") n++ } print n }')"
  if [ "$n" -gt 120 ]; then
    echo "cortex-map: description is $n characters (max 120) — describe the folder's role, not its contents" >&2
    return 2
  fi
  return 0
}

# desc_file <dir>: path of the description file for <dir>.
desc_file() { printf '%s\n' "$MAPDIR/${1%/}.cortex"; }

# described_dirs: every described folder, one per line, sorted.
described_dirs() {
  local f rel
  [ -d "$MAPDIR" ] || return 0
  while IFS= read -r f; do
    rel="${f#"$MAPDIR"/}"
    printf '%s\n' "${rel%.cortex}"
  done < <(find "$MAPDIR" -type f -name '*.cortex' 2>/dev/null) | sort
}

# drift_sets <dirs> <plus> <minus>: from a sorted list of scanned folders, write
# the sorted "+" set (scanned, representable, not described) and the sorted "-"
# set (described, no longer a directory on disk). Set work is done with comm on
# sorted files so cost stays linear in the size of the tree.
drift_sets() {
  local dirs="$1" plus="$2" minus="$3" d
  described_dirs > "$plus.described"
  : > "$plus"; : > "$minus"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    validate_target "$d" 2>/dev/null && printf '%s\n' "$d"
  done < <(comm -23 "$dirs" "$plus.described") > "$plus"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$ROOT/$d" ] || printf '%s\n' "$d"
  done < "$plus.described" > "$minus"
  rm -f "$plus.described"
}

# by_depth: sort folder paths by depth, then bytewise (LC_ALL=C).
by_depth() {
  awk -F/ '{ print NF "\t" $0 }' | sort -t "$(printf '\t')" -k1,1n -k2 | cut -f2-
}

# reconcile: the mechanical half of keeping the map current (spec §6.1).
# Renamed folders keep their descriptions (detected against the snapshot of the
# previous run's file list), vanished folders lose theirs, and what is left is
# printed as pending. The scan is the source of truth for everything, so a
# missing or failing scan aborts before anything is touched: an empty listing
# would otherwise read as "every folder was deleted".
# Each "moved"/"removed" line is printed as soon as that change is on disk; a
# later failure ends the output with "error\t<reason>" and a non-zero exit, and
# the snapshot is not written.
reconcile() {
  # W is global on purpose: the EXIT trap runs after this function returns.
  local state="$ROOT/.cortex/.state" src dst d tab i prev pfrom pto from to top
  tab="$(printf '\t')"
  if [ ! -f "$SCAN" ]; then
    echo "cortex-map: scanner not found: $SCAN" >&2; return 1
  fi
  W="$(mktemp -d)" || return 1
  trap 'rm -rf "${W:-}"' EXIT
  bash "$SCAN" --files "$ROOT" > "$W/files" || { echo "cortex-map: scan failed; nothing changed" >&2; return 1; }
  bash "$SCAN" --dirs "$ROOT" > "$W/dirs" || { echo "cortex-map: scan failed; nothing changed" >&2; return 1; }
  drift_sets "$W/dirs" "$W/plus" "$W/minus"

  if [ -f "$state/tree" ] && [ -s "$W/minus" ] && [ -s "$W/plus" ]; then
    by_depth < "$W/minus" > "$W/R"
    detect_moves "$W/R" "$W/plus" "$state/tree" "$W/files" "$W/dirs" | by_depth_pairs > "$W/moves"

    # Every description at or under each moved folder, mapped to its new home
    # by the deepest move that covers it. Output, grouped by move (in depth
    # order) and parent first within a group:
    #   <move#>\t<depth>\t<src>\t<dst>\t<move from>\t<move to>
    described_dirs > "$W/described"
    awk -F'\t' '
      FILENAME == ARGV[1] { to[$1] = $2; idx[$1] = ++n; next }
      { d = $0; s = ""
        if (d in to) s = d
        else while ((j = match(d, /\/[^\/]*$/)) > 0) { d = substr(d, 1, j - 1); if (d in to) { s = d; break } }
        if (s != "") print idx[s] "\t" split($0, parts, "/") "\t" $0 "\t" to[s] substr($0, length(s) + 1) "\t" s "\t" to[s]
      }' "$W/moves" "$W/described" | sort -t "$tab" -k1,1n -k2,2n -k3 > "$W/pairs"
    prev=""; pfrom=""; pto=""; : > "$W/orig"
    while IFS="$tab" read -r i d src dst from to; do
      [ -n "$prev" ] && [ "$i" != "$prev" ] && printf 'moved\t%s\t%s\n' "$pfrom" "$pto"
      prev="$i"; pfrom="$from"; pto="$to"
      if [ -e "$(desc_file "$dst")" ]; then
        rm -f "$(desc_file "$src")" 2>/dev/null || { reconcile_error "could not remove the description of $src"; return 1; }
      else
        { mkdir -p "$(dirname "$(desc_file "$dst")")" && mv "$(desc_file "$src")" "$(desc_file "$dst")"; } 2>/dev/null ||
          { reconcile_error "could not move the description of $src to $dst"; return 1; }
        printf '%s\t%s\n' "$dst" "$src" >> "$W/orig"
      fi
    done < "$W/pairs"
    [ -n "$prev" ] && printf 'moved\t%s\t%s\n' "$pfrom" "$pto"
    drift_sets "$W/dirs" "$W/plus" "$W/minus"
  fi

  # Whatever is still "-" is gone for good: drop it (its subtree is gone too, so
  # every described descendant is in the set as well). Only the topmost folder
  # of each removed subtree is reported, once its whole subtree is dropped. A
  # description carried along by a parent's move just above is reported by the
  # path it had before that move: its new path never existed.
  [ -f "$W/orig" ] || : > "$W/orig"
  awk -F'\t' 'FILENAME == ARGV[1] { orig[$1] = $2; next }
       { set[$0] = 1; l[++n] = $0 }
       END { for (i = 1; i <= n; i++) { d = l[i]; top = d
               while ((j = match(d, /\/[^\/]*$/)) > 0) { d = substr(d, 1, j - 1); if (d in set) top = d }
               print ((top in orig) ? orig[top] : top) "\t" l[i] } }' "$W/orig" "$W/minus" | sort > "$W/rm"
  prev=""
  while IFS="$tab" read -r top d; do
    [ -n "$prev" ] && [ "$top" != "$prev" ] && printf 'removed\t%s\n' "$prev"
    prev="$top"
    rm -f "$(desc_file "$d")" 2>/dev/null || { reconcile_error "could not remove the description of $d"; return 1; }
  done < "$W/rm"
  [ -n "$prev" ] && printf 'removed\t%s\n' "$prev"

  by_depth < "$W/plus" | awk '{ print "pending\t" $0 }'

  [ -d "$MAPDIR" ] && find "$MAPDIR" -mindepth 1 -depth -type d -empty -delete 2>/dev/null
  { mkdir -p "$state" && cp "$W/files" "$state/tree.tmp" && mv "$state/tree.tmp" "$state/tree"; } 2>/dev/null || {
    reconcile_error "could not write the snapshot $state/tree"; return 1; }
  return 0
}

# reconcile_error <reason>: the last line of a failed reconcile, on stdout for
# the Stop hook and on stderr for a person.
reconcile_error() {
  printf 'error\t%s\n' "$1"
  echo "cortex-map: $1" >&2
}

# detect_moves <R> <plus> <snapshot> <files> <dirs>: print "<old>\t<new>" for
# every detected rename. <R> holds the gone folders shallowest first, <plus> the
# new undescribed ones, <snapshot> and <files> the previous and current file
# lists, <dirs> every current folder.
#
# A gone folder r matches the unclaimed new folder holding the most of r's
# files by relative path, if that is at least half of them. Files under an
# already matched subfolder of r are compared at the place they moved to, and
# the passes repeat until nothing new matches, so a parent renamed together
# with the subfolder holding most of its files is still recognised. A
# subfolder of a matched folder that is not at its carried position is matched
# on its own. Equal scores prefer the same last name, then the same parent
# folder, then the same shape (the same count of files at each depth inside
# it), then the same depth in the tree, then the lowest name. Moves implied by
# a parent's move are dropped.
detect_moves() {
  awk -F'\t' '
    function parent(p,   j) { j = match(p, /\/[^\/]*$/); return j ? substr(p, 1, j - 1) : "" }
    function base(p,   j) { j = match(p, /\/[^\/]*$/); return j ? substr(p, j + 1) : p }
    # deepest moved folder at or above p and strictly below stop ("" if none)
    function mover(p, stop) {
      while (p != "" && p != stop) { if (p in mt) return p; p = parent(p) }
      return ""
    }
    # a is taken when it, or the folder it sits in, already receives a moved
    # folder that had a subfolder at that same relative position
    function taken(a,   b) {
      for (b = a; b != ""; b = parent(b))
        if ((b in claim) && ((claim[b] substr(a, length(b) + 1)) in sdir)) return 1
      return 0
    }
    function depth(p,   t) { return split(p, t, "/") }
    # the new folder a holds as many files at each depth as x held
    function shaped(a, x,   k) {
      if (nmax[a] != omax[x]) return 0
      for (k = 0; k <= omax[x]; k++) if (ncnt[a, k] + 0 != ocnt[x, k] + 0) return 0
      return 1
    }
    function better(a, b, x) {
      if ((base(a) == base(x)) != (base(b) == base(x))) return base(a) == base(x)
      if ((parent(a) == parent(x)) != (parent(b) == parent(x))) return parent(a) == parent(x)
      if (shaped(a, x) != shaped(b, x)) return shaped(a, x)
      if ((depth(a) == depth(x)) != (depth(b) == depth(x))) return depth(a) == depth(x)
      return a < b
    }
    function add(d) { if (!(d in sc)) cl[++nc] = d; sc[d]++ }
    function pick(x,   n, fs, k, f, path, m, np, d, cs, c, a, best, bs) {
      split("", sc); nc = 0
      n = split(substr(fl[x], 2), fs, "\001")
      for (k = 1; k <= n; k++) {
        f = fs[k]; path = x "/" f; m = mover(parent(path), x)
        if (m != "") {
          np = mt[m] substr(path, length(m) + 1)
          if (np in cur) for (d = parent(np); d != ""; d = parent(d)) if (d in isA) add(d)
        } else if (f in co) {
          c = split(substr(co[f], 2), cs, "\001")
          for (d = 1; d <= c; d++) add(cs[d])
        }
      }
      best = ""; bs = 0
      for (c = 1; c <= nc; c++) {
        a = cl[c]
        if (sc[a] * 2 < fr[x] || taken(a)) continue
        if (best == "" || sc[a] > bs || (sc[a] == bs && better(a, best, x))) { best = a; bs = sc[a] }
      }
      return best
    }
    FILENAME == ARGV[1] { r[++nr] = $0; isR[$0] = 1; next }
    FILENAME == ARGV[2] { isA[$0] = 1; next }
    FILENAME == ARGV[3] {
      p = $0
      for (d = parent(p); d != ""; d = parent(d)) {
        sdir[d] = 1
        if (d in isR) {
          rel = substr(p, length(d) + 2); fr[d]++; fl[d] = fl[d] "\001" rel; want[rel] = 1
          k = gsub(/\//, "/", rel); ocnt[d, k]++; if (k > omax[d]) omax[d] = k
        }
      }
      next
    }
    FILENAME == ARGV[4] {
      p = $0; cur[p] = 1
      for (d = parent(p); d != ""; d = parent(d)) {
        if (!(d in isA)) continue
        rel = substr(p, length(d) + 2)
        if (rel in want) co[rel] = co[rel] "\001" d
        k = gsub(/\//, "/", rel); ncnt[d, k]++; if (k > nmax[d]) nmax[d] = k
      }
      next
    }
    { cdir[$0] = 1 }
    END {
      nm = 0
      do {
        changed = 0
        for (i = 1; i <= nr; i++) {
          x = r[i]
          if ((x in done) || !(x in fr)) continue
          # under a moved folder and present at its carried position: implied
          m = mover(parent(x), "")
          if (m != "" && ((mt[m] substr(x, length(m) + 1)) in cdir)) { done[x] = 1; continue }
          # nothing moved since x was last scored: the answer cannot change
          if ((x in seen) && seen[x] == nm) continue
          seen[x] = nm
          best = pick(x)
          if (best != "") { mt[x] = best; claim[best] = x; mf[++nm] = x; done[x] = 1; changed = 1 }
        }
      } while (changed)
      for (k = 1; k <= nm; k++) {
        x = mf[k]; m = mover(parent(x), "")
        if (m != "" && mt[x] == mt[m] substr(x, length(m) + 1)) continue
        print x "\t" mt[x]
      }
    }' "$@"
}

# by_depth_pairs: sort "<src>\t<dst>" lines by the depth of <src>, so a parent
# is moved before its children.
by_depth_pairs() {
  awk -F'\t' '{ n = split($1, x, "/"); print n "\t" $0 }' | sort -t "$(printf '\t')" -k1,1n -k2 | cut -f2-
}

case "${1:-}" in
  --check)
    [ "$#" -eq 2 ] || usage
    validate_target "$2"; exit $?
    ;;
  --set)
    [ "$#" -eq 3 ] || usage
    TARGET="${2%/}"
    DESC="$3"
    DESC="${DESC#"${DESC%%[![:space:]]*}"}"
    DESC="${DESC%"${DESC##*[![:space:]]}"}"
    validate_target "$TARGET" || exit 2
    validate_desc "$DESC" || exit 2
    if [ ! -d "$ROOT/$TARGET" ]; then
      echo "cortex-map: not a directory under the project root: $TARGET" >&2; exit 2
    fi
    f="$(desc_file "$TARGET")"
    mkdir -p "$(dirname "$f")" || exit 1
    printf '%s\n' "$DESC" > "$f" || exit 1
    ;;
  --drift)
    [ "$#" -eq 1 ] || usage
    WORK="$(mktemp -d)" || exit 1
    trap 'rm -rf "${WORK:-}"' EXIT
    bash "$SCAN" --dirs "$ROOT" > "$WORK/dirs" || exit 1
    drift_sets "$WORK/dirs" "$WORK/plus" "$WORK/minus"
    sed 's/^/+ /' "$WORK/plus"
    sed 's/^/- /' "$WORK/minus"
    ;;
  --reconcile)
    [ "$#" -eq 1 ] || usage
    reconcile; exit $?
    ;;
  --find)
    shift
    [ "$#" -ge 1 ] || usage
    # Terms are lowercased and joined with \001; matching is literal (index(), never ~).
    TERMS=""
    # A blank term is a substring of everything: it would turn the query into
    # "list the whole map", so it is a usage error, not a match-all.
    for t in "$@"; do
      case "$t" in *[![:space:]]*) ;; *) usage ;; esac
      TERMS="$TERMS$(printf '%s' "$t" | tr 'A-Z' 'a-z')"$'\001'
    done
    QUERY="$*"
    [ -d "$MAPDIR" ] || { echo "No folder matches: $QUERY"; exit 0; }
    find "$MAPDIR" -type f -name '*.cortex' -exec awk 'FNR==1{print FILENAME "\t" $0}' {} + 2>/dev/null |
    CORTEX_FIND_TERMS="$TERMS" CORTEX_FIND_MAPDIR="$MAPDIR/" awk -F'\t' '
      # fold: ASCII tolower plus Latin-1 capitals in UTF-8 (C3 80-9E except C3 97)
      # to lowercase (second byte + 0x20).
      function fold(s,   out, i, n, c, b, k) {
        s = tolower(s); n = length(s); out = ""
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1)
          if (c == "\303" && i < n) {
            b = substr(s, i + 1, 1)
            k = index(UP, b)
            if (k > 0) { out = out c substr(LO, k, 1); i++; continue }
          }
          out = out c
        }
        return out
      }
      BEGIN {
        for (k = 128; k <= 158; k++) if (k != 151) { UP = UP sprintf("%c", k); LO = LO sprintf("%c", k + 32) }
        n = split(ENVIRON["CORTEX_FIND_TERMS"], T, "\001"); n--; pre = length(ENVIRON["CORTEX_FIND_MAPDIR"])
        for (i = 1; i <= n; i++) T[i] = fold(T[i])
      }
      {
        dir = substr($1, pre + 1); sub(/\.cortex$/, "", dir)
        desc = $2
        hay = fold(dir " " desc); low = fold(dir)
        last = low; sub(/.*\//, "", last)
        ok = 1; g1 = 0; g2 = 0
        for (i = 1; i <= n; i++) {
          if (index(hay, T[i]) == 0) { ok = 0; break }
          if (index(last, T[i]) > 0) g1 = 1
          else if (index(low, T[i]) > 0) g2 = 1
        }
        if (ok) print (g1 ? 1 : (g2 ? 2 : 3)) "\t" dir "\t" desc
      }' |
    sort -t "$(printf '\t')" -k1,1n -k2,2 |
    CORTEX_FIND_QUERY="$QUERY" awk -F'\t' '
      { c++; if (c <= 40) print $2 "/  " $3 }
      END {
        if (c == 0) print "No folder matches: " ENVIRON["CORTEX_FIND_QUERY"]
        else if (c > 40) print "… " (c - 40) " more — add another term to narrow"
      }'
    exit 0
    ;;
  *) usage ;;
esac
