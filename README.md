# CORTEX — Knowledge layer for AI agents

**A dynamic knowledge system for AI coding assistants.**
Zero dependencies. Markdown + bash. Native enforcement for Claude Code and OpenCode.

CORTEX lives in `.cortex/` and gives your agent a complete, living map of every folder in the
project — what each one contains and where new work belongs. It uses each agent's native
mechanisms to guarantee the knowledge is loaded at every session start.

---

## How it works

CORTEX keeps four things in `.cortex/`:

| What | Holds | Who writes it |
|---|---|---|
| `.cortex/LOOKUP.md` | How to look things up with the map | The installer (overwrites it). Never edit it. |
| `.cortex/MAINTAIN.md` | How to keep the map and `PROJECT.md` current | The installer (overwrites it). Never edit it. |
| `.cortex/PROJECT.md` | Tech stack, conventions, notes | Tech Stack: the agent. Conventions: deduced once by `/cortex-sync`, then the user. Notes: the user. The installer never overwrites it. |
| `.cortex/map/` | One short description per folder | Only `cortex-map.sh` |

```
project/
├── .cortex/                     ← Agent-agnostic knowledge (always committed)
│   ├── LOOKUP.md                ← How to look things up (do not edit)
│   ├── MAINTAIN.md              ← How to maintain the map (do not edit)
│   ├── PROJECT.md               ← Tech stack + conventions + notes
│   ├── map/                     ← One <folder>.cortex file per folder, written only by cortex-map.sh
│   ├── .state/                  ← Local snapshot used to detect renames (gitignored)
│   ├── commands/
│   │   └── cortex-sync.md       ← Template for the /cortex-sync command
│   └── scripts/
│       ├── cortex-scan.sh       ← Gitignore-aware folder enumeration
│       ├── cortex-describe.sh   ← The work queue /cortex-sync uses to describe and verify every folder
│       └── cortex-map.sh        ← The only writer of the map (--set / --find / --reconcile / --drift / --dirs / --ignored / --check)
│
├── .claude/                     ← Claude Code only
│   ├── settings.json            ← Registers CORTEX hooks (commit this)
│   ├── rules/
│   │   └── cortex.md            ← Imports LOOKUP.md, MAINTAIN.md and PROJECT.md at session start
│   ├── hooks/
│   │   ├── cortex-subagent.sh      ← SubagentStart: gives every subagent LOOKUP.md
│   │   └── cortex-stop.sh          ← Stop: reconciles the map; blocks once per turn for new undescribed folders
│   └── commands/
│       └── cortex-sync.md       ← Slash command for Claude Code
│
├── .opencode/                   ← OpenCode only
│   └── commands/
│       └── cortex-sync.md       ← Slash command for OpenCode
│
└── opencode.json                ← OpenCode only: auto-loads LOOKUP.md, MAINTAIN.md and PROJECT.md
```

**The map is folder-granular and stored one file per folder.** Each folder has a
`.cortex/map/<folder>.cortex` file holding a single line: what the folder is for, in at most 120
characters. Descriptions state a role, never file names, entry points or naming patterns (those
belong in `PROJECT.md`). Two branches only conflict if they change the description of the same
folder, and a merge request shows the map change as a plain added file.

**Agents query the map instead of loading it.** `cortex-map.sh --find <term>…` returns the folders
whose path or description contains every term, most relevant first (at most 40 lines). Subfolders
that only match through a listed ancestor's name are folded into that ancestor's line as a count
(`(+N subfolders match)`), so a broad term does not list a whole subtree. Renamed,
moved and deleted folders need no work from the agent: `cortex-map.sh --reconcile` moves or drops
their descriptions on its own, using a local snapshot of the file list (`.cortex/.state/`, never
committed). Only new folders need a description. In git repositories the map carries its own `.cortex/map/.gitignore`, so folders named like
something your project ignores (e.g. `reports`) still get their descriptions committed.

It works the same with and without git. With git, `.gitignore` is respected; without it, common
build and dependency folders are skipped.

### Enforcement mechanism

- **Claude Code**
  - `.claude/rules/cortex.md` imports `LOOKUP.md`, `MAINTAIN.md` and `PROJECT.md`, so the main agent
    and general-purpose subagents have them at session start.
  - `cortex-subagent.sh` (`SubagentStart`) gives every subagent `LOOKUP.md`, including Explore and
    Plan, which do not receive the rule file.
  - `cortex-stop.sh` (`Stop`) runs `--reconcile` at the end of every turn. It is stateless: if new
    folders still lack a description it blocks once per turn and lists up to 20 of them, each with a
    ready-to-copy `--set` command. If it only moved or removed descriptions, it just reports that.
    It stays silent until the map has its first entry (run `/cortex-sync` after installing). Set
    `CORTEX_STOP_HOOK=0` to disable it.
- **OpenCode**: `opencode.json` → `instructions` auto-loads `.cortex/LOOKUP.md`,
  `.cortex/MAINTAIN.md` and `.cortex/PROJECT.md` at every session start.

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

The installer creates `.cortex/PROJECT.md` from `templates/PROJECT.md` (empty sections, titled with
your project's name) only if it does not exist yet, and adds `.cortex/.state/` to `.gitignore` when
the project uses git.

**After installing for Claude Code:** commit `.claude/settings.json` and `.claude/rules/cortex.md`
— they register the hooks and load the knowledge. Per-user overrides go in
`.claude/settings.local.json` (gitignored).

**Upgrading from v5:** the installer never removes anything. It warns when it finds v5 leftovers
and points at the manual cleanup steps in [CHANGELOG.md](./CHANGELOG.md) → "Upgrading from v5".

### 2. Build (and keep) the knowledge map

```
/cortex-sync
```

One command, idempotent. On a fresh project every folder lacks a description, so it generates the
whole map; on a mature one it only closes the gaps — reconciles renamed and deleted folders,
describes the new ones, and refreshes the Tech Stack table. The first time, when the Conventions
section of `PROJECT.md` is still the empty template (`_None yet._`), it also deduces the conventions
from the code and lists them in its report for you to review. After that, Conventions and Notes are
yours. It works identically on Claude Code and OpenCode.

The descriptions are not left to the agent's discretion. `cortex-describe.sh` hands out one folder at
a time with its real contents; a second agent verifies each description against the same contents, and
the sync only finishes when `cortex-describe.sh --status` exits 0 — every folder verified, none changed
since, none missing. Large projects are split across parallel subagents; an interrupted sync resumes.
`cortex-describe.sh --report` shows who wrote and verified what, and warns when verification looks like a rubber stamp. Use `cortex-describe.sh --init --all` to redo a map whose descriptions turned out generic.

Run it after installing, and after structural changes made outside a session — a `git pull` that
reshapes the tree, folders created by hand, a branch switch.

During normal work you generally don't need to run it yourself: on Claude Code, the `Stop` hook asks
the agent to describe any new folder at the end of the turn. On OpenCode, `MAINTAIN.md` instructs
the agent to do the same — but nothing enforces it, so it depends on the agent following the
instruction.

---

## Project resources

| Resource | Description |
|----------|-------------|
| [`install.sh`](./install.sh) | Install CORTEX in a single project (agent selection) |
| [CHANGELOG.md](./CHANGELOG.md) | Version history following Keep a Changelog |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | How to report bugs, suggest features, and submit PRs |
| [docs/](./docs/) | Web landing page (GitHub Pages) |
| [LICENSE](./LICENSE) | MIT License with non-commercial redistribution clause |

---

## Compatibility

| Agent | Enforcement | Commands |
|---|---|---|
| **Claude Code** | `.claude/rules/cortex.md` loads LOOKUP.md, MAINTAIN.md and PROJECT.md; `SubagentStart` hook gives every subagent LOOKUP.md; `Stop` hook reconciles the map and blocks once per turn for new undescribed folders | `/cortex-sync` |
| **OpenCode** | `opencode.json` → `instructions` auto-loads LOOKUP.md, MAINTAIN.md and PROJECT.md; no hooks exist, so map maintenance is followed by instruction alone, with nothing enforcing it | `/cortex-sync` |

---

## License

MIT with non-commercial redistribution — see [LICENSE](./LICENSE).
