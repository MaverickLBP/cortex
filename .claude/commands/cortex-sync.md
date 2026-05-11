# cortex-sync

Re-sincroniza el conocimiento estructural de CORTEX tras cambios en el proyecto. Es una versión incremental de `cortex-init`: no regenera desde cero, sino que detecta diferencias entre lo documentado y el estado actual del proyecto.

**Filosofía:** No asumas que nada cambió. Usa `glob`, `grep` y `read` para verificar cada área activamente. Si no encuentras diferencias, confírmalo explícitamente en el informe final.

Puede invocarse como `/cortex-sync` en Claude Code, o por lenguaje natural ("Sincroniza CORTEX", "actualiza el mapa del proyecto") en cualquier plataforma.

---

## Fase 1: Detectar cambios

Antes de modificar nada, descubre qué cambió realmente. Usa el archivo documentado como referencia y compáralo con el estado actual.

### 1.1 Arquitectura (`map/architecture.md`)

Lee el archivo actual y compáralo con la realidad:

| Pregunta | Cómo verificarlo |
|----------|------------------|
| ¿El stack tecnológico sigue siendo el mismo? | Revisa package.json, requirements.txt, etc. ¿Versiones cambiaron? ¿Nuevas tecnologías? |
| ¿La estructura de directorios cambió? | `read` sobre la raíz y directorios de primer nivel. ¿Nuevas carpetas relevantes? ¿Carpetas que ya no existen? |
| ¿Hay nuevos puntos de entrada? | Busca nuevos archivos main, index, app, server, CLI en las ubicaciones documentadas |
| ¿El flujo general sigue siendo válido? | Si hubo cambios arquitectónicos importantes, actualiza la descripción |

### 1.2 Dependencias (`map/dependencies.md`)

Lee el archivo de dependencias actual (package.json, requirements.txt, etc.) y compáralo línea por línea con la tabla documentada:

- ¿Dependencias añadidas? → Añádelas a la tabla
- ¿Dependencias eliminadas? → Márcalas como `[ELIMINADA]` (no las borres, pueden tener valor histórico)
- ¿Versiones cambiadas? → Actualiza la versión y añade nota del cambio

### 1.3 Módulos (`map/modules/`)

Usa `glob` para listar los directorios de código fuente actuales y compáralos con los archivos en `map/modules/`:

- ¿Nuevos directorios de código fuente? → Crea su archivo de módulo (con el mismo formato que en cortex-init)
- ¿Directorios que ya no existen? → Marca el módulo como `[OBSOLETO]` en el archivo (no lo borres)
- ¿Módulos cuyo contenido cambió significativamente? → Actualiza archivos principales, exposures y dependencias

**Regla de cobertura:** debe haber 1:1 entre directorios de código fuente y archivos de módulo, igual que en cortex-init.

### 1.4 Entorno y workflows (`ops/`)

| Pregunta | Cómo verificarlo |
|----------|------------------|
| ¿Nuevas variables de entorno? | Busca `process.env.`, `os.getenv`, `env()` en el código fuente con `grep`. Compara con la tabla documentada |
| ¿Nuevos comandos? | Revisa scripts en package.json, Makefile, etc. ¿Hay comandos que no están documentados? |
| ¿Servicios externos cambiaron? | Revisa docker-compose.yml, CI/CD, etc. |

---

## Fase 2: Actualizar

Con la lista de cambios detectados en la Fase 1, aplica las actualizaciones necesarias:

1. **architecture.md** — solo las secciones que cambiaron
2. **dependencies.md** — añade/actualiza filas según 1.2
3. **modules/** — crea nuevos, marca obsoletos, actualiza existentes
4. **environment.md** y **workflows.md** — actualiza según 1.4

**Importante:** no modifiques secciones que no hayan cambiado. Si todo está igual que en la documentación, confírmalo en el informe.

---

## Fase 3: Verificación

Antes de informar, ejecuta estas comprobaciones:

### 3.1 Integridad

- Lee cada archivo modificado. ¿Todos los campos tienen contenido? Usa `[por documentar]` si falta información.
- ¿Hay `—` del template original donde debería haber contenido real? Reemplázalo.

### 3.2 Cobertura de módulos

Usa `glob` para listar los directorios de código fuente y los archivos de módulos. Deben coincidir 1:1.

### 3.3 Cobertura de dependencias

Cuenta las dependencias en el archivo de dependencias del proyecto y las filas en `dependencies.md`. Deben coincidir (las marcadas como `[ELIMINADA]` cuentan como presentes).

---

## Qué NO tocar

- `.claude/cortex/memory/` — El conocimiento experiencial acumulado no se regenera
- `.claude/cortex/sessions/` — El historial de sesiones no se modifica
- `.claude/cortex/state/` — Ni `tech-debt.md` ni `scope.md`; se gestionan autónomamente (ver §2.2 de CLAUDE.md)

---

## Fase 4: Informe final

Muestra al usuario un resumen estructurado:

```
CORTEX sync — resumen
─────────────────────
Archivos actualizados: [lista]
Módulos añadidos: [N]
Módulos marcados obsoletos: [N]
Dependencias añadidas/eliminadas: [+N / -N]
Sin cambios: [áreas verificadas sin diferencias]
Inconsistencias detectadas: [si las hay]
```

Si no hubo cambios en ninguna área, confírmalo en una línea: *"Sin cambios detectados, señor. Todo sincronizado."*
