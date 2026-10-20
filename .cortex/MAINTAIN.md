# CORTEX — Maintaining the map

> Version: 6.1.0
> System file — do not modify manually. The installer overwrites it.

The map is one short description per folder, stored in `.cortex/map/`. It answers "which folder do I
look in?", never "what does each file do?". This file says how to keep it, and `PROJECT.md`, current.

## Who documents a change

**Whoever makes the change documents the change.** That includes work done by your subagents.
Structural changes made outside a session (a `git pull`, folders created by hand, a branch switch)
are closed by the user running `/cortex-sync`.

## When you finish a task

Review the folders where you created files. For each new folder the map does not know yet, describe it:

```bash
bash .cortex/scripts/cortex-map.sh --set "src/billing" "Billing: invoice issuing and download."
```

Quote the folder and the description. Deleted and renamed folders need nothing from you: the map
reconciles itself (`cortex-map.sh --reconcile`, run by the `Stop` hook and by `/cortex-sync`).

To see what is undescribed or stale, ask for the drift:

```bash
bash .cortex/scripts/cortex-map.sh --drift
```

Many undescribed folders at once (first install, a big pull) are not for hand-written `--set`
commands: `/cortex-sync` works them through `cortex-describe.sh`, one folder at a time, each one
verified by a second agent.

Under Claude Code the `Stop` hook enforces this at the end of every turn and lists the folders still
missing a description. Under OpenCode there are no hooks, so this instruction is the whole mechanism:
follow it deliberately.

## Writing a description

- One line, at most 120 characters.
- Describe the folder's role: what kind of thing lives there and why.
- Never name files, entry points or naming patterns. A file name goes stale on the first rename, and
  naming conventions belong in `PROJECT.md`.
- Do not list contents, and do not widen the description with every new feature. If it still
  describes the folder's role, leave it alone.
- Good: `Icon-only button components, one per icon.`
- Wrong: `PascalCase components with .stories.tsx alongside. See IconButton.tsx.`

## Finding a folder

Use `bash .cortex/scripts/cortex-map.sh --find <term>` before grepping the repository. It matches
folder paths and descriptions.

## The map travels with the code

Map changes are committed together with the change that caused them, never in a separate housekeeping
pass. By the time the work is ready to commit, the map is already up to date.

## Who writes what in PROJECT.md

| Section | Who writes it |
|---|---|
| Tech Stack | You, on your own initiative. It is a checkable fact: update it whenever a dependency manifest changes (a dependency added, removed or upgraded). |
| Conventions | The user only, by hand or by asking an agent expressly. You may suggest that something should become a convention; do not write it unless asked. One exception: the first `/cortex-sync` deduces them from the code when the section is still the empty template (`_None yet._`). |
| Notes | The user only, by hand or by asking an agent expressly. |

A convention is a decision about how the project is worked. An agent rewriting it would be changing
the rules it is supposed to follow.

## Stale map

The map can lag behind the tree: a folder deleted, or one that arrived with a pull. Treat a missing
folder as possible staleness, not proof it does not exist. If you find a gap, say so and suggest
`/cortex-sync`.
