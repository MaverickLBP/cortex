#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — Stop hook: the only decision point.
#
# Fires once per turn. Reads the session touch record written
# by cortex-file-change.sh, and if the map needs work, blocks
# once so the agent reconciles it before returning control.
#
# STATELESS BY DESIGN: every turn is evaluated from scratch,
# with no memory of previously-reported folders. A per-session
# memory was designed and rejected — it misses folders whose
# nature changes on a later turn, and fixing that costs two
# state files and a content-hash comparison.
#
# A broken hook must never block anything: all errors exit 0.
# ──────────────────────────────────────────────────────
set -uo pipefail

[ "${CORTEX_STOP_HOOK:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

HOOK_JSON="$(cat 2>/dev/null || true)"
[ -z "$HOOK_JSON" ] && exit 0

ACTIVE="$(jq -r '.stop_hook_active // false' <<<"$HOOK_JSON" 2>/dev/null || echo false)"
[ "$ACTIVE" = "true" ] && exit 0

CWD="$(jq -r '.cwd        // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
SID="$(jq -r '.session_id // empty' <<<"$HOOK_JSON" 2>/dev/null || true)"
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
REC="$PROJ/.cortex/.touched/$SID"
[ -s "$REC" ] || exit 0

MAPSH="$PROJ/.cortex/scripts/cortex-map.sh"
[ -f "$MAPSH" ] || exit 0

emit() {
  jq -nc --arg r "$1" '{decision:"block", reason:$r}' 2>/dev/null || true
  exit 0
}

# A malformed map means every path we reconstruct could be wrong. Report, act on
# nothing — do NOT block: a pre-existing corrupt map would trap every turn.
# Do NOT truncate the record here: nothing was reconciled, so there is nothing
# to protect by clearing it. Leave it intact so the accumulated touches are
# still there to reconcile once the map is fixed and a later turn has activity.
if ! VERR="$(CORTEX_ROOT="$PROJ" bash "$MAPSH" --validate 2>&1)"; then
  echo "CORTEX: .cortex/MAP.md is malformed and was not updated. Run 'cortex-map.sh --validate' and fix the reported line before continuing.
$VERR"
  exit 0
fi

MSG=""

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

# Defense in depth: a record entry should never carry an absolute path, a
# '..' or '.' segment, or a control character — cortex-file-change.sh's
# record() normalizes '.'/'..' segments away and rejects control characters
# and truly outside-project paths before a record is ever written — but if one
# somehow reaches this file anyway (e.g. a record from a pre-fix session), it
# must be dropped rather than surfaced as a "folder". Each shape has its own
# reason: an absolute path (e.g. "/tmp") would render a malformed root node in
# MAP.md; a '..'/'.' segment would do the same or point outside the project;
# and a control character can never be represented in MAP.md at all —
# validate_target() in cortex-map.sh refuses any --set/--remove target
# containing one, so surfacing it here would hand the agent a suggested
# command that is guaranteed to fail. A plain space is NOT filtered: a
# space-named folder round-trips through MAP.md fine, and dropping it would
# leave that folder permanently unmapped with no signal that it was skipped.
# `reject_escaped` filters $2 (tab-separated) out of a T/D record stream.
reject_escaped() { # stdin: "mark\tpath" records → same, minus escaped paths
  awk -F'\t' '$2 !~ /^\// && $2 !~ /(^|\/)\.\.(\/|$)/ && $2 !~ /(^|\/)\.(\/|$)/ && $2 !~ /[\001-\037\177]/'
}

# Ask cortex-map.sh whether a folder can be represented at all, instead of
# re-deriving its rule here. Every suggestion below is a command the agent is
# told to run verbatim, so suggesting one the writer would refuse wastes a turn
# and breaks the invariant the rest of this system is built on. reject_escaped
# above stays as a cheap prefilter over raw records; THIS is the authority.
representable() { CORTEX_ROOT="$PROJ" bash "$MAPSH" --check "$1" >/dev/null 2>&1; }

# Folders of touched files, plus every ancestor, so a new nested tree is reported whole.
# `sed -n '...p'` (not a bare substitution) so root-level files with no '/' in
# their path are dropped instead of passed through unchanged as bogus "folder"
# candidates — the project root is never a node in MAP.md.
TOUCHED_DIRS="$(reject_escaped < "$REC" | awk -F'\t' '$1=="T" { print $2 }' \
  | sed -n 's|/[^/]*$||p' | grep -v '^$' \
  | awk -F/ '{ p=""; for (i=1; i<=NF; i++) { p = (i==1 ? $1 : p "/" $i); print p } }' \
  | LC_ALL=C sort -u)"

while IFS= read -r d; do
  [ -n "$d" ] || continue
  representable "$d" || continue
  DESC="$(CORTEX_ROOT="$PROJ" bash "$MAPSH" --lookup "$d" 2>/dev/null || true)"
  if [ "$DESC" = "MISSING" ]; then
    MSG="${MSG}• ${d} — not in the map. Add it:
    bash .cortex/scripts/cortex-map.sh --set $(shq "$d") '<what this folder contains>'
"
  elif [ "$DESC" = "(undescribed)" ] || [ -z "$DESC" ]; then
    MSG="${MSG}• ${d} — present but undescribed. Describe it:
    bash .cortex/scripts/cortex-map.sh --set $(shq "$d") '<what this folder contains>'
"
  else
    MSG="${MSG}• ${d} — the map says: \"${DESC}\"
    You touched files here. If that no longer covers the folder, update it with --set.
"
  fi
done <<< "$TOUCHED_DIRS"

# Folders emptied by deletions (parent of each deleted file — same rule: only
# lines that actually matched a '/' contribute a candidate).
DELETED_DIRS="$(reject_escaped < "$REC" | awk -F'\t' '$1=="D" { print $2 }' \
  | sed -n 's|/[^/]*$||p' | grep -v '^$' | LC_ALL=C sort -u)"

while IFS= read -r d; do
  [ -n "$d" ] || continue
  representable "$d" || continue
  [ -d "$PROJ/$d" ] && [ -n "$(ls -A "$PROJ/$d" 2>/dev/null)" ] && continue
  DESC="$(CORTEX_ROOT="$PROJ" bash "$MAPSH" --lookup "$d" 2>/dev/null || true)"
  [ "$DESC" = "MISSING" ] && continue
  MSG="${MSG}• ${d} — no longer holds files. Remove it:
    bash .cortex/scripts/cortex-map.sh --remove $(shq "$d")
"
done <<< "$DELETED_DIRS"

# Deleted paths that were themselves mapped folders (e.g. `rm -rf lib/vendor/acme`
# records D lib/vendor/acme — the parent lib/vendor may still hold other files,
# so the check above alone would miss the removed directory itself).
DELETED_PATHS="$(reject_escaped < "$REC" | awk -F'\t' '$1=="D" { print $2 }' | LC_ALL=C sort -u)"

while IFS= read -r d; do
  [ -n "$d" ] || continue
  representable "$d" || continue
  [ -e "$PROJ/$d" ] && continue
  DESC="$(CORTEX_ROOT="$PROJ" bash "$MAPSH" --lookup "$d" 2>/dev/null || true)"
  [ "$DESC" = "MISSING" ] && continue
  MSG="${MSG}• ${d} — no longer holds files. Remove it:
    bash .cortex/scripts/cortex-map.sh --remove $(shq "$d")
"
done <<< "$DELETED_PATHS"

# Manifests → PROJECT.md.
if awk -F'\t' '$1=="M"' "$REC" | grep -q .; then
  MANS="$(awk -F'\t' '$1=="M" { print $2 }' "$REC" | LC_ALL=C sort -u | tr '\n' ' ')"
  MSG="${MSG}• Manifest touched (${MANS%% }) — review the Tech Stack table in .cortex/PROJECT.md.
"
fi

rm -f "$REC"

[ -z "$MSG" ] && exit 0

emit "CORTEX — reconcile the knowledge map before finishing this turn:

${MSG}
Descriptions say what a folder contains — never name files (see SYSTEM.md §2.2).
Do not edit MAP.md by hand; always go through cortex-map.sh."
