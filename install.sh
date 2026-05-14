#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# CORTEX — Context-Oriented Runtime Technical Experience
# Installer
#
# Uso:
#   curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash
#   curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash -s -- /ruta/al/proyecto
# ──────────────────────────────────────────────

REPO_URL="https://github.com/MaverickLBP/cortex.git"
BRANCH="main"
TARGET="${1:-$(pwd)}"

# ── Validaciones ──────────────────────────────
if [ ! -d "$TARGET" ]; then
  echo "Error: '$TARGET' no es un directorio válido."
  exit 1
fi

# ── Obtener CORTEX ────────────────────────────
TMP_DIR=$(mktemp -d)
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR" 2>/dev/null || {
  echo "Error al descargar CORTEX. Verifica tu conexión."
  rm -rf "$TMP_DIR"
  exit 1
}

# ── Crear .claude/cortex/ en el destino ───────
mkdir -p "$TARGET/.claude/cortex"
cp "$TMP_DIR/.claude/cortex/SYSTEM.md" "$TARGET/.claude/cortex/SYSTEM.md"

if [ ! -f "$TARGET/.claude/cortex/context.md" ]; then
  cp "$TMP_DIR/.claude/cortex/context.md" "$TARGET/.claude/cortex/context.md"
  echo "✔ context.md creado (plantilla inicial)"
else
  echo "○ context.md existente — conservado"
fi

# ── Configurar CLAUDE.md ──────────────────────
LOADER_LINE="→ Carga .claude/cortex/SYSTEM.md para las instrucciones completas."

if ! grep -q "CORTEX" "$TARGET/CLAUDE.md" 2>/dev/null; then
  echo "" >> "$TARGET/CLAUDE.md"
  echo "Este proyecto utiliza **CORTEX** para contexto persistente del proyecto." >> "$TARGET/CLAUDE.md"
  echo "$LOADER_LINE" >> "$TARGET/CLAUDE.md"
  echo "✔ CLAUDE.md actualizado"
else
  echo "○ CLAUDE.md ya tiene referencia a CORTEX — no se modificó"
fi

# ── Limpiar ───────────────────────────────────
rm -rf "$TMP_DIR"

echo ""
echo "CORTEX instalado en $TARGET"
echo "Edita .claude/cortex/context.md para describir tu proyecto."
