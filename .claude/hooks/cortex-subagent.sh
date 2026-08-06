#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — SubagentStart hook
#
# Subagents never receive SessionStart context, so without this
# they are blind to CORTEX. They get the SAME three files as the
# main agent — not a summary: a subagent needs MAP.md to navigate
# the project, and PostToolUse fires inside subagents too, so its
# work lands in the same session record.
#
# A broken hook must never block anything: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
CWD="$(echo "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$(pwd)"

# The `prev` sentinel guards against a non-advancing `dirname`.
PROJ=""
dir="$CWD"
prev=""
while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$prev" ]; do
  if [ -f "$dir/.cortex/SYSTEM.md" ]; then
    PROJ="$dir"
    break
  fi
  prev="$dir"
  dir="$(dirname "$dir")"
done
[ -z "$PROJ" ] && exit 0

SYSTEM_CONTENT="$(cat "$PROJ/.cortex/SYSTEM.md" 2>/dev/null || true)"
[ -z "$SYSTEM_CONTENT" ] && exit 0

MSG="CORTEX — this project maintains a knowledge layer. Same rules as the main agent:\n\n"
MSG="${MSG}--- SYSTEM.md ---\n\n${SYSTEM_CONTENT}"
if [ -f "$PROJ/.cortex/PROJECT.md" ]; then
  PROJECT_CONTENT="$(cat "$PROJ/.cortex/PROJECT.md" 2>/dev/null || true)"
  [ -n "$PROJECT_CONTENT" ] && MSG="${MSG}\n\n--- PROJECT.md ---\n\n${PROJECT_CONTENT}"
fi
if [ -f "$PROJ/.cortex/MAP.md" ]; then
  MAP_CONTENT="$(cat "$PROJ/.cortex/MAP.md" 2>/dev/null || true)"
  [ -n "$MAP_CONTENT" ] && MSG="${MSG}\n\n--- MAP.md ---\n\n${MAP_CONTENT}"
fi

jq -n --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$ctx}}' \
  2>/dev/null || true
exit 0
