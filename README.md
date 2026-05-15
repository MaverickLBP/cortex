# CORTEX — Context-Oriented Runtime Technical Experience

**Persistent project context for AI coding assistants.**

CORTEX is a minimal system that tells the agent what technologies your project uses, how it is structured, what commands to run, and what decisions have been made. A single context file loaded by the agent at session start.

```
project/
├── CLAUDE.md              ← "This project uses CORTEX"
└── .claude/
    ├── commands/
    │   └── cortex-init.md  ← Instructions to generate context.md (optional)
    └── cortex/             ← Everything CORTEX lives here
        ├── SYSTEM.md       ← Agent instructions (do not edit)
        └── context.md      ← Project data (edit this)
```

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash
```

In a specific directory:

```bash
curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash -s -- /path/to/project
```

## Quick start

### Set up context manually

1. Edit `.claude/cortex/context.md` with your project's information
2. The agent automatically loads the context when starting a session
3. When the project changes, update `context.md`

### Or generate it automatically with cortex-init

`cortex-init` scans your project and generates `context.md` from scratch — run it once on first setup:

```
Claude Code:  /cortex-init
OpenCode:     "run cortex-init"
Any agent:    "run cortex-init"
```

The agent reads `package.json`, maps the directory structure, extracts conventions and commands, and writes everything to `context.md`. Review the result and fill in any gaps. Afterwards, `context.md` is maintained automatically — the agent updates it as you work and git syncs it across the team.

## Compatibility

Works with Claude Code, OpenCode, Cursor, GitHub Copilot, and any agent that reads `CLAUDE.md`. CORTEX is one more subdirectory in `.claude/` — compatible with other systems sharing the same space.

## License

MIT — see [LICENSE](./LICENSE).
