#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — Knowledge layer for AI coding agents
# Installer for a single project
#
# Usage:
#   bash install.sh                           # Interactive (prompts for project path)
#   bash install.sh /path/to/project           # Install in specified project
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
      echo "  bash install.sh                           # Interactive (prompts for path)"
      echo "  bash install.sh /path/to/project           # Install in specified project"
      echo "  bash install.sh --source /path/to/cortex /path/to/target"
      exit 0
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

# ── Colours ───────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  GREEN=''; CYAN=''; YELLOW=''; NC=''
fi

ok()     { echo -e "  ${GREEN}✔${NC} $1"; }
info()   { echo -e "  ${CYAN}→${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
prompt() { echo -e -n "  ${CYAN}?${NC} $1 "; }

# ── Helpers ────────────────────────────────────────────

copy_file() {
  local src="$1" dst="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    return 0
  fi
  return 1
}

# ── CLAUDE.md setup ────────────────────────────────────

setup_claude_md() {
  local target="$1"
  local clauderc="$target/CLAUDE.md"

  if [ -f "$clauderc" ] && grep -q "## Session start" "$clauderc" 2>/dev/null; then
    warn "CLAUDE.md already has CORTEX instructions — not modified"
    return 0
  fi

  {
    echo "# CORTEX — Project"
    echo ""
    echo "This project uses **CORTEX** as its knowledge layer."
    echo ""
    echo "## Session start"
    echo "At session start, you MUST load \`.claude/cortex/SYSTEM.md\`."
    echo "It contains mandatory system instructions and defines the project knowledge map (MAP.md)."
    echo "Follow all instructions within — this is required before any task execution."
  } >> "$clauderc"
  ok "CLAUDE.md configured with CORTEX instructions"
}

# ── Install ────────────────────────────────────────────

install_cortex() {
  local target="$1"
  local src="$2"
  local project_name
  project_name="$(basename "$target")"

  echo ""
  info "Installing CORTEX in ${CYAN}$project_name${NC}"
  echo ""

  target="$(cd "$target" 2>/dev/null && pwd)" || {
    echo "  Error: '$target' is not a valid directory."
    exit 1
  }

  # Create directories
  mkdir -p "$target/.claude/cortex/commands"
  mkdir -p "$target/.claude/cortex/scripts"
  mkdir -p "$target/.claude/commands"
  ok "Created directory structure"

  # Core files
  copy_file "$src/.claude/cortex/SYSTEM.md" "$target/.claude/cortex/SYSTEM.md" && \
    ok "Installed SYSTEM.md" || warn "SYSTEM.md not found in source"

  local map_file="$target/.claude/cortex/MAP.md"
  if [ ! -f "$map_file" ]; then
    if copy_file "$src/.claude/cortex/MAP.md" "$map_file"; then
      ok "Created MAP.md (template)"
    else
      cat > "$map_file" << 'EOM'
# Knowledge Map — [Project Name]

> Knowledge layer for AI coding agents.
> MAP.md generated: (pending)
> Run `/cortex-init` to generate the full map automatically.

## 🛠 Tech Stack

| Technology | Version | Purpose |
|------------|---------|---------|

## Notes
EOM
      ok "Created MAP.md (default template)"
    fi
  else
    warn "MAP.md exists — preserved (not overwritten)"
  fi

  # Commands
  copy_file "$src/.claude/cortex/commands/cortex-init.md" \
    "$target/.claude/cortex/commands/cortex-init.md" && \
    ok "Installed cortex-init" || warn "cortex-init.md not found"
  copy_file "$src/.claude/cortex/commands/cortex-update.md" \
    "$target/.claude/cortex/commands/cortex-update.md" && \
    ok "Installed cortex-update" || warn "cortex-update.md not found"
  copy_file "$src/.claude/cortex/commands/cortex-view-map.md" \
    "$target/.claude/cortex/commands/cortex-view-map.md" && \
    ok "Installed cortex-view-map" || warn "cortex-view-map.md not found"

  # Scripts
  if copy_file "$src/.claude/cortex/scripts/cortex-init.sh" \
    "$target/.claude/cortex/scripts/cortex-init.sh"; then
    chmod +x "$target/.claude/cortex/scripts/cortex-init.sh"
    ok "Installed cortex-init script"
  fi

  # Slash commands (for Claude Code UI)
  copy_file "$src/.claude/cortex/commands/cortex-init.md" \
    "$target/.claude/commands/cortex-init.md" &>/dev/null || true
  copy_file "$src/.claude/cortex/commands/cortex-update.md" \
    "$target/.claude/commands/cortex-update.md" &>/dev/null || true
  copy_file "$src/.claude/cortex/commands/cortex-view-map.md" \
    "$target/.claude/commands/cortex-view-map.md" &>/dev/null || true

  # CLAUDE.md
  setup_claude_md "$target"
}

# ───────────────────────────────────────────────────────
# MAIN
# ───────────────────────────────────────────────────────

echo ""
echo -e "  ${CYAN}⟐ CORTEX${NC} — Knowledge layer for AI coding agents"
echo "  ───────────────────────────────────────"

# Resolve target
if [ -z "$TARGET" ]; then
  if [ -t 0 ]; then
    # Interactive terminal — prompt the user
    echo ""
    prompt "Enter project path:"
    read -r TARGET
    if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
      echo "  Error: '$TARGET' is not a valid directory."
      exit 1
    fi
  else
    # Non-interactive (piped stdin) — default to current directory
    TARGET="."
    echo ""
    info "No project path specified; using current directory: $(pwd)"
  fi
fi

TARGET="$(cd "$TARGET" && pwd)"

# Resolve source
if [ -n "$SOURCE_DIR" ]; then
  SRC="$SOURCE_DIR"
  if [ ! -d "$SRC/.claude/cortex" ]; then
    echo "  Error: '$SRC' does not contain .claude/cortex/"
    exit 1
  fi
  info "Using local source: $SRC"
else
  TMP_DIR=$(mktemp -d)
  info "Downloading CORTEX from $REPO_URL..."
  if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR" 2>/dev/null; then
    echo "  Error downloading CORTEX. Check your connection."
    rm -rf "$TMP_DIR"
    exit 1
  fi
  SRC="$TMP_DIR"
  ok "Downloaded"
fi

install_cortex "$TARGET" "$SRC"

# Cleanup
if [ -n "${TMP_DIR:-}" ]; then
  rm -rf "$TMP_DIR"
fi

echo ""
echo "  ───────────────────────────────────────"
echo -e "  ${GREEN}✔ CORTEX installed in${NC} $TARGET"
echo ""
echo "  Next steps:"
echo "    1. Run  /cortex-init  to generate the knowledge map"
echo "    2. Run  /cortex-view-map  to see the map at any time"
