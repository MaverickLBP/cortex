# cortex-session-load

Carga una sesión pausada y restaura el contexto completo para retomar el trabajo sin fricción.

Ejemplo de uso: `/cortex-session-load auth-refactor` (Claude Code) o "Carga sesión auth-refactor" / "Retoma auth-refactor" (lenguaje natural)

## Pasos

1. **Leer `.claude/cortex/sessions/[nombre]/state.md`** y `.claude/cortex/sessions/[nombre]/context.md`

2. **Presentar resumen de retoma** de forma clara y estructurada:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Retomando: [nombre]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Objetivo:         [tarea]
Último paso:      [último paso completado]
Siguiente paso:   [siguiente paso exacto]
Archivos activos: [lista]
Bloqueado por:    [bloqueo o "-"]

Notas de contexto:
[contenido relevante de context.md]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

3. **Preflight automático** — sin que el usuario lo pida, consultar rápidamente:
   - Gotchas relacionados con los archivos activos o el área de trabajo
   - Decisiones relevantes para esta tarea
   Si hay algo importante, mencionarlo. Si no, no añadir ruido.

4. **Actualizar `.claude/cortex/sessions/index.md`**:
   - Esta sesión: ACTIVA
   - Sesión anteriormente activa (si la hubiera): PAUSADA

5. **Verificar**: confirma que `index.md` refleja correctamente el cambio (esta sesión ACTIVA, la anterior PAUSADA).

6. **Preguntar** si el usuario quiere empezar directamente con el siguiente paso indicado.
