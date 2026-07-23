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

MODE="--files"
case "${1:-}" in --files|--dirs) MODE="$1"; shift ;; esac
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

FLOOR_RE='^(\.git|\.cortex|\.claude|\.opencode)(/|$)'

list_files() {
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Tracked + untracked-but-not-ignored, all respecting .gitignore.
    git -C "$ROOT" ls-files --cached --others --exclude-standard 2>/dev/null
  else
    # Fallback: broadened static excludes (no gitignore available).
    local ex=".git node_modules dist build .next out target vendor _build .venv venv __pycache__ .cache .gradle bin obj Pods .terraform"
    local flags=()
    for d in $ex; do flags+=( -not -path "*/$d/*" -not -name "$d" ); done
    find . "${flags[@]}" -type f -not -name "." 2>/dev/null | sed 's|^\./||'
  fi
}

if [ "$MODE" = "--files" ]; then
  list_files | grep -Ev "$FLOOR_RE" | sort -u
else
  list_files | grep -Ev "$FLOOR_RE" | grep '/' \
    | sed 's|/[^/]*$||' | sort -u
fi
exit 0
