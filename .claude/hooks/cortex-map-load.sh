#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — PreToolUse safety net (Claude Code only).
# Two nets, both non-blocking reminders:
#   Grep/Glob → if the search path resolves to an area whose
#     sub-map exists, remind the agent to read that sub-map
#     instead of searching blind (discovery net).
#   Write (new file) → if the target path resolves to an area,
#     point the agent at that area's sub-map/conventions before
#     the file lands (placement net).
# Silent when: flat repo, no manifest, unresolved path.
# A broken hook must never block: all error paths exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
[ -z "$HOOK_JSON" ] && exit 0
TOOL="$(jq -r '.tool_name // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
CWD="$(jq -r '.cwd // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$(pwd)"

# Walk up to the project containing .cortex/maps/index.json
find_proj() {
  local d="$1" prev=""
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "$prev" ]; do
    [ -f "$d/.cortex/maps/index.json" ] && { echo "$d"; return 0; }
    prev="$d"; d="$(dirname "$d")"
  done
  return 1
}
PROJ="$(find_proj "$CWD")" || exit 0
MANIFEST="$PROJ/.cortex/maps/index.json"
[ "$(jq -r '.flat' "$MANIFEST" 2>/dev/null)" = "true" ] && exit 0

emit(){ jq -n --arg c "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null || true; exit 0; }

# Resolve a repo-relative path to the longest-prefix area (map file).
resolve_map() { # $1 = repo-relative path
  local rel="$1"
  jq -r --arg p "$rel" '
    .areas
    | map(select(.root=="." or $p==.root or (.root as $r | $p | startswith($r+"/"))))
    | sort_by(.root|length) | last | .map // empty' "$MANIFEST" 2>/dev/null
}

# Make a path repo-relative to PROJ.
relify() { # $1 = path (abs or rel to CWD)
  local p="$1"
  case "$p" in /*) : ;; *) p="$CWD/$p" ;; esac
  printf '%s' "${p#"$PROJ"/}"
}

case "$TOOL" in
  Grep|Glob)
    RAW="$(jq -r '.tool_input.path // .tool_input.glob // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
    [ -z "$RAW" ] && exit 0
    REL="$(relify "$RAW")"
    MAP="$(resolve_map "$REL")"
    [ -z "$MAP" ] && exit 0
    [ -f "$PROJ/.cortex/$MAP" ] || exit 0
    emit "CORTEX: '$REL' is in a mapped area. Before searching, read its sub-map .cortex/$MAP — it lists the area's files and key functions, so you can go straight to the target instead of grepping blind."
    ;;
  Write)
    FILE="$(jq -r '.tool_input.file_path // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
    [ -z "$FILE" ] && exit 0
    # Only fire for genuinely new files, not overwrites of existing ones.
    case "$FILE" in /*) ABS_FILE="$FILE" ;; *) ABS_FILE="$CWD/$FILE" ;; esac
    [ -e "$ABS_FILE" ] && exit 0
    REL="$(relify "$FILE")"
    MAP="$(resolve_map "$REL")"
    [ -z "$MAP" ] && exit 0
    emit "CORTEX: new file '$REL' falls in a mapped area. Check .cortex/$MAP and the root MAP.md conventions to confirm this is the right location, then add the file's one-line entry to .cortex/$MAP."
    ;;
esac
exit 0
