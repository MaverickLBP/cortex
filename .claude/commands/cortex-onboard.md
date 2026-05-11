# cortex-onboard

Genera un documento de onboarding completo para un desarrollador nuevo basándote en todo el conocimiento acumulado en CORTEX. Escribe directamente en `.claude/cortex/ops/onboarding.md`.

Puede invocarse como `/cortex-onboard` en Claude Code, o por lenguaje natural ("Genera onboarding", "guía para nuevo desarrollador") en cualquier plataforma.

## Estructura del documento

### 1. ¿Qué es este proyecto?
Basado en `.claude/cortex/map/architecture.md`. Una descripción clara del propósito, no más de un párrafo.

### 2. Setup inicial
Basado en `.claude/cortex/ops/environment.md` y `.claude/cortex/ops/workflows.md`. Pasos exactos para tener el proyecto funcionando en local desde cero.

### 3. Cómo está organizado el código
Basado en `.claude/cortex/map/modules/` y `.claude/cortex/map/architecture.md`. Qué hace cada parte sin entrar en detalles de implementación.

### 4. Dependencias clave
Basado en `.claude/cortex/map/dependencies.md`. Solo las más importantes con su propósito. No listar todas.

### 5. Cómo trabajar en este proyecto
Basado en `.claude/cortex/memory/patterns.md` y `.claude/cortex/memory/decisions.md`. Patrones que hay que seguir y decisiones que no se cuestionan sin contexto previo.

### 6. Trampas conocidas
Basado en `.claude/cortex/memory/gotchas.md`. Las más importantes. Esto evita que el nuevo desarrollador pierda tiempo con problemas ya resueltos.

### 7. Deuda técnica conocida
Basado en `.claude/cortex/state/tech-debt.md`. Para que el nuevo desarrollador no "arregle" algo que existe por una razón.

### 8. Comandos frecuentes
Basado en `.claude/cortex/ops/workflows.md`. Referencia rápida de los comandos del día a día.

## Estilo

- Tono directo y práctico, sin relleno
- Escrito para alguien que ya sabe programar, no hace falta explicar conceptos básicos
- Si algo no está documentado en CORTEX, indícalo como `[por documentar]` en lugar de inventar
- Al terminar, informa al usuario de qué secciones quedaron incompletas por falta de información en el knowledge base
