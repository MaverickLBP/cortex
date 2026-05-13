# CORTEX System Instructions

> Archivo de sistema CORTEX. No modificar manualmente.
> Este archivo contiene las instrucciones de comportamiento que el asistente DEBE seguir.
> Es cargado por `.claude/CLAUDE.md` (loader) al iniciar la sesión.

---

## 1. Carga de contexto automática

Al iniciar la sesión o al comenzar una tarea, el asistente DEBE cargar los siguientes archivos de CORTEX para disponer del contexto completo del proyecto.

### Memoria activa (siempre al inicio)

- `.claude/cortex/memory/decisions.md` — Decisiones técnicas previas
- `.claude/cortex/memory/gotchas.md` — Trampas conocidas y bugs no obvios
- `.claude/cortex/memory/patterns.md` — Patrones y convenciones del proyecto
- `.claude/cortex/state/tech-debt.md` — Deuda técnica registrada
- `.claude/cortex/state/scope.md` — Control de alcance de tareas
- `.claude/cortex/governance/team.md` — Protocolos de equipo y disciplina de commit

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

Los archivos de comandos residen en `.claude/commands/cortex-*.md` (directorio estándar de Claude Code). Cuando el usuario invoque un comando, el asistente debe leer el archivo correspondiente y seguir las instrucciones allí definidas.

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

- Los comandos del sistema están en `.claude/commands/cortex-*.md` — instrucciones detalladas para cada comando.
- El loader de CORTEX está en `.claude/CLAUDE.md` — no modificar, solo redirige a este archivo.
- Este archivo es `.claude/cortex/SYSTEM.md` — instrucciones de comportamiento del asistente.
- El resto del sistema está en `.claude/cortex/` (memory/, map/, ops/, state/, sessions/, governance/).

---

## 5. Team Coordination Protocol

Al trabajar en un repositorio compartido con otros miembros del equipo, el asistente DEBE cumplir el protocolo definido en `governance/team.md`. Los principios fundamentales son:

### 5.1 Antes de empezar una tarea

El asistente DEBE ejecutar la **verificación de frescura** como parte del preflight:

1. `git fetch origin` (traer referencias remotas sin hacer merge)
2. Comprobar si el remoto tiene cambios en `.claude/` que el local no ha integrado:
   ```
   git log --oneline origin/main..HEAD -- .claude/
   ```
3. Si hay cambios remotos no integrados: **advertir al usuario** antes de proseguir

### 5.2 Al hacer commit

El conocimiento en `memory/` y `state/` debe viajar en el **mismo commit** que el código que lo motivó. El mensaje de commit debe mencionar los archivos CORTEX afectados (ver `governance/team.md` §1).

### 5.3 Al añadir nuevas funciones o reglas

- **Nuevas funciones**: ejecutar `cortex-sync` para actualizar `map/` y `ops/`
- **Nuevas reglas de comportamiento del asistente**: modificar este archivo (`SYSTEM.md`) e incrementar la versión en el loader
- **Nuevas convenciones de código**: añadir a `memory/patterns.md`
- **Cambios estructurales en CORTEX**: describir en el mensaje de commit

### 5.4 Resolución de conflictos

Ver `governance/team.md` §3. Regla general: en archivos de memoria con fecha, conservar ambas entradas y ordenar cronológicamente.

### 5.5 Sesiones

Estrictamente personales (ver `governance/team.md` §5). Los archivos de sesión están gitignored.
