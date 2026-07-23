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
│   ├── MAP.md                   ← Knowledge map (root index; auto-generated + maintained)
│   ├── maps/                    ← Per-area sub-maps (large projects only — see below)
│   │   ├── index.json           ← Manifest: area root → sub-map file, per-area file counts
│   │   └── <area>.md            ← One sub-map per area, e.g. src__api.md
│   ├── commands/                ← Command templates (copied to agent dirs by installer)
│   │   ├── cortex-init.md
│   │   ├── cortex-update.md
│   │   └── cortex-view-map.md
│   └── scripts/
│       ├── cortex-init.sh       ← Tree scanner (flat listing)
│       ├── cortex-scan.sh       ← Gitignore-aware file/dir scanner
│       └── cortex-areas.sh      ← Scale-adaptive area partitioner + index.json writer
│
├── .claude/                     ← Claude Code only
│   ├── settings.json            ← Registers CORTEX hooks (commit this)
│   ├── hooks/
│   │   ├── cortex-session.sh       ← SessionStart: injects SYSTEM.md + full MAP.md content
│   │   ├── cortex-file-change.sh   ← PostToolUse: reminds to update MAP.md on file creation/removal
│   │   ├── cortex-subagent.sh      ← SubagentStart: gives subagents CORTEX context
│   │   └── cortex-map-load.sh      ← PreToolUse: Grep/Glob discovery reminder + Write placement reminder
│   └── commands/               ← Slash commands for Claude Code
│
├── .opencode/                   ← OpenCode only
│   └── commands/               ← Slash commands for OpenCode
│
└── opencode.json                ← OpenCode only: auto-loads SYSTEM.md + MAP.md
```

**MAP.md** is the heart of CORTEX. It documents every directory and every file in the project — including a **Tech Stack** table with detected technologies and versions. The agent consults it to find what it needs and knows exactly where to create new files based on the project's conventions.

**Flat vs hierarchical, by scale.** Small and medium projects stay **flat**: `MAP.md` alone documents every file directly, and there is no `.cortex/maps/` directory at all — nothing extra to load. Once a project crosses a file-count threshold, `cortex-init`/`cortex-update` partition it into **areas** (`cortex-areas.sh`, scale-adaptive: splits oversized directories, promotes subtrees, collapses pass-through chains, rolls stragglers into `_misc`). In that hierarchical mode, `MAP.md` becomes a lightweight **index** that is always in context, each area gets its own `.cortex/maps/<area>.md` loaded **on demand**, and `.cortex/maps/index.json` is the manifest resolving a path to its area's sub-map (longest-root-prefix match). This keeps the always-loaded context cost flat regardless of project size, while every file is still documented somewhere.

### Enforcement mechanism

- **Claude Code**: four hooks provide active enforcement, no passive CLAUDE.md needed.
  - `cortex-session.sh` (`SessionStart`) injects SYSTEM.md content and the **full content of MAP.md** as `additionalContext` — the agent doesn't need to read the file separately. The hook also supports workspace mode (see below).
  - `cortex-file-change.sh` (`PostToolUse`) reminds the agent to update MAP.md the moment it creates a file the map doesn't reference, deletes a documented file with a local `rm`, or moves/renames a file with a local `mv`. Detection is local only — `git rm`/`git mv` are not tracked; the map is kept in sync in reaction to local filesystem changes, not git commands. The reminder reaches whoever made the change, at that moment — keeping the map in sync is the actor's responsibility, not a later pass. Silent for undocumented/scratch deletions, plain edits, excluded paths, and non-CORTEX directories.
  - `cortex-map-load.sh` (`PreToolUse`, on `Grep`/`Glob`/`Write`) is the safety net for hierarchical projects: before a blind `Grep`/`Glob`, it reminds the agent to check `.cortex/maps/index.json` and read the relevant sub-map first instead of searching blind; before a `Write` to a new path, it reminds the agent to place the file per MAP.md's documented conventions and keep the map in sync. Silent on flat projects (no `.cortex/maps/` directory) and on non-CORTEX paths.
  - `cortex-subagent.sh` (`SubagentStart`) injects a short CORTEX note into subagents, which never receive SessionStart context on their own.
- **OpenCode**: `opencode.json` → `instructions` auto-loads `.cortex/SYSTEM.md` and `.cortex/MAP.md` at every session start. OpenCode has no hook mechanism at all — there is no PreToolUse-equivalent safety net — so `SYSTEM.md` §2.5's standing instructions (consult `index.json`, read the right sub-map before searching, place files per convention, update the correct sub-map after a change) are the **entire** enforcement mechanism for hierarchical projects on OpenCode, not a supplement to it.

Both agents use `/cortex-init`, `/cortex-update`, and `/cortex-view-map` as slash commands. Note: OpenCode has no hook mechanism, so it can't get an *active* reminder at the exact moment a file is created/deleted/moved the way Claude Code does. The same three situations are still covered, though — `SYSTEM.md` §2.3 ("Updating MAP.md") already lists them agent-agnostically, and since `opencode.json → instructions` reloads the full `SYSTEM.md` every session, that table is always in an OpenCode agent's context. The gap is the trigger mechanism (event-driven vs. standing instruction), not which situations call for a MAP.md update.

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

**After installing for Claude Code:** commit `.claude/settings.json` — it registers the hook that enforces CORTEX at session start. Per-user overrides go in `.claude/settings.local.json` (gitignored).

### 2. Generate the knowledge map

```
/cortex-init
```

> Works the same in Claude Code and OpenCode — type the slash command in your agent's chat.

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
| [`install.sh`](./install.sh) | Install CORTEX in a single project (agent selection) |
| [`install-workspace-bridge.sh`](./install-workspace-bridge.sh) | Generate `.cortex-workspace.json` for multi-project workspaces (Claude Code) |
| [CHANGELOG.md](./CHANGELOG.md) | Version history following Keep a Changelog |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | How to report bugs, suggest features, and submit PRs |
| [docs/](./docs/) | Web landing page (GitHub Pages) |
| [LICENSE](./LICENSE) | MIT License with non-commercial redistribution clause |

---

## Compatibility

| Agent | Enforcement | Commands |
|---|---|---|
| **Claude Code** | `SessionStart` hook injects SYSTEM.md + full MAP.md content; `PostToolUse` hook reminds to update MAP.md on file changes; `PreToolUse` hook nudges sub-map discovery on Grep/Glob and placement on Write; `SubagentStart` hook briefs subagents | `/cortex-init`, `/cortex-update`, `/cortex-view-map` |
| **OpenCode** | `opencode.json` → `instructions` auto-loads SYSTEM.md + MAP.md; no hooks — SYSTEM.md's standing instructions (§2.5) are the full mechanism for hierarchical (large) projects | `/cortex-init`, `/cortex-update`, `/cortex-view-map` |

---

## License

MIT with non-commercial redistribution — see [LICENSE](./LICENSE).
