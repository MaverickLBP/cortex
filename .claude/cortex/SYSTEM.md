# CORTEX — System Instructions

> System file — **do not modify manually.**
> Version: 3.0.0
> Knowledge layer for AI coding agents.

---

## 1. The Knowledge Map

CORTEX is built around a single file: **MAP.md**.

- `MAP.md` is the project's knowledge map — a complete directory tree where **every folder and file is documented** with its purpose.
- The agent MUST load `MAP.md` at session start and keep it in context.
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

Updates happen **silently** as part of normal work. No need to announce them — just keep MAP.md accurate.

## 3. The cortex-init command

When run for the first time in a project (or when the project structure changes significantly):

**`/cortex-init`** (Claude Code) or **"run cortex-init"** (any agent)

Procedure:
1. Execute `.claude/cortex/scripts/cortex-init.sh` to generate the raw directory tree
2. Walk through every directory in the output, exploring files and documenting their purpose
3. Write the complete MAP.md
4. Inform the user that the knowledge map is ready

## 4. Viewing the map

To display the current knowledge map at any time:

**`/cortex-view-map`** (Claude Code) or **"run cortex-view-map"** (any agent)

With optional filter: `/cortex-view-map src/api` to show only a specific section.

The agent reads MAP.md and presents it to the user in a readable format.

## 5. Knowledge sharing

- MAP.md and all CORTEX files live in `.claude/cortex/` — they are part of the project
- **Commit MAP.md changes** alongside related code changes
- When another developer starts a session, their agent loads the same MAP.md — knowledge is shared via git
- CORTEX files are normal project files. They appear in pull requests, code review, and history

## 6. Project structure

```
.claude/
└── cortex/
    ├── SYSTEM.md          ← This file. Behaviour instructions. Do not edit.
    ├── MAP.md             ← Knowledge map. The only file you edit regularly.
    ├── commands/
    │   ├── cortex-init.md       ← Project scanner command
    │   └── cortex-view-map.md   ← View map command
    └── scripts/
        └── cortex-init.sh       ← Tree scanner (optional, one-time setup)
```

## 7. Compatibility

CORTEX v3 works with **Claude Code** and **OpenCode**. Both read CLAUDE.md, follow the reference to SYSTEM.md, and load the instructions. No platform-specific features are required.
