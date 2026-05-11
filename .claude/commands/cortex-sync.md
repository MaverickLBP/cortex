# cortex-sync

Re-sincroniza el conocimiento estructural de CORTEX tras cambios arquitectónicos importantes. Actualiza MAP y OPS sin tocar MEMORY ni SESSIONS.

Puede invocarse como `/cortex-sync` en Claude Code, o por lenguaje natural ("Sincroniza CORTEX", "actualiza el mapa del proyecto") en cualquier plataforma.

## Qué actualizar

1. **.claude/cortex/map/architecture.md**
   Re-examina la estructura actual del proyecto. Actualiza lo que haya cambiado: nuevas carpetas relevantes, cambios en el stack, nuevos puntos de entrada.

2. **.claude/cortex/map/dependencies.md**
   Revisa los archivos de dependencias (package.json, requirements.txt, etc.) y refleja dependencias añadidas, eliminadas o con cambios de versión relevantes.

3. **.claude/cortex/map/modules/**
   - Actualiza los módulos que hayan cambiado significativamente
   - Añade archivos para módulos nuevos
   - Marca como `[OBSOLETO]` los módulos que ya no existen (no los borres, pueden tener valor histórico)

4. **.claude/cortex/ops/environment.md** y **.claude/cortex/ops/workflows.md**
   Actualiza si hay nuevas variables de entorno, nuevos comandos o cambios en los procesos.

## Qué NO tocar

- `.claude/cortex/memory/` — El conocimiento experiencial acumulado no se regenera
- `.claude/cortex/sessions/` — El historial de sesiones no se modifica
- `.claude/cortex/state/tech-debt.md` — La deuda técnica acumulada se mantiene

## Al terminar

Informa al usuario:
- Qué archivos se han actualizado
- Cambios significativos detectados respecto al estado anterior
- Si hay inconsistencias entre lo documentado y lo encontrado
