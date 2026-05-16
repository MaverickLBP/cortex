# CORTEX — Knowledge layer for AI agents

**A dynamic knowledge system for AI coding assistants.**

CORTEX lives in `.claude/cortex/` and provides your agent with a complete, living map of the project — what every folder contains, what each file does, and where things belong.

## How it works

```
project/
├── CLAUDE.md                    ← "This project uses CORTEX"
└── .claude/
    └── cortex/
        ├── SYSTEM.md            ← Agent behaviour instructions (do not edit)
        ├── MAP.md               ← Knowledge map (generated + maintained)
        ├── commands/
        │   ├── cortex-init.md       ← Project scanner command
        │   └── cortex-view-map.md   ← View map command
        └── scripts/
            └── cortex-init.sh       ← Tree scanner (one-time setup)
```

**MAP.md** is the heart of CORTEX. It documents every directory and every file in the project. The agent consults it to find what it needs and knows exactly where to create new files based on the project's conventions.

## Quick start

### 1. Install CORTEX in your project

```bash
curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash
```

Or copy the `.claude/cortex/` directory manually into your project and add this line to `CLAUDE.md`:

```markdown
This project uses **CORTEX** for its knowledge layer.
→ Load `.claude/cortex/SYSTEM.md` for complete system instructions.
```

### 2. Generate the knowledge map

```
/cortex-init          (Claude Code)
run cortex-init       (OpenCode / any agent)
```

The agent scans the entire project and builds MAP.md automatically.

### 3. View the map anytime

```
/cortex-view-map      (Claude Code)
run cortex-view-map   (OpenCode / any agent)
```

You can filter by section: `/cortex-view-map src/api`

### 4. Work with knowledge

The agent uses MAP.md on every session — finding files, understanding structure, and keeping the map updated as the project evolves.

## Compatibility

- **Claude Code** — Full support
- **OpenCode** — Full support
- **Any agent that reads CLAUDE.md** — Full support

## License

MIT — see [LICENSE](./LICENSE).
