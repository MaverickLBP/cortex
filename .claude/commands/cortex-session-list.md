# cortex-session-list

Muestra el estado de todas las sesiones de trabajo del proyecto.

## Pasos

1. **Leer `.claude/cortex/sessions/index.md`** y los `state.md` de las sesiones EN PROGRESO.

2. **Mostrar la información** agrupada por estado:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SESIONES DEL PROYECTO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▶ ACTIVA
  payment-api
  Siguiente paso: Implementar webhook de confirmación

⏸ EN PROGRESO (pausadas)
  auth-refactor
  Siguiente paso: Revisar tests en /tests/auth/

✓ COMPLETADAS
  bug-login (2025-01-14)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

3. **Si no hay sesiones**, informar al usuario y recordarle que puede crear una con el comando `cortex-session-new` (o diciendo "Nueva sesión: [nombre]").

4. **Si hay varias EN PROGRESO**, recordar que se puede cambiar de contexto con `cortex-session-load [nombre]` (o "Carga sesión [nombre]").
