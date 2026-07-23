#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — cortex-areas: scale-adaptive area partition.
# Reads documentable files (cortex-scan), decides flat vs
# hierarchical, greedily splits oversized areas by subtree
# size, collapses single-child chains, merges tiny leftovers,
# and writes .cortex/maps/index.json.
# Usage: cortex-areas.sh [ROOT]
# ──────────────────────────────────────────────────────
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 0; }

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
FLAT_CAP="${CORTEX_FLAT_CAP:-150}"
AREA_CAP="${CORTEX_AREA_CAP:-60}"
MERGE_MIN="${CORTEX_MERGE_MIN:-8}"

FILES="$(bash "$SELF_DIR/cortex-scan.sh" --files "$ROOT")"
TOTAL="$(printf '%s\n' "$FILES" | grep -c . || true)"

mkdir -p "$ROOT/.cortex/maps"
MANIFEST="$ROOT/.cortex/maps/index.json"

# ── Flat gate ─────────────────────────────────────────
if [ "$TOTAL" -le "$FLAT_CAP" ]; then
  jq -n --argjson t "$TOTAL" '{version:1,flat:true,areas:[]}' > "$MANIFEST"
  echo "FLAT $TOTAL"
  exit 0
fi

# ── Greedy split by subtree size (awk does the counting) ──
# cnt[d] = number of files whose path is under directory d (any depth).
# Start with top-level dirs as candidate roots; recursively split any
# candidate whose subtree > AREA_CAP by promoting its immediate
# subdirs with subtree >= MERGE_MIN into the worklist. Every candidate
# is kept in `roots` (even ones later collapsed as pass-throughs); the
# collapse step below drops roots that own zero direct files AND have
# exactly one child root.
printf '%s\n' "$FILES" | awk -v cap="$AREA_CAP" -v mmin="$MERGE_MIN" '
{
  n=split($0,p,"/");
  path="";
  for(i=1;i<n;i++){ path=(i==1?p[1]:path"/"p[i]); cnt[path]++ }
}
END{
  for(d in cnt){
    slashes=0; tmp=d; while(match(tmp,/\//)){slashes++; tmp=substr(tmp,RSTART+1)}
    if(slashes==0){ if(cnt[d]>=mmin){ q[++qn]=d } }
  }
  head=1;
  while(head<=qn){
    R=q[head++];
    if(R in seen) continue;
    seen[R]=1;
    roots[R]=1;
    if(cnt[R]<=cap) continue;
    # oversized: find immediate children dirs of R, promote big-enough ones
    for(d in cnt){
      if(index(d,R"/")==1){
        rest=substr(d,length(R)+2);
        if(index(rest,"/")==0){        # immediate child dir of R
          if(cnt[d]>=mmin){ q[++qn]=d }
        }
      }
    }
  }
  for(r in roots) print r, cnt[r];
}' | sort > "$ROOT/.cortex/maps/.roots.tmp"

ROOTLIST="$(awk '{print $1}' "$ROOT/.cortex/maps/.roots.tmp")"

owned_count() { # $1 = root ; files under root minus files under any deeper root
  local r="$1"
  printf '%s\n' "$FILES" | awk -v r="$r" -v rl="$ROOTLIST" '
    BEGIN{ nr=split(rl,R,"\n") }
    {
      if(index($0,r"/")!=1) next;
      # is there a deeper (longer-prefix) root that also prefixes this file?
      best=r;
      for(i=1;i<=nr;i++){
        rr=R[i]; if(rr==""||rr==r) continue;
        if(index($0,rr"/")==1 && length(rr)>length(best)) best=rr;
      }
      if(best==r) c++;
    }
    END{ print c+0 }'
}

# Determine the set of roots that are "children" of a given root (a
# deeper root R2 whose immediate-uncollapsed ancestor among roots is R).
# For chain collapse we need: does R have exactly one *other* root that
# is a strict descendant of R with no *other* root strictly between them?
# Simpler equivalent: a root R with owned_count==0 is a pass-through; if
# it is a pass-through, drop it — its files are already fully claimed by
# some deeper root(s), so removing it just means longest-prefix picks the
# next root in the chain. Iterate until stable (in case of multi-level
# chains: a -> a/b -> a/b/c/pkg).
cp "$ROOT/.cortex/maps/.roots.tmp" "$ROOT/.cortex/maps/.roots2.tmp"
CHANGED=1
while [ "$CHANGED" -eq 1 ]; do
  CHANGED=0
  ROOTLIST="$(awk '{print $1}' "$ROOT/.cortex/maps/.roots2.tmp")"
  : > "$ROOT/.cortex/maps/.roots3.tmp"
  while read -r r _; do
    [ -z "$r" ] && continue
    oc="$(owned_count "$r")"
    if [ "$oc" -eq 0 ]; then
      CHANGED=1
      continue
    fi
    echo "$r $oc" >> "$ROOT/.cortex/maps/.roots3.tmp"
  done < "$ROOT/.cortex/maps/.roots2.tmp"
  mv "$ROOT/.cortex/maps/.roots3.tmp" "$ROOT/.cortex/maps/.roots2.tmp"
done

# Emit areas from the surviving (non-pass-through) roots.
AREAS_JSON="[]"
while read -r r oc; do
  [ -z "$r" ] && continue
  mapname="maps/$(printf '%s' "$r" | sed 's|/|__|g').md"
  AREAS_JSON="$(jq -c --arg root "$r" --arg map "$mapname" --argjson files "$oc" \
    '. + [{root:$root,map:$map,files:$files}]' <<<"$AREAS_JSON")"
done < "$ROOT/.cortex/maps/.roots2.tmp"

# Root-level leftover files (owned by no area) → _misc area.
ROOTLIST="$(awk '{print $1}' "$ROOT/.cortex/maps/.roots2.tmp")"
MISC="$(printf '%s\n' "$FILES" | awk -v rl="$ROOTLIST" '
  BEGIN{ nr=split(rl,R,"\n") }
  { for(i=1;i<=nr;i++){ if(R[i]!="" && index($0,R[i]"/")==1){next} } c++ }
  END{ print c+0 }')"
if [ "$MISC" -gt 0 ]; then
  AREAS_JSON="$(jq -c --argjson files "$MISC" \
    '. + [{root:".",map:"maps/_misc.md",files:$files}]' <<<"$AREAS_JSON")"
fi

jq -n --argjson areas "$AREAS_JSON" '{version:1,flat:false,areas:$areas}' > "$MANIFEST"
rm -f "$ROOT/.cortex/maps/.roots.tmp" "$ROOT/.cortex/maps/.roots2.tmp"

jq -r '.areas[] | "AREA \(.root) \(.files)"' "$MANIFEST"
exit 0
