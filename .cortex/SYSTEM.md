# CORTEX — System Instructions

> System file — **do not modify manually.**
> Version: 5.0.0
> Knowledge layer for AI coding agents.

---

## 1. The three files

CORTEX keeps three files, all loaded into your context at session start.

| File | What it holds | Who writes it |
|---|---|---|
| `.cortex/SYSTEM.md` | This file — how you behave | The installer. Never edit it. |
| `.cortex/PROJECT.md` | Tech stack, conventions, notes | See §3 |
| `.cortex/MAP.md` | A commented tree of every folder | Only `cortex-map.sh`. See §2 |

## 2. MAP.md — where everything lives

`MAP.md` lists **every folder** in the project with a one-line description of what it
contains. It answers "which folder do I look in?" — not "what does each file do?".

- Consult it before searching. It replaces blind `Grep`/`Glob` across the repository.
- **It is complete**: if a folder is not in `MAP.md`, it does not exist — unless the map is
  stale (§4).

### 2.1 You never edit MAP.md by hand

Its indentation is structure, not formatting: paths are reconstructed from it, so one wrong
space corrupts a path. Always go through the script:

```bash
bash .cortex/scripts/cortex-map.sh --set    "src/billing" "Billing: invoice issuing and download."
bash .cortex/scripts/cortex-map.sh --remove "src/legacy"
bash .cortex/scripts/cortex-map.sh --lookup "src/billing"
```

A node line carries two things by position: the name, which ends at its slash, and the depth,
which is the leading indentation. So a folder name may contain spaces — quote it as usual — but it
may not **start** with one in any segment, because that space reads back as indentation and
corrupts the whole file rather than just its own line. Nor may it contain a control character (a
tab or newline), which a line-oriented format cannot carry at all.

A top-level name opening with `#` or `>` is out too — the parser reads those lines as header
prose, so the node would vanish on write.

`validate_target` in `cortex-map.sh` is the single definition of all this, and you can ask it
directly with `--check <dir>` (read-only, answer in the exit status). `--set` and `--remove` reject
with exit 2, `--drift` never proposes a folder `--set` would reject, and the Stop hook never
suggests one — all by consulting that one rule rather than restating it. Such folders are simply
left out of the map. On top of that, no write lands unless the resulting file parses back to
exactly what was written, so a shape that slipped through every check still fails cleanly instead
of leaving an unusable map.

### 2.2 Descriptions never name files

Describe **what the folder contains**. Nothing else — no file names, no entry points, no
"notable files", no naming patterns, not even for large flat folders.

Naming conventions belong in `PROJECT.md`; repeating them here would duplicate the same fact
in two files. And a file name in the map is a file-level fact — exactly what makes a map
expensive to maintain, since it goes stale the moment someone renames.

- Good: `icon-buttons/  Icon-only button components, one per icon.`
- Wrong: `icon-buttons/  PascalCase components with .stories.tsx alongside. See IconButton.tsx.`

## 3. PROJECT.md — two halves, two rules

| Section | Who writes it |
|---|---|
| **Tech Stack** | You, on your own. It is a checkable fact: a dependency is in the manifest or it is not. Update it when a manifest changes. |
| **Conventions** | The user. **You ask.** |
| **Notes** | The user. **You ask.** |

Never edit Conventions or Notes unprompted. When you believe one should change, say so and
wait. A convention is a decision about how the project is worked, and that decision is the
user's — an agent rewriting it would be changing the rules it is supposed to follow.

## 4. Keeping the map current

**Whoever makes the change documents the change.** You maintain the map for the work *you*
did — including work done by your subagents. Structural changes made outside a session (a
`git pull`, folders created by hand, a branch switch) are closed by the user running
`/cortex-sync`.

> **When you finish a task, review the folders whose files you created, edited, moved or
> deleted.** For each one, check `MAP.md`: add it with `cortex-map.sh --set` if it is missing,
> update its description if it fell short, remove it with `--remove` if it is now empty.

Under Claude Code a `Stop` hook enforces this at the end of every turn. Under OpenCode there
are no hooks, so this instruction is the whole mechanism — follow it deliberately.

Because out-of-session changes are not tracked, **the map may be stale** in one direction: it
can list a folder that was deleted, or miss one that arrived with a pull. Treat a folder
missing from the map as possible staleness, not as proof it does not exist. If you find such a
gap, say so and suggest `/cortex-sync`.

### 4.1 Map changes travel with the code

`MAP.md` and `PROJECT.md` are committed alongside the change that caused them, never in a
separate housekeeping pass. That is why you update the map in the same turn: by the time the
work is ready to commit, the map change is already part of it.

## 5. The command

**`/cortex-sync`** — reconciles the map with the filesystem. Idempotent: it works the same on
a fresh project (where everything is missing) and on a mature one. There is no separate
initialisation step.

## 6. Project structure

```
.cortex/
├── SYSTEM.md      ← this file, do not edit
├── PROJECT.md     ← tech stack + conventions + notes
├── MAP.md         ← folder tree, written only by cortex-map.sh
├── commands/
│   └── cortex-sync.md
└── scripts/
    ├── cortex-scan.sh   ← gitignore-aware folder enumeration
    └── cortex-map.sh    ← the only writer of MAP.md
```

## 7. Compatibility

- **Claude Code** — `SessionStart` and `SubagentStart` hooks inject the three files; a
  `PostToolUse` hook records what you touch; a `Stop` hook enforces §4 at end of turn.
- **OpenCode** — `opencode.json → instructions` loads the three files. No hooks exist, so §4
  is followed by instruction alone.

Both agents use the same files, the same scripts and the same `/cortex-sync`.
