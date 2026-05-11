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

- `.claude/cortex/sessions/[código]/state.md`
- `.claude/cortex/sessions/[código]/context.md`

---

## 2. Comportamiento autónomo obligatorio

Después de cada acción, evalúa en silencio si aplica alguno de estos casos y **actualiza el archivo correspondiente sin que el usuario lo pida**:

| Si... | Entonces actualiza |
|---|---|
| Tomaste una decisión técnica importante (arquitectura, librería, patrón, enfoque) | `.claude/cortex/memory/decisions.md` |
| Encontraste un comportamiento inesperado, bug no obvio, o trampa de una librería | `.claude/cortex/memory/gotchas.md` |
| Detectaste un patrón que se repite en el código del proyecto | `.claude/cortex/memory/patterns.md` |
| Hiciste un workaround o solución temporal que genera deuda técnica | `.claude/cortex/state/tech-debt.md` |
| El alcance de la tarea está cambiando respecto a lo pedido originalmente | `.claude/cortex/state/scope.md` **y avisa al usuario** |

**No anuncies** estas actualizaciones a menos que sean relevantes para la conversación.

### Consulta antes de actuar

- Revisa `.claude/cortex/memory/decisions.md` antes de proponer soluciones. No vuelvas a proponer algo ya descartado.
- Revisa `.claude/cortex/memory/gotchas.md` antes de trabajar en un área conocida. Avisa si hay trampas relevantes.
- Respeta los patrones en `.claude/cortex/memory/patterns.md`. El código nuevo debe ser consistente con el proyecto.

### Sesión activa

Si hay una sesión marcada como ACTIVA en `.claude/cortex/sessions/index.md`, trabaja dentro de su contexto. Registra decisiones específicas de esa tarea en `.claude/cortex/sessions/[código]/context.md`.

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
| **cortex-session-load** | `/cortex-session-load [código]` | "Carga sesión [código]" / "retoma [código]" | Restaura el contexto de una sesión pausada |
| **cortex-session-save** | `/cortex-session-save` | "Guarda sesión" / "pausa" / "guarda estado" | Persiste el estado exacto de la sesión activa |
| **cortex-session-list** | `/cortex-session-list` | "Lista sesiones" / "muestra sesiones" | Muestra todas las sesiones con su estado |
| **cortex-session-close** | `/cortex-session-close` | "Cierra sesión" / "finaliza sesión" | Marca la sesión activa como completada |

---

## 4. Archivos de referencia

Los archivos en `.claude/commands/*.md` contienen las instrucciones detalladas para cada comando. Sirven como documentación de referencia para el asistente en cualquier plataforma.
