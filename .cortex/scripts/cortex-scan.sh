#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — cortex-scan: gitignore-aware enumeration.
# Prints documentable files (default) or their parent dirs.
# Honors the repo's .gitignore inside a git work tree;
# find-based fallback otherwise. Always excludes the
# universal floor: .git .cortex .claude .opencode
# Usage: cortex-scan.sh [--files|--dirs] [ROOT]
# ──────────────────────────────────────────────────────
set -uo pipefail

# Character classification below decides which names are representable, so it is
# pinned to the C locale: in an 8-bit locale (ISO-8859-*) the bytes 0x80-0x9F
# classify as control characters, and those bytes occur inside perfectly ordinary
# UTF-8 sequences (the 0x82 in '€'). Without this an accented folder name would be
# rejected or dropped depending on the ambient locale of whoever invoked us.
export LC_ALL=C

MODE="--files"
case "${1:-}" in --files|--dirs) MODE="$1"; shift ;; esac
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

FLOOR_RE='^(\.git|\.cortex|\.claude|\.opencode)(/|$)'

# Both branches emit NUL-delimited paths, so nothing ever quotes, escapes or
# splits a name. That matters for two shapes that used to break differently in
# each branch: git quoted and octal-escaped non-ASCII names (yielding a string
# naming no real folder), while find happily emitted a newline-containing name
# as two lines — losing the real folder and inventing a phantom one from the
# fragment. Delimiting on NUL removes both failure modes at the source instead
# of pattern-matching their symptoms afterwards.
list_files_raw() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Tracked + untracked-but-not-ignored, all respecting .gitignore.
    # -z is what disables quoting entirely, so core.quotePath never applies.
    git -C "$ROOT" ls-files -z --cached --others --exclude-standard 2>/dev/null
  else
    # Fallback: broadened static excludes (no gitignore available).
    local ex=".git node_modules dist build .next out target vendor _build .venv venv __pycache__ .cache .gradle bin obj Pods .terraform"
    local flags=()
    for d in $ex; do flags+=( -not -path "*/$d/*" -not -name "$d" ); done
    find . "${flags[@]}" -type f -not -name "." -print0 2>/dev/null
  fi
}

# NUL-delimited in, newline-delimited out, minus the paths that cannot survive a
# line-oriented format at all. This is NOT the full representability rule —
# cortex-map.sh's validate_target owns that, and --drift applies it. Here we only
# drop what would corrupt this script's own output. A newline inside a name becomes 0x01 first so that it survives as a
# detectable control character instead of splitting the record; the grep then
# drops it along with tabs and the rest. Emitting lines is safe precisely
# because by this point no path contains a control character. Octal escapes in
# `tr` (not \0 / \n shorthands) — BSD and GNU tr agree on those.
list_files() {
  list_files_raw \
    | tr '\n' '\001' | tr '\000' '\n' \
    | LC_ALL=C grep -v '[[:cntrl:]]' \
    | sed 's|^\./||'
}

if [ "$MODE" = "--files" ]; then
  list_files | grep -Ev "$FLOOR_RE" | sort -u
else
  list_files | grep -Ev "$FLOOR_RE" | grep '/' \
    | sed 's|/[^/]*$||' \
    | awk -F/ '{ p=""; for (i=1; i<NF+1; i++) { p = (i==1 ? $1 : p "/" $i); print p } }' \
    | sort -u
fi
exit 0
