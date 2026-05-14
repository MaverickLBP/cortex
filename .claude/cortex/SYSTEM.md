# CORTEX — System Instructions

> Archivo de sistema. **No modificar manualmente.**
> Si necesitas cambiar el contexto del proyecto, edita `context.md`.
> Versión: 2.0.0

---

## 1. Carga de contexto

Al iniciar la sesión, el asistente DEBE cargar `.claude/cortex/context.md` y usar su contenido como referencia del proyecto. Este archivo contiene el stack tecnológico, estructura de directorios, convenciones, comandos y notas del proyecto.

## 2. Uso del contexto

- **Stack:** usa las tecnologías listadas. No propongas añadir dependencias que ya están cubiertas por el stack existente.
- **Estructura:** ubica los archivos según el mapa de directorios antes de explorar con herramientas de búsqueda. Esto evita lecturas innecesarias del sistema de archivos.
- **Convenciones:** el código nuevo debe seguir los patrones y reglas documentadas.
- **Comandos:** usa los comandos exactos para tareas comunes (dev, test, build, lint, etc.). No improvises flags o rutas.
- **Notas:** consulta esta sección antes de trabajar en áreas con gotchas o decisiones documentadas.

## 3. Mantenimiento del contexto

El asistente DEBE mantener `context.md` actualizado de forma autónoma:

| Situación | Acción |
|-----------|--------|
| El stack, estructura o comandos no reflejan la realidad del proyecto | Actualizar la sección correspondiente |
| Se descubre un gotcha, trampa o comportamiento no documentado | Añadir entrada en **Notas** con fecha |
| Se toma una decisión técnica no obvia (arquitectura, librería, approach) | Añadir entrada en **Notas** con fecha, motivo y alternativas descartadas |
| Se detecta un patrón recurrente en 2+ lugares del código | Documentarlo en **Convenciones** |

No es necesario anunciar estas actualizaciones. El asistente las realiza en silencio como parte de su operación normal.

## 4. Compatibilidad con otros sistemas

CORTEX vive exclusivamente en `.claude/cortex/`. Otros sistemas pueden coexistir en `.claude/` sin interferencias. Cada sistema tiene su propio `SYSTEM.md` que el asistente cargará según las referencias del `CLAUDE.md` raíz.

## 5. Estructura del sistema

```
.claude/cortex/
├── SYSTEM.md       ← Este archivo. Instrucciones de comportamiento.
└── context.md      ← Datos del proyecto. Único archivo editable.
```
