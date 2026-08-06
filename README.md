# CORTEX — Knowledge layer for AI agents

**A dynamic knowledge system for AI coding assistants.**
Zero dependencies. Markdown + bash. Native enforcement for Claude Code and OpenCode.

CORTEX lives in `.cortex/` and gives your agent a complete, living map of every folder in the
project — what each one contains and where new work belongs. It uses each agent's native
mechanisms to guarantee the knowledge is loaded at every session start.

---

## How it works

CORTEX keeps three files, all loaded into context at session start:

| File | What it holds | Who writes it |
|---|---|---|
| `.cortex/SYSTEM.md` | Agent behaviour instructions | The installer. Never edit it. |
| `.cortex/PROJECT.md` | Tech stack, conventions, notes | The agent (Tech Stack) and the user (Conventions, Notes) |
| `.cortex/MAP.md` | A commented tree of every folder in the project, one line each | Only `cortex-map.sh` |

```
project/
├── .cortex/                     ← Agent-agnostic knowledge (always committed)
│   ├── SYSTEM.md                ← Agent behaviour instructions (do not edit)
│   ├── PROJECT.md                ← Tech stack + conventions + notes
│   ├── MAP.md                   ← Folder-level knowledge map, written only by cortex-map.sh
│   ├── commands/
│   │   └── cortex-sync.md       ← Template for the /cortex-sync command
│   └── scripts/
│       ├── cortex-scan.sh       ← Gitignore-aware folder enumeration
│       └── cortex-map.sh        ← The only writer of MAP.md (--set / --remove / --validate / --drift)
│
├── .claude/                     ← Claude Code only
│   ├── settings.json            ← Registers CORTEX hooks (commit this)
│   ├── hooks/
│   │   ├── cortex-session.sh       ← SessionStart: injects SYSTEM.md, PROJECT.md and MAP.md
│   │   ├── cortex-subagent.sh      ← SubagentStart: gives subagents the same three files
│   │   ├── cortex-file-change.sh   ← PostToolUse: mute collector, records what a turn touched
│   │   └── cortex-stop.sh          ← Stop: the only decision point — blocks once per turn if the map needs work
│   └── commands/
│       └── cortex-sync.md       ← Slash command for Claude Code
│
├── .opencode/                   ← OpenCode only
│   └── commands/
│       └── cortex-sync.md       ← Slash command for OpenCode
│
└── opencode.json                ← OpenCode only: auto-loads SYSTEM.md, PROJECT.md and MAP.md
```

**MAP.md is folder-granular.** Every entry is a folder and a one-line description of what it
contains — never a file name, entry point, or naming pattern (those belong in `PROJECT.md`).
There is one map and one command — no partitioning by project size: `MAP.md` is always loaded
in full, regardless of how large the project is.

### Enforcement mechanism

- **Claude Code**: four hooks provide active enforcement, no passive CLAUDE.md needed.
  - `cortex-session.sh` (`SessionStart`) injects `SYSTEM.md`, `PROJECT.md` and the full content
    of `MAP.md` as `additionalContext` — the agent doesn't need to read the files separately.
    Supports workspace mode (see below).
  - `cortex-subagent.sh` (`SubagentStart`) gives subagents the same three files, since they
    never receive `SessionStart` context on their own.
  - `cortex-file-change.sh` (`PostToolUse`) is a mute collector: it records which paths a turn
    touched and makes no decisions, emits no reminders, and never interrupts the agent.
  - `cortex-stop.sh` (`Stop`) is the only decision point. It fires once per turn, reads the
    touch record, and — if the map now needs work — blocks once so the agent reconciles it
    before returning control. It is stateless: every turn is evaluated fresh, with no memory of
    previously reported folders.
- **OpenCode**: `opencode.json` → `instructions` auto-loads `.cortex/SYSTEM.md`,
  `.cortex/PROJECT.md` and `.cortex/MAP.md` at every session start.

**Claude Code and OpenCode do not offer the same guarantee.** Under Claude Code a `Stop` hook
enforces map maintenance at the end of every turn. OpenCode has no hook mechanism, so there the
same rule is followed by instruction alone — the map still converges, but nothing enforces it.
`/cortex-sync` works identically on both.

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

**After installing for Claude Code:** commit `.claude/settings.json` — it registers the hooks
that enforce CORTEX at session start and at the end of every turn. Per-user overrides go in
`.claude/settings.local.json` (gitignored).

**Upgrading from a pre-v5 install:** `install.sh` only ever adds the current file set — it never
removes files or hook registrations left by an older version. If your project has any of
`.cortex/scripts/cortex-areas.sh`, `.cortex/scripts/cortex-init.sh`,
`.claude/hooks/cortex-map-load.sh`, or a `PreToolUse` entry in `.claude/settings.json`, delete the
following by hand before re-running `install.sh`:

- `.cortex/` (all of it — includes `MAP.md`, `PROJECT.md`, and `.cortex/maps/` if present)
- `.claude/hooks/cortex-*.sh`
- `.claude/commands/cortex-*.md` and `.opencode/commands/cortex-*.md`, if present
- Any hook entry in `.claude/settings.json` whose `command` points at a `cortex-*.sh` script

Then run `install.sh` again for a clean v5 install.

### 2. Build (and keep) the knowledge map

```
/cortex-sync
```

One command, idempotent. On a fresh project everything is missing, so it generates the whole
map; on a mature one it only closes the gaps — adds folders that appeared, removes folders that
are gone, and refreshes the Tech Stack table. There is no separate initialisation step, and it
works identically on Claude Code and OpenCode.

Run it after structural changes made outside a session — a `git pull` that reshapes the tree,
folders created by hand, a branch switch.

During normal work you generally don't need to run it yourself: on Claude Code, the `Stop` hook
prompts the agent to reconcile the map at the end of any turn that touched files. On OpenCode,
`SYSTEM.md` instructs the agent to do the same — but nothing enforces it, so it depends on the
agent following the instruction.

### 3. Workspace bridge (multi-project, Claude Code only)

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
| **Claude Code** | `SessionStart` and `SubagentStart` hooks inject SYSTEM.md, PROJECT.md and full MAP.md content; `PostToolUse` hook silently records touched paths; `Stop` hook blocks once per turn if the map needs reconciling | `/cortex-sync` |
| **OpenCode** | `opencode.json` → `instructions` auto-loads SYSTEM.md, PROJECT.md and MAP.md; no hooks exist, so map maintenance is followed by instruction alone, with nothing enforcing it | `/cortex-sync` |

---

## License

MIT with non-commercial redistribution — see [LICENSE](./LICENSE).
