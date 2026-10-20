#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — cortex-describe: the work queue behind /cortex-sync.
# Hands folders to agents one at a time together with their real contents,
# records who described and who verified each one, and only reports the
# sync as complete when every folder is verified and still matches the map.
# Queue state lives in .cortex/.state/describe/ (gitignored). The map itself
# is only ever written through cortex-map.sh --set.
# Usage: cortex-describe.sh --init [--all] [--restart]
#        | --next --role write|verify --worker <id>
#        | --submit <dir> <desc> --worker <id>
#        | --verdict <dir> ok|reject <text> --worker <id>
#        | --status | --report | --reset <dir> | --requeue-claimed | --show <dir>
# ──────────────────────────────────────────────────────
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -z "${CORTEX_ROOT:-}" ] && [ -z "$SCRIPT_DIR" ]; then
  echo "cortex-describe: cannot resolve the script directory and CORTEX_ROOT is not set" >&2
  exit 2
fi
ROOT="${CORTEX_ROOT:-$SCRIPT_DIR/../..}"
MAPSH="$SCRIPT_DIR/cortex-map.sh"
SCAN="$SCRIPT_DIR/cortex-scan.sh"
S="$ROOT/.cortex/.state/describe"
export CORTEX_ROOT="$ROOT"

TAB="$(printf '\t')"

usage() {
  cat >&2 <<'EOF'
usage: cortex-describe.sh --init [--all] [--restart]
       cortex-describe.sh --next --role write|verify --worker <id>
       cortex-describe.sh --submit <dir> <desc> --worker <id>
       cortex-describe.sh --verdict <dir> ok|reject <text> --worker <id>
       cortex-describe.sh --status | --report | --reset <dir> | --requeue-claimed | --show <dir>
EOF
  exit 2
}

# enc <dir>: state-directory name for a folder ('%' -> '%25', then '/' -> '%2F').
enc() { local s="${1//%/%25}"; printf '%s' "${s//\//%2F}"; }
# dec <name>: inverse of enc.
dec() { local s="${1//%2F//}"; printf '%s' "${s//%25/%}"; }
# fdir <dir>: per-folder state directory. A path whose encoding would not fit in a
# file name (over 200 bytes) gets "%00<cksum>-<n>" instead; "%00" cannot start an
# encoded name, and the directory's "path" file says which folder it belongs to.
fdir() {
  local e c base n=0; e="$(enc "$1")"
  if [ "${#e}" -le 200 ]; then printf '%s\n' "$S/f/$e"; return; fi
  base="$S/f/%00$(printf '%s' "$1" | cksum | tr ' ' '-')"
  while :; do
    c="$base-$n"
    if [ ! -e "$c/path" ] || [ "$(cat "$c/path")" = "$1" ]; then printf '%s\n' "$c"; return; fi
    n=$((n + 1))
  done
}
# get_state <dir>: current state, empty when the folder is not in the queue.
get_state() { cat "$(fdir "$1")/state" 2>/dev/null; }

# refresh_cache: snapshot the scan so every later command is cheap and consistent.
refresh_cache() {
  local files dirs
  files="$(bash "$SCAN" --files "$ROOT")" || return 1
  dirs="$(bash "$SCAN" --dirs "$ROOT")" || return 1
  mkdir -p "$S" || return 1
  printf '%s\n' "$files" > "$S/files" && printf '%s\n' "$dirs" > "$S/dirs"
}

# cached_list files|dirs: the cached scan if there is one, a live scan otherwise.
cached_list() {
  if [ -f "$S/$1" ]; then cat "$S/$1"; else bash "$SCAN" "--$1" "$ROOT"; fi
}

# direct_children <list> <dir>: names directly under <dir> in a path list (stdin).
direct_children() {
  CD_DIR="$1" awk '
    BEGIN { p = ENVIRON["CD_DIR"] "/"; n = length(p) }
    index($0, p) == 1 { r = substr($0, n + 1); if (r != "" && index(r, "/") == 0) print r }' | LC_ALL=C sort
}

# digest <dir>: the content summary an agent works from (shape fixed by the plan).
digest() {
  local d="$1" files dirs name size sub st desc ext n total=0 budget=6000 count=0 chunk shown=0 exts
  files="$(cached_list files | direct_children "$d")"
  dirs="$(cached_list dirs | direct_children "$d")"
  printf '== CONTENTS of %s ==\n' "$d"
  if [ -z "$files" ]; then
    echo "NOFILES"
  else
    n="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
    while IFS= read -r name; do
      count=$((count + 1))
      [ "$count" -gt 60 ] && break
      size="$(wc -c < "$ROOT/$d/$name" 2>/dev/null | tr -d ' ')"
      printf 'FILE %s %s\n' "$name" "${size:-0}"
    done <<< "$files"
    [ "$n" -gt 60 ] && printf '… %s more\n' "$((n - 60))"
  fi
  if [ -n "$dirs" ]; then
    while IFS= read -r sub; do
      st="$(get_state "$d/$sub")"
      desc="(not yet described)"
      case "$st" in
        written|claimed-verify|verified)
          desc="$(head -n 1 "$ROOT/.cortex/map/$d/$sub.cortex" 2>/dev/null)"
          [ -n "$desc" ] || desc="(not yet described)" ;;
      esac
      printf 'DIR %s: %s\n' "$sub" "$desc"
    done <<< "$dirs"
  fi
  if [ -n "$files" ]; then
    exts="$(printf '%s\n' "$files" | awk '{ n = $0; i = 0
        for (k = length(n); k > 1; k--) if (substr(n, k, 1) == ".") { i = k; break }
        e = (i > 1) ? substr(n, i + 1) : "(none)"; c[e]++ }
      END { for (e in c) print c[e] "\t" e }' | sort -t "$TAB" -k1,1nr -k2,2)"
    while IFS="$TAB" read -r n ext; do printf 'EXT %s %s\n' "$ext" "$n"; done <<< "$exts"
    while IFS= read -r name; do
      [ "$shown" -ge 5 ] && break
      [ "$budget" -gt 0 ] || break
      [ -s "$ROOT/$d/$name" ] && grep -Iq . "$ROOT/$d/$name" 2>/dev/null || continue
      chunk="$(head -n 30 "$ROOT/$d/$name" | cut -c1-200)"
      chunk="$(printf '%s' "$chunk" | head -c "$budget")"
      budget=$((budget - ${#chunk}))
      shown=$((shown + 1))
      printf '== EXCERPT %s ==\n%s\n' "$name" "$chunk"
    done <<< "$files"
  fi
  echo "== END =="
}

# set_state <dir> <state>: replace the state file atomically.
set_state() {
  local f; f="$(fdir "$1")"
  mkdir -p "$f" && { [ -e "$f/path" ] || printf '%s\n' "$1" > "$f/path"; } &&
    printf '%s\n' "$2" > "$f/state.tmp" && mv "$f/state.tmp" "$f/state"
}

# touch_active: keep the "a queue is running" marker fresh (the Stop hook reads it).
# A finished queue (S/done) never revives it: a lagging worker must not silence the hook.
touch_active() { [ -e "$S/done" ] && return 0; mkdir -p "$S" && touch "$S/active"; }

# touch_active_if_queue: refresh the marker only when a queue exists.
touch_active_if_queue() { [ -f "$S/scope" ] && touch_active; return 0; }

# scope_list: folders in the queue, one per line.
scope_list() { cat "$S/scope" 2>/dev/null; }

# carry_moves <tmp>: reconcile moves descriptions with renamed folders; the queue state
# (including "written" but not yet verified) must move with them, or unverified text
# would escape the queue. Uses the "moved<TAB>from<TAB>to" lines in <tmp>/rec.
carry_moves() {
  local w="$1" old new n=0 pre="$S/f/.mv"
  [ -f "$S/scope" ] || return 0
  sed -n "s/^moved${TAB}//p" "$w/rec" > "$w/moves"
  [ -s "$w/moves" ] || return 0
  scope_list | awk -F'\t' '
    FILENAME == ARGV[1] { mv[++m] = $1; to[m] = $2; next }
    { best = 0
      for (i = 1; i <= m; i++) { f = mv[i]; if ($0 == f || index($0, f "/") == 1) if (best == 0 || length(f) > length(mv[best])) best = i }
      print $0 "\t" (best ? to[best] substr($0, length(mv[best]) + 1) : $0) }' "$w/moves" - > "$w/pairs"
  rm -rf "$S/f/.mv"; mkdir -p "$S/f/.mv"
  while IFS="$TAB" read -r old new; do
    [ "$old" = "$new" ] && continue
    n=$((n + 1)); [ -d "$(fdir "$old")" ] && mv "$(fdir "$old")" "$S/f/.mv/$n" && printf '%s\t%s\n' "$n" "$new" >> "$w/placed"
  done < "$w/pairs"
  [ -f "$w/placed" ] && while IFS="$TAB" read -r n new; do
    mkdir -p "$(dirname "$(fdir "$new")")"; rm -rf "$(fdir "$new")"
    mv "$S/f/.mv/$n" "$(fdir "$new")" && printf '%s\n' "$new" > "$(fdir "$new")/path"
  done < "$w/placed"
  rm -rf "$S/f/.mv"
  cut -f2 "$w/pairs" | LC_ALL=C sort > "$S/scope"
}

# init_queue [--all] [--restart]: build or resume the queue.
init_queue() {
  local all=0 restart=0 mode old cur add d keep n_new=0 w
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      --restart) restart=1 ;;
      *) usage ;;
    esac
    shift
  done
  [ -e "$S/done" ] && rm -rf "$S"   # a finished queue is history: start a new one
  if [ -f "$S/scope" ] && [ "$restart" -eq 0 ] && [ "$all" -eq 1 ]; then
    echo "cortex-describe: a queue already exists; use --init --restart --all to rebuild it from scratch" >&2
    return 2
  fi
  [ "$restart" -eq 1 ] && rm -rf "$S"
  w="$(mktemp -d)" || return 1
  bash "$MAPSH" --reconcile > "$w/rec" || { rm -rf "$w"; echo "cortex-describe: reconcile failed" >&2; return 1; }
  refresh_cache || { rm -rf "$w"; echo "cortex-describe: scan failed" >&2; return 1; }
  carry_moves "$w"
  if [ -f "$S/scope" ]; then mode="$(cat "$S/mode" 2>/dev/null)"; else mode="pending"; [ "$all" -eq 1 ] && mode="all"; fi
  bash "$MAPSH" --dirs | LC_ALL=C sort > "$w/cur" || { rm -rf "$w"; return 1; }
  if [ "$mode" = all ]; then
    cp "$w/cur" "$w/add"
  else
    bash "$MAPSH" --drift | sed -n 's/^+ //p' | LC_ALL=C sort > "$w/add"
  fi
  scope_list | LC_ALL=C sort > "$w/old"
  comm -12 "$w/old" "$w/cur" > "$w/keep"
  comm -23 "$w/old" "$w/cur" > "$w/gone"
  { cat "$w/keep"; comm -23 "$w/add" "$w/old"; } | LC_ALL=C sort -u > "$w/new"
  while IFS= read -r d; do [ -n "$d" ] && rm -rf "$(fdir "$d")"; done < "$w/gone"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$(get_state "$d")" in
      "") set_state "$d" todo; n_new=$((n_new + 1)) ;;
      claimed-write) set_state "$d" todo ;;
      claimed-verify) set_state "$d" written ;;
    esac
    rmdir "$(fdir "$d")/.lock" 2>/dev/null
  done < "$w/new"
  cp "$w/new" "$S/scope" && printf '%s\n' "$mode" > "$S/mode" || { rm -rf "$w"; return 1; }
  rm -rf "$w"
  touch_active
  printf 'queued %s folders (%s new)\n' "$(wc -l < "$S/scope" | tr -d ' ')" "$n_new"
}

# valid_worker <id>: ids are plain words so they can live in state files.
valid_worker() { case "$1" in ""|*[!A-Za-z0-9._-]*) return 1 ;; esac; return 0; }

# lock_acquire <state dir>: take the folder's mutex (mkdir). A lock older than two
# minutes belongs to a worker that died mid-transition (they last milliseconds): break it.
lock_acquire() {
  local l="$1/.lock" tries=0
  while ! mkdir "$l" 2>/dev/null; do
    [ -d "$1" ] || return 1
    tries=$((tries + 1)); [ "$tries" -le 3 ] || return 1
    [ -n "$(find "$l" -maxdepth 0 -mmin +2 2>/dev/null)" ] || return 1
    rmdir "$l" 2>/dev/null
  done
  return 0
}

# claim <dir> <from> <to> <worker>: atomically move a folder <from> -> <to>.
# mkdir is the mutex; exit 1 when the folder is not in <from> or is locked.
claim() {
  local f; f="$(fdir "$1")"
  lock_acquire "$f" || return 1
  if [ "$(get_state "$1")" = "$2" ]; then
    set_state "$1" "$3"; printf '%s\n' "$4" > "$f/worker"
    rmdir "$f/.lock"; return 0
  fi
  rmdir "$f/.lock"; return 1
}

# snapshot: "<dir><TAB><state>" for every queued folder, in a single process.
snapshot() {
  [ -d "$S/f" ] || return 0
  grep -rH '' --include=state "$S/f" 2>/dev/null | awk -v pre="$S/f/" '
    { r = substr($0, length(pre) + 1); i = index(r, "/state:"); if (i == 0) next
      e = substr(r, 1, i - 1); st = substr(r, i + 7)
      if (substr(e, 1, 3) == "%00") { p = ""; if ((getline p < (pre e "/path")) <= 0) next; close(pre e "/path"); e = p }
      else { gsub(/%2F/, "/", e); gsub(/%25/, "%", e) }
      print e "\t" st }'
}

# candidates <role>: "C<TAB>depth<TAB>dir" for what <role> may claim now, plus
# "P<TAB>n" = how much work can still reach this role (so it should wait, not quit):
#   write  -> folders still todo (unless a needs-human descendant makes them dead)
#   verify -> written folders, plus what writers may still produce (claimed-write, todo)
# A folder is writable only when every queued descendant is verified.
candidates() {
  snapshot | awk -F'\t' -v role="$1" '
    { n++; order[n] = $1; st[$1] = $2 }
    END {
      for (i = 1; i <= n; i++) { d = order[i]
        if (st[d] != "verified") { a = d; while ((j = match(a, /\/[^\/]*$/)) > 0) { a = substr(a, 1, j - 1); blocked[a] = 1 } }
        if (st[d] == "needs-human") { a = d; while ((j = match(a, /\/[^\/]*$/)) > 0) { a = substr(a, 1, j - 1); dead[a] = 1 } } }
      for (i = 1; i <= n; i++) { d = order[i]; s = st[d]; ok = (s == "todo" && !(d in blocked))
        if (s == "todo" && !(d in dead)) todo++
        if (s == "written") written++
        if (s == "claimed-write") cw++
        if ((role == "write" && ok) || (role == "verify" && s == "written")) { c = d; print "C\t" gsub(/\//, "/", c) "\t" d } }
      print "P\t" (role == "write" ? todo : written + cw + todo) + 0 }'
}

# expire_claims: a claim nobody finished within the lease (default 20 min) belongs to a
# worker that died or gave up: put the folder back so another worker takes it.
expire_claims() {
  local lease="${CORTEX_DESCRIBE_LEASE_MIN:-20}" w f d st
  [ -d "$S/f" ] || return 0
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    f="$(dirname "$w")"; d="$(cat "$f/path" 2>/dev/null)"; [ -n "$d" ] || continue
    lock_acquire "$f" || continue
    if [ -n "$(find "$w" -maxdepth 0 -mmin +"$lease" 2>/dev/null)" ]; then
      st="$(get_state "$d")"
      case "$st" in
        claimed-write) set_state "$d" todo; rm -f "$w" ;;
        claimed-verify) set_state "$d" written; rm -f "$w" ;;
      esac
    fi
    rmdir "$f/.lock" 2>/dev/null
  done < <(find "$S/f" -maxdepth 2 -name worker -mmin +"$lease" 2>/dev/null)
}

# log_event <event> <dir> <worker>: append-only record used by --report.
log_event() { printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$1" "$2" "$3" >> "$S/log" 2>/dev/null; return 0; }

# report_cmd: who did what, so a reader can see whether verification really judged anything.
report_cmd() {
  [ -f "$S/scope" ] || { echo "cortex-describe: no queue; run --init" >&2; return 1; }
  [ -f "$S/log" ] || : > "$S/log"
  awk -F'\t' '
    $2 == "submit" { sub_n++; wr[$4]++ }
    $2 == "ok" { ok_n++; vo[$4]++; vs[$4] = 1 }
    $2 == "reject" { rj_n++; vj[$4]++; vs[$4] = 1 }
    END {
      printf "A\tsubmissions=%d approved=%d rejected=%d\n", sub_n, ok_n, rj_n
      for (w in wr) printf "B\tWRITER %s: %d\n", w, wr[w]
      for (v in vs) printf "C\tVERIFIER %s: ok=%d rejected=%d\n", v, vo[v] + 0, vj[v] + 0
      if (ok_n + rj_n >= 10 && rj_n == 0) printf "Z\tWARNING: no folder was rejected out of %d verdicts — check that the verifiers really reviewed the contents\n", ok_n
      for (v in vs) if (v in wr) printf "Z\tWARNING: worker %s acted as both writer and verifier\n", v
    }' "$S/log" | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2 | cut -f2-
}

# next_cmd <role> <worker>: serve the next folder with its digest.
next_cmd() {
  local role="" worker="" out cands prog dir f
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --role) role="${2:-}"; shift 2 || usage ;;
      --worker) worker="${2:-}"; shift 2 || usage ;;
      *) usage ;;
    esac
  done
  case "$role" in write|verify) ;; *) usage ;; esac
  valid_worker "$worker" || { echo "cortex-describe: --worker must be a plain id (letters, digits, . _ -)" >&2; return 2; }
  [ -f "$S/scope" ] || { echo "cortex-describe: no queue; run --init" >&2; return 1; }
  [ -e "$S/done" ] && return 4
  touch_active
  expire_claims
  out="$(candidates "$role")"
  prog="$(printf '%s\n' "$out" | sed -n "s/^P${TAB}//p")"
  cands="$(printf '%s\n' "$out" | sed -n "s/^C${TAB}//p" | sort -t "$TAB" -k1,1nr -k2,2 | cut -f2-)"
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    f="$(fdir "$dir")"
    if [ "$role" = write ]; then
      claim "$dir" todo claimed-write "$worker" || continue
      printf 'TASK write %s\n' "$dir"
      if [ "$(cat "$f/rejects" 2>/dev/null || echo 0)" -gt 0 ] && [ -s "$f/reason" ]; then
        printf 'REJECTED: %s\n' "$(head -n 1 "$f/reason")"
      fi
      echo "GUIDE: Say what this folder is FOR, in at most 120 characters and in English, from the contents below. Do not repeat the folder name or path, do not name files, and do not only describe its structure (\"holds X\", \"contains Y\")."
    else
      [ "$(cat "$f/writer" 2>/dev/null)" = "$worker" ] && continue
      claim "$dir" written claimed-verify "$worker" || continue
      printf 'TASK verify %s\n' "$dir"
      printf 'DESCRIPTION: %s\n' "$(head -n 1 "$ROOT/.cortex/map/$dir.cortex" 2>/dev/null)"
      echo "GUIDE: Approve only if the description is true for the contents below AND tells someone searching by function why to open this folder. Reject it if it only restates the folder name, its location or its structure."
    fi
    digest "$dir"
    return 0
  done <<< "$cands"
  [ "${prog:-0}" -gt 0 ] && return 3
  return 4
}

# submit_cmd <dir> <desc> --worker <id>: apply a description through cortex-map --set.
submit_cmd() {
  [ "$#" -eq 4 ] && [ "$3" = --worker ] || usage
  local dir="${1%/}" desc="$2" worker="$4" f
  valid_worker "$worker" || { echo "cortex-describe: --worker must be a plain id" >&2; return 2; }
  f="$(fdir "$dir")"
  lock_acquire "$f" || { echo "cortex-describe: $dir is not in the queue or is busy" >&2; return 1; }
  if [ "$(get_state "$dir")" != claimed-write ] || [ "$(cat "$f/worker" 2>/dev/null)" != "$worker" ]; then
    rmdir "$f/.lock"; echo "cortex-describe: $dir is not claimed for writing by $worker" >&2; return 1
  fi
  if ! bash "$MAPSH" --set "$dir" "$desc"; then rmdir "$f/.lock"; return 1; fi
  cksum < "$ROOT/.cortex/map/$dir.cortex" > "$f/hash"
  printf '%s\n' "$worker" > "$f/writer"
  : > "$f/reason"; rm -f "$f/worker"
  set_state "$dir" written
  log_event submit "$dir" "$worker"
  rmdir "$f/.lock"
  touch_active
}

# verdict_cmd <dir> ok|reject <text> --worker <id>: the verifier's decision.
verdict_cmd() {
  [ "$#" -eq 5 ] && [ "$4" = --worker ] || usage
  local dir="${1%/}" kind="$2" text="$3" worker="$5" f name names ok=0 n=0 rejects
  case "$kind" in ok|reject) ;; *) usage ;; esac
  valid_worker "$worker" || { echo "cortex-describe: --worker must be a plain id" >&2; return 2; }
  case "$text" in *[![:space:]]*) ;; *) echo "cortex-describe: a verdict needs text (evidence for ok, the reason for reject)" >&2; return 2 ;; esac
  f="$(fdir "$dir")"
  if [ "$kind" = ok ]; then
    # Evidence: the text must cite a file or folder name from the digest the verifier saw.
    names="$(digest "$dir" | sed -n 's/^FILE \(.*\) [0-9]*$/\1/p; s/^DIR \([^:]*\): .*$/\1/p')"
    while IFS= read -r name; do
      [ "${#name}" -ge 3 ] || continue
      n=$((n + 1))
      case "$text" in *"$name"*) ok=1; break ;; esac
    done <<< "$names"
    if [ "$n" -gt 0 ] && [ "$ok" -eq 0 ]; then
      echo "cortex-describe: ok must cite a file or folder name from the contents (e.g. one of: $(printf '%s' "$names" | tr '\n' ' '))" >&2
      return 2
    fi
  fi
  lock_acquire "$f" || { echo "cortex-describe: $dir is not in the queue or is busy" >&2; return 1; }
  if [ "$(get_state "$dir")" != claimed-verify ] || [ "$(cat "$f/worker" 2>/dev/null)" != "$worker" ]; then
    rmdir "$f/.lock"; echo "cortex-describe: $dir is not claimed for verification by $worker" >&2; return 1
  fi
  rm -f "$f/worker"
  log_event "$kind" "$dir" "$worker"
  if [ "$kind" = ok ]; then
    set_state "$dir" verified
  else
    rejects=$(( $(cat "$f/rejects" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$rejects" > "$f/rejects"
    printf '%s\n' "$text" | head -n 1 > "$f/reason"
    if [ "$rejects" -ge 3 ]; then set_state "$dir" needs-human; else set_state "$dir" todo; fi
  fi
  rmdir "$f/.lock"
  touch_active
}

# reset_cmd <dir>: take a needs-human folder back into the queue.
reset_cmd() {
  [ "$#" -eq 1 ] || usage
  local dir="${1%/}" f
  f="$(fdir "$dir")"
  if [ "$(get_state "$dir")" != needs-human ]; then
    echo "cortex-describe: $dir is not waiting for a human" >&2; return 2
  fi
  printf '0\n' > "$f/rejects"; : > "$f/reason"
  set_state "$dir" todo
  touch_active
}

# requeue_claimed: release every unfinished claim (use when no worker is alive).
requeue_claimed() {
  local d st n=0
  [ -f "$S/scope" ] || { echo "cortex-describe: no queue; run --init" >&2; return 1; }
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    st="$(get_state "$d")"
    case "$st" in
      claimed-write) set_state "$d" todo; n=$((n + 1)) ;;
      claimed-verify) set_state "$d" written; n=$((n + 1)) ;;
      *) continue ;;
    esac
    rm -f "$(fdir "$d")/worker"; rmdir "$(fdir "$d")/.lock" 2>/dev/null
  done < "$S/scope"
  touch_active
  printf '%s\n' "$n"
}

# show_status: counts, blockers, and the exit code that gates /cortex-sync.
# Complete = every queued folder verified, each description unchanged since it was
# verified, and no folder on disk outside the queue still lacking a description.
show_status() {
  local d st todo=0 claimed=0 written=0 verified=0 human=0 blocked="" nb=0 reason w now
  if [ ! -f "$S/scope" ]; then echo "cortex-describe: no queue; run --init" >&2; return 1; fi
  block() { nb=$((nb + 1)); [ "$nb" -le 50 ] && blocked="${blocked}BLOCKED${TAB}$1${TAB}$2"$'\n'; return 0; }
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    st="$(get_state "$d")"
    case "$st" in
      todo) todo=$((todo + 1)) ;;
      claimed-write|claimed-verify) claimed=$((claimed + 1)) ;;
      written) written=$((written + 1)) ;;
      verified) verified=$((verified + 1)) ;;
      needs-human) human=$((human + 1)) ;;
    esac
    case "$st" in
      verified)
        [ "$(cksum < "$ROOT/.cortex/map/$d.cortex" 2>/dev/null)" = "$(cat "$(fdir "$d")/hash" 2>/dev/null)" ] ||
          block "$d" "description changed after verification" ;;
      claimed-*) block "$d" claimed ;;
      needs-human) block "$d" "needs-human: $(head -n 1 "$(fdir "$d")/reason" 2>/dev/null)" ;;
      *) block "$d" "$st" ;;
    esac
  done < "$S/scope"
  w="$(mktemp -d)" || return 1
  scope_list | LC_ALL=C sort > "$w/scope"
  bash "$MAPSH" --drift | sed -n 's/^+ //p' | LC_ALL=C sort > "$w/pending"
  while IFS= read -r d; do [ -n "$d" ] && block "$d" "new folder not in the queue"; done < <(comm -13 "$w/scope" "$w/pending")
  rm -rf "$w"
  printf 'todo=%s claimed=%s written=%s verified=%s needs-human=%s\n' "$todo" "$claimed" "$written" "$verified" "$human"
  [ -n "$blocked" ] && printf '%s' "$blocked"
  if [ "$nb" -eq 0 ]; then rm -f "$S/active"; : > "$S/done"; return 0; fi
  return 1
}

case "${1:-}" in
  --init) shift; init_queue "$@"; exit $? ;;
  --report) [ "$#" -eq 1 ] || usage; report_cmd; exit $? ;;
  --status) [ "$#" -eq 1 ] || usage; touch_active_if_queue; show_status; exit $? ;;
  --next) shift; next_cmd "$@"; exit $? ;;
  --submit) shift; submit_cmd "$@"; exit $? ;;
  --verdict) shift; verdict_cmd "$@"; exit $? ;;
  --reset) shift; reset_cmd "$@"; exit $? ;;
  --requeue-claimed) [ "$#" -eq 1 ] || usage; requeue_claimed; exit $? ;;
  --show)
    [ "$#" -eq 2 ] || usage
    [ -d "$ROOT/${2%/}" ] || { echo "cortex-describe: not a directory under the project root: $2" >&2; exit 2; }
    digest "${2%/}"
    ;;
  *) usage ;;
esac
