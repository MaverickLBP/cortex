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
ROOT="${CORTEX_ROOT:-$SCRIPT_DIR/../..}"
MAPDIR="$ROOT/.cortex/map"
SCAN="$SCRIPT_DIR/cortex-scan.sh"

usage() {
  echo "usage: cortex-map.sh --check <dir> | --set <dir> <desc> | --drift | --reconcile | --find <term>..." >&2
  exit 2
}

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
reconcile() {
  # W is global on purpose: the EXIT trap runs after this function returns.
  local state="$ROOT/.cortex/.state" src dst d tab
  tab="$(printf '\t')"
  if [ ! -f "$SCAN" ]; then
    echo "cortex-map: scanner not found: $SCAN" >&2; return 1
  fi
  W="$(mktemp -d)" || return 1
  trap 'rm -rf "${W:-}"' EXIT
  bash "$SCAN" --files "$ROOT" > "$W/files" || { echo "cortex-map: scan failed; nothing changed" >&2; return 1; }
  bash "$SCAN" --dirs "$ROOT" > "$W/dirs" || { echo "cortex-map: scan failed; nothing changed" >&2; return 1; }
  drift_sets "$W/dirs" "$W/plus" "$W/minus"
  : > "$W/moves"

  if [ -f "$state/tree" ] && [ -s "$W/minus" ] && [ -s "$W/plus" ]; then
    by_depth < "$W/minus" > "$W/R"
    # One pass over the snapshot and one over the current listing score every
    # (gone, new) pair by shared relative paths; the greedy choice then runs in
    # depth order. Output: "<old>\t<new>" per detected rename.
    awk -F'\t' '
      FILENAME == ARGV[1] { r[++nr] = $0; isR[$0] = 1; next }
      FILENAME == ARGV[2] { isA[$0] = 1; next }
      FILENAME == ARGV[3] {
        p = $0; d = p
        while ((i = match(d, /\/[^\/]*$/)) > 0) {
          d = substr(d, 1, i - 1)
          if (d in isR) { rel = substr(p, length(d) + 2); fr[d]++; owners[rel] = owners[rel] "\001" d }
        }
        next
      }
      {
        p = $0; d = p
        while ((i = match(d, /\/[^\/]*$/)) > 0) {
          d = substr(d, 1, i - 1)
          if (!(d in isA)) continue
          rel = substr(p, length(d) + 2)
          if (!(rel in owners)) continue
          n = split(substr(owners[rel], 2), os, "\001")
          for (k = 1; k <= n; k++) {
            key = os[k] SUBSEP d
            if (!(key in score)) cands[os[k]] = cands[os[k]] "\001" d
            score[key]++
          }
        }
      }
      END {
        nm = 0; nc = 0
        for (i = 1; i <= nr; i++) {
          x = r[i]
          if (!(x in fr)) continue
          skip = 0
          for (m = 1; m <= nm; m++) if (index(x "/", moved[m] "/") == 1) { skip = 1; break }
          if (skip) continue
          best = ""; bs = 0
          n = split(substr(cands[x], 2), cs, "\001")
          for (k = 1; k <= n; k++) {
            a = cs[k]; taken = 0
            for (c = 1; c <= nc; c++) if (index(a "/", claimed[c] "/") == 1) { taken = 1; break }
            if (taken) continue
            s = score[x SUBSEP a]
            if (s > 0 && 2 * s >= fr[x] && (s > bs || (s == bs && (a "") < (best "")))) { best = a; bs = s }
          }
          if (best != "") { moved[++nm] = x; claimed[++nc] = best; print x "\t" best }
        }
      }' "$W/R" "$W/plus" "$state/tree" "$W/files" > "$W/moves"

    # Every description at or under each moved folder, mapped to its new home.
    described_dirs > "$W/described"
    awk -F'\t' '
      FILENAME == ARGV[1] { from[++n] = $1; to[n] = $2; next }
      { for (i = 1; i <= n; i++) {
          if ($0 == from[i]) { print $0 "\t" to[i]; break }
          if (index($0, from[i] "/") == 1) { print $0 "\t" to[i] substr($0, length(from[i]) + 1); break }
      } }' "$W/moves" "$W/described" | by_depth_pairs > "$W/pairs"
    while IFS="$tab" read -r src dst; do
      if [ -e "$(desc_file "$dst")" ]; then
        rm -f "$(desc_file "$src")" || return 1
      else
        mkdir -p "$(dirname "$(desc_file "$dst")")" && mv "$(desc_file "$src")" "$(desc_file "$dst")" || return 1
      fi
    done < "$W/pairs"
    drift_sets "$W/dirs" "$W/plus" "$W/minus"
  fi

  # Whatever is still "-" is gone for good: drop it (its subtree is gone too, so
  # every described descendant is in the set as well).
  while IFS= read -r d; do
    rm -f "$(desc_file "$d")" || return 1
  done < "$W/minus"

  awk '{ print "moved\t" $0 }' "$W/moves"
  awk '{ set[$0] = 1; l[++n] = $0 }
       END { for (i = 1; i <= n; i++) { d = l[i]; top = 1
               while ((j = match(d, /\/[^\/]*$/)) > 0) { d = substr(d, 1, j - 1); if (d in set) { top = 0; break } }
               if (top) print "removed\t" l[i] } }' "$W/minus"
  by_depth < "$W/plus" | awk '{ print "pending\t" $0 }'

  [ -d "$MAPDIR" ] && find "$MAPDIR" -mindepth 1 -depth -type d -empty -delete 2>/dev/null
  mkdir -p "$state" && cp "$W/files" "$state/tree.tmp" && mv "$state/tree.tmp" "$state/tree" || {
    echo "cortex-map: could not write the snapshot $state/tree" >&2; return 1; }
  return 0
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
    validate_target "$TARGET" || exit 2
    validate_desc "$3" || exit 2
    if [ ! -d "$ROOT/$TARGET" ]; then
      echo "cortex-map: not a directory under the project root: $TARGET" >&2; exit 2
    fi
    f="$(desc_file "$TARGET")"
    mkdir -p "$(dirname "$f")" || exit 1
    printf '%s\n' "$3" > "$f" || exit 1
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
      BEGIN { n = split(ENVIRON["CORTEX_FIND_TERMS"], T, "\001"); n--; pre = length(ENVIRON["CORTEX_FIND_MAPDIR"]) }
      {
        dir = substr($1, pre + 1); sub(/\.cortex$/, "", dir)
        desc = $2
        hay = tolower(dir " " desc); low = tolower(dir)
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
