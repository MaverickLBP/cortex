#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# CORTEX — Context-Oriented Runtime Technical Experience
# Installer
#
# Usage:
#   curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash
#   curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash -s -- /path/to/project
# ──────────────────────────────────────────────

REPO_URL="https://github.com/MaverickLBP/cortex.git"
BRANCH="main"
TARGET="${1:-$(pwd)}"

# ── Validate target ──────────────────────────
if [ ! -d "$TARGET" ]; then
  echo "Error: '$TARGET' is not a valid directory."
  exit 1
fi

# ── Fetch CORTEX ─────────────────────────────
TMP_DIR=$(mktemp -d)
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR" 2>/dev/null || {
  echo "Error downloading CORTEX. Check your connection."
  rm -rf "$TMP_DIR"
  exit 1
}

# ── Create .claude/cortex/ at target ─────────
mkdir -p "$TARGET/.claude/cortex"
cp "$TMP_DIR/.claude/cortex/SYSTEM.md" "$TARGET/.claude/cortex/SYSTEM.md"

if [ ! -f "$TARGET/.claude/cortex/context.md" ]; then
  cp "$TMP_DIR/.claude/cortex/context.md" "$TARGET/.claude/cortex/context.md"
  echo "✔ context.md created (initial template)"
else
  echo "○ context.md exists — preserved"
fi

# ── Configure CLAUDE.md ──────────────────────
LOADER_LINE="→ Load .claude/cortex/SYSTEM.md for complete system instructions."

if ! grep -q "CORTEX" "$TARGET/CLAUDE.md" 2>/dev/null; then
  echo "" >> "$TARGET/CLAUDE.md"
  echo "This project uses **CORTEX** for persistent project context." >> "$TARGET/CLAUDE.md"
  echo "$LOADER_LINE" >> "$TARGET/CLAUDE.md"
  echo "✔ CLAUDE.md updated"
else
  echo "○ CLAUDE.md already references CORTEX — not modified"
fi

# ── Cleanup ──────────────────────────────────
rm -rf "$TMP_DIR"

echo ""
echo "CORTEX installed in $TARGET"
echo "Edit .claude/cortex/context.md to describe your project."
