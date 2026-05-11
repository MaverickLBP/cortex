# cortex-session-close

Marca la sesión activa como completada y cierra el contexto de la tarea.

## Pasos

1. **Identificar la sesión activa** en `.claude/cortex/sessions/index.md`. Si no hay sesión activa, informar y no hacer nada.

2. **Preguntar al usuario** si hay algo final que registrar antes de cerrar:
   - ¿Alguna decisión importante tomada en esta sesión que no haya quedado registrada?
   - ¿Quedó alguna deuda técnica intencionada que deba anotarse?
   - ¿Algo que el siguiente que trabaje en esta área deba saber?

3. **Registrar lo que el usuario indique** en los archivos de memory/state correspondientes.

4. **Actualizar `.claude/cortex/sessions/[nombre]/state.md`**:
   ```
   Estado: COMPLETADA
   Cerrada: [fecha actual]
   Siguiente paso: -
   ```

5. **Actualizar `.claude/cortex/sessions/index.md`**:
   - Estado de la sesión: COMPLETADA
   - Sin sesión activa marcada

6. **Verificar**: confirma que `state.md` refleja `Estado: COMPLETADA` y que `index.md` ya no marca la sesión como ACTIVA.

7. **Confirmar** el cierre con un resumen de lo que se hizo en la sesión (objetivo → resultado).
