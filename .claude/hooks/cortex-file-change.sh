#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — PostToolUse hook
#
# Fires after Write (new files) and after a Bash local `rm`/`mv`.
# When a newly created file is not referenced in the governing
# .cortex/MAP.md, injects a reminder to update the map NOW —
# closing the gap where session-start instructions get buried.
# Symmetrically, when a documented file is deleted by a local `rm`,
# or moved/renamed by a local `mv`, reminds to remove/move that entry
# too — MAP.md should always reflect what actually exists.
#
# Detection is LOCAL only: `git rm`/`git mv` are deliberately not
# matched. The map is maintained in reaction to local filesystem
# operations, not git commands.
#
# Silence policy (never noisy):
#   - file already referenced in MAP.md (basename or relative path) —
#     for creation only; for local rm it's the OPPOSITE: only fire
#     when the deleted path IS referenced, so scratch/temp cleanup
#     (never documented) stays silent
#   - tracked, pre-existing file (overwrite, not creation)
#   - excluded path segments (.git, .cortex, .claude, .opencode,
#     .superpowers, node_modules, dist, build, target)
#   - no .cortex/MAP.md ancestor (not a CORTEX project)
#
# A broken hook must never block anything: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
[ -z "$HOOK_JSON" ] && exit 0

TOOL_NAME="$(echo "$HOOK_JSON" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -z "$TOOL_NAME" ] && exit 0

emit() {
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}' \
    2>/dev/null || true
  exit 0
}

# Walk up from $1 looking for a directory containing .cortex/MAP.md
find_project() {
  local dir="$1"
  local prev=""
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$prev" ]; do
    if [ -f "$dir/.cortex/MAP.md" ]; then
      echo "$dir"
      return 0
    fi
    prev="$dir"
    dir="$(dirname "$dir")"
  done
  return 1
}

is_excluded() {
  case "/$1/" in
    */.git/*|*/.cortex/*|*/.claude/*|*/.opencode/*|*/.superpowers/*|\
    */node_modules/*|*/dist/*|*/build/*|*/target/*) return 0 ;;
    *) return 1 ;;
  esac
}

case "$TOOL_NAME" in
  Write)
    FILE="$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
    [ -z "$FILE" ] && exit 0
    is_excluded "$FILE" && exit 0
    PROJ="$(find_project "$(dirname "$FILE")")" || exit 0
    MAP="$PROJ/.cortex/MAP.md"
    REL="${FILE#"$PROJ"/}"
    BASE="$(basename "$FILE")"
    # Already documented (by basename or relative path)? → silent
    if grep -qF "$BASE" "$MAP" 2>/dev/null; then exit 0; fi
    if grep -qF "$REL" "$MAP" 2>/dev/null; then exit 0; fi
    # Only remind for NEW files (untracked/staged-new); overwrites are silent.
    if git -C "$PROJ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      STATUS="$(git -C "$PROJ" status --porcelain -- "$FILE" 2>/dev/null | head -1 || true)"
      case "$STATUS" in
        "??"*|A*) : ;;   # new file — fall through to reminder
        *) exit 0 ;;      # tracked/clean/unknown — silent
      esac
    fi
    emit "CORTEX: '$REL' is a new file not referenced in .cortex/MAP.md. Update the map now — add a one-line entry silently, per SYSTEM.md — or consciously skip only if an existing folder-level entry already covers it."
    ;;
  Bash)
    CMD="$(echo "$HOOK_JSON" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    CWD="$(echo "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)"
    [ -z "$CWD" ] && CWD="$(pwd)"
    case "$CMD" in
      "rm "*)
        # Local deletion only. `git rm`/`git mv` are deliberately NOT
        # matched — MAP.md is kept in sync in reaction to LOCAL file
        # operations, not git commands. Remind only when a DOCUMENTED
        # file was deleted, so scratch/temp cleanup stays silent.
        # Best-effort word-split parsing of the command's arguments
        # (no full shell parsing).
        PROJ="$(find_project "$CWD")" || exit 0
        MAP="$PROJ/.cortex/MAP.md"
        for arg in $CMD; do
          case "$arg" in
            rm|-*) continue ;;
          esac
          case "$arg" in
            /*) ABS="$arg" ;;
            *) ABS="$CWD/$arg" ;;
          esac
          BASE="$(basename "$ABS")"
          REL="${ABS#"$PROJ"/}"
          if grep -qF "$BASE" "$MAP" 2>/dev/null || grep -qF "$REL" "$MAP" 2>/dev/null; then
            emit "CORTEX: '$arg' was deleted via a local rm and appears to be documented in .cortex/MAP.md. Check the map now and remove the corresponding entry if the file no longer exists, per SYSTEM.md."
          fi
        done
        exit 0
        ;;
      "mv "*)
        # Local move/rename only (`git mv` is NOT matched). A local `mv`
        # changes the working tree at both ends, so MAP.md can go stale
        # twice: the SOURCE entry now points at a path that's gone, and
        # the DEST is a new path the map may not list. Best-effort
        # word-split: drop `mv` and flags; the last remaining token is
        # the destination, the rest are sources.
        PROJ="$(find_project "$CWD")" || exit 0
        MAP="$PROJ/.cortex/MAP.md"
        DEST=""
        SRCS=""
        for arg in $CMD; do
          case "$arg" in
            mv|-*) continue ;;
          esac
          [ -n "$DEST" ] && SRCS="$SRCS $DEST"
          DEST="$arg"
        done
        [ -z "$DEST" ] && exit 0
        [ -z "$SRCS" ] && exit 0   # need at least one source + a dest
        MSG=""
        # Sources documented in MAP.md → their entry is now stale.
        for s in $SRCS; do
          case "$s" in
            /*) SABS="$s" ;;
            *) SABS="$CWD/$s" ;;
          esac
          SBASE="$(basename "$SABS")"
          SREL="${SABS#"$PROJ"/}"
          if grep -qF "$SBASE" "$MAP" 2>/dev/null || grep -qF "$SREL" "$MAP" 2>/dev/null; then
            MSG="${MSG}moved-from '$s' (documented in MAP.md) — its entry now points at a path that no longer exists; "
          fi
        done
        # Dest is a new path not yet in MAP.md (unless it's an excluded path).
        if ! is_excluded "$DEST"; then
          case "$DEST" in
            /*) DABS="$DEST" ;;
            *) DABS="$CWD/$DEST" ;;
          esac
          DBASE="$(basename "$DABS")"
          DREL="${DABS#"$PROJ"/}"
          if ! grep -qF "$DBASE" "$MAP" 2>/dev/null && ! grep -qF "$DREL" "$MAP" 2>/dev/null; then
            MSG="${MSG}moved-to '$DEST' — this path is not referenced in MAP.md; "
          fi
        fi
        [ -z "$MSG" ] && exit 0
        emit "CORTEX: a local mv changed the working tree — ${MSG}update .cortex/MAP.md now (move/rename the affected entries so the map matches reality), per SYSTEM.md."
        exit 0
        ;;
      *) exit 0 ;;
    esac
    ;;
esac
exit 0
