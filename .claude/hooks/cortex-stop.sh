#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — Stop hook: keeps the map current at the end of every turn.
#
# STATELESS: it records nothing during the session. It compares the real
# tree with the map (`cortex-map.sh --reconcile`), which moves renamed and
# drops removed descriptions on its own and prints the new folders still
# waiting for one. Those block the turn once, each with a ready --set
# command; mechanical changes alone are only reported.
#
# A broken hook must never block anything: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail
export LC_ALL=C

[ "${CORTEX_STOP_HOOK:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
ACTIVE="$(printf '%s' "$HOOK_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || true)"
[ "$ACTIVE" = "true" ] && exit 0
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

MAPSH="$PROJ/.cortex/scripts/cortex-map.sh"
[ -f "$MAPSH" ] || exit 0

# While a /cortex-sync queue is running (marker touched within the last 12 h) the
# queue drives the work: suggesting --set commands here would invite the shortcut
# the queue exists to prevent. A marker left by an abandoned sync expires.
MARKER="$PROJ/.cortex/.state/describe/active"
[ -n "$(find "$MARKER" -mmin -720 -print -quit 2>/dev/null || true)" ] && exit 0

# A fresh install has no descriptions yet: /cortex-sync builds the map, not
# this hook. Checked without a pipe (CTR-12620).
ANY="$(find "$PROJ/.cortex/map" -name '*.cortex' -type f -print -quit 2>/dev/null || true)"
[ -z "$ANY" ] && exit 0

# A failed reconcile never blocks. If it failed before touching anything (a
# failed scan) it printed nothing: stay silent. If it failed half-way, it
# printed what it had done and then an `error` line: report both.
OUT="$(CORTEX_ROOT="$PROJ" bash "$MAPSH" --reconcile 2>/dev/null)"
RC=$?

# Render a folder name as a single-quoted shell literal. The suggestions below
# are meant to be run verbatim by an agent, and a folder name is arbitrary
# user data: under double quotes a name like `$(id)` or one holding a backtick
# would be expanded by the shell that runs it, and a name holding a double
# quote would produce shell that simply does not parse. Single quotes suppress
# every expansion; the only byte needing care is the apostrophe itself, closed
# and reopened around an escaped one in the usual '\'' idiom.
shq() { # $1 = raw name → a shell literal safe to paste into a command
  local q="'"
  printf "%s" "'${1//$q/$q\\$q$q}'"
}

MAX=20
DONE=""
LIST=""
NPEND=0
NDONE=0
ERR=""
TAB="$(printf '\t')"
while IFS="$TAB" read -r kind a b; do
  case "$kind" in
    moved)
      NDONE=$((NDONE + 1))
      [ "$NDONE" -le "$MAX" ] && DONE="${DONE:+$DONE; }moved $a → $b"
      ;;
    removed)
      NDONE=$((NDONE + 1))
      [ "$NDONE" -le "$MAX" ] && DONE="${DONE:+$DONE; }removed $a"
      ;;
    error)
      ERR="$a"
      ;;
    pending)
      NPEND=$((NPEND + 1))
      [ "$NPEND" -le "$MAX" ] && LIST="${LIST}• ${a}
    bash .cortex/scripts/cortex-map.sh --set $(shq "$a") '<role of this folder>'
"
      ;;
  esac
done <<< "$OUT"
[ "$NDONE" -gt "$MAX" ] && DONE="${DONE}; …and $((NDONE - MAX)) more"

if [ "$RC" -ne 0 ]; then
  if [ -n "$DONE" ] || [ -n "$ERR" ]; then
    MSG="CORTEX map update incomplete: ${DONE:+$DONE; }error: ${ERR:-unknown}. Run /cortex-sync."
    jq -nc --arg m "$MSG" '{systemMessage:$m}' 2>/dev/null || true
  fi
  exit 0
fi

if [ "$NPEND" -gt 0 ]; then
  REASON="CORTEX — describe the new folders before finishing this turn:

${LIST}"
  [ "$NPEND" -gt "$MAX" ] && REASON="${REASON}…and $((NPEND - MAX)) more — run /cortex-sync
"
  [ -n "$DONE" ] && REASON="${REASON}
Done automatically: ${DONE}
"
  REASON="${REASON}
Describe the folder's role in one line (max 120 chars). Never name files or list contents."
  jq -nc --arg r "$REASON" '{decision:"block", reason:$r}' 2>/dev/null || true
elif [ -n "$DONE" ]; then
  jq -nc --arg m "CORTEX map updated: $DONE" '{systemMessage:$m}' 2>/dev/null || true
fi
exit 0
