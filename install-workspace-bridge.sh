#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# CORTEX — Install Workspace Bridge (Claude Code only)
#
# Creates a .cortex-workspace.json marker at the workspace
# root. The per-project cortex-session.sh SessionStart hook
# walks up from cwd looking for this marker; when found it
# enters workspace mode and lists all CORTEX-enabled projects.
#
# Does NOT install CORTEX in projects — run install.sh
# on each project separately.
#
# Usage:
#   bash install-workspace-bridge.sh                              # Interactive
#   bash install-workspace-bridge.sh --file workspace.code-workspace
#   bash install-workspace-bridge.sh path/to/workspace.code-workspace
# ──────────────────────────────────────────────────────
set -euo pipefail

WS_FILE=""

# ── Parse arguments ───────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      WS_FILE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage:"
      echo "  bash install-workspace-bridge.sh                              # Interactive"
      echo "  bash install-workspace-bridge.sh --file workspace.code-workspace"
      echo "  bash install-workspace-bridge.sh path/to/workspace.code-workspace"
      exit 0
      ;;
    *)
      WS_FILE="$1"
      shift
      ;;
  esac
done

# ── Colours ───────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  GREEN=''; CYAN=''; YELLOW=''; NC=''
fi

ok()     { echo -e "  ${GREEN}✔${NC} $1"; }
info()   { echo -e "  ${CYAN}→${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
prompt() { echo -e -n "  ${CYAN}?${NC} $1 "; }

# ── Helpers ────────────────────────────────────────────

parse_workspace_folders() {
  local ws_file="$1"
  local ws_dir
  ws_dir="$(cd "$(dirname "$ws_file")" && pwd)"

  if command -v python3 &>/dev/null; then
    python3 - "$ws_file" "$ws_dir" << 'PYEOF' 2>/dev/null && return 0 || true
import json, os, sys, re
try:
    ws_file = sys.argv[1]
    ws_dir  = sys.argv[2]
    with open(ws_file) as f:
        raw = f.read()
    raw = re.sub(r',\s*([\]}])', r'\1', raw)
    data = json.loads(raw)
    for folder in data.get('folders', []):
        path = folder.get('path', '')
        if not path:
            continue
        if not os.path.isabs(path):
            path = os.path.join(ws_dir, path)
        print(os.path.normpath(path))
except Exception as e:
    sys.stderr.write('Error: ' + str(e) + '\n')
    sys.exit(1)
PYEOF
  fi

  # Fallback: grep-based parser
  grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$ws_file" | \
    sed 's/"path" *: *"//;s/"$//' | \
    while IFS= read -r rel; do
      if [ "${rel:0:1}" = "/" ]; then
        echo "$rel"
      else
        echo "$ws_dir/$rel"
      fi
    done
}

# ── Resolve workspace file ────────────────────────────

if [ -z "$WS_FILE" ]; then
  echo ""
  echo "  CORTEX — Install Workspace Bridge"
  echo "  ───────────────────────────────────────"
  echo ""
  prompt "Enter path to .code-workspace file:"
  read -r WS_FILE
  if [ -z "$WS_FILE" ] || [ ! -f "$WS_FILE" ]; then
    echo "  File not found. Aborting."
    exit 1
  fi
fi

if [ ! -f "$WS_FILE" ]; then
  echo "  Error: '$WS_FILE' not found."
  exit 1
fi
WS_FILE="$(cd "$(dirname "$WS_FILE")" && pwd)/$(basename "$WS_FILE")"

TARGET="$(dirname "$WS_FILE")"

# ── Gather projects ───────────────────────────────────

echo ""
echo -e "  ${CYAN}⟐ CORTEX${NC} — Workspace Bridge"
echo "  ───────────────────────────────────────"
echo ""

info "Parsing: $(basename "$WS_FILE")"

project_dirs=()
while IFS= read -r proj; do
  [ -n "$proj" ] && project_dirs+=("$proj")
done < <(parse_workspace_folders "$WS_FILE")

if [ ${#project_dirs[@]} -eq 0 ]; then
  echo "  No projects found in workspace file. Aborting."
  exit 1
fi

info "Found ${#project_dirs[@]} project(s) in workspace"

# ── Generate .cortex-workspace.json marker ────────────

marker="$TARGET/.cortex-workspace.json"

projects_json="[]"
for proj in "${project_dirs[@]}"; do
  [ -d "$proj" ] || continue
  proj_name=$(basename "$proj")
  if [ -f "$proj/.cortex/SYSTEM.md" ]; then
    cortex_status="initialized"
  else
    cortex_status="not_initialized"
  fi
  entry="$(jq -n --arg name "$proj_name" --arg path "$proj" --arg cortex "$cortex_status" \
    '{name: $name, path: $path, cortex: $cortex}')"
  projects_json="$(echo "$projects_json" | jq --argjson entry "$entry" '. += [$entry]')"
done

generated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
workspace_name="$(basename "$WS_FILE" .code-workspace)"

cat > "$marker" << EOF
{
  "cortex": true,
  "version": "4.0.0",
  "workspace": "${workspace_name}",
  "generated": "${generated}",
  "projects": ${projects_json}
}
EOF

ok "Created .cortex-workspace.json at $TARGET"

echo ""
echo "  Projects:"
for proj in "${project_dirs[@]}"; do
  [ -d "$proj" ] || continue
  proj_name=$(basename "$proj")
  if [ -f "$proj/.cortex/SYSTEM.md" ]; then
    echo -e "    ${GREEN}✔${NC} $proj_name (CORTEX initialized)"
  else
    echo -e "    ${YELLOW}⚠${NC} $proj_name (CORTEX not initialized)"
  fi
done

echo ""
echo "  ───────────────────────────────────────"
echo -e "  ${GREEN}✔ Workspace bridge ready${NC}"
echo ""
echo "  The cortex-session.sh hook will detect .cortex-workspace.json"
echo "  and enter workspace mode automatically at session start."
echo ""
echo "  Next step: Run install.sh on each project"
echo "  that doesn't have CORTEX yet (marked ⚠ above)."
