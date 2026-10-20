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

# Absolute, symlink-resolved path of a file (POSIX; no readlink -f / realpath).
abs_path() { echo "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"; }

# Copy a file; a no-op when source and destination are the same file
# (self-install: the source repo is also the target).
copy_file() {
  local src="$1" dst="$2"
  [ -f "$src" ] || return 1
  if [ -f "$dst" ] && [ "$(abs_path "$src")" = "$(abs_path "$dst")" ]; then
    return 0
  fi
  cp "$src" "$dst"
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

# Idempotent: add a hook command to settings.json under an event.
# Existing (foreign) hooks are preserved.
settings_add_hook() {
  local file="$1" event="$2" cmd="$3" tmp
  tmp="$(mktemp)"
  jq --arg ev "$event" --arg cmd "$cmd" '
    .hooks[$ev] //= [] |
    if ([.hooks[$ev][] | (.hooks // [])[] | select(.command == $cmd)] | length) > 0
    then .
    else .hooks[$ev] += [{"hooks":[{"type":"command","command":$cmd}]}]
    end
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Remove exact-match lines from a file (portable replacement for sed -i).
gitignore_drop_line() {
  local file="$1" line="$2" tmp
  tmp="$(mktemp)"
  grep -vxF -- "$line" "$file" > "$tmp" || true
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# ── v5 leftovers ───────────────────────────────────────

# Report (never modify) files and settings entries left by CORTEX v5.
warn_v5_leftovers() {
  local target="$1" found=() f
  for f in .cortex/SYSTEM.md .cortex/MAP.md \
           .claude/hooks/cortex-session.sh .claude/hooks/cortex-file-change.sh; do
    [ -e "$target/$f" ] && found+=("$f")
  done
  local settings="$target/.claude/settings.json"
  if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
    if [ "$(jq '[.. | objects | .command? // empty | strings
                 | select(test("cortex-session\\.sh|cortex-file-change\\.sh"))] | length' \
            "$settings" 2>/dev/null || echo 0)" != "0" ]; then
      found+=(".claude/settings.json (hook entries for cortex-session.sh / cortex-file-change.sh)")
    fi
  fi
  local oc="$target/opencode.json"
  if [ -f "$oc" ] && command -v jq >/dev/null 2>&1; then
    if [ "$(jq '[(.instructions? // []) | if type == "array" then .[] else empty end | strings
                 | select(test("(^|/)\\.cortex/(SYSTEM|MAP)\\.md$"))] | length' \
            "$oc" 2>/dev/null || echo 0)" != "0" ]; then
      found+=("opencode.json (instructions entries for .cortex/SYSTEM.md / .cortex/MAP.md)")
    fi
  fi
  if [ -f "$target/.gitignore" ] && grep -qE '^/?\.cortex/\.touched/?[[:space:]]*$' "$target/.gitignore" 2>/dev/null; then
    found+=(".gitignore (entry for .cortex/.touched/)")
  fi
  if [ "${#found[@]}" -gt 0 ]; then
    echo ""
    warn "CORTEX v5 leftovers found (not modified):"
    for f in "${found[@]}"; do
      echo "      - $f"
    done
    warn "See CHANGELOG 6.0.0 → \"Upgrading from v5\""
  fi
}

# ── Install .cortex/ knowledge ─────────────────────────

install_knowledge() {
  local target="$1" src="$2"

  mkdir -p "$target/.cortex/scripts" "$target/.cortex/map"
  ok "Created .cortex/"

  for f in LOOKUP.md MAINTAIN.md; do
    copy_file "$src/.cortex/$f" "$target/.cortex/$f" && \
      ok "Installed $f" || warn "$f not found in source"
  done

  # PROJECT.md comes from the template, never from the source's own
  # .cortex/PROJECT.md (that one describes the source project).
  if [ ! -f "$target/.cortex/PROJECT.md" ]; then
    local project_name tmpl tmp pre post
    project_name="$(basename "$target")"
    tmpl="$src/templates/PROJECT.md"
    if [ -f "$tmpl" ]; then
      tmp="$(mktemp)"
      while IFS= read -r line || [ -n "$line" ]; do
        # Literal split (no pattern replacement): portable across bash
        # versions/BASH_COMPAT and keeps '&' in the name literal.
        case "$line" in
          *'{{PROJECT_NAME}}'*)
            pre=${line%%'{{PROJECT_NAME}}'*}
            post=${line#*'{{PROJECT_NAME}}'}
            printf '%s\n' "$pre$project_name$post" ;;
          *) printf '%s\n' "$line" ;;
        esac
      done < "$tmpl" > "$tmp"
      mv "$tmp" "$target/.cortex/PROJECT.md"
      ok "Installed PROJECT.md from template"
    else
      warn "templates/PROJECT.md not found in source"
    fi
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

  # With git, the tree snapshot is local state: keep it out of commits.
  if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local gitignore="$target/.gitignore"
    [ -f "$gitignore" ] || touch "$gitignore"
    if ! grep -qxF '.cortex/.state/' "$gitignore" 2>/dev/null; then
      printf '\n# CORTEX local tree snapshot\n.cortex/.state/\n' >> "$gitignore"
      ok "Added .cortex/.state/ to .gitignore"
    fi
  fi
}

# ── Install for Claude Code ────────────────────────────

install_claude() {
  local target="$1" src="$2"

  mkdir -p "$target/.claude/hooks" "$target/.claude/commands" "$target/.claude/rules"

  for hook in cortex-subagent.sh cortex-stop.sh; do
    if copy_file "$src/.claude/hooks/$hook" "$target/.claude/hooks/$hook"; then
      chmod +x "$target/.claude/hooks/$hook"
      ok "Installed $hook hook"
    else
      warn "$hook not found in source"
    fi
  done

  copy_file "$src/.claude/rules/cortex.md" "$target/.claude/rules/cortex.md" && \
    ok "Installed rule cortex.md" || warn "rules/cortex.md not found in source"

  # settings.json — merge only SubagentStart and Stop (idempotent)
  local settings="$target/.claude/settings.json"
  if command -v jq >/dev/null 2>&1; then
    [ -f "$settings" ] || echo '{}' > "$settings"
    settings_add_hook "$settings" SubagentStart "bash .claude/hooks/cortex-subagent.sh"
    settings_add_hook "$settings" Stop "bash .claude/hooks/cortex-stop.sh"
    ok "Merged SubagentStart and Stop hooks into .claude/settings.json"
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
  if grep -qxF ".claude/settings.json" "$gitignore" 2>/dev/null; then
    gitignore_drop_line "$gitignore" ".claude/settings.json"
    warn "Removed .claude/settings.json from .gitignore (it should now be committed)"
  fi
  if ! grep -q "\.claude/settings\.local\.json" "$gitignore" 2>/dev/null; then
    echo ".claude/settings.local.json" >> "$gitignore"
    ok "Added .claude/settings.local.json to .gitignore"
  fi
}

# ── Install for OpenCode ───────────────────────────────

install_opencode() {
  local target="$1" src="$2"

  mkdir -p "$target/.opencode/commands"

  # opencode.json — merge instructions (idempotent)
  local oc_json="$target/opencode.json"
  if command -v jq >/dev/null 2>&1; then
    json_array_add "$oc_json" "instructions" ".cortex/LOOKUP.md"
    json_array_add "$oc_json" "instructions" ".cortex/MAINTAIN.md"
    json_array_add "$oc_json" "instructions" ".cortex/PROJECT.md"
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

  warn_v5_leftovers "$target"

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
echo "    1. Run /cortex-sync to generate the folder map."
echo "    2. Commit .cortex/ and .claude/ (if Claude Code)"
