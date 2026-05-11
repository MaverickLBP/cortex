# cortex-session-new

Crea una nueva sesión de trabajo con código único. El usuario proporciona un nombre descriptivo.

Ejemplo de uso: `/cortex-session-new auth-refactor` (Claude Code) o "Nueva sesión: auth-refactor" (lenguaje natural)

## Pasos

1. **Leer `.claude/cortex/sessions/index.md`** para determinar el siguiente número correlativo (S001, S002, S003...). Si el archivo está vacío, empezar por S001.

2. **Construir el código de sesión**: `S[NNN]-[nombre-proporcionado]`
   Ejemplo: `S003-auth-refactor`

3. **Crear la carpeta** `.claude/cortex/sessions/S[NNN]-[nombre]/`

4. **Crear `state.md`** con esta estructura exacta:

```
Código: S[NNN]-[nombre]
Tarea: [pedir al usuario que describa el objetivo en una frase clara]
Estado: EN PROGRESO
Creada: [fecha actual YYYY-MM-DD]
Última actividad: [fecha actual YYYY-MM-DD]

Último paso completado: -
Siguiente paso: [inicio de la tarea, pendiente de definir]
Archivos activos: -
Bloqueado por: -
```

5. **Crear `context.md`** con esta estructura:

```
# Contexto — S[NNN]-[nombre]

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

6. **Actualizar `.claude/cortex/sessions/index.md`**: añadir la sesión nueva a la tabla y marcarla como ACTIVA. Si había otra sesión ACTIVA, cambiarla a PAUSADA.

7. **Confirmar al usuario**: mostrar el código de sesión creado y el `state.md` inicial. Preguntar si quiere hacer un preflight (revisión previa) antes de comenzar.

8. **Verificar**: confirma que `state.md` y `context.md` existen en la ruta correcta y que `index.md` refleja el cambio.
