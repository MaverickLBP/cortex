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
what it moved and removed, and lists the new folders that still have no description. Step 2 builds its
work queue from them. If it exits non-zero, stop and report its error: nothing was changed.

The output goes to a file because on a fresh, large repository it lists every folder — far more than
a single command's output can show. Read it in chunks of 200 lines, never all at once and never
through a `| head` pipeline:

```bash
awk 'NR>=1 && NR<=200' .cortex/.state/reconcile.txt
awk 'NR>=201 && NR<=400' .cortex/.state/reconcile.txt
```

…and so on until you reach the line count printed above.

### Step 2 — Describe every folder, through the queue

The work is driven by `cortex-describe.sh`, not by you. It hands out one folder at a time together with
its real contents, never lets a description be verified by the worker that wrote it, and decides when the sync is
finished. Do not write descriptions from path names, from the parent folder, or with scripts, templates
or loops: the text must come from the contents the script shows you.

```bash
bash .cortex/scripts/cortex-describe.sh --init          # folders with no description yet
bash .cortex/scripts/cortex-describe.sh --init --all    # every folder
```

Use `--all` whenever the existing descriptions did not come through this queue: the first sync after
installing or upgrading, a map written by hand or by an older `/cortex-sync`, or any map that looks
generic. Without it only folders that have no description at `--init` time are checked.

`--init` resumes a queue left half-done by an earlier run and picks up new or renamed folders; run it
again only when no worker is alive, because it releases every unfinished claim. `--init --restart`
discards the queue. After a sync has finished, the next `--init` starts a new queue.

Then work the queue with **writers** and **verifiers**. Each takes a unique `--worker <id>`
(letters, digits, `.`, `_`, `-`); a folder is never verified by the worker that wrote it.

- Writer loop: `bash .cortex/scripts/cortex-describe.sh --next --role write --worker <id>` prints
  `TASK write <folder>`, any earlier rejection reason, and the folder's contents. Describe the folder's
  **role** in at most 120 characters, in English, naming no files:
  `bash .cortex/scripts/cortex-describe.sh --submit "<folder>" "<description>" --worker <id>`.
  Repeat. Exit code 3 means "nothing to take right now, try again shortly"; 4 means "nothing left for
  you": stop. Exit 3 covers two situations you cannot tell apart: other workers are still busy, or the
  work you need is not ready yet (for example a parent waiting for its subfolders to be verified). Wait a
  few seconds and ask again; if you keep getting 3 (about 20 tries) and nothing is served, stop too.
- Verifier loop: `--next --role verify --worker <id>` prints the folder, the description to check and the
  contents. Decide whether the description is true and specific for *this* content, then
  `--verdict "<folder>" ok "<evidence>" --worker <id>`, where the evidence must contain the exact name of a
  file or subfolder listed in the contents you were shown — the script checks this and refuses an `ok`
  without it — or
  `--verdict "<folder>" reject "<what is wrong>" --worker <id>`. A rejected folder goes back to a writer
  with your reason; after 3 rejections it needs a human.

Verifiers get the same codes: 3 while writers may still hand them work, 4 when nothing is left to verify.
Because a writer stops when no folder is waiting to be written, and a rejection or a parent waiting for
its children can create new work afterwards, work in **rounds**: when all workers have stopped, run
`--status`; if it is not 0, start another round of writers and verifiers. Stop only when `--status`
is 0, or when a whole round makes no progress (report that, with the `BLOCKED` lines).

Run writers and verifiers at the same time within a round. **With a subagent tool, use it**: launch several writer
subagents and several verifier subagents in parallel, each with its own worker id and the loop above as
its instructions. Parents are only served once their subfolders are verified, so near the root there may
be waits. Without a subagent tool, run both loops yourself with different worker ids.

If a subagent dies and leaves folders claimed, run `bash .cortex/scripts/cortex-describe.sh --requeue-claimed`
once no worker is alive. A folder stuck as `needs-human` can be sent back with `--reset "<folder>"`
after you have read the last rejection reason that `--status` prints next to it, and the folder itself.

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
bash .cortex/scripts/cortex-describe.sh --status
```

The sync is finished only when this exits `0`: every folder in the queue is verified, none of the
descriptions changed after verification, and no folder is missing from the queue. Otherwise it prints
a counts line and one `BLOCKED` line per problem (at most 50): fix those (more writer or verifier
rounds, `--init` to pick up new folders, `--reset` for `needs-human`) and run it again. If folders stay
`needs-human`, report "done with exceptions" and list them; never report the sync as complete.

Then report: folders described, moved and removed; Tech Stack changes; and, if you wrote them in Step 4,
the deduced conventions, listed so the user can review them.
