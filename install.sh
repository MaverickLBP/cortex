#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# CORTEX — Context-Oriented Runtime Technical Experience
# Installer
#
# Modos de uso:
#
#   1. Desde GitHub (recomendado):
#      curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash
#      curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash -s -- /ruta/al/proyecto
#
#   2. Local (si clonaste el repo):
#      ./install.sh
#      ./install.sh /ruta/al/proyecto
#
# ──────────────────────────────────────────────

REPO_URL="https://github.com/MaverickLBP/cortex.git"
BRANCH="main"

# ── Colores ────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Argumento: directorio destino ──────────────
TARGET="${1:-$(pwd)}"

# ── Banner ─────────────────────────────────────
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         CORTEX — Installer               ║${NC}"
echo -e "${CYAN}║  Persistent project memory for AI agents  ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# ── Validar directorio destino ─────────────────
if [ ! -d "$TARGET" ]; then
  echo -e "${RED}✖ Error: '$TARGET' no es un directorio válido.${NC}"
  exit 1
fi

echo -e "  Target: ${YELLOW}$TARGET${NC}"
echo ""

# ── Detectar modo: local vs remoto ─────────────
CORTEX_SOURCE=""

# Intentar detectar si estamos ejecutando desde el repo clonado
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/.claude/CLAUDE.md" ]; then
  CORTEX_SOURCE="$SCRIPT_DIR"
  echo -e "  Modo: ${GREEN}local${NC} ($CORTEX_SOURCE)"
else
  # Modo remoto: descargar de GitHub
  echo -e "  Modo: ${CYAN}remoto${NC} (git fetch desde GitHub)"
  echo ""

  # Verificar que git está disponible
  if ! command -v git &>/dev/null; then
    echo -e "${RED}✖ Error: git no está instalado.${NC}"
    echo -e "${YELLOW}  Instálalo o descarga el repo manualmente desde:${NC}"
    echo -e "${YELLOW}  $REPO_URL${NC}"
    exit 1
  fi

  TMP_DIR=$(mktemp -d)
  echo -e "  ${YELLOW}  Descargando CORTEX...${NC}"

  if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR" 2>/dev/null; then
    echo -e "${RED}✖ Error al descargar el repositorio.${NC}"
    echo -e "${YELLOW}  Verifica tu conexión o descarga manualmente.${NC}"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  CORTEX_SOURCE="$TMP_DIR"
fi

CLAUDE_SRC="$CORTEX_SOURCE/CLAUDE.md"
CLAUDE_DOT_SRC="$CORTEX_SOURCE/.claude"
CLAUDE_DEST="$TARGET/CLAUDE.md"
CLAUDE_DOT_DEST="$TARGET/.claude"

# ── Instalar CLAUDE.md ─────────────────────────
COPY_CLAUDE=true

if [ -f "$CLAUDE_DEST" ]; then
  EXISTING_LINES=$(wc -l < "$CLAUDE_DEST")
  if [ "$EXISTING_LINES" -gt 5 ]; then
    echo -e "  ${YELLOW}⚠ CLAUDE.md existente con $EXISTING_LINES líneas. No se sobrescribe.${NC}"
    echo -e "  ${YELLOW}  Añade esta línea manualmente si no está:${NC}"
    echo -e "  ${YELLOW}  → Carga .claude/CLAUDE.md para las instrucciones completas.${NC}"
    COPY_CLAUDE=false
  else
    echo -e "  ${YELLOW}⚠ Ya existe CLAUDE.md. ¿Sobrescribir? (s/N)${NC}"
    read -r CONFIRM < /dev/tty || true
    if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
      COPY_CLAUDE=false
    fi
  fi
fi

if [ "$COPY_CLAUDE" = true ]; then
  cp "$CLAUDE_SRC" "$CLAUDE_DEST"
  echo -e "  ${GREEN}✔ CLAUDE.md instalado${NC}"
else
  echo -e "  ${YELLOW}○ CLAUDE.md no se modificó${NC}"
fi

# ── Instalar .claude/ ──────────────────────────
if [ -d "$CLAUDE_DOT_DEST" ]; then
  echo -e "  ${YELLOW}⚠ Ya existe .claude/ en el destino.${NC}"
  echo -e "  ${YELLOW}  ¿Actualizar? (Se conservarán tus datos) (s/N)${NC}"
  read -r CONFIRM < /dev/tty || true
  if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
      echo -e "  ${RED}✖ Instalación cancelada.${NC}"
      exit 1
  fi

  # Backup de datos existentes (memoria, estado, sesiones)
  echo -e "  ${YELLOW}  Preservando datos existentes...${NC}"
  TMP_BACKUP=$(mktemp -d)

  for dir in memory state sessions; do
    src="$CLAUDE_DOT_DEST/cortex/$dir"
    if [ -d "$src" ]; then
      cp -r "$src" "$TMP_BACKUP/$dir" 2>/dev/null || true
    fi
  done

  # Reemplazar .claude/
  rm -rf "$CLAUDE_DOT_DEST"
  cp -r "$CLAUDE_DOT_SRC" "$CLAUDE_DOT_DEST"

  # Restaurar backup
  for dir in memory state sessions; do
    backup="$TMP_BACKUP/$dir"
    if [ -d "$backup" ]; then
      dest_dir="$CLAUDE_DOT_DEST/cortex/$dir"
      rm -rf "$dest_dir"
      cp -r "$backup" "$dest_dir"
    fi
  done

  rm -rf "$TMP_BACKUP"
  echo -e "  ${GREEN}✔ .claude/ actualizado (datos preservados)${NC}"
else
  cp -r "$CLAUDE_DOT_SRC" "$CLAUDE_DOT_DEST"
  echo -e "  ${GREEN}✔ .claude/ instalado${NC}"
fi

# ── Limpiar si usamos temp ─────────────────────
if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
  rm -rf "$TMP_DIR"
fi

# ── Resumen final ──────────────────────────────
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   CORTEX instalado correctamente         ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Próximos pasos:${NC}"
echo ""
echo -e "  1. Inicia una sesión con tu agente IA en:"
echo -e "     ${YELLOW}$TARGET${NC}"
echo ""
echo -e "  2. CORTEX se activará automáticamente al leer el CLAUDE.md."
echo ""
echo -e "  3. Opcional: genera la base de conocimiento inicial:"
echo -e "     ${YELLOW}/cortex-init${NC}     (Claude Code)"
echo -e "     ${YELLOW}\"Inicia CORTEX\"${NC}  (cualquier agente)"
echo ""
