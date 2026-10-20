#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — SubagentStart hook
#
# Subagents never receive the project rules, so without this they are
# blind to CORTEX. They get LOOKUP.md only (how to search with the
# map): small enough to inject into every subagent.
#
# A broken hook must never block anything: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail
export LC_ALL=C

command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
CWD="$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$(pwd)"

# The `prev` sentinel guards against a non-advancing `dirname`.
PROJ=""
dir="$CWD"
prev=""
while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$prev" ]; do
  if [ -f "$dir/.cortex/LOOKUP.md" ]; then
    PROJ="$dir"
    break
  fi
  prev="$dir"
  dir="$(dirname "$dir")"
done
[ -z "$PROJ" ] && exit 0

LOOKUP="$(cat "$PROJ/.cortex/LOOKUP.md" 2>/dev/null || true)"
[ -z "$LOOKUP" ] && exit 0

jq -n --arg ctx "$LOOKUP" \
  '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$ctx}}' \
  2>/dev/null || true
exit 0
