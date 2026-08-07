#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — Knowledge layer for AI coding agents
# Installer for a single project
#
# Usage:
#   bash install.sh                                    # Interactive
#   bash install.sh /path/to/project                   # Install in specified project
#   bash install.sh --agent claude|opencode|both [path]
#   bash install.sh --source /path/to/cortex [--agent ...] [path]
# ──────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ─────────────────────────────────────
REPO_URL="https://github.com/MaverickLBP/cortex.git"
BRANCH="main"
SOURCE_DIR=""
TARGET=""
AGENT=""   # claude | opencode | both (empty = ask)

# ── Parse arguments ───────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --agent)
      AGENT="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage:"
      echo "  bash install.sh                                   # Interactive"
      echo "  bash install.sh /path/to/project                  # Install in specified project"
      echo "  bash install.sh --agent claude|opencode|both [path]"
      echo "  bash install.sh --source /path/to/cortex [--agent ...] [path]"
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
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
  GREEN=''; CYAN=''; YELLOW=''; RED=''; NC=''
fi

ok()     { echo -e "  ${GREEN}✔${NC} $1"; }
info()   { echo -e "  ${CYAN}→${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()    { echo -e "  ${RED}✖${NC} $1"; }
prompt() { echo -e -n "  ${CYAN}?${NC} $1 "; }

# ── Helpers ────────────────────────────────────────────

copy_file() {
  local src="$1" dst="$2"
  [ -f "$src" ] && cp "$src" "$dst" && return 0
  return 1
}

# Idempotent jq merge: add key=value to a JSON object file.
# Creates the file with {} if it doesn't exist.
json_set() {
  local file="$1" key="$2" value="$3"
  local tmp
  tmp="$(mktemp)"
  if [ ! -f "$file" ]; then
    echo '{}' > "$file"
  fi
  jq --argjson val "$value" ".\"$key\" = \$val" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Idempotent: add a string to a JSON array at key, no duplicates.
json_array_add() {
  local file="$1" key="$2" item="$3"
  local tmp
  tmp="$(mktemp)"
  if [ ! -f "$file" ]; then
    echo '{}' > "$file"
  fi
  jq --arg item "$item" --arg key "$key" \
    'if (.[$key] | type) == "array"
     then if (.[$key] | index($item)) == null then .[$key] += [$item] else . end
     else .[$key] = [$item]
     end' \
    "$file" > "$tmp" && mv "$tmp" "$file"
}

# ── Install .cortex/ knowledge ─────────────────────────

install_knowledge() {
  local target="$1" src="$2"

  mkdir -p "$target/.cortex/scripts"
  ok "Created .cortex/"

  copy_file "$src/.cortex/SYSTEM.md" "$target/.cortex/SYSTEM.md" && \
    ok "Installed SYSTEM.md" || warn "SYSTEM.md not found in source"

  # MAP.md is never copied from the source repo: the source's own MAP.md
  # describes the source project's folders (e.g. CORTEX's own dogfooded
  # tree), and that header/body would become permanently baked into every
  # installed project — map_write preserves "everything before the first
  # node line" as the header forever, with no sanctioned way to change it
  # (hand-editing MAP.md is forbidden by design). Instead, write a fresh
  # header-only map with no folder nodes, using the target's own directory
  # name, in the same header format cortex-map.sh's map_write falls back to.
  local map_file="$target/.cortex/MAP.md"
  if [ ! -f "$map_file" ]; then
    local project_name
    project_name="$(basename "$target")"
    cat > "$map_file" << EOM
# Knowledge Map — ${project_name}

> Folder-level map. Every folder containing tracked files appears here.
> Generated and maintained by cortex-map.sh. Do not edit by hand.
EOM
    ok "Created MAP.md (header only — run /cortex-sync to populate it)"
  else
    warn "MAP.md exists — preserved (not overwritten)"
  fi

  if [ ! -f "$target/.cortex/PROJECT.md" ]; then
    copy_file "$src/.cortex/PROJECT.md" "$target/.cortex/PROJECT.md" && \
      ok "Installed PROJECT.md template" || warn "PROJECT.md not found in source"
  else
    info "PROJECT.md already exists — left untouched"
  fi

  for s in cortex-scan.sh cortex-map.sh; do
    if copy_file "$src/.cortex/scripts/$s" "$target/.cortex/scripts/$s"; then
      chmod +x "$target/.cortex/scripts/$s"
      ok "Installed $s"
    else
      warn "$s not found in source"
    fi
  done
}

# ── Install for Claude Code ────────────────────────────

install_claude() {
  local target="$1" src="$2"

  mkdir -p "$target/.claude/hooks" "$target/.claude/commands"

  # Hooks (session + active-enforcement)
  for hook in cortex-session.sh cortex-file-change.sh cortex-subagent.sh cortex-stop.sh; do
    if copy_file "$src/.claude/hooks/$hook" "$target/.claude/hooks/$hook"; then
      chmod +x "$target/.claude/hooks/$hook"
      ok "Installed $hook hook"
    else
      warn "$hook not found in source"
    fi
  done

  # settings.json — merge hook (idempotent)
  local settings="$target/.claude/settings.json"
  local hook_cmd="bash .claude/hooks/cortex-session.sh"
  local hook_entry
  hook_entry='{"type":"command","command":"bash .claude/hooks/cortex-session.sh","statusMessage":"Loading CORTEX knowledge..."}'

  if command -v jq >/dev/null 2>&1; then
    if [ ! -f "$settings" ]; then
      echo '{}' > "$settings"
    fi
    # Add hook only if not already present
    local tmp
    tmp="$(mktemp)"
    jq --argjson entry "$hook_entry" '
      .hooks.SessionStart //= [] |
      if (.hooks.SessionStart // [] |
          map(.hooks // [] | .[] | select(.command == "bash .claude/hooks/cortex-session.sh")) |
          length) > 0
      then .
      else
        .hooks.SessionStart += [{"hooks": [$entry]}]
      end
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    ok "Merged SessionStart hook into .claude/settings.json"

    # PostToolUse — file-change reminders (idempotent)
    tmp="$(mktemp)"
    jq '
      .hooks.PostToolUse //= [] |
      if (.hooks.PostToolUse // [] |
          map(.hooks // [] | .[] | select(.command == "bash .claude/hooks/cortex-file-change.sh")) |
          length) > 0
      then .
      else
        .hooks.PostToolUse += [
          {"matcher":"Write","hooks":[
            {"type":"command","command":"bash .claude/hooks/cortex-file-change.sh"}
          ]},
          {"matcher":"Bash","hooks":[
            {"type":"command","command":"bash .claude/hooks/cortex-file-change.sh","if":"Bash(rm *)"},
            {"type":"command","command":"bash .claude/hooks/cortex-file-change.sh","if":"Bash(mv *)"}
          ]}
        ]
      end
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    ok "Merged PostToolUse hooks into .claude/settings.json"

    # SubagentStart — CORTEX note for subagents (idempotent)
    tmp="$(mktemp)"
    jq '
      .hooks.SubagentStart //= [] |
      if (.hooks.SubagentStart // [] |
          map(.hooks // [] | .[] | select(.command == "bash .claude/hooks/cortex-subagent.sh")) |
          length) > 0
      then .
      else
        .hooks.SubagentStart += [{"hooks":[
          {"type":"command","command":"bash .claude/hooks/cortex-subagent.sh"}
        ]}]
      end
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    ok "Merged SubagentStart hook into .claude/settings.json"

    # Stop — consolidate the knowledge map once per turn (idempotent)
    tmp="$(mktemp)"
    jq '
      .hooks.Stop //= [] |
      if (.hooks.Stop // [] |
          map(.hooks // [] | .[] | select(.command == "bash .claude/hooks/cortex-stop.sh")) |
          length) > 0
      then .
      else
        .hooks.Stop += [{"hooks":[
          {"type":"command","command":"bash .claude/hooks/cortex-stop.sh"}
        ]}]
      end
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    ok "Merged Stop hook into .claude/settings.json"
  else
    warn "jq not found — skipping settings.json merge (install jq and re-run)"
  fi

  # Commands
  for cmd in cortex-sync; do
    if copy_file "$src/.cortex/commands/${cmd}.md" "$target/.claude/commands/${cmd}.md"; then
      ok "Installed ${cmd} command (Claude Code)"
    else
      warn "${cmd}.md not found in source"
    fi
  done

  # .gitignore — track settings.json, ignore settings.local.json
  local gitignore="$target/.gitignore"
  if [ ! -f "$gitignore" ]; then
    touch "$gitignore"
    ok "Created .gitignore"
  fi
  # Remove old blanket ignore of .claude/settings.json if present
  if grep -q "^\.claude/settings\.json$" "$gitignore" 2>/dev/null; then
    sed -i '/^\.claude\/settings\.json$/d' "$gitignore"
    warn "Removed .claude/settings.json from .gitignore (it should now be committed)"
  fi
  if ! grep -q "\.claude/settings\.local\.json" "$gitignore" 2>/dev/null; then
    echo ".claude/settings.local.json" >> "$gitignore"
    ok "Added .claude/settings.local.json to .gitignore"
  fi
  # Older installs ignored the flat '.cortex/.touched-*' glob; records now live
  # under '.cortex/.touched/' instead, so migrate the stale line forward.
  if grep -qxF '.cortex/.touched-*' "$gitignore" 2>/dev/null; then
    sed -i '/^\.cortex\/\.touched-\*$/d' "$gitignore"
  fi
  grep -qF '.cortex/.touched/' "$gitignore" 2>/dev/null || {
    printf '\n# CORTEX session touch records (ephemeral)\n.cortex/.touched/\n' >> "$gitignore"
    ok "Added .cortex/.touched/ to .gitignore"
  }
}

# ── Install for OpenCode ───────────────────────────────

install_opencode() {
  local target="$1" src="$2"

  mkdir -p "$target/.opencode/commands"

  # opencode.json — merge instructions (idempotent)
  local oc_json="$target/opencode.json"
  if command -v jq >/dev/null 2>&1; then
    json_array_add "$oc_json" "instructions" ".cortex/SYSTEM.md"
    json_array_add "$oc_json" "instructions" ".cortex/PROJECT.md"
    json_array_add "$oc_json" "instructions" ".cortex/MAP.md"
    ok "Merged CORTEX instructions into opencode.json"
  else
    warn "jq not found — skipping opencode.json merge (install jq and re-run)"
  fi

  # Commands
  for cmd in cortex-sync; do
    if copy_file "$src/.cortex/commands/${cmd}.md" "$target/.opencode/commands/${cmd}.md"; then
      ok "Installed ${cmd} command (OpenCode)"
    else
      warn "${cmd}.md not found in source"
    fi
  done
}

# ── Main installer ─────────────────────────────────────

install_cortex() {
  local target="$1"
  local src="$2"
  local agent="$3"
  local project_name
  project_name="$(basename "$target")"

  echo ""
  info "Installing CORTEX in ${CYAN}$project_name${NC}"
  echo ""

  target="$(cd "$target" 2>/dev/null && pwd)" || {
    err "Directory not found: '$target'"
    exit 1
  }

  # Knowledge (always)
  install_knowledge "$target" "$src"

  # Agent-specific
  case "$agent" in
    claude)
      install_claude "$target" "$src"
      ;;
    opencode)
      install_opencode "$target" "$src"
      ;;
    both)
      install_claude "$target" "$src"
      install_opencode "$target" "$src"
      ;;
  esac
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
    echo ""
    prompt "Enter project path (leave blank for current directory):"
    read -r TARGET
    [ -z "$TARGET" ] && TARGET="."
    if [ ! -d "$TARGET" ]; then
      err "Directory not found: '$TARGET'"
      exit 1
    fi
  else
    TARGET="."
    info "No project path specified; using current directory: $(pwd)"
  fi
fi

TARGET="$(cd "$TARGET" && pwd)"

# Resolve agent
if [ -z "$AGENT" ]; then
  if [ -t 0 ]; then
    echo ""
    echo "  Which agent(s) to configure?"
    echo "    1) Claude Code"
    echo "    2) OpenCode"
    echo "    3) Both"
    prompt "Enter choice [1/2/3]:"
    read -r choice
    case "$choice" in
      1) AGENT="claude" ;;
      2) AGENT="opencode" ;;
      3) AGENT="both" ;;
      *) err "Invalid choice. Use 1, 2, or 3."; exit 1 ;;
    esac
  else
    AGENT="claude"
    info "Non-interactive mode: defaulting to Claude Code. Use --agent to override."
  fi
fi

case "$AGENT" in
  claude|opencode|both) ;;
  *) err "Invalid --agent value: '$AGENT'. Use claude, opencode, or both."; exit 1 ;;
esac

# Resolve source
if [ -n "$SOURCE_DIR" ]; then
  SRC="$SOURCE_DIR"
  if [ ! -d "$SRC/.cortex" ]; then
    err "'$SRC' does not contain .cortex/"
    exit 1
  fi
  info "Using local source: $SRC"
else
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "${TMP_DIR:-}"' EXIT
  info "Downloading CORTEX from $REPO_URL..."
  if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR" 2>/dev/null; then
    err "Download failed. Check your connection."
    rm -rf "$TMP_DIR"
    exit 1
  fi
  SRC="$TMP_DIR"
  ok "Downloaded"
fi

install_cortex "$TARGET" "$SRC" "$AGENT"

# Cleanup
if [ -n "${TMP_DIR:-}" ]; then
  rm -rf "$TMP_DIR"
fi

echo ""
echo "  ───────────────────────────────────────"
echo -e "  ${GREEN}✔ CORTEX installed in${NC} $TARGET"
echo ""
echo "  Next steps:"
echo "    1. Run  /cortex-sync  to generate or refresh the knowledge map"
echo "    2. Commit .cortex/ and .claude/settings.json (if Claude Code)"
