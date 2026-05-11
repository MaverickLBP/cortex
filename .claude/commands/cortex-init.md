# cortex-init

Realiza una exploración exhaustiva del proyecto y genera el sistema de conocimiento CORTEX completo desde cero. Sigue estos pasos en orden.

## 1. Exploración inicial

Examina sin generar nada todavía:
- Estructura de directorios completa (2-3 niveles)
- Archivos de configuración en la raíz (package.json, requirements.txt, Cargo.toml, pom.xml, go.mod, composer.json, etc.)
- README y cualquier documentación existente
- Archivos de entorno (.env.example, docker-compose.yml, Dockerfile, etc.)
- Configuración de CI/CD si existe (.github/workflows/, .gitlab-ci.yml, etc.)
- Estructura de tests
- Archivos de configuración de herramientas (eslint, prettier, tsconfig, etc.)

## 2. Genera .claude/cortex/map/architecture.md

Documenta:
- Nombre del proyecto y propósito en una frase
- Stack tecnológico con versiones exactas
- Estructura de directorios con descripción de cada carpeta relevante
- Puntos de entrada principales (main, index, app, server, etc.)
- Flujo general de la aplicación (cómo fluye una petición/acción típica)
- Capas o módulos principales identificados

## 3. Genera .claude/cortex/map/dependencies.md

Para cada dependencia principal (no todas, las relevantes):
- Nombre y versión
- Para qué se usa concretamente en este proyecto
- Si hay algo crítico a saber sobre su uso aquí

## 4. Genera .claude/cortex/map/modules/[nombre].md para cada módulo relevante

Un archivo por cada módulo o área funcional importante. Cada uno contiene:
- Propósito del módulo
- Archivos principales
- Lo que expone (API, funciones exportadas, componentes, etc.)
- De qué depende internamente

## 5. Genera .claude/cortex/ops/environment.md

Documenta:
- Variables de entorno requeridas y para qué sirve cada una
- Variables opcionales con sus valores por defecto
- Diferencias conocidas entre entornos (dev / staging / prod)
- Servicios externos requeridos (bases de datos, APIs, etc.)

## 6. Genera .claude/cortex/ops/workflows.md

Documenta:
- Comandos de instalación
- Comandos de desarrollo (start, watch, etc.)
- Comandos de build y deploy
- Comandos de test
- Cualquier proceso manual no obvio

## 7. Inicializa archivos de memoria y estado con cabeceras vacías

Crea estos archivos con solo su cabecera, listos para recibir entradas:
- .claude/cortex/memory/decisions.md
- .claude/cortex/memory/gotchas.md
- .claude/cortex/memory/patterns.md
- .claude/cortex/state/tech-debt.md
- .claude/cortex/state/scope.md
- .claude/cortex/sessions/index.md (con tabla vacía)

## 8. Resumen final

Muestra al usuario:
- Lista de archivos generados
- Stack detectado en una línea
- Cualquier área donde no hayas podido obtener información suficiente
- Sugerencia de próximo paso (crear sesión con `cortex-session-new` o diciendo "Nueva sesión: [nombre]")
