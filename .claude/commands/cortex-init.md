# cortex-init

Realiza una exploración exhaustiva del proyecto y genera el sistema de conocimiento CORTEX completo desde cero.

**Filosofía:** La exploración debe ser sistemática, no intuitiva. Usa las herramientas de búsqueda (`glob`, `grep`, `read`) para descubrir TODO el contenido del proyecto antes de documentar nada. No confíes en tu conocimiento previo del proyecto — el inventario debe ser completo, no muestral.

Sigue estos pasos **en orden, sin saltarte ninguno**.

---

## Fase 1: Inventario completo de archivos

No generes nada todavía. Solo descubre y cataloga.

### 1.1 Inventario global

Ejecuta estos comandos de forma independiente:

1. `glob` con `**/*` para obtener TODOS los archivos del proyecto (excluye `node_modules`, `.git`, `.venv`, `dist`, `build`, `coverage`, `target`, `__pycache__`)
2. `glob` con `**/.*` para archivos ocultos (`.env.example`, `.gitignore`, `.dockerignore`, `.eslintrc*`, `.prettierrc*`, etc.)
3. `glob` con `**/*.{json,yaml,yml,toml,xml,cfg,ini}` para archivos de configuración
4. `glob` con `**/*.{sh,bat,ps1}` para scripts

Guarda los resultados. Vas a necesitarlos para las fases siguientes.

### 1.2 Catalogar por categorías

Con los resultados del inventario, identifica archivos en cada una de estas categorías. Si un archivo encaja en varias, anótalo en todas:

| Categoría | Qué buscar | Cómo verificarlo |
|-----------|-----------|------------------|
| **Config raíz** | package.json, requirements.txt, Cargo.toml, go.mod, pom.xml, composer.json, Gemfile, setup.py, pyproject.toml | `glob` con `*.*` en la raíz |
| **Build/empaquetado** | Dockerfile, docker-compose*.yml, Makefile, webpack/vite/rollup.config.*, .dockerignore | `glob` con nombres conocidos |
| **Linting/formatting** | .eslintrc*, .prettierrc*, .stylelintrc*, biome.json, .golangci.yml, .rubocop.yml | `glob` con `.*rc*` y `.*.config.*` |
| **Type checking** | tsconfig*.json, jsconfig.json, mypy.ini, .mypy.ini | `glob` con `tsconfig*` |
| **CI/CD** | .github/workflows/*, .gitlab-ci.yml, Jenkinsfile, .circleci/config.yml, .travis.yml | `glob` en `.github/`, `.gitlab-ci.yml` |
| **Entorno** | .env, .env.example, .env.*, .envrc, env.yaml | `glob` con `.env*` |
| **Tests** | Archivos en test/, tests/, __tests__/, spec/ o con sufijos .test.*, .spec.*, _test.go | `glob` con `**/test*/**` y `**/*.test.*` |
| **Docs** | README*, docs/, *.md, CHANGELOG*, CONTRIBUTING*, API*.md | `glob` con `**/*.md` |
| **Source** | Código fuente en src/, app/, lib/, cmd/, internal/ (según lenguaje) | Leer directorios raíz |
| **Assets** | public/, static/, assets/, images/, locales/, i18n/, migrations/ | Leer directorios raíz |
| **Scripts** | scripts/, bin/, tools/, *.sh, Makefile, Justfile, Taskfile.yml | `glob` con `scripts/**` |

### 1.3 Árbol de directorios

Usa `read` sobre la raíz del proyecto para obtener la estructura completa. Luego lee cada subdirectorio de primer nivel. Debes poder reconstruir el árbol completo mentalmente.

### 1.4 Lectura de archivos clave

Lee el contenido COMPLETO de:

- **Archivo de dependencias principal** (package.json, requirements.txt, Cargo.toml, etc.)
- **README.md** completo
- **Archivo de entorno** (.env.example o similar)
- **Archivos de CI/CD** (workflows de GitHub, .gitlab-ci.yml, etc.)
- **tsconfig.json** o equivalente (si existe)
- **Dockerfile** (si existe)
- **docker-compose.yml** (si existe)
- **Archivos de linting** (.eslintrc*, .prettierrc*, etc.)

Para configuraciones más pequeñas, usa `read` con límite suficiente para captar el contenido completo.

---

## Fase 2: Documentar arquitectura y mapa

Con el inventario completo, genera los archivos de documentación. Usa el inventario de la Fase 1 como fuente; no vuelvas a explorar.

### 2.1 Genera `.claude/cortex/map/architecture.md` — Arquitectura

Escribe el archivo con esta información **obtenida del inventario**:

- **Nombre y propósito:** del README o del archivo de configuración principal. Si no hay README, deduce el propósito del código.
- **Stack tecnológico:** tabla con TODAS las tecnologías identificadas (lenguaje, framework, base de datos, cola, cache, testing, CI/CD). Versiones exactas.
- **Estructura de directorios:** árbol completo. Cada directorio de primer nivel debe tener UNA línea de descripción de su propósito.
- **Puntos de entrada:** todos los archivos que arrancan algo (main, index, app, server, CLI). Para cada uno, qué hace.
- **Flujo general:** describe cómo fluye una petición/comando/acción típica. Si hay múltiples flujos (API web + CLI + worker), documenta cada uno.
- **Módulos principales:** lista con el nombre de cada módulo y una línea de propósito. Esto debe coincidir 1:1 con los archivos que generarás en 2.3.

### 2.2 Genera `.claude/cortex/map/dependencies.md` — Dependencias

Para **CADA** dependencia listada en el archivo de dependencias principal. Sin filtros:

| Dependencia | Versión | Para qué se usa | Dev? | Notas |
|-------------|---------|-----------------|------|-------|
| express | ^4.18.0 | Framework HTTP | No | — |
| vitest | ^1.0.0 | Testing | Sí | — |

**Reglas:**
- Incluye TODAS, tanto producción como desarrollo. "Principal" no significa filtrado — todas son relevantes.
- Si no sabes para qué se usa una dependencia, escribe `[por determinar]` y una nota de por qué crees que está.
- Si el proyecto no tiene un archivo de dependencias (ej. scripts sueltos), indícalo explícitamente.

### 2.3 Genera `.claude/cortex/map/modules/[nombre].md` — Módulos

Por **cada directorio de código fuente** en src/, app/, lib/, cmd/, internal/ o equivalente:

1. **Crea un archivo** en `.claude/cortex/map/modules/` con el nombre del directorio
2. **Documenta:**
   - **Propósito:** qué hace este módulo (deducido de los archivos que contiene)
   - **Archivos principales:** lista de archivos dentro del módulo, con una línea de descripción cada uno
   - **Lo que expone:** API endpoints, funciones exportadas, componentes, clases públicas
   - **Dependencias internas:** de qué otros módulos del proyecto depende
   - **Dependencias externas:** qué librerías usa específicamente de las listadas en dependencies.md

**Regla de cobertura obligatoria:** TODO directorio de código fuente debe tener su archivo de módulo. Si un directorio no es un módulo funcional (ej. `utils/`, `helpers/`, `types/`, `constants/`, `middleware/`), documéntalo igual pero márcalo como `**[compartido/utilidad]**` en el propósito. No lo omitas.

**Para monorepos o proyectos multi-lenguaje:** crea un archivo por cada área funcional, no por cada subdirectorio — pero asegúrate de que todas las áreas quedan cubiertas.

---

## Fase 3: Documentar operaciones

### 3.1 Genera `.claude/cortex/ops/environment.md` — Entorno

Usando el inventario de la Fase 1:

- **Variables de entorno:** revisa `.env.example`, `.env`, `docker-compose.yml`, archivos de CI/CD, Y **busca en el código fuente** menciones a variables de entorno (`process.env.`, `os.getenv`, `env()`, `Deno.env`, etc.) usando `grep`.
- Para cada variable: nombre, requerida (Sí/No), descripción, valor por defecto
- **Servicios externos:** bases de datos, APIs, colas — extraídos de docker-compose, CI config, y el código
- **Diferencias entre entornos:** si hay `.env.dev`, `.env.prod`, o configuraciones diferenciadas

### 3.2 Genera `.claude/cortex/ops/workflows.md` — Comandos

Usando el inventario de la Fase 1:

- **Instalación:** del README o scripts detectados
- **Desarrollo:** comandos de start/watch/hot-reload (de package.json scripts, Makefile, etc.)
- **Tests:** comandos de test, cobertura, linting
- **Build:** comandos de compilación/empaquetado
- **Deploy:** comandos de deploy si existen (de CI/CD, Makefile, scripts)
- **Otros:** cualquier comando relevante (migraciones, seed, formateo, etc.)

**Para cada comando, incluye el comando exacto** (ej. `npm run dev`, `make test`, `docker compose up`).

---

## Fase 4: Inicializar archivos de memoria y estado

Crea estos archivos con solo su cabecera y formato de ejemplo, listos para recibir entradas durante el trabajo diario. Si ya existen, no los sobreescribas — solo añade los que falten:

- `.claude/cortex/memory/decisions.md`
- `.claude/cortex/memory/gotchas.md`
- `.claude/cortex/memory/patterns.md`
- `.claude/cortex/state/tech-debt.md`
- `.claude/cortex/state/scope.md`
- `.claude/cortex/sessions/index.md` (con tabla vacía y estado actual en `—`)

---

## Fase 5: Verificación de cobertura

Antes de informar al usuario, ejecuta estas comprobaciones en orden.

### 5.1 Integridad del inventario

- Repasa la tabla de categorías de la Fase 1.2. ¿Tienes archivos identificados en cada categoría? Si alguna categoría tiene 0 archivos, verifica activamente que realmente no exista nada (no asumas).
- ¿Los directorios `map/modules/` y `sessions/` existen?

### 5.2 Cobertura de código fuente

1. Usa `glob` para listar TODOS los directorios de código fuente (src/, app/, lib/, etc.)
2. Usa `glob` para listar los archivos en `.claude/cortex/map/modules/`
3. Compara ambas listas. Si falta algún directorio, créalo ahora.

### 5.3 Cobertura de dependencias

1. Cuenta las dependencias en el archivo de dependencias original
2. Cuenta las filas en `.claude/cortex/map/dependencies.md`
3. Deben coincidir. Si falta alguna, añádela.

### 5.4 Calidad del contenido

Lee CADA archivo generado:
- ¿Todos los campos tienen contenido? Si falta información, usa **`[por documentar]`** en lugar de dejar `—` o espacios en blanco.
- ¿Hay placeholders `—` del template original? Reemplázalos con contenido real o `[por documentar]`.
- Confirma que los enlaces a rutas de archivos dentro del proyecto son correctos.

---

## Fase 6: Resumen final

Muestra al usuario un resumen estructurado:

```
CORTEX inicializado — resumen
─────────────────────────────
Stack: [lenguaje/framework principal] + [base de datos] + [otros]
Archivos generados: [lista de archivos]
Módulos documentados: [N] directorios de código fuente
Dependencias documentadas: [N] en total ([N] producción, [N] desarrollo)
Pendientes [por documentar]: [N] campos
```

Además:
- Lista los archivos generados
- Menciona cualquier categoría de la Fase 1.2 que esté vacía (para que el usuario sepa que no existe)
- Si hay `[por documentar]`, explica brevemente qué falta y por qué
- Sugerencia de próximo paso: crear sesión con `cortex-session-new`
