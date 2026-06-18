# CORTEX — Knowledge layer for AI agents

**A dynamic knowledge system for AI coding assistants.**  
Zero dependencies. Markdown + bash. Native enforcement for Claude Code and OpenCode.

CORTEX lives in `.cortex/` and provides your agent with a complete, living map of the project — what every folder contains, what each file does, and where things belong. It uses each agent's native mechanisms to guarantee the knowledge is loaded at every session start.

---

## How it works

```
project/
├── .cortex/                     ← Agent-agnostic knowledge (always committed)
│   ├── SYSTEM.md                ← Agent behaviour instructions (do not edit)
│   ├── MAP.md                   ← Knowledge map (auto-generated + maintained)
│   ├── commands/                ← Command templates (copied to agent dirs by installer)
│   │   ├── cortex-init.md
│   │   ├── cortex-update.md
│   │   └── cortex-view-map.md
│   └── scripts/
│       └── cortex-init.sh       ← Tree scanner
│
├── .claude/                     ← Claude Code only
│   ├── settings.json            ← Registers cortex-session.sh hook (commit this)
│   ├── hooks/
│   │   └── cortex-session.sh   ← Injects SYSTEM.md + MAP.md at session start
│   └── commands/               ← Slash commands for Claude Code
│
├── .opencode/                   ← OpenCode only
│   └── commands/               ← Slash commands for OpenCode
│
└── opencode.json                ← OpenCode only: auto-loads SYSTEM.md + MAP.md
```

**MAP.md** is the heart of CORTEX. It documents every directory and every file in the project — including a **Tech Stack** table with detected technologies and versions. The agent consults it to find what it needs and knows exactly where to create new files based on the project's conventions.

### Enforcement mechanism

- **Claude Code**: A `SessionStart` hook (`cortex-session.sh`) injects SYSTEM.md content and the order to load MAP.md as `additionalContext` — no passive CLAUDE.md needed. The hook also supports workspace mode (see below).
- **OpenCode**: `opencode.json` → `instructions` auto-loads `.cortex/SYSTEM.md` and `.cortex/MAP.md` at every session start.

Both agents use `/cortex-init`, `/cortex-update`, and `/cortex-view-map` as slash commands.

---

## Quick start

### 1. Install CORTEX in your project

Install in the current directory (interactive — asks which agent to configure):

```bash
curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh | bash
```

Or specify a project path and agent directly:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh) --agent claude /path/to/project
bash <(curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh) --agent opencode /path/to/project
bash <(curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install.sh) --agent both /path/to/project
```

From a local copy (no download):

```bash
bash install.sh --source /path/to/cortex --agent claude /path/to/project
```

**Migrating from v3?** The installer detects the old `.claude/cortex/` layout and automatically moves the knowledge to `.cortex/` (MAP.md is preserved).

**After installing for Claude Code:** commit `.claude/settings.json` — it registers the hook that enforces CORTEX at session start. Per-user overrides go in `.claude/settings.local.json` (gitignored).

### 2. Generate the knowledge map

```
/cortex-init
```

The agent scans the entire project, detects the tech stack, and builds MAP.md automatically.

### 3. Update the map as the project evolves

```
/cortex-update
```

Unlike `cortex-init`, this command **preserves existing content** — it only adds new entries, removes deleted ones, and detects missing sections (e.g. Tech Stack). Run it after adding, moving, or removing files.

### 4. View the map anytime

```
/cortex-view-map
/cortex-view-map src/api    ← filter by path or keyword
```

### 5. Workspace bridge (multi-project, Claude Code only)

If you work with a VS Code multi-root workspace (`.code-workspace`), install the workspace bridge to enable workspace mode in the hook:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/MaverickLBP/cortex/main/install-workspace-bridge.sh) --file workspace.code-workspace
```

Or from a local copy:

```bash
bash install-workspace-bridge.sh --file /path/to/workspace.code-workspace
```

This creates a `.cortex-workspace.json` marker at the workspace root. The `cortex-session.sh` hook in each project detects it and enters workspace mode — injecting a list of all CORTEX-enabled projects and ordering the agent to load the MAP.md of whichever project is being worked on.

> **Note:** Workspace mode is activated by the hook in the primary cwd project. Open your session from a project that has CORTEX installed for Claude Code.

---

## Project resources

| Resource | Description |
|----------|-------------|
| [`install.sh`](./install.sh) | Install CORTEX in a single project (agent selection, migration) |
| [`install-workspace-bridge.sh`](./install-workspace-bridge.sh) | Generate `.cortex-workspace.json` for multi-project workspaces (Claude Code) |
| [CHANGELOG.md](./CHANGELOG.md) | Version history following Keep a Changelog |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | How to report bugs, suggest features, and submit PRs |
| [docs/](./docs/) | Web landing page (GitHub Pages) |
| [LICENSE](./LICENSE) | MIT License with non-commercial redistribution clause |

---

## Compatibility

- **Claude Code** — Full support via `SessionStart` hook + slash commands
- **OpenCode** — Full support via `opencode.json` instructions + slash commands

---

## License

MIT with non-commercial redistribution — see [LICENSE](./LICENSE).
