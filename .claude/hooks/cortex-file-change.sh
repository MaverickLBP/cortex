#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — PostToolUse hook: a mute collector.
#
# Records which paths this turn touched, and nothing else.
# It does NOT read MAP.md, does not resolve folders, does not
# emit reminders and never interrupts the agent. All decisions
# happen in the Stop hook (cortex-stop.sh).
#
# Marks:  T  touched (Write, Edit, mv destination)
#         D  removed from its folder (rm, mv source)
#         M  manifest touched
#
# The record is per-session so concurrent sessions cannot
# interfere. Fires inside subagents too, so their work lands in
# the same record.
#
# A broken hook must never block anything: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail
set -f  # disable globbing: `for arg in $CMD` below must not expand against cwd

# Character classification below decides which names are representable, so it is
# pinned to the C locale: in an 8-bit locale (ISO-8859-*) the bytes 0x80-0x9F
# classify as control characters, and those bytes occur inside perfectly ordinary
# UTF-8 sequences (the 0x82 in '€'). Without this an accented folder name would be
# rejected or dropped depending on the ambient locale of whoever invoked us.
export LC_ALL=C

command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
[ -z "$HOOK_JSON" ] && exit 0

TOOL="$(jq -r '.tool_name  // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
CWD="$(jq -r  '.cwd        // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
SID="$(jq -r  '.session_id // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
[ -z "$TOOL" ] && exit 0
[ -z "$CWD" ] && CWD="$(pwd)"
[ -z "$SID" ] && SID="default"

find_project() {
  local dir="$1" prev=""
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$prev" ]; do
    [ -f "$dir/.cortex/SYSTEM.md" ] && { echo "$dir"; return 0; }
    prev="$dir"; dir="$(dirname "$dir")"
  done
  return 1
}

PROJ="$(find_project "$CWD")" || exit 0
REC="$PROJ/.cortex/.touched-$SID"

is_excluded() {
  case "/$1/" in
    */.git/*|*/.cortex/*|*/.claude/*|*/.opencode/*|*/.superpowers/*|\
    */node_modules/*|*/dist/*|*/build/*|*/target/*) return 0 ;;
    *) return 1 ;;
  esac
}

is_manifest() {
  case "$(basename "$1")" in
    package.json|go.mod|Cargo.toml|pyproject.toml|pom.xml|Gemfile|\
    composer.json|pubspec.yaml|requirements.txt|build.gradle|mix.exs) return 0 ;;
    *) return 1 ;;
  esac
}

# Lexically normalize an absolute-ish path: drop '.' segments, resolve '..'
# by popping the previous kept segment (or dropping it if there is nothing
# to pop, which only happens when the path tries to escape above /).
# Pure string manipulation — no filesystem access, no realpath/readlink
# dependency, so behavior is identical on every platform.
normalize_abs() { # $1 = an absolute-ish path, possibly containing . and ..
  printf '%s' "$1" | awk '
    {
      n = split($0, parts, "/")
      depth = 0
      for (i = 1; i <= n; i++) {
        seg = parts[i]
        if (seg == "" || seg == ".") continue
        if (seg == "..") {
          if (depth > 0) depth--
          continue
        }
        stack[++depth] = seg
      }
      out = ""
      for (i = 1; i <= depth; i++) out = out "/" stack[i]
      if (out == "") out = "/"
      print out
    }'
}

record() { # $1 = mark, $2 = absolute or relative path
  local abs="$2" rel
  case "$abs" in /*) : ;; *) abs="$CWD/$abs" ;; esac
  abs="$(normalize_abs "$abs")"
  rel="${abs#"$PROJ"/}"
  # After normalization, a path outside $PROJ always still starts with '/'
  # (either it never matched the $PROJ/ prefix, or normalization resolved
  # it to somewhere outside $PROJ). A path with no leftover '.'/'..'
  # segments and no leading '/' is provably inside the project — record it.
  case "$rel" in /*) return 0 ;; esac
  # A space is fine: MAP.md ends a folder name at its slash, so a space-named
  # folder round-trips and must reach the Stop hook. A control character does
  # not: a literal tab would be mistaken for this record's own mark/path
  # delimiter, and validate_target() in cortex-map.sh refuses it anyway — drop
  # it here rather than write a record no later stage can safely consume.
  case "$rel" in *[[:cntrl:]]*) return 0 ;; esac
  is_excluded "$rel" && return 0
  printf '%s\t%s\n' "$1" "$rel" >> "$REC" 2>/dev/null || true
}

case "$TOOL" in
  Write|Edit)
    FILE="$(jq -r '.tool_input.file_path // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
    [ -z "$FILE" ] && exit 0
    if is_manifest "$FILE"; then record "M" "$FILE"; else record "T" "$FILE"; fi
    ;;
  Bash)
    CMD="$(jq -r '.tool_input.command // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
    case "$CMD" in
      "rm "*)
        for arg in $CMD; do
          case "$arg" in rm|-*) continue ;; esac
          record "D" "$arg"
        done
        ;;
      "mv "*)
        DEST=""; SRCS=""
        for arg in $CMD; do
          case "$arg" in mv|-*) continue ;; esac
          [ -n "$DEST" ] && SRCS="$SRCS $DEST"
          DEST="$arg"
        done
        [ -z "$DEST" ] && exit 0
        [ -z "$SRCS" ] && exit 0
        for s in $SRCS; do record "D" "$s"; done
        record "T" "$DEST"
        ;;
    esac
    ;;
esac
exit 0
