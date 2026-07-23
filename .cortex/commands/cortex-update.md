---
description: Update the knowledge map after project structure changes. Preserves existing content.
---

# cortex-update — Update the knowledge map

Updates `.cortex/MAP.md` when the project structure changes or when the MAP.md format evolves. Unlike `cortex-init`, this command **preserves all existing content** and only adds, removes, or updates what has changed.

Run this when:
- New files or directories are added to the project
- Files are deleted or renamed
- The MAP.md format gains new sections (e.g. Tech Stack, Architecture, etc.)
- You want to refresh the map without losing custom notes

---

## Procedure

### Step 1 — Read existing map state
Read `.cortex/MAP.md` and, if present, `.cortex/maps/index.json` + sub-maps. Note custom Notes.

### Step 2 — Re-partition
Run `bash .cortex/scripts/cortex-areas.sh`. It rewrites `.cortex/maps/index.json`. Compare the new area set to the old.

### Step 3 — Handle flat ↔ hierarchical transitions (promotion/demotion)
- **Flat → hierarchical promotion:** the repo grew past `FLAT_CAP`. `cortex-areas.sh` now emits areas. Generate the `maps/<area>.md` sub-maps (per `cortex-init.md` Step 2) and rewrite `MAP.md` as an index.
- **Hierarchical → flat demotion:** the repo shrank below `FLAT_CAP` (`FLAT <n>`). Fold sub-map detail back into a single `MAP.md` and remove `maps/`.

### Step 4 — Sync changed areas only
For areas whose files changed: update only the affected `maps/<area>.md`. Resolve which sub-map a changed path belongs to via `index.json` (longest-root-prefix). Unchanged areas and their sub-maps are left intact.

When re-listing an area's files (e.g. to re-check coverage), remember areas partition files **disjointly** — an area's `files` count in `index.json` excludes any deeper nested area's files. Use the same exclusive listing recipe as `cortex-init.md` Step 2: exclude any other area whose `root` nests under this area's root (`grep -vE '^<deeper-area-root>/'` per deeper area found via longest-root-prefix in `index.json`), and for the root/`_misc` area (`root: "."`) list root-level files with `grep -v '/'` instead of `grep -E '^\./'` (which matches nothing).

### Step 5 — Refresh the index + Tech Stack
Update `MAP.md` directory descriptions, conventions, area pointers, and the Tech Stack (best-effort cascade) for added/removed deps.

### Step 6 — Preserve Notes and report
Preserve custom Notes. Report: areas added/removed, sub-maps updated, any transition, files documented.
