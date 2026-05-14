# CORTEX — Context-Oriented Runtime Technical Experience

**Persistent project context for AI coding assistants.**

CORTEX is a minimal system that tells the agent what technologies your project uses, how it is structured, what commands to run, and what decisions have been made. A single context file loaded by the agent at session start.

```
project/
├── CLAUDE.md              ← "This project uses CORTEX"
└── .claude/
    └── cortex/             ← Everything CORTEX lives here
        ├── SYSTEM.md       ← Agent instructions (do not edit)
        └── context.md      ← Project data (edit this)
```

## Installation

```bash
curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash
```

In a specific directory:

```bash
curl -sSL https://github.com/MaverickLBP/cortex/raw/main/install.sh | bash -s -- /path/to/project
```

## Usage

1. Edit `.claude/cortex/context.md` with your project's information
2. The agent automatically loads the context when starting a session
3. When the project changes, update `context.md`

## Compatibility

Works with Claude Code, OpenCode, Cursor, GitHub Copilot, and any agent that reads `CLAUDE.md`. CORTEX is one more subdirectory in `.claude/` — compatible with other systems sharing the same space.

## License

MIT — see [LICENSE](./LICENSE).
