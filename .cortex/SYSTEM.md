# CORTEX — System Instructions

> System file — **do not modify manually.**
> Version: 4.1.0
> Knowledge layer for AI coding agents.

---

## 1. The Knowledge Map

CORTEX is built around a single file: **MAP.md**.

- `MAP.md` is the project's knowledge map — a complete directory tree where **every folder and file is documented** with its purpose.
- The agent MUST load `.cortex/MAP.md` at session start and keep it in context.
- MAP.md is the **single source of truth** for project structure. Before searching or creating any file, consult MAP.md first.

## 2. How to use MAP.md

### 2.1 Finding things

When the user asks you to work on something:

1. Consult MAP.md to locate the relevant directories and files
2. Navigate directly to them — no guesswork, no unnecessary filesystem scanning
3. If you need to understand what a utility, component, or module does, read the MAP.md documentation for that file

### 2.2 Creating new files

When you need to create a new file:

1. Consult MAP.md to determine where it belongs (e.g., utilities go in `src/shared/utils/`, repositories in `src/database/repositories/`)
2. Follow the conventions documented for that directory
3. If the file type doesn't exist yet in the project, create it where it logically fits and **update MAP.md**

### 2.3 Updating MAP.md

MAP.md is **living documentation**. Update it when:

| Situation | Action |
|-----------|--------|
| A new directory or file is created | Add it to MAP.md with a brief description |
| An existing file is renamed or moved | Update the path and description in MAP.md |
| A directory's purpose changes | Update the description |
| A file is removed | Remove or archive it in MAP.md |
| A dependency is added, removed, or upgraded | Update the Tech Stack table accordingly |
| A new technology appears in the project | Add it to the Tech Stack table |

Updates happen **silently** as part of normal work. No need to announce them — just keep MAP.md accurate.

### 2.4 Active enforcement (reminders are not optional)

Under Claude Code, CORTEX registers hooks that fire during the session:

- A `PostToolUse` hook injects a reminder when you create a file the map does
  not reference, delete a documented file with a local `rm`, or move/rename a
  file with a local `mv` (a documented source whose entry is now stale, or a
  new destination path the map doesn't list). Detection is local only —
  `git rm`/`git mv` are not tracked; the map is kept in sync in reaction to
  local filesystem changes, not git commands. The reminder fires at the exact
  moment you make the change, because keeping MAP.md in sync is the
  responsibility of whoever creates, deletes, or updates the file — not a later
  pass. When you receive such a reminder, act on it immediately: update MAP.md
  silently, or consciously decide the existing folder-level entry covers it.
  Never ignore or defer these reminders.
- A `SubagentStart` hook gives subagents a short CORTEX note automatically.

Regardless of agent: when YOU dispatch subagents or delegate work that may
create, delete, or rename project files, include in the dispatch prompt that
this project uses CORTEX and that `.cortex/MAP.md` must be consulted for file
placement and updated for structural changes.

## 3. The cortex-init command

When run for the first time in a project:

**`/cortex-init`** (Claude Code and OpenCode)

Procedure:
1. Execute `.cortex/scripts/cortex-init.sh` to generate the raw directory tree
2. Detect the project's tech stack (package.json, go.mod, Dockerfile, etc.)
3. Walk through every directory in the output, exploring files and documenting their purpose
4. Write the complete MAP.md with Tech Stack table + directory entries
5. Inform the user that the knowledge map is ready

## 3.1 The cortex-update command

When the project structure changes or the MAP.md format evolves:

**`/cortex-update`** (Claude Code and OpenCode)

Unlike `cortex-init`, this command **preserves all existing content** and only adds, removes, or updates what has changed. Use it for:
- New files or directories added
- Files deleted or renamed
- Missing sections (e.g. Tech Stack not yet present)
- Refreshing the map without losing custom notes

## 4. Viewing the map

To display the current knowledge map at any time:

**`/cortex-view-map`** (Claude Code and OpenCode)

With optional filter: `/cortex-view-map src/api` to show only a specific section.

The agent reads MAP.md and presents it to the user in a readable format.

## 5. Knowledge sharing

- MAP.md and all CORTEX files live in `.cortex/` — they are part of the project
- **Commit MAP.md changes** alongside related code changes
- When another developer starts a session, their agent loads the same MAP.md — knowledge is shared via git
- CORTEX files are normal project files. They appear in pull requests, code review, and history

## 6. Project structure

```
.cortex/                       ← CORTEX knowledge (agent-agnostic, always committed)
├── SYSTEM.md                  ← This file. Behaviour instructions. Do not edit.
├── MAP.md                     ← Knowledge map. The only file you edit regularly.
├── commands/
│   ├── cortex-init.md         ← First-run project scanner
│   ├── cortex-update.md       ← Maintenance updater (preserves content)
│   └── cortex-view-map.md     ← View map command
└── scripts/
    └── cortex-init.sh         ← Tree scanner

.claude/                       ← Claude Code only (when installed for Claude)
├── settings.json              ← SessionStart hook → .claude/hooks/cortex-session.sh
├── hooks/
│   ├── cortex-session.sh      ← Injects SYSTEM.md + MAP.md content at session start
│   ├── cortex-file-change.sh  ← PostToolUse: reminds to update MAP.md on file creation/removal
│   └── cortex-subagent.sh     ← SubagentStart: gives subagents CORTEX context
└── commands/                  ← Slash commands (cortex-init.md, cortex-update.md, cortex-view-map.md)

.opencode/                     ← OpenCode only (when installed for OpenCode)
└── commands/                  ← Slash commands (cortex-init.md, cortex-update.md, cortex-view-map.md)

opencode.json                  ← OpenCode only: instructions field loads SYSTEM.md + MAP.md
```

## 7. Compatibility

CORTEX v4 supports **Claude Code** and **OpenCode** using their native enforcement mechanisms:

- **Claude Code**: A `SessionStart` hook (`cortex-session.sh`) injects SYSTEM.md and MAP.md content at session start; `PostToolUse` and `SubagentStart` hooks provide mid-session enforcement (Claude Code only — OpenCode has no hook mechanism; it loads SYSTEM.md + MAP.md via `opencode.json → instructions` and relies on the instructions themselves for updates).
- **OpenCode**: `opencode.json` → `instructions` loads `.cortex/SYSTEM.md` and `.cortex/MAP.md` at every session start automatically.

Both agents use `/cortex-init`, `/cortex-update`, and `/cortex-view-map` as slash commands.
