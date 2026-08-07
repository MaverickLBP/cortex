#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — cortex-map: sole owner of the MAP.md format.
# MAP.md is an indented folder tree (two spaces per level), wrapped in a
# fenced code block so the indentation survives Markdown rendering —
# unfenced, consecutive indented lines collapse into one paragraph in every
# Markdown renderer (GitHub, GitLab, ...), losing the tree structure:
#     ```
#     rsrc/  Application source.
#       modules/  Business features, one folder per feature.
#     ```
# Indentation is STRUCTURE, not formatting: paths are
# reconstructed from it. Nothing else may write this file.
# Usage: cortex-map.sh --validate|--lookup <dir>|--set <dir> <desc>
#                      |--remove <dir>|--drift [ROOT]|--check <dir>
# ──────────────────────────────────────────────────────
set -uo pipefail

# The fence marker, in ONE place. Held in a variable rather than typed
# literally at each use site because three backticks inside double quotes
# would otherwise be read as (invalid) command substitution syntax.
FENCE='```'

# Character classification below decides which names are representable, so it is
# pinned to the C locale: in an 8-bit locale (ISO-8859-*) the bytes 0x80-0x9F
# classify as control characters, and those bytes occur inside perfectly ordinary
# UTF-8 sequences (the 0x82 in '€'). Without this an accented folder name would be
# rejected or dropped depending on the ambient locale of whoever invoked us.
export LC_ALL=C

MODE=""
case "${1:-}" in
  --validate|--lookup|--set|--remove|--drift|--check) MODE="$1"; shift ;;
  *) echo "usage: cortex-map.sh --validate|--lookup <dir>|--set <dir> <desc>|--remove <dir>|--drift [ROOT]|--check <dir>" >&2; exit 2 ;;
esac

# Positional args differ per mode; ROOT is resolved from the env or the
# script location, never from a trailing argument that could be a description.
ROOT="${CORTEX_ROOT:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
MAP="${CORTEX_MAP_FILE:-$ROOT/.cortex/MAP.md}"

# ── Parser ────────────────────────────────────────────
# The node-line predicate, in ONE place. Every part of this script that has to
# tell a node line from a header or continuation line uses this exact string:
# indentation, a name that starts with a non-space and holds no slash, then the
# slash and the two spaces that open the description. Two copies of this rule
# drifted apart once already (the header extractor in map_write silently ate
# header lines the parser preserved), so there is only one copy now.
NODE_RE='^ *[^ ][^/]*/  '

# Emits "<path>\t<description>" per node line, in file order.
# Exits 1 and prints a diagnostic on malformed indentation.
# $1 = file to parse (defaults to $MAP) — map_write parses its own candidate
# output through here before installing it.
map_parse() {
  local f="${1:-$MAP}"
  [ -f "$f" ] || return 0
  awk -v node_re="$NODE_RE" '
    /^[[:space:]]*$/ { next }
    /^#/             { next }
    /^>/             { next }
    /\t/ {
      printf("cortex-map: tab indentation at line %d\n", NR) > "/dev/stderr"
      bad = 1; exit 1
    }
    # Not a node line (see NODE_RE): ignored here, and NOT preserved — map_write
    # regenerates everything after the header, so only header lines survive a write.
    $0 !~ node_re { next }
    {
      n = match($0, /[^ ]/)
      indent = n - 1
      if (indent % 2 != 0) {
        printf("cortex-map: odd indentation (%d spaces) at line %d\n", indent, NR) > "/dev/stderr"
        bad = 1; exit 1
      }
      level = indent / 2
      if (!seen && level != 0) {
        printf("cortex-map: the first node must start at the root (0 indentation) at line %d\n", NR) > "/dev/stderr"
        bad = 1; exit 1
      }
      if (seen && level > prev_level + 1) {
        printf("cortex-map: level skip (%d -> %d) at line %d\n", prev_level, level, NR) > "/dev/stderr"
        bad = 1; exit 1
      }
      rest  = substr($0, n)
      slash = index(rest, "/")
      name  = substr(rest, 1, slash - 1)
      desc  = substr(rest, slash + 1)
      sub(/^ +/, "", desc)
      stack[level] = name
      path = stack[0]
      for (i = 1; i <= level; i++) path = path "/" stack[i]
      printf("%s\t%s\n", path, desc)
      prev_level = level; seen = 1
    }
    END { if (bad) exit 1 }
  ' "$f"
}

# Sort "path\tdesc" records in tree order. `/` is replaced by a literal
# 0x01 byte (which sorts below every printable character) so that a parent
# always precedes its children AND siblings like "a-b" never land between
# "a" and "a/b". Built with `tr` on a printf-constructed separator rather
# than sed's `\x01` escape: GNU sed interprets `\x01` as the byte 0x01, but
# BSD/macOS sed treats it as the literal three characters `x01` — which
# reintroduces the exact hyphen-vs-slash corruption this function exists to
# prevent. `tr` translates single characters identically on every platform.
map_sort() {
  local sep
  sep="$(printf '\001')"
  tr '/' "$sep" | LC_ALL=C sort -t"$(printf '\t')" -k1,1 | tr "$sep" '/'
}

# Regenerate the whole file from a sorted "path\tdesc" stream on stdin,
# preserving the original header (everything before the first node line).
#
# The candidate file is parsed back before it is installed, and the mv only
# happens if it yields exactly the records it was built from. This is the net
# under every representability rule: any name or description shape that the
# format cannot carry turns into a clean non-zero exit with the existing map
# untouched, instead of a corrupted MAP.md that no sanctioned command can
# repair (hand-editing is forbidden — SYSTEM.md §2.1).
map_write() {
  local tmp header records parsed
  records="$(grep -v '^$' || true)"
  tmp="$(mktemp "$(dirname "$MAP")/.MAP.md.XXXXXX")" || return 1
  header=""
  if [ -f "$MAP" ]; then
    # Mirror map_parse's skip rules: header lines are recognised BEFORE the node
    # test, exactly as the parser does it, so a '#' or '>' line that happens to
    # look like a node ("> See docs/  for details.") is preserved rather than
    # mistaken for the end of the header and silently dropped.
    header="$(awk -v node_re="$NODE_RE" '
      /^#/ { print; next }
      /^>/ { print; next }
      $0 ~ node_re { exit }
      { print }' "$MAP")"
  fi
  if [ -z "$header" ]; then
    header="$(printf '# Knowledge Map\n\n> Folder-level map. Every folder containing tracked files appears here.\n> Generated and maintained by cortex-map.sh. Do not edit by hand.\n\n%s' "$FENCE")"
  fi
  # A map written before the fence existed has it missing from its preserved
  # header (the header capture above stops at the first node line, so a
  # legacy header ends in the '>' blurb, not a fence). Inject the opening
  # fence so every write — not just fresh ones — self-heals into the fenced
  # form. A header that already ends in the fence (the normal case on every
  # write after the first) is left alone.
  case "$header" in
    *"$FENCE") : ;;
    *) header="${header}"$'\n'"$FENCE" ;;
  esac
  printf '%s\n' "$header" > "$tmp"
  if [ -n "$records" ]; then
    printf '%s\n' "$records" | awk -F'\t' '{
      n = split($1, parts, "/")
      indent = ""
      for (i = 1; i < n; i++) indent = indent "  "
      printf("%s%s/  %s\n", indent, parts[n], $2)
    }' >> "$tmp"
  fi
  printf '%s\n' "$FENCE" >> "$tmp"
  parsed="$(map_parse "$tmp" 2>/dev/null)"
  if [ "$parsed" != "$records" ]; then
    echo "cortex-map: refusing to write a MAP.md that does not read back as written; the map is unchanged" >&2
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$MAP"
}

# Reject a target path that the map's own writer/parser cannot round-trip
# safely. THE single definition of "representable" — --set, --remove, --drift
# and --check all go through it, so what drift proposes is exactly what set
# accepts. Prints a diagnostic and returns 2.
#
# A node line carries TWO positional channels:
#
#     <indent><name>/  <description>
#
# The name ends at its slash, so interior and trailing spaces round-trip fine.
# The depth is the leading indentation, two spaces per level — which is why a
# name may not START with a space in any segment: that space is read back as
# indentation and corrupts the whole file, not just its own node.
#
# The rest: an absolute path would render a malformed empty root component via
# the ancestor-expansion awk; a `.` or `..` segment is redundant or escapes the
# tree; an empty segment renders a nameless node; a control character cannot be
# carried at all (the format is line-oriented and the hooks' touch record is
# tab-delimited); and a top-level name opening with `#` or `>` renders a line
# the parser skips as a header comment, so the node would vanish on write and
# every later --set would append another duplicate.
validate_target() {
  local t="$1"
  case "$t" in
    /*)
      echo "cortex-map: absolute paths are not allowed: $t" >&2
      return 2
      ;;
  esac
  case "/$t" in
    */\ *)
      echo "cortex-map: folder names may not start with a space — a leading space is read back as MAP.md indentation: $t" >&2
      return 2
      ;;
  esac
  case "$t" in
    *//*)
      echo "cortex-map: empty path segments are not allowed: $t" >&2
      return 2
      ;;
  esac
  case "$t" in
    '#'*|'>'*)
      echo "cortex-map: a top-level folder name may not start with '#' or '>' — MAP.md reads such a line as a header comment: $t" >&2
      return 2
      ;;
  esac
  case "/$t/" in
    */../*)
      echo "cortex-map: '..' path segments are not allowed: $t" >&2
      return 2
      ;;
  esac
  case "/$t/" in
    */./*)
      echo "cortex-map: '.' path segments are not allowed: $t" >&2
      return 2
      ;;
  esac
  case "$t" in
    *[[:cntrl:]]*)
      echo "cortex-map: folder names may not contain tabs, newlines or other control characters: $t" >&2
      return 2
      ;;
  esac
  return 0
}

case "$MODE" in
  --validate)
    map_parse >/dev/null || exit 1
    exit 0
    ;;
  --lookup)
    TARGET="${1:-}"
    [ -n "$TARGET" ] || { echo "cortex-map: --lookup needs a directory" >&2; exit 2; }
    TARGET="${TARGET%/}"
    FOUND="$(map_parse | CX_T="$TARGET" awk -F'\t' '$1 == ENVIRON["CX_T"] { print $2; found=1; exit } END { exit !found }')" \
      && { printf '%s\n' "$FOUND"; exit 0; }
    echo "MISSING"
    exit 1
    ;;
  --set)
    TARGET="${1:-}"; shift || true
    DESC="${*:-}"
    [ -n "$TARGET" ] || { echo "cortex-map: --set needs a directory" >&2; exit 2; }
    # A description opens after the two spaces that follow the name, and the
    # parser strips them, so leading spaces here are not part of the value.
    # Drop them BEFORE the emptiness test, or an all-spaces description passes
    # it and writes a node with no description at all.
    while [ "${DESC# }" != "$DESC" ]; do DESC="${DESC# }"; done
    [ -n "$DESC" ]   || { echo "cortex-map: --set needs a description" >&2; exit 2; }
    # The description shares the node line with the name, so it is bound by the
    # same line-oriented limits. map_write's round-trip guard would catch a tab
    # or newline, but only as an opaque "does not read back" refusal — and a
    # lone carriage return survives the round-trip while still writing a control
    # byte into the map. Reject them here, where the diagnostic can say why.
    case "$DESC" in
      *[[:cntrl:]]*)
        echo "cortex-map: a description may not contain control characters" >&2
        exit 2
        ;;
    esac
    TARGET="${TARGET%/}"
    validate_target "$TARGET" || exit 2
    map_parse >/dev/null || exit 1

    RECORDS="$(map_parse)"
    # Every ancestor of TARGET must exist; add placeholders for any that don't.
    ANCESTORS="$(printf '%s\n' "$TARGET" | awk -F/ '{ p=""; for (i=1; i<NF; i++) { p = (i==1 ? $1 : p "/" $i); print p } }')"
    while IFS= read -r anc; do
      [ -n "$anc" ] || continue
      printf '%s\n' "$RECORDS" | CX_A="$anc" awk -F'\t' '$1 == ENVIRON["CX_A"] { found=1 } END { exit !found }' \
        || RECORDS="$(printf '%s\n%s\t(undescribed)' "$RECORDS" "$anc")"
    done <<< "$ANCESTORS"

    # Upsert TARGET.
    RECORDS="$(printf '%s\n' "$RECORDS" | CX_T="$TARGET" awk -F'\t' '$1 != ENVIRON["CX_T"]')"
    RECORDS="$(printf '%s\n%s\t%s' "$RECORDS" "$TARGET" "$DESC")"

    printf '%s\n' "$RECORDS" | map_sort | map_write || exit 1
    exit 0
    ;;
  --remove)
    TARGET="${1:-}"
    [ -n "$TARGET" ] || { echo "cortex-map: --remove needs a directory" >&2; exit 2; }
    TARGET="${TARGET%/}"
    validate_target "$TARGET" || exit 2
    map_parse >/dev/null || exit 1

    # Drop the target and everything beneath it.
    RECORDS="$(map_parse | CX_T="$TARGET" awk -F'\t' '$1 != ENVIRON["CX_T"] && index($1, ENVIRON["CX_T"] "/") != 1')"

    # Prune ancestors that are now childless AND were only placeholders.
    CHANGED=1
    while [ "$CHANGED" -eq 1 ]; do
      CHANGED=0
      PRUNE="$(printf '%s\n' "$RECORDS" | awk -F'\t' '
        $2 == "(undescribed)" { cand[$1] = 1 }
        { all[NR] = $1 }
        END {
          for (c in cand) {
            has_child = 0
            for (i in all) if (index(all[i], c "/") == 1) { has_child = 1; break }
            if (!has_child) print c
          }
        }')"
      if [ -n "$PRUNE" ]; then
        while IFS= read -r p; do
          [ -n "$p" ] || continue
          RECORDS="$(printf '%s\n' "$RECORDS" | CX_T="$p" awk -F'\t' '$1 != ENVIRON["CX_T"]')"
          CHANGED=1
        done <<< "$PRUNE"
      fi
    done

    # `|| exit 1` as in --set: this script is the sole writer of MAP.md, so a
    # write it could not perform must never be reported to the caller as done.
    printf '%s\n' "$RECORDS" | grep -v '^$' | map_sort | map_write || exit 1
    exit 0
    ;;
  --check)
    # Read-only: ask whether a name is representable, without touching the map.
    # This is the seam that keeps other components — the Stop hook above all —
    # from re-deriving the rule by hand. Diagnostics go to stderr; the answer is
    # the exit status.
    TARGET="${1:-}"
    [ -n "$TARGET" ] || { echo "cortex-map: --check needs a directory" >&2; exit 2; }
    validate_target "${TARGET%/}" || exit 2
    exit 0
    ;;
  --drift)
    [ -n "${1:-}" ] && ROOT="$1"
    MAP="${CORTEX_MAP_FILE:-$ROOT/.cortex/MAP.md}"
    SCAN="$ROOT/.cortex/scripts/cortex-scan.sh"
    [ -f "$SCAN" ] || SCAN="$(dirname "$0")/cortex-scan.sh"
    map_parse >/dev/null || exit 1

    # Drop what validate_target would refuse, by ASKING validate_target rather
    # than re-deriving its rule here. Every folder drift proposes is then one
    # --set can actually apply, which is what lets /cortex-sync reach its "both
    # must be silent" end state. A second approximation of the rule is exactly
    # how the leading-space shape stayed proposed-but-unappliable once already.
    ON_DISK="$(bash "$SCAN" --dirs "$ROOT" | grep -v '^$' | while IFS= read -r d; do
      validate_target "$d" 2>/dev/null && printf '%s\n' "$d"
    done | LC_ALL=C sort -u)"
    IN_MAP="$(map_parse | cut -f1 | grep -v '^$' | LC_ALL=C sort -u)"

    # `printf '%s\n' "$VAR"` still emits one blank line when VAR is empty, and
    # the greps above ran inside the command substitution so they cannot remove
    # it. comm would then report that blank line as a difference and it would
    # render as a marker with no folder name — which is the fresh-install case
    # (empty map, folders on disk) and its mirror. Filter where it is introduced.
    nonblank() { printf '%s\n' "$1" | grep -v '^$'; }

    LC_ALL=C comm -23 <(nonblank "$ON_DISK") <(nonblank "$IN_MAP") | sed 's/^/+ /'
    LC_ALL=C comm -13 <(nonblank "$ON_DISK") <(nonblank "$IN_MAP") | sed 's/^/- /'
    exit 0
    ;;
esac
exit 2
