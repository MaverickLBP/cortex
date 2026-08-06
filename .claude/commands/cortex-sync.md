---
description: Reconcile the knowledge map with the filesystem. Works on a fresh project and on a mature one.
---

# cortex-sync — Reconcile the knowledge map

Brings `.cortex/MAP.md` and `.cortex/PROJECT.md` in line with what is actually on disk.

**idempotent.** On a fresh project every folder is missing, so this generates the whole map; on a
mature one it only closes the gaps. There is no separate initialisation command.

Run it after structural changes made outside an agent session — a `git pull` that reshapes the
tree, folders created by hand, a branch switch — or on a fresh install.

---

## Procedure

### Step 1 — Validate the existing map

```bash
bash .cortex/scripts/cortex-map.sh --validate
```

If this fails, it prints the offending line number. `MAP.md` was hand-edited and its indentation is
broken. **Stop and fix that line first** — every step below would otherwise operate on
mis-reconstructed paths.

### Step 2 — Compute the drift

```bash
bash .cortex/scripts/cortex-map.sh --drift
```

Output is one line per difference:

```
+ rsrc/modules/billing      folder on disk, absent from the map
- public/assets/legacy      folder in the map, absent from disk
```

No output means the map is in sync — skip to Step 5.

### Step 3 — Add every `+` folder

For each one, look at what it holds and write a one-line description of **what the folder
contains**. Never name files, entry points or naming patterns (see SYSTEM.md §2.2) — those belong
in `PROJECT.md`.

```bash
bash .cortex/scripts/cortex-map.sh --set "rsrc/modules/billing" "Billing: invoice issuing, download and tax reports."
```

A folder listing plus a glance at one or two representative files is normally enough. You do not
need to read every file.

If there are many, work through them in tree order so related folders get consistent wording. On a
large repository this step may be dispatched to subagents — folders are independent, so there is no
ordering constraint between them — but **only the main agent writes the map**: subagents report
their descriptions and the main agent runs `--set`.

### Step 4 — Remove every `-` folder

```bash
bash .cortex/scripts/cortex-map.sh --remove "public/assets/legacy"
```

Ancestors left childless are pruned automatically when they were only placeholders.

### Step 5 — Refresh the Tech Stack

Re-run the detection cascade and update the table in `PROJECT.md`:

1. Parse known manifests (`package.json`, `pom.xml`, `Cargo.toml`, `pyproject.toml`, `go.mod`,
   `composer.json`, `Gemfile`, `pubspec.yaml`) for name, key dependencies and versions.
2. Record unparsed manifest-looking files (`mix.exs`, `deno.json`, `*.csproj`) as present.
3. Extension histogram — guarantees the table is never empty:
   ```bash
   bash .cortex/scripts/cortex-scan.sh --files | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -15
   ```
4. Refine versions from `.nvmrc`, `.tool-versions`, Dockerfile `FROM`, CI files.

Unknown version → `latest` or `N/A`. Missing detection is never an error.

### Step 6 — Conventions and Notes: ask, do not edit

If the new folders suggest a convention that `PROJECT.md` does not record, **say so and wait**. Do
not edit the Conventions or Notes sections on your own — they are the user's.

### Step 7 — Verify and report

```bash
bash .cortex/scripts/cortex-map.sh --validate && bash .cortex/scripts/cortex-map.sh --drift
```

Both must be silent. Then report: folders added, folders removed, tech stack changes, and any
convention you are suggesting.
