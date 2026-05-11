# cortex-session-save

Guarda el estado exacto de la sesión activa antes de pausarla o cerrar el trabajo del día.

## Pasos

1. **Identificar la sesión activa** leyendo `.claude/cortex/sessions/index.md`. Si no hay sesión activa, informar al usuario y no hacer nada más.

2. **Recopilar el estado actual** — usa esta regla: si puedes responder las 3 preguntas sin ambigüedad (sin "probablemente", "creo que", "el último paso fue algo como..."), no preguntes. Si tienes cualquier duda, **pregunta al usuario**. Es mejor preguntar que registrar algo incorrecto.
   - ¿Cuál fue exactamente el último paso completado? (debe ser verificable: un comando ejecutado, un archivo creado, un test pasado)
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

6. **Verificar**: lee el `state.md` actualizado y confirma que ningún campo requerido quedó vacío. Si falta algo, corrígelo antes de finalizar.

> El objetivo es que al cargar la sesión de nuevo (con `cortex-session-load`), el asistente pueda retomar exactamente desde aquí sin necesitar más contexto del usuario.
