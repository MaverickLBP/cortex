# Governance del Equipo — CORTEX

> Protocolos formales para el trabajo colaborativo con CORTEX.
> Versión: 1.0.0 · Última revisión: 2026-05-12

---

## 1. Disciplina de Commit

### 1.1 Conocimiento atómico con el código

El conocimiento generado durante una tarea debe viajar en el **mismo commit** que el código que lo motivó:

| Si durante la tarea... | Entonces incluye en el commit |
|---|---|
| Tomaste una decisión técnica no obvia (arquitectura, librería, approach) | `memory/decisions.md` |
| Descubriste un gotcha o trampa que contradice documentación oficial | `memory/gotchas.md` |
| Identificaste un patrón recurrente en 2+ lugares | `memory/patterns.md` |
| Introdujiste deuda técnica intencionada por tiempo/restricciones | `state/tech-debt.md` |
| El alcance de la tarea se desvió significativamente de lo pedido | `state/scope.md` |

### 1.2 Mensaje de commit

El mensaje debe mencionar qué archivos de CORTEX se actualizaron para que el equipo pueda localizar el contexto rápidamente:

```
feat(api): implementa autenticación JWT

Añade middleware de verificación, endpoints de login/refresh y tests.

CORTEX: decisions.md, patterns.md
```

### 1.3 Qué NO se commitea

| Archivo | Motivo |
|---------|--------|
| `sessions/*/state.md` | Estado de sesión personal |
| `sessions/*/context.md` | Contexto de sesión personal |
| `.claude/settings.json` | Overrides personales del asistente |
| `.env`, `.env.local`, `*.key` | Secretos y credenciales |

Estos archivos están en `.gitignore`. Si alguno no lo está, reportarlo.

---

## 2. Ritual de inicio de tarea

Antes de comenzar cualquier tarea, ejecutar **`/cortex-preflight`**. El asistente debe verificar activamente que el conocimiento local está al día.

### 2.1 Verificación de frescura (preflight)

Como parte del preflight, el asistente DEBE:

1. `git fetch origin` para obtener las referencias remotas sin hacer merge automático
2. Comparar si el remoto tiene cambios en `.claude/` que el local no ha integrado:
   ```
   git log --oneline HEAD..origin/main -- .claude/
   ```
   (Lo que hay en origin/main que el local no ha integrado)
3. Si hay cambios remotos no integrados: **advertir al usuario** antes de continuar

### 2.2 Post-sincronización

Si se integraron cambios remotos (pull, merge, rebase), ejecutar `cortex-sync` para asegurar que `map/` y `ops/` reflejan el estado actual del proyecto tras los cambios de otros miembros.

---

## 3. Resolución de conflictos en archivos CORTEX

Los archivos de CORTEX son Markdown plano. Cuando dos miembros modifican simultáneamente los mismos archivos, se aplican estas reglas:

### 3.1 Archivos de memoria (`memory/decisions.md`, `gotchas.md`, `patterns.md`)

**Regla: anexar ambas entradas.** No se sobrescribe ni se descarta.

Cada entrada tiene fecha (`## [YYYY-MM-DD]`). En un conflicto de merge:

1. Conservar ambas entradas completas
2. Ordenarlas cronológicamente (más reciente primero)
3. Añadir `> [CONFLICTO RESUELTO] Fusión manual de dos entradas concurrentes` al inicio del bloque

### 3.2 Archivos de estado (`state/tech-debt.md`, `state/scope.md`)

Requieren resolución manual. Leer ambas versiones y verificar contra el estado real del proyecto. `cortex-sync` puede ayudar a determinar qué versión refleja la realidad.

### 3.3 Archivos estructurales (`map/`, `ops/`)

**Requieren resolución manual obligatoria.** Son tablas, árboles y descripciones que deben reflejar la realidad:

1. Leer ambas versiones completas
2. Verificar contra el estado actual del proyecto: ejecutar `cortex-sync` si es necesario
3. Si ambas versiones describen cambios compatibles (ej: dos dependencias distintas añadidas), fusionar
4. Si son contradictorias, priorizar la versión del commit más reciente (fecha de autoría)

### 3.4 Archivo de sistema (`cortex/SYSTEM.md`)

**Requiere coordinación explícita del equipo.** No se modifica unilateralmente. Cualquier cambio debe:

1. Ser discutido y acordado por al menos dos miembros del equipo
2. Incrementar la versión en el loader (`.claude/CLAUDE.md`)
3. El mensaje de commit debe describir el cambio en el sistema

### 3.5 Corrección de entradas incorrectas en memoria

Si el asistente registró información errónea en `memory/decisions.md`, `gotchas.md` o `patterns.md`:

**Regla: no borrar la entrada original.** Marcarla como `[CORREGIDA]` y añadir una nota explicativa. Esto preserva el historial para que otro miembro no tropiece con el mismo error.

**Formato:**
```
## [YYYY-MM-DD] Título original [CORREGIDA]
**Área:** Módulo o tecnología afectada
**Problema:** Descripción original ~~incorrecta~~ [CORREGIDA: explicación de la corrección]
**Solución:** Solución corregida o referencia a la entrada correcta
```

**Ejemplo:**
```
## 2026-05-12 Error con acentos en módulo X [CORREGIDA]
**Área:** Módulo X
**Problema:** Los acentos no se renderizan correctamente [CORREGIDA: era error de configuración de charset en la BD, no bug del módulo]
**Solución:** Verificar que la conexión a BD usa utf8mb4
```

Si el usuario solicita explícitamente eliminar una entrada, el asistente puede hacerlo, pero debe registrarlo en el mensaje de commit.

---

## 4. Evolución del sistema

### 4.1 Dónde documentar cada tipo de regla

| Tipo de regla | Dónde documentarla |
|---|---|
| Convención de código (naming, estructura, patrones) | `memory/patterns.md` |
| Decisión técnica (arquitectura, librería, approach) | `memory/decisions.md` |
| Comportamiento del asistente (cómo debe operar) | `cortex/SYSTEM.md` (solo si aplica a todo el equipo) |
| Override personal de comportamiento del asistente | `.claude/settings.json` (gitignored) |
| Flujo de trabajo (comandos, procesos) | `ops/workflows.md` |
| Configuración de entorno (variables, servicios) | `ops/environment.md` |
| Acuerdos del equipo sobre CORTEX | `governance/team.md` |

### 4.2 Procedimiento al añadir nuevas funciones

Cuando se incorpora una feature significativa al proyecto:

1. Ejecutar `cortex-sync` para actualizar `map/architecture.md` y `map/dependencies.md`
2. Si introduce nuevos comandos o scripts, actualizar `ops/workflows.md`
3. Si introduce nuevas variables de entorno o servicios, actualizar `ops/environment.md`
4. Documentar patrones específicos de la feature en `memory/patterns.md`
5. Si la feature descarta o modifica una decisión previa, actualizar `memory/decisions.md`

### 4.3 Procedimiento al añadir reglas más específicas

Si el equipo decide que el asistente necesita reglas más precisas:

1. **Reglas generales del proyecto** → `cortex/SYSTEM.md`
2. **Reglas específicas de un módulo/área** → `memory/patterns.md`
3. **Ajustes de comportamiento del agente** → `.claude/settings.json` (personal) o `cortex/SYSTEM.md` (equipo)
4. Tras modificar `cortex/SYSTEM.md`, incrementar la versión en el loader (`.claude/CLAUDE.md`)

### 4.4 Versionado del sistema CORTEX

El sistema tiene un número de versión semántica en el loader (`.claude/CLAUDE.md`):

- **MAJOR**: Cambios incompatibles (estructura de CORTEX, comportamiento del asistente)
- **MINOR**: Añadiduras compatibles (nuevas secciones, nuevos comandos)
- **PATCH**: Correcciones, aclaraciones, mejoras editoriales

El asistente debe verificar al inicio si su versión local coincide con la del remoto comparando `.claude/CLAUDE.md`.

---

## 5. Sesiones

### 5.1 Ámbito estrictamente personal

Las sesiones son personales e intransferibles. Cada desarrollador gestiona las suyas:

- `sessions/*/state.md` y `sessions/*/context.md` están en `.gitignore`
- El naming de sesiones queda a criterio individual
- Recomendación de nomenclatura: `[iniciales]-[descripción-breve]` (ej: `dj-fix-auth`, `mr-add-pagination`)

### 5.2 Sin sesiones compartidas en git

No se commitean sesiones personales al repositorio compartido. Si dos desarrolladores necesitan colaborar en la misma tarea:

1. Cada uno crea su propia sesión personal
2. Las decisiones de alcance global se documentan en `memory/decisions.md`
3. No se depende del `context.md` del otro desarrollador para completar el trabajo

---

## 6. Verificación post-tarea (anti-duplicados)

Cuando una tarea finaliza y el asistente ha registrado cambios en `memory/` o `state/`, se debe verificar que no haya duplicados con conocimiento generado por otros miembros del equipo mientras se trabajaba.

### 6.1 Cuándo se ejecuta

Al finalizar la tarea, antes de hacer commit del código + CORTEX, si hay cambios sin commit en `.claude/cortex/memory/` o `.claude/cortex/state/`.

### 6.2 Procedimiento

1. **Obtener cambios remotos:** `git fetch origin`
2. **Detectar si el remoto tiene cambios** en memoria o estado que el local no ha integrado:
   ```
   git log --oneline HEAD..origin/main -- .claude/cortex/memory/ .claude/cortex/state/
   ```
3. **Si NO hay cambios remotos:** no hay riesgo de duplicado. Proceder al commit normal (ver §1).
4. **Si HAY cambios remotos:** ejecutar verificación de duplicados:
   a. Leer el diff remoto: `git diff HEAD..origin/main -- .claude/cortex/memory/ .claude/cortex/state/`
   b. Leer los cambios locales sin commit: `git diff -- .claude/cortex/memory/ .claude/cortex/state/`
   c. Comparar ambas fuentes entrada por entrada
   d. Si dos entradas abordan el **mismo tema** (misma decisión, mismo gotcha, mismo patrón, misma deuda):
      - Fusionarlas en una sola entrada
      - Incluir la información de ambos contextos
      - Añadir nota: `> [FUSIONADO] Combinada con entrada de [autor] desde commit [hash]`
   e. Si las entradas son **temas distintos**: conservar ambas, orden cronológico
   f. Si son **contradictorias**: aplicar reglas de conflicto (§3.1 o §3.2 según tipo de archivo)

### 6.3 Ejemplo

```
Tu decisión local:     "Usamos JWT porque teníamos jsonwebtoken instalado"
Decisión de compañero: "Usamos JWT para autenticación de API"

Resultado fusionado:
## 2026-05-12 Elección de autenticación JWT
**Decisión:** Usamos JWT para autenticación de API porque ya teníamos jsonwebtoken instalado
**Motivo:** Consistencia con el stack existente + evitar dependencias adicionales
**Descartado:** Sessions (requeriría instalar express-session)
**Contexto:** Sesión dj-auth-refactor · Sesión mr-api-integration
> [FUSIONADO] Combinada con entrada de mr desde commit a3f2c1
```

### 6.4 Post-verificación

Tras la verificación y posible fusión:

1. Re-leer los archivos modificados para confirmar integridad (§2.3 de SYSTEM.md)
2. Si se detectaron duplicados, mencionarlo en el mensaje de commit:
   ```
   feat(api): autenticación JWT

   Añade middleware de verificación, endpoints de login/refresh y tests.

   CORTEX: decisions.md, patterns.md
   Duplicados resueltos: fusionada decisión JWT con entrada de mr@a3f2c1
   ```
3. Proceder con el commit estándar (§1)
