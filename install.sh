#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — Knowledge layer for AI coding agents
# Installer
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash
#   curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash -s -- /path/to/project
#
# Development:
#   bash install.sh --source /path/to/cortex /path/to/target
# ──────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ─────────────────────────────────────
REPO_URL="https://github.com/MaverickLBP/cortex.git"
BRANCH="main"
SOURCE_DIR=""
TARGET=""

# ── Parse arguments ───────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage:"
      echo "  curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash"
      echo "  curl ... | bash -s -- /path/to/project"
      echo ""
      echo "  Local development:"
      echo "  bash install.sh --source /path/to/cortex [/path/to/target]"
      exit 0
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

# Default target: current directory
TARGET="${TARGET:-$(pwd)}"

# ── Colours ───────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  GREEN=''; CYAN=''; YELLOW=''; NC=''
fi

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

# ── Validate target directory ─────────────────────────
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
  echo "Error: '$TARGET' is not a valid directory."
  exit 1
}

echo ""
echo -e "  ${CYAN}⟐ CORTEX${NC} — Knowledge layer for AI coding agents"
echo "  ───────────────────────────────────────"
echo ""

# ── Fetch or locate CORTEX source ─────────────────────
if [ -n "$SOURCE_DIR" ]; then
  # Local development mode
  SRC="$SOURCE_DIR"
  if [ ! -d "$SRC/.claude/cortex" ]; then
    echo "Error: '$SRC' does not contain .claude/cortex/"
    exit 1
  fi
  info "Using local source: $SRC"
else
  # Production mode: clone from GitHub
  TMP_DIR=$(mktemp -d)
  info "Downloading CORTEX from $REPO_URL..."
  if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR" 2>/dev/null; then
    echo "Error downloading CORTEX. Check your connection."
    rm -rf "$TMP_DIR"
    exit 1
  fi
  SRC="$TMP_DIR"
  ok "Downloaded"
fi

# ── Create directories ────────────────────────────────
mkdir -p "$TARGET/.claude/cortex/commands"
mkdir -p "$TARGET/.claude/cortex/scripts"
mkdir -p "$TARGET/.claude/commands"
ok "Created directory structure"

# ── Helper: copy file if source exists ────────────────
copy_file() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    return 0
  fi
  return 1
}

# ── Install CORTEX files ──────────────────────────────
copy_file "$SRC/.claude/cortex/SYSTEM.md" "$TARGET/.claude/cortex/SYSTEM.md" && \
  ok "Installed SYSTEM.md" || warn "SYSTEM.md not found"

if [ ! -f "$TARGET/.claude/cortex/MAP.md" ]; then
  if copy_file "$SRC/.claude/cortex/MAP.md" "$TARGET/.claude/cortex/MAP.md"; then
    ok "Created MAP.md (template)"
  else
    cat > "$TARGET/.claude/cortex/MAP.md" << 'EOM'
# Knowledge Map — [Project Name]

> This is the project's knowledge map.
> Run `/cortex-init` (Claude Code) or `run cortex-init` (OpenCode)
> to generate the full map automatically.

## Notes
EOM
    ok "Created MAP.md (default template)"
  fi
else
  warn "MAP.md exists — preserved (not overwritten)"
fi

copy_file "$SRC/.claude/cortex/commands/cortex-init.md" \
          "$TARGET/.claude/cortex/commands/cortex-init.md" && \
  ok "Installed cortex-init command" || warn "cortex-init.md not found"

copy_file "$SRC/.claude/cortex/commands/cortex-view-map.md" \
          "$TARGET/.claude/cortex/commands/cortex-view-map.md" && \
  ok "Installed cortex-view-map command" || warn "cortex-view-map.md not found"

if copy_file "$SRC/.claude/cortex/scripts/cortex-init.sh" \
             "$TARGET/.claude/cortex/scripts/cortex-init.sh"; then
  chmod +x "$TARGET/.claude/cortex/scripts/cortex-init.sh"
  ok "Installed cortex-init script"
else
  warn "cortex-init.sh not found"
fi

# ── Install Claude Code slash commands ─────────────────
copy_file "$SRC/.claude/cortex/commands/cortex-init.md" \
          "$TARGET/.claude/commands/cortex-init.md" && \
  ok "Installed /cortex-init slash command"

copy_file "$SRC/.claude/cortex/commands/cortex-view-map.md" \
          "$TARGET/.claude/commands/cortex-view-map.md" && \
  ok "Installed /cortex-view-map slash command"

# ── Configure CLAUDE.md ───────────────────────────────
CLAUDERC="$TARGET/CLAUDE.md"
LOADER_REF="→ Load .claude/cortex/SYSTEM.md for complete system instructions."
CORTEX_LINE="This project uses **CORTEX** for its knowledge layer."

if [ ! -f "$CLAUDERC" ]; then
  {
    echo "# Project"
    echo ""
    echo "$CORTEX_LINE"
    echo "$LOADER_REF"
  } > "$CLAUDERC"
  ok "Created CLAUDE.md with CORTEX reference"
elif ! grep -q "CORTEX" "$CLAUDERC" 2>/dev/null; then
  {
    echo ""
    echo "$CORTEX_LINE"
    echo "$LOADER_REF"
  } >> "$CLAUDERC"
  ok "Updated CLAUDE.md with CORTEX reference"
else
  warn "CLAUDE.md already references CORTEX — not modified"
fi

# ── Cleanup ────────────────────────────────────────────
if [ -n "${TMP_DIR:-}" ]; then
  rm -rf "$TMP_DIR"
fi

echo ""
echo "  ───────────────────────────────────────"
echo -e "  ${GREEN}✔ CORTEX installed in${NC} $TARGET"
echo ""
echo "  Next steps:"
echo "    1. Run  /cortex-init  (Claude Code)"
echo "       or   run cortex-init  (OpenCode / any agent)"
echo "    2. The agent will scan the project and build MAP.md"
echo "    3. Run  /cortex-view-map  to see the map at any time"
echo "       or   run cortex-view-map  (with optional filter)"
echo ""
