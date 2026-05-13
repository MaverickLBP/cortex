# cortex-preflight

Realiza una revisión del conocimiento relevante en CORTEX antes de comenzar una tarea compleja. El usuario habrá descrito en qué va a trabajar.

Puede invocarse como `/cortex-preflight` en Claude Code, o por lenguaje natural ("Preflight", "revisión previa", "preparación") en cualquier plataforma.

## Pasos

0. **Verificación de frescura remota** — Antes de nada, comprueba que el conocimiento local está al día:
   - Ejecuta `git fetch origin` para obtener referencias remotas
   - Ejecuta `git log --oneline HEAD..origin/main -- .claude/` para detectar cambios en CORTEX remotos no integrados
   - Si hay cambios: **ADVIERTE al usuario** con el listado de commits que faltan por integrar
   - Si no hay cambios: silencioso, continúa

1. **Gotchas relevantes** — Revisa `.claude/cortex/memory/gotchas.md`
   ¿Hay trampas conocidas en el área donde se va a trabajar o en las dependencias involucradas? Si las hay, adviértelas antes de empezar.

2. **Decisiones relacionadas** — Revisa `.claude/cortex/memory/decisions.md`
   ¿Hay decisiones ya tomadas que afecten a esta tarea? ¿Se ha descartado algo que podría parecer una buena idea? Recuérdalas.

3. **Deuda técnica relacionada** — Revisa `.claude/cortex/state/tech-debt.md`
   ¿Hay deuda técnica en el área afectada? ¿Esta tarea podría resolverla o podría empeorarla?

4. **Patrones del proyecto** — Revisa `.claude/cortex/memory/patterns.md`
   ¿Qué patrones debe seguir el código nuevo para ser consistente con el proyecto?

5. **Verificación de scope** — Resume en puntos concretos exactamente qué se va a hacer y qué queda fuera. Esto establece el alcance antes de empezar.

## Formato de respuesta

Presenta solo lo que sea realmente relevante para la tarea específica. Si no hay nada en alguna categoría, no la menciones. Sé conciso: esto es una revisión previa, no un informe completo.

Si todo está despejado, confírmalo en una línea y ofrece empezar.
