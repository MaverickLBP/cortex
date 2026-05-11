# cortex-session-new

Crea una nueva sesión de trabajo. El usuario proporciona el nombre que se usará como identificador único.

Ejemplo de uso: `/cortex-session-new auth-refactor` (Claude Code) o "Nueva sesión: auth-refactor" (lenguaje natural)

## Pasos

1. **Usar el nombre proporcionado** como identificador de la sesión. El nombre define la carpeta y todas las referencias.

2. **Crear la carpeta** `.claude/cortex/sessions/[nombre]/`

3. **Crear `state.md`** con esta estructura exacta:

```
Sesión: [nombre]
Tarea: [pedir al usuario que describa el objetivo en una frase clara]
Estado: EN PROGRESO
Creada: [fecha actual YYYY-MM-DD]
Última actividad: [fecha actual YYYY-MM-DD]

Último paso completado: -
Siguiente paso: [inicio de la tarea, pendiente de definir]
Archivos activos: -
Bloqueado por: -
```

4. **Crear `context.md`** con esta estructura:

```
# Contexto — [nombre]

> Decisiones y notas específicas de esta tarea. Actualización autónoma por CORTEX.
> Las decisiones con impacto permanente (arquitectura global, elección de librería) deben duplicarse en `memory/decisions.md`.

---

<!-- Formato para decisiones:

## Decisión: [título breve]
**Qué:** Descripción de la decisión.
**Alternativas:** Qué otras opciones se consideraron (o "ninguna").
**Por qué:** Justificación.
-->

<!-- Formato para notas:

## Nota: [asunto]
**Detalle:** Información relevante para la sesión.
-->
```

5. **Actualizar `.claude/cortex/sessions/index.md`**: añadir la sesión nueva a la tabla y marcarla como ACTIVA. Si había otra sesión ACTIVA, cambiarla a PAUSADA.

6. **Confirmar al usuario**: mostrar la sesión creada y el `state.md` inicial. Preguntar si quiere hacer un preflight (revisión previa) antes de comenzar.

7. **Verificar**: confirma que `state.md` y `context.md` existen en la ruta correcta y que `index.md` refleja el cambio.
