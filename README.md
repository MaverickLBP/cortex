# CORTEX — Context-Oriented Runtime Technical Experience

**Contexto persistente del proyecto para asistentes de código con IA.**

CORTEX es un sistema mínimo que le dice al agente qué tecnologías usa tu proyecto, cómo está estructurado, qué comandos ejecutar y qué decisiones se han tomado. Un solo archivo de contexto que el agente carga al iniciar la sesión.

```
proyecto/
├── CLAUDE.md              ← "Este proyecto usa CORTEX"
└── .claude/
    └── cortex/             ← Todo CORTEX está aquí
        ├── SYSTEM.md       ← Instrucciones al agente (no tocar)
        └── context.md      ← Datos del proyecto (editar)
```

## Instalación

```bash
curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash
```

En un directorio específico:

```bash
curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash -s -- /ruta/al/proyecto
```

## Uso

1. Edita `.claude/cortex/context.md` con la información de tu proyecto
2. El agente carga automáticamente el contexto al iniciar sesión
3. Cuando el proyecto cambie, actualiza `context.md`

## Compatibilidad

Funciona con Claude Code, OpenCode, Cursor, GitHub Copilot y cualquier agente que lea `CLAUDE.md`. CORTEX es un subdirectorio más en `.claude/` — compatible con otros sistemas que usen el mismo espacio.

## Licencia

MIT — ver [LICENSE](./LICENSE).
