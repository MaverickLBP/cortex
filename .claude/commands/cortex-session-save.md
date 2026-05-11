# cortex-session-save

Guarda el estado exacto de la sesión activa antes de pausarla o cerrar el trabajo del día.

## Pasos

1. **Identificar la sesión activa** leyendo `.claude/cortex/sessions/index.md`. Si no hay sesión activa, informar al usuario y no hacer nada más.

2. **Recopilar el estado actual** — si no es evidente por el contexto de la conversación, preguntar al usuario:
   - ¿Cuál fue el último paso completado?
   - ¿Cuál es exactamente el siguiente paso al retomar? (debe ser suficientemente específico para empezar sin fricción)
   - ¿Hay algún bloqueo o dependencia pendiente?

3. **Actualizar `.claude/cortex/sessions/[código]/state.md`** con:
   - Último paso completado (específico, no genérico)
   - Siguiente paso exacto
   - Archivos que estaban activos o son relevantes para retomar
   - Cualquier bloqueo activo
   - Fecha de última actividad actualizada

4. **Actualizar `.claude/cortex/sessions/index.md`** con la fecha de última actividad.

5. **Confirmar** mostrando el `state.md` actualizado para que el usuario valide que el estado es correcto.

> El objetivo es que al cargar la sesión de nuevo (con `cortex-session-load`), el asistente pueda retomar exactamente desde aquí sin necesitar más contexto del usuario.
