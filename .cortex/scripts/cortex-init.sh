#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — cortex-init: Project tree scanner
#
# Outputs a complete directory tree of the project,
# excluding common generated/ignored directories.
# The agent reads this output and builds MAP.md.
#
# Usage:
#   bash .cortex/scripts/cortex-init.sh
# ──────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ─────────────────────────────────────
EXCLUDE_DIRS=".git node_modules dist build .next out target vendor _build .venv __pycache__ .cache"

# ── Build find exclusion flags ────────────────────────
EXCLUDE_FLAGS=()
for dir in $EXCLUDE_DIRS; do
  EXCLUDE_FLAGS+=( -not -path "*/$dir/*" -not -name "$dir" )
done

# ── Get project root ──────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"

PROJECT_NAME="$(basename "$PROJECT_ROOT")"

# ── Output as a tree ──────────────────────────────────
echo "# Project tree: $PROJECT_NAME"
echo "# Root: $PROJECT_ROOT"
echo "# Generated: $(date '+%Y-%m-%d %H:%M')"
echo "# Excluded: $EXCLUDE_DIRS"
echo ""
echo "$PROJECT_NAME/"

# Collect all entries (dirs + files), sorted
# Format: "depth type name" where type is "d" or "f"
entries=$(find . "${EXCLUDE_FLAGS[@]}" -not -name "." \( -type d -o -type f \) | sort)

# Process each entry and output with proper indentation
echo "$entries" | while IFS= read -r entry; do
  clean="${entry#./}"
  depth=0
  temp="$clean"
  while [[ "$temp" == */* ]]; do
    depth=$((depth + 1))
    temp="${temp#*/}"
  done

  # Build indentation (2 spaces per depth level)
  indent=""
  for ((i=0; i<depth; i++)); do
    indent="${indent}  "
  done

  if [ -d "$entry" ]; then
    echo "${indent}📁 ${clean}/"
  else
    echo "${indent}📄 ${clean}"
  fi
done
