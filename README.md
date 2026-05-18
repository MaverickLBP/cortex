# CORTEX — Knowledge layer for AI agents

**A dynamic knowledge system for AI coding assistants.**  
Zero dependencies. Markdown + bash. Works with Claude Code, OpenCode, and any agent that reads `CLAUDE.md`.

CORTEX lives in `.claude/cortex/` and provides your agent with a complete, living map of the project — what every folder contains, what each file does, and where things belong.

---

## How it works

```
project/
├── CLAUDE.md                    ← "This project uses CORTEX"
└── .claude/
    └── cortex/
        ├── SYSTEM.md            ← Agent behaviour instructions (do not edit)
        ├── MAP.md               ← Knowledge map (auto-generated + maintained)
        ├── commands/
        │   ├── cortex-init.md       ← First-run project scanner
        │   ├── cortex-update.md     ← Incremental map updater
        │   └── cortex-view-map.md   ← View map command
        └── scripts/
            └── cortex-init.sh       ← Tree scanner (one-time setup)
```

**MAP.md** is the heart of CORTEX. It documents every directory and every file in the project — including a **Tech Stack** table with detected technologies and versions. The agent consults it to find what it needs and knows exactly where to create new files based on the project's conventions.

---

## Quick start

### 1. Install CORTEX in your project

Install in the current directory:

```bash
curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash
```

Or specify a project path directly:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh) /path/to/project
```

With no arguments, `install.sh` prompts for the project path interactively. Use `--source` to install from a local copy (no download):

```bash
bash install.sh --source /path/to/cortex /path/to/project
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

The agent scans the entire project, detects the tech stack, and builds MAP.md automatically.

### 3. Update the map as the project evolves

```
/cortex-update        (Claude Code)
run cortex-update     (OpenCode / any agent)
```

Unlike `cortex-init`, this command **preserves existing content** — it only adds new entries, removes deleted ones, and detects missing sections (e.g. Tech Stack). Run it after adding, moving, or removing files.

### 4. View the map anytime

```
/cortex-view-map      (Claude Code)
run cortex-view-map   (OpenCode / any agent)
```

You can filter by section: `run cortex-view-map src/api`

### 5. Workspace bridge (multi-project)

If you work with a VS Code multi-root workspace (`.code-workspace`), generate a bridge `CLAUDE.md` that routes context to each project's CORTEX:

```bash
bash install-workspace-bridge.sh --file /path/to/workspace.code-workspace
```

Run without arguments for interactive mode. The bridge shows CORTEX status per project and instructs the agent to load the correct `SYSTEM.md` based on context.

---

## Project resources

| Resource | Description |
|----------|-------------|
| [`install.sh`](./install.sh) | Install CORTEX in a single project (interactive or direct path) |
| [`install-workspace-bridge.sh`](./install-workspace-bridge.sh) | Generate a multi-project workspace bridge from `.code-workspace` |
| [CHANGELOG.md](./CHANGELOG.md) | Version history following Keep a Changelog |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | How to report bugs, suggest features, and submit PRs |
| [docs/](./docs/) | Web landing page (GitHub Pages) |
| [LICENSE](./LICENSE) | MIT License with non-commercial redistribution clause |

---

## Compatibility

- **Claude Code** — Full support (slash commands `/cortex-init`, `/cortex-update`, `/cortex-view-map`)
- **OpenCode** — Full support (`run cortex-init`, `run cortex-update`, `run cortex-view-map`)
- **Any agent that reads CLAUDE.md** — Full support

---

## License

MIT with non-commercial redistribution — see [LICENSE](./LICENSE).
