#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — SubagentStart hook
#
# Subagents never receive SessionStart context, so without this
# they are blind to CORTEX. Injects a SHORT note (not the full
# MAP — subagents are task-scoped): where the map lives, that it
# must be consulted for file placement, and that it must be
# updated on file creation/deletion. The PostToolUse hook
# (cortex-file-change.sh) also fires for subagent tool calls,
# closing the loop at the moment of a Write.
#
# A broken hook must never block anything: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
CWD="$(echo "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$(pwd)"

# The `prev` sentinel guards against a non-advancing `dirname` (e.g. a
# relative path with no ancestor) so this loop always terminates.
PROJ=""
dir="$CWD"
prev=""
while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$prev" ]; do
  if [ -f "$dir/.cortex/MAP.md" ]; then
    PROJ="$dir"
    break
  fi
  prev="$dir"
  dir="$(dirname "$dir")"
done
[ -z "$PROJ" ] && exit 0

MSG="CORTEX: this project maintains a knowledge map at ${PROJ}/.cortex/MAP.md.\n"
MSG="${MSG}- Consult it to locate existing code and to decide where new files belong.\n"
MSG="${MSG}- If you create, delete, or rename project files, update MAP.md accordingly (one-line entry, silently).\n"
MSG="${MSG}- Never modify ${PROJ}/.cortex/SYSTEM.md."

jq -n --arg ctx "$MSG" \
  '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$ctx}}' \
  2>/dev/null || true
exit 0
