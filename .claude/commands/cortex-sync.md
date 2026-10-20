---
description: Reconcile the knowledge map with the filesystem. Works on a fresh project and on a mature one.
---

# cortex-sync — Reconcile the knowledge map

Brings the folder map in `.cortex/map/` and `.cortex/PROJECT.md` in line with what is actually on
disk.

**Idempotent.** On a fresh project every folder is missing a description, so this generates the whole
map; on a mature one it only closes the gaps. There is no separate initialisation command.

Run it after structural changes made outside an agent session — a `git pull` that reshapes the
tree, folders created by hand, a branch switch — or right after installing.

---

## Procedure

### Step 1 — Reconcile

```bash
mkdir -p .cortex/.state
bash .cortex/scripts/cortex-map.sh --reconcile > .cortex/.state/reconcile.txt
wc -l < .cortex/.state/reconcile.txt
```

The script does everything that needs no judgement: folders that were renamed or moved take their
description (and their subfolders') with them, and folders that disappeared lose theirs. It writes
what it moved and removed, and lists the new folders that still have no description. Those are your
work for Step 2. If it exits non-zero, stop and report its error: nothing was changed.

The output goes to a file because on a fresh, large repository it lists every folder — far more than
a single command's output can show. Read it in chunks of 200 lines, never all at once and never
through a `| head` pipeline:

```bash
awk 'NR>=1 && NR<=200' .cortex/.state/reconcile.txt
awk 'NR>=201 && NR<=400' .cortex/.state/reconcile.txt
```

…and so on until you reach the line count printed above.

### Step 2 — Describe every pending folder

For each folder listed, look at what it holds and write one line about its **role**: what kind of
thing lives there and why. At most 120 characters. Never name files, entry points or naming
patterns — those belong in `PROJECT.md`.

```bash
bash .cortex/scripts/cortex-map.sh --set "rsrc/modules/billing" "Billing: invoice issuing, download and tax reports."
```

A folder listing plus a glance at one or two representative files is normally enough. You do not need
to read every file. Work in tree order (parents first) so related folders get consistent wording.

On a large repository this step may be split across subagents. Folders are independent, so there is
no ordering constraint between them, but **only the main agent writes the map**: subagents return
their descriptions and the main agent runs `--set`.

### Step 3 — Refresh the Tech Stack

Re-run the detection cascade and update the Tech Stack table in `.cortex/PROJECT.md`:

1. Parse known manifests (`package.json`, `pom.xml`, `Cargo.toml`, `pyproject.toml`, `go.mod`,
   `composer.json`, `Gemfile`, `pubspec.yaml`) for name, key dependencies and versions.
2. Record unparsed manifest-looking files (`mix.exs`, `deno.json`, `*.csproj`) as present.
3. Extension histogram — guarantees the table is never empty:
   ```bash
   bash .cortex/scripts/cortex-scan.sh --files | sed 's/.*\.//' | sort | uniq -c | sort -rn | awk 'NR<=15'
   ```
4. Refine versions from `.nvmrc`, `.tool-versions`, Dockerfile `FROM`, CI files.

Unknown version → `latest` or `N/A`. Missing detection is never an error.

### Step 4 — Conventions

Read the body of the Conventions section in `.cortex/PROJECT.md`.

- If it is exactly `_None yet._` (or empty), this is the first run: deduce the project's conventions
  from the code (layout, naming, test and build tooling, recurring patterns), write them as a bullet
  list, and keep them to what the code actually shows. Do not invent decisions.
- Otherwise, do not touch it. Conventions belong to the user from then on. If the new folders suggest
  one that is not recorded, say so and wait.

Notes is never edited here.

### Step 5 — Verify and report

```bash
bash .cortex/scripts/cortex-map.sh --drift > .cortex/.state/drift.txt
wc -l < .cortex/.state/drift.txt
```

The count must be `0`. If it is not, read the file in chunks of 200 lines as in Step 1 (`awk 'NR>=1 &&
NR<=200' .cortex/.state/drift.txt`, …), close the gaps, and run it again. Then report: folders described, moved and removed; Tech Stack changes; and,
if you wrote them in Step 4, the deduced conventions, listed so the user can review them.
