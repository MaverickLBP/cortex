#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — SessionStart hook
#
# Reads the cwd from the Claude Code hook JSON payload (stdin),
# then injects CORTEX knowledge as additionalContext so the agent
# loads .cortex/SYSTEM.md + .cortex/MAP.md with full authority
# (no "may or may not be relevant" disclaimer).
#
# Two modes:
#   Workspace  — a .cortex-workspace.json marker exists in an
#                ancestor directory; injects a project list and
#                instructs the agent to load the MAP.md of the
#                project currently being worked on.
#   Single     — .cortex/SYSTEM.md exists in the cwd; injects
#                SYSTEM.md content and orders the agent to load
#                .cortex/MAP.md immediately.
#
# A broken hook must never block the session: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

# ── Read cwd from hook payload ────────────────────────
HOOK_JSON=""
if [ -t 0 ]; then
  CWD="$(pwd)"
else
  HOOK_JSON="$(cat 2>/dev/null || true)"
  CWD="$(echo "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
  [ -z "$CWD" ] && CWD="$(pwd)"
fi

[ -d "$CWD" ] || exit 0

# ── Walk up looking for .cortex-workspace.json ────────
WS_ROOT=""
dir="$CWD"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/.cortex-workspace.json" ]; then
    WS_ROOT="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

# ── Workspace mode ────────────────────────────────────
if [ -n "$WS_ROOT" ]; then
  project_list=""
  while IFS= read -r sys_md; do
    proj_dir="$(dirname "$(dirname "$sys_md")")"
    proj_name="$(basename "$proj_dir")"
    project_list="${project_list}- ${proj_name} (.cortex/ at ${proj_dir}/.cortex/)\n"
  done < <(find "$WS_ROOT" -maxdepth 4 -name "SYSTEM.md" -path "*/.cortex/SYSTEM.md" | sort)

  [ -z "$project_list" ] && exit 0

  SYSTEM_CONTENT=""
  if [ -f "$CWD/.cortex/SYSTEM.md" ]; then
    SYSTEM_CONTENT="$(cat "$CWD/.cortex/SYSTEM.md" 2>/dev/null || true)"
  fi
  PROJECT_CONTENT=""
  if [ -f "$CWD/.cortex/PROJECT.md" ]; then
    PROJECT_CONTENT="$(cat "$CWD/.cortex/PROJECT.md" 2>/dev/null || true)"
  fi
  MAP_CONTENT=""
  if [ -f "$CWD/.cortex/MAP.md" ]; then
    MAP_CONTENT="$(cat "$CWD/.cortex/MAP.md" 2>/dev/null || true)"
  fi

  MSG="CORTEX WORKSPACE — mandatory startup sequence (no exceptions):\n\n"
  MSG="${MSG}This is a multi-project workspace. Projects with CORTEX:\n${project_list}\n"
  MSG="${MSG}REQUIRED ACTIONS:\n"
  MSG="${MSG}1. The current (cwd) project's MAP.md is injected below — keep it authoritative for the whole session.\n"
  MSG="${MSG}2. When the task moves to a DIFFERENT project, read that project's .cortex/MAP.md at that moment and keep it in context.\n"
  MSG="${MSG}3. If a project has .cortex/SYSTEM.md, follow its instructions.\n"
  if [ -n "$SYSTEM_CONTENT" ]; then
    MSG="${MSG}\nCurrent project (${CWD}) SYSTEM.md:\n\n${SYSTEM_CONTENT}"
  fi
  if [ -n "$PROJECT_CONTENT" ]; then
    MSG="${MSG}\n\n--- Current project (${CWD}) PROJECT.md ---\n\n${PROJECT_CONTENT}"
  fi
  if [ -n "$MAP_CONTENT" ]; then
    MSG="${MSG}\n\n--- Current project (${CWD}) MAP.md ---\n\n${MAP_CONTENT}"
  fi

  jq -n --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' \
    || exit 0
  exit 0
fi

# ── Single-project mode ───────────────────────────────
SYSTEM_MD="$CWD/.cortex/SYSTEM.md"
PROJECT_MD="$CWD/.cortex/PROJECT.md"
MAP_MD="$CWD/.cortex/MAP.md"

[ -f "$SYSTEM_MD" ] || exit 0

SYSTEM_CONTENT="$(cat "$SYSTEM_MD" 2>/dev/null || true)"
[ -z "$SYSTEM_CONTENT" ] && exit 0

MSG="CORTEX — mandatory startup context (no exceptions):\n\n"
MSG="${MSG}1. PROJECT.md (stack + conventions) and MAP.md (every folder in the project) are injected below. Keep both authoritative for the whole session.\n"
MSG="${MSG}2. Follow all instructions in SYSTEM.md below.\n"
MSG="${MSG}3. Before searching for or creating any file, consult MAP.md first.\n"
if [ ! -f "$MAP_MD" ]; then
  MSG="${MSG}   MAP.md not yet generated — run /cortex-sync to create it.\n"
fi
MSG="${MSG}\n--- SYSTEM.md ---\n\n${SYSTEM_CONTENT}"
if [ -f "$PROJECT_MD" ]; then
  PROJECT_CONTENT="$(cat "$PROJECT_MD" 2>/dev/null || true)"
  [ -n "$PROJECT_CONTENT" ] && MSG="${MSG}\n\n--- PROJECT.md ---\n\n${PROJECT_CONTENT}"
fi
if [ -f "$MAP_MD" ]; then
  MAP_CONTENT="$(cat "$MAP_MD" 2>/dev/null || true)"
  [ -n "$MAP_CONTENT" ] && MSG="${MSG}\n\n--- MAP.md ---\n\n${MAP_CONTENT}"
fi

jq -n --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' \
  || exit 0
