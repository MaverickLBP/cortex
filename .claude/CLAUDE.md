# CORTEX — Context-Oriented Runtime Technical Experience

Sistema de memoria persistente para asistentes de desarrollo de software.
Compatible con Claude Code (slash commands), OpenCode y otros agentes de IA.

El sistema se activa al leer este archivo. El proyecto anfitrión lo referencia desde `CLAUDE.md` en la raíz.

---

## 1. Carga de contexto automática

Al iniciar la sesión o al comenzar una tarea, el asistente DEBE cargar los siguientes archivos de CORTEX para disponer del contexto completo del proyecto.

### Memoria activa (siempre al inicio)

- `.claude/cortex/memory/decisions.md` — Decisiones técnicas previas
- `.claude/cortex/memory/gotchas.md` — Trampas conocidas y bugs no obvios
- `.claude/cortex/memory/patterns.md` — Patrones y convenciones del proyecto
- `.claude/cortex/state/tech-debt.md` — Deuda técnica registrada
- `.claude/cortex/state/scope.md` — Control de alcance de tareas

### Contexto estático (cuando sea relevante a la tarea)

- `.claude/cortex/map/architecture.md` — Arquitectura del proyecto
- `.claude/cortex/map/dependencies.md` — Dependencias principales
- `.claude/cortex/ops/environment.md` — Variables de entorno y configuración
- `.claude/cortex/ops/workflows.md` — Comandos y flujos de trabajo

### Sesión activa (si existe)

Si `.claude/cortex/sessions/index.md` indica una sesión ACTIVA, cargar también:

- `.claude/cortex/sessions/[nombre]/state.md`
- `.claude/cortex/sessions/[nombre]/context.md`

---

## 2. Ciclo de comportamiento autónomo

### 2.1 Antes de actuar: consultar la memoria

Revisa estos archivos **antes** de proponer soluciones o escribir código. Que esté en esta sección y no en la de "después" es intencionado.

- `.claude/cortex/memory/decisions.md` — No propongas algo ya descartado en decisiones previas.
- `.claude/cortex/memory/gotchas.md` — Si trabajas en un área con trampas conocidas, avísalas antes de empezar.
- `.claude/cortex/memory/patterns.md` — El código nuevo debe seguir los patrones documentados.
- `.claude/cortex/sessions/[nombre]/context.md` — Si hay sesión ACTIVA, revisa el contexto específico antes de actuar.

### 2.2 Después de actuar: registrar

Evalúa en silencio si aplica alguno de estos casos y **actualiza el archivo correspondiente sin que el usuario lo pida**:

| Si... | Entonces actualiza |
|---|---|
| Elegiste entre múltiples opciones técnicas (arquitectura, librería, approach, algoritmo) y la decisión no es obvia, o descartaste alternativas viables | `.claude/cortex/memory/decisions.md` |
| Encontraste un comportamiento que contradice la documentación oficial, o una trampa que le costaría tiempo a otro developer | `.claude/cortex/memory/gotchas.md` |
| Notaste el mismo approach, naming o estructura apareciendo en **2+ lugares** (y no es imposición del framework) | `.claude/cortex/memory/patterns.md` |
| Implementaste algo que sabes que deberías hacer de otra forma pero no puedes ahora (por tiempo, restricciones externas, deuda intencionada) | `.claude/cortex/state/tech-debt.md` |
| La tarea se está expandiendo respecto a lo pedido originalmente (más archivos, más features, refactors no solicitados) | `.claude/cortex/state/scope.md` **y avisa al usuario** |

**No anuncies** estas actualizaciones a menos que sean relevantes para la conversación.

**Relación context.md vs decisions.md:** Si hay sesión ACTIVA, las decisiones específicas de la tarea van a `sessions/[nombre]/context.md`. Si la decisión tiene relevancia más allá de la sesión actual (arquitectura global, elección de librería, convención del proyecto), regístrala **también** en `memory/decisions.md`. La duplicación es deliberada: `context.md` es el detalle de la sesión, `decisions.md` es el índice permanente.

### 2.3 Después de escribir: verificar

Tras escribir o modificar cualquier archivo en `.claude/cortex/`:

1. **Vuelve a leer el archivo** y confirma que todos los campos del formato están poblados.
2. Si un campo quedó sin información, usa explícitamente **`[por documentar]`** en lugar de dejarlo vacío o con `—`.
3. Si el archivo es nuevo, confirma que se creó en la ruta correcta y que el directorio padre existe.

---

## 3. Comandos del sistema

El sistema expone comandos que pueden invocarse de dos formas:

- **Claude Code:** Usando el slash command (ej: `/cortex-init`)
- **OpenCode y otros:** Mediante lenguaje natural (ej: "Inicia CORTEX" o "ejecuta cortex-init")

Cuando el usuario invoque un comando, el asistente debe leer el archivo correspondiente en `.claude/commands/` y seguir las instrucciones allí definidas.

| Comando | Claude Code | Lenguaje natural | Descripción |
|---------|-------------|------------------|-------------|
| **cortex-init** | `/cortex-init` | "Inicia CORTEX" / "inicializa el sistema" | Explora el proyecto y genera el knowledge base desde cero |
| **cortex-preflight** | `/cortex-preflight` | "Preflight" / "revisión previa" / "preparación" | Revisa conocimiento relevante antes de empezar una tarea |
| **cortex-sync** | `/cortex-sync` | "Sincroniza CORTEX" / "actualiza el mapa" | Re-sincroniza MAP y OPS tras cambios estructurales |
| **cortex-onboard** | `/cortex-onboard` | "Genera onboarding" / "guía para nuevo dev" | Crea documento de onboarding basado en el knowledge base |
| **cortex-session-new** | `/cortex-session-new [nombre]` | "Nueva sesión: [nombre]" | Crea una nueva sesión de trabajo |
| **cortex-session-load** | `/cortex-session-load [nombre]` | "Carga sesión [nombre]" / "retoma [nombre]" | Restaura el contexto de una sesión pausada |
| **cortex-session-save** | `/cortex-session-save` | "Guarda sesión" / "pausa" / "guarda estado" | Persiste el estado exacto de la sesión activa |
| **cortex-session-list** | `/cortex-session-list` | "Lista sesiones" / "muestra sesiones" | Muestra todas las sesiones con su estado |
| **cortex-session-close** | `/cortex-session-close` | "Cierra sesión" / "finaliza sesión" | Marca la sesión activa como completada |

---

## 4. Archivos de referencia

Los archivos en `.claude/commands/*.md` contienen las instrucciones detalladas para cada comando. Sirven como documentación de referencia para el asistente en cualquier plataforma.
