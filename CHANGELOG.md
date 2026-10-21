# Changelog

All notable changes to CORTEX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [6.1.3] — 2026-10-21

### Fixed
- Map descriptions of folders named like something the project's `.gitignore` excludes (for
  example `reports`) were silently left out of commits. `cortex-map.sh` now writes a
  `.cortex/map/.gitignore` (`!*`, in git repositories) on `--set` and `--reconcile`, so the
  Stop hook and `/cortex-sync` repair existing installs by themselves.

### Added
- `cortex-map.sh --ignored` (read-only): map entries git would leave out of a commit.
- `cortex-map.sh --set` warns when the file it wrote is git-ignored, and
  `cortex-describe.sh --status` does not complete while any queued description is.

## [6.1.2] — 2026-10-20

### Added
- `cortex-describe.sh --report`: submissions, approvals and rejections, plus how many folders each
  worker wrote or verified, with warnings when no folder was rejected out of 10 or more verdicts and
  when a worker acted as both writer and verifier. `/cortex-sync` includes it in its final report.
- `--next` prints a short guide with every task (what a good description says for a writer; what to
  reject for a verifier), so it reaches subagents whatever prompt they were given.

### Changed
- A claim nobody finishes within 20 minutes (`CORTEX_DESCRIBE_LEASE_MIN`) returns to the queue on its own,
  so a dead worker no longer leaves a folder stuck. `/cortex-sync` forbids the main agent from writing or
  verifying folders when subagents are available: it launches another worker instead. The first
  end-to-end run on a 994-folder project had the main agent write and verify five folders itself.

## [6.1.1] — 2026-10-20

### Changed
- `/cortex-sync` spells out that exit 3 from `--next` means "wait and ask again" for both roles, and
  that `--verdict ok` is refused unless its evidence names a file or subfolder from the contents.
- The map of this repository was rebuilt through the queue (`--init --all`) as a first end-to-end run.

## [6.1.0] — 2026-10-20

### Added
- `cortex-describe.sh`: a work queue for `/cortex-sync`. It hands out one folder at a time with its
  real contents (files, subfolders, a bounded excerpt), lets a worker describe it with `--submit`,
  hands the description to a different worker to verify with `--verdict` (which must cite a file or
  folder name from the contents), and sends rejections back, escalating to `needs-human` after 3.
  Parents are written only after their subfolders are verified. `--status` exits 0 only when every
  folder is verified, no description changed since, and no folder is missing from the queue.
  Includes `--init [--all] [--restart]` (resumes by default), `--reset`, `--requeue-claimed`, `--show`.
- `cortex-map.sh --dirs`: read-only list of every representable folder, described or not.

### Changed
- `/cortex-sync` drives the queue with parallel writer and verifier subagents (or one agent playing
  both roles) and finishes only when `cortex-describe.sh --status` exits 0. Before, it finished at
  `--drift` = 0, which a 994-folder migration reached with over half of the descriptions being filler.
- The `Stop` hook stays silent while a queue is active (marker younger than 12 h), so it does not
  offer `--set` shortcuts in the middle of a sync.

## [6.0.1] — 2026-10-19

### Fixed
- `cortex-map.sh --reconcile` matches renames in repeated passes, so a subfolder renamed inside a
  renamed or unchanged parent keeps its description, and a parent's move no longer reports every
  child as moved.
- Rename ties are broken deterministically: equal scores prefer the candidate with the same last
  name, then the one in the same parent folder, then the one with the same shape (as many files at
  each depth inside it), then the one at the same depth in the tree, then the lowest name. A chain
  of single-file folders renamed at every level now keeps every description.
- A described subfolder deleted inside a renamed parent is reported as `removed` under the path it
  had, not under the new path it never existed at.
- A partial `--reconcile` failure is no longer silent: each change is printed once it is on disk, a
  later failure ends the output with an `error` line and a non-zero exit, and the Stop hook reports
  it as a non-blocking message.
- `--find` folds accented capital letters, so `FACTURACIÓN` and `facturación` match each other.
- Folder names that are not valid UTF-8 are rejected as unrepresentable instead of corrupting the
  map, and descriptions are trimmed of surrounding whitespace.
- `cortex-map.sh` guards the `ROOT` resolution, and the scan checks for a git work tree once instead of on every listing.
- `install.sh` survives an invalid `.claude/settings.json` or `opencode.json` (unparseable, not a
  single JSON object, or several documents): it names the file, skips only that merge without
  touching the file, finishes every other step and exits non-zero. An empty file is treated as `{}`.
- `install.sh` leaves `.gitignore` alone when the target is not a git repository (it used to create
  one for `.claude/settings.local.json`). With git, a fresh `.gitignore` no longer starts blank.
- The `/cortex-sync` extension histogram no longer ends in `| head`, which broke under `pipefail`.

## [6.0.0] — 2026-10-19

### Changed
- The folder map is now one file per folder under `.cortex/map/` (`<folder>.cortex`, a single line of
  at most 120 characters) instead of one `MAP.md`. Two branches only conflict when they change the
  description of the same folder.
- Agents query the map with `cortex-map.sh --find <term>…` (all terms must match, most relevant first,
  at most 40 lines) instead of loading it whole.
- `cortex-map.sh --reconcile` moves the descriptions of renamed or moved folders and drops those of
  deleted ones by itself, using a local snapshot of the file list in `.cortex/.state/` (gitignored).
  `--drift` and `--check` remain; `--set` now enforces the 120-character limit.
- Knowledge files: `.cortex/LOOKUP.md` and `.cortex/MAINTAIN.md` replace `SYSTEM.md`. They are loaded
  through `.claude/rules/cortex.md` (Claude Code) and `opencode.json` (OpenCode). `LOOKUP.md` is also
  the marker the hooks and installer use to recognise a CORTEX project.
- The `SubagentStart` hook injects only `LOOKUP.md`, so Explore and Plan subagents get the lookup
  instructions. The `Stop` hook is stateless: it reconciles the map and blocks once per turn only for
  new folders without a description (at most 20 listed, with ready-to-copy `--set` commands).
- `.cortex/PROJECT.md` is created from `templates/PROJECT.md` (empty sections, project name as title)
  and never overwritten. `/cortex-sync` deduces Conventions from the code the first time, while the
  section is still `_None yet._`; after that Conventions and Notes belong to the user.
- `/cortex-sync` is rewritten: reconcile, describe pending folders, refresh Tech Stack, deduce
  Conventions (first run only), verify with `--drift`.
- The installer adds `.cortex/.state/` to `.gitignore` when the project uses git, and warns (without
  touching anything) when it finds v5 leftovers.

### Removed
- `SYSTEM.md` and `MAP.md`.
- The `SessionStart` hook (`cortex-session.sh`) and the `PostToolUse` hook (`cortex-file-change.sh`),
  plus the `.cortex/.touched/` record.
- `cortex-map.sh --validate`, `--lookup`, `--remove` and `--move` (reconciliation covers them).
- Workspace mode: `install-workspace-bridge.sh` and `.cortex-workspace.json`.

### Breaking
- v6 does not migrate a v5 install. Remove the v5 files by hand (below) and install v6. Open branches
  that edited `MAP.md` will hit a modify/delete conflict once; resolve it by deleting `MAP.md`.

### Upgrading from v5

Everything from v5 is deleted, including `PROJECT.md`: v6 installs the template and `/cortex-sync`
fills it in (Tech Stack detected, Conventions deduced from the code). Because `PROJECT.md` is in git,
nothing is lost; review `git diff .cortex/PROJECT.md` afterwards and restore by hand any convention
that is a decision rather than something the code shows.

1. Delete the files:
   ```bash
   rm -rf .cortex .claude/hooks/cortex-*.sh .claude/commands/cortex-sync.md .opencode/commands/cortex-sync.md
   ```
2. In `.claude/settings.json`, remove only the hook entries whose `command` points at
   `.claude/hooks/cortex-*`, keeping any hooks that are not CORTEX's:
   ```bash
   jq 'if .hooks then .hooks |= (map_values(map(.hooks |= map(select((.command // "") | test("\\.claude/hooks/cortex-") | not))) | map(select(.hooks | length > 0))) | with_entries(select(.value | length > 0))) | (if .hooks == {} then del(.hooks) else . end) else . end' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
   ```
3. In `opencode.json` (if present), remove `.cortex/SYSTEM.md`, `.cortex/MAP.md` and
   `.cortex/PROJECT.md` from `instructions`. v6 adds its own.
4. In `.gitignore`, remove `.cortex/.touched/` and its comment.
5. Workspace mode: delete `.cortex-workspace.json` if it exists in any parent directory.
6. Run the v6 installer, then run `/cortex-sync` to generate the map and deduce Conventions.
7. Commit the cleanup, the install and the generated map together.

## [5.0.3] — 2026-08-24

### Fixed
- `cortex-map.sh --lookup` no longer reports a mapped folder as `MISSING` (CTR-12620). The
  matching `awk` exited as soon as it found its target, which closed the pipe while `map_parse`
  was still streaming the rest of `MAP.md`; the producer died with SIGPIPE (141) and `pipefail`
  promoted that to the pipeline's status, so the branch that prints the description never ran.
  Since the failure depended on how far into the map the target sat, it hit essentially every
  folder except the last one — and the Stop hook, which calls `--lookup` per touched folder,
  repeated bogus "not in the map, add it" instructions every turn. The match action now drains
  its input instead of exiting early; paths are unique, so nothing else changes.
- The Stop hook's manifest check no longer loses its reminder on long sessions. `awk … | grep -q`
  had the same interaction — `grep -q` leaves on its first match and can SIGPIPE the `awk` still
  writing — so once a session's touch record outgrew the pipe buffer, a touched manifest was read
  as untouched and the PROJECT.md reminder disappeared silently. The check now reads the record
  directly, with no pipe.

## [5.0.2] — 2026-08-07

### Fixed
- `MAP.md`'s node tree is now wrapped in a fenced code block. Without it, every Markdown
  renderer (GitHub, GitLab, ...) collapses the indented tree into a single unreadable paragraph,
  since consecutive indented lines with no blank line between them merge into one paragraph
  rather than preserving line breaks. `cortex-map.sh --set`/`--remove` inject the fence on
  write, self-healing any map written before this existed the next time it is touched — no
  manual migration needed.

## [5.0.1] — 2026-08-07

### Fixed
- Session touch records (`.cortex/.touched-<session_id>`) now live under `.cortex/.touched/<session_id>`
  instead of as loose dotfiles directly in `.cortex/`. The Stop hook also deletes the record file once
  reconciled instead of truncating it to empty, so no zero-byte file lingers between turns.
  `install.sh` migrates the old `.gitignore` glob (`.cortex/.touched-*`) to the new directory-based
  rule (`.cortex/.touched/`) on existing installs.

## [5.0.0] — 2026-08-03

### Breaking changes

- **Map granularity is now per folder, not per project scale.** The flat/hierarchical split,
  areas, sub-maps and `index.json` are gone — there is one `MAP.md`, always loaded in full,
  regardless of project size. Existing installations need a reinstall (re-run `install.sh`) and
  a `/cortex-sync` to regenerate `MAP.md` in the new format.

### Added
- `.cortex/scripts/cortex-map.sh` — the only writer of `MAP.md`. `--set`/`--remove` maintain a
  folder-level entry and its ancestors; `--validate` checks indentation and structure;
  `--lookup` resolves a path by its full path, not by basename; `--drift` diffs the map against
  the filesystem and only ever proposes folders `--set` can actually accept; `--check` answers,
  read-only, whether a given path is representable at all — the one place every other component
  (the `Stop` hook, `--drift`) asks instead of re-deriving the rule.
- A folder name may contain interior or trailing spaces and non-ASCII characters — a node line
  in `MAP.md` ends the name at its slash, so the boundary stays unambiguous. What it cannot
  carry is a leading space in any segment (misread as indentation), a control character, or a
  top-level name opening with `#`/`>` (misread as header prose). `--set`/`--remove` reject those
  with a diagnostic and exit 2; no write is ever installed unless it reads back as exactly what
  was written, so a shape that slipped past every check still fails clean instead of leaving an
  unreadable map.
- `.cortex/PROJECT.md` — a per-project file with three sections: **Tech Stack** (agent-owned,
  refreshed from manifests), and **Conventions**/**Notes** (user-owned; the agent asks before
  editing either).
- `.claude/hooks/cortex-stop.sh` — `Stop` hook and the system's only decision point. Fires once
  per turn, reads the touch record left by `cortex-file-change.sh`, and blocks once if the map
  needs reconciling before returning control. Stateless by design: every turn is evaluated fresh.
  Every suggested command is single-quoted around the folder name it targets, so an unusual name
  (spaces, `$(...)`, quotes) can never be misread as shell syntax by the agent that runs it.
- `/cortex-sync` — the single command for building and maintaining the map. Idempotent: it
  generates the whole map on a fresh project and only closes gaps on a mature one. Replaces the
  `cortex-init`/`cortex-update` split.

### Changed
- Map granularity is now per folder: `MAP.md` documents every directory with a one-line
  description of what it contains, never a file name or naming pattern.
- `MAP.md` is written only by `cortex-map.sh` — no other script or hand-edit may touch it.
- `cortex-scan.sh`'s enumeration is NUL-delimited end to end, so a folder name holding a space,
  a non-ASCII character, or a stray quote reaches every caller (the map, `--drift`, the tech
  stack histogram) exactly as it exists on disk — never quoted, escaped, or split across lines
  by the scanning tool itself.
- `cortex-subagent.sh` (`SubagentStart`) now injects the full three-file context (`SYSTEM.md`,
  `PROJECT.md`, `MAP.md`) into subagents instead of a short note.
- `cortex-file-change.sh` (`PostToolUse`) is now a mute collector: it records touched paths per
  session and makes no decisions, emits no reminders, and never interrupts the agent — all
  decision-making moved to the new `Stop` hook.

### Removed
- Flat/hierarchical map modes, areas, `.cortex/maps/`, `index.json`, and per-area sub-maps.
- `.cortex/scripts/cortex-init.sh` and `.cortex/scripts/cortex-areas.sh`.
- The `cortex-init`, `cortex-update` and `cortex-view-map` commands and their templates
  (`.cortex/commands/`, `.claude/commands/`, `.opencode/commands/`).
- `.claude/hooks/cortex-map-load.sh` and the `PreToolUse` hook it was registered under.

## [4.2.0] — 2026-07-23

### Added
- `.cortex/scripts/cortex-scan.sh` — gitignore-aware file/directory scanner. Enumerates
  documentable files (or their parent directories) honoring `.gitignore` via `git
  ls-files` in git repos, falling back to `find` with common excludes otherwise.
  Always excludes the universal floor (`.git`, `.cortex`, `.claude`, `.opencode`).
- `.cortex/scripts/cortex-areas.sh` — scale-adaptive area partitioner and manifest
  writer. Below `CORTEX_FLAT_CAP` files, writes a flat manifest (no partitioning);
  above it, greedily splits oversized directories by subtree size
  (`CORTEX_AREA_CAP`), promotes subdirectories whose subtree size clears
  `CORTEX_MERGE_MIN`, collapses single-child pass-through directory chains to their
  deepest meaningful root, and rolls unclaimed root-level files into a synthetic
  `_misc` area. Writes `.cortex/maps/index.json` (`{version, flat, areas:[{root, map,
  files}]}`).
- Three-layer hierarchical map for large projects: root `MAP.md` becomes a
  lightweight, always-loaded **index**; each area gets its own on-demand sub-map at
  `.cortex/maps/<area>.md` (naming: `a/b/c` → `maps/a__b__c.md`); `.cortex/maps/
  index.json` is the manifest resolving any path to its area via longest-root-prefix
  match. Small/medium projects stay flat — no `maps/` directory, no behavior change.
- `.claude/hooks/cortex-map-load.sh` — PreToolUse hook: a safety net for hierarchical
  projects only. On `Grep`/`Glob`, reminds the agent to consult
  `.cortex/maps/index.json` and read the resolved sub-map instead of searching blind.
  On `Write` to a new path, reminds the agent to place the file per MAP.md's
  documented conventions and keep the relevant sub-map in sync. Silent on flat
  projects and non-CORTEX paths.
- `tests/map-test.sh` — test harness for `cortex-scan.sh` and `cortex-areas.sh`:
  gitignore-aware scanning, directory enumeration, non-git fallback, the flat/
  hierarchical partition gate, subtree splitting, tiny-leftover non-promotion, and
  single-child chain collapse, all against temporary fixtures.
- `.cortex/SYSTEM.md` §2.5 ("The hierarchical map") — standing instructions for
  discovering, placing, and maintaining files under the three-layer hierarchy.
  These instructions apply to every agent; on OpenCode (no hook mechanism) they are
  the entire enforcement mechanism, not a supplement to hooks.
- Best-effort tech stack cascade in `cortex-init`/`cortex-update`: tech stack
  detection now degrades gracefully across partial/missing manifests instead of
  assuming a single canonical dependency file, so genericity holds on unfamiliar
  stacks.

### Changed
- `install.sh` installs and registers `cortex-scan.sh`, `cortex-areas.sh`, and the
  new `cortex-map-load.sh` PreToolUse hook (idempotent); re-run it on installed
  projects to upgrade.
- `.cortex/commands/cortex-init.md` and `.cortex/commands/cortex-update.md`
  procedures rewritten to drive the scan → area-partition → per-area sub-map
  pipeline, falling back to the pre-existing flat behavior below the scale
  threshold.
- `SYSTEM.md` v4.2.0 — adds §2.5 and cross-references it from §2.4 so active
  enforcement (Claude Code hooks) and standing instructions (all agents, and the
  sole mechanism on OpenCode) read as one coherent story rather than two
  independent sections.

## [4.1.0] — 2026-07-20

### Added
- `.claude/hooks/cortex-file-change.sh` — PostToolUse hook: reminds the agent to
  update MAP.md at the exact moment a new file is created that the map does not
  reference, a documented file is deleted with a local `rm`, or a file is
  moved/renamed with a local `mv` (documented source now stale, and/or a new
  destination the map doesn't list). Detection is local only — `git rm`/`git mv`
  are not tracked; the map is kept in sync in reaction to local filesystem
  operations, not git commands. The `rm` reminder fires only when the deleted
  path is referenced in MAP.md, so scratch/temp cleanup stays silent while
  MAP.md never goes stale pointing at a file that no longer exists. Silent for
  undocumented/scratch deletions, plain edits, excluded paths, and non-CORTEX
  directories.
- `.claude/hooks/cortex-subagent.sh` — SubagentStart hook: injects a short CORTEX
  note into subagents (which never receive SessionStart context).
- `tests/hooks-test.sh` — pipe-test harness covering all hooks and installer
  registration (synthetic hook payloads; no live session required).

### Changed
- `cortex-session.sh` now injects the FULL content of MAP.md at session start
  (single-project mode, and the cwd project in workspace mode) instead of only an
  instruction to read it — bringing Claude Code to parity with OpenCode's
  `instructions` mechanism.
- `install.sh` registers the new PostToolUse and SubagentStart hooks (idempotent);
  re-run it on installed projects to upgrade.
- `SYSTEM.md` v4.1.0 — documents active enforcement (Claude Code-scoped) and adds
  an agent-agnostic obligation to brief subagents about CORTEX when dispatching.

## [4.0.0] — 2026-06-18

### Breaking changes

- **Knowledge moved to `.cortex/`** — all files previously in `.claude/cortex/` are now in `.cortex/` (agent-agnostic). Re-run `install.sh` for a clean install.
- **Enforcement via native agent mechanisms** — CLAUDE.md is no longer used for CORTEX enforcement. Claude Code uses a `SessionStart` hook (`cortex-session.sh`); OpenCode uses `opencode.json` → `instructions`. `CLAUDE.md` is no longer generated by the installer.
- **`.claude/settings.json` is now committed** — the hook registration lives there. Per-user overrides go in `.claude/settings.local.json` (gitignored). Update your `.gitignore` accordingly (installer handles this automatically).

### Added
- `.cortex/` knowledge directory — agent-agnostic home for SYSTEM.md, MAP.md, commands, and scripts
- `.claude/hooks/cortex-session.sh` — SessionStart hook that injects SYSTEM.md + MAP.md load order as `additionalContext` with full enforcement authority. Supports single-project and workspace modes.
- `.cortex-workspace.json` marker — replaces the CLAUDE.md workspace bridge; detected by `cortex-session.sh` to activate workspace mode
- `install.sh --agent claude|opencode|both` — agent selection flag; interactive prompt in TTY mode
- OpenCode support: `opencode.json` → `instructions` + `.opencode/commands/` slash commands
- Commands now have frontmatter `description:` field for both Claude Code and OpenCode compatibility

### Changed
- `install-workspace-bridge.sh` now generates `.cortex-workspace.json` (JSON marker) instead of a CLAUDE.md bridge
- `install.sh` no longer generates or modifies `CLAUDE.md` (eliminated `setup_claude_md`)
- `cortex-init.sh` `PROJECT_ROOT` calculation updated for new `.cortex/scripts/` location (2 levels up instead of 3)
- `SYSTEM.md` bumped to v4.0.0; updated structure diagram and compatibility section
- Commands (cortex-init, cortex-update, cortex-view-map) now live in `.cortex/commands/` as templates; installer copies them to `.claude/commands/` and/or `.opencode/commands/`

## [3.1.0] — 2026-05-18

### Added
- `cortex-update` command — incremental MAP.md updates that preserve existing content
- Tech Stack detection and table in MAP.md format

### Fixed
- `install.sh` now copies `cortex-update.md` to both `.claude/cortex/commands/` and `.claude/commands/`

## [3.0.0] — 2026-05-16

### Changed
- Complete rewrite as a dynamic knowledge system for AI coding agents
- MAP.md is now auto-generated and maintained by the agent, not manually written

### Added
- `cortex-init.sh` scanner script — walks project tree excluding common ignored directories
- `cortex-view-map` command — display the knowledge map with optional path filtering
- Multi-agent support: Claude Code, OpenCode, and any agent that reads CLAUDE.md

### Removed
- Legacy manual MAP.md editing workflow

## [2.0.0] — 2026-05-15

### Added
- Commands directory structure (`.claude/cortex/commands/`)
- `cortex-init` command for first-run project scanning
- Slash command support for Claude Code (`.claude/commands/`)

### Changed
- System structure updated to include commands directory

## [1.1.0] — 2026-05-14

### Added
- English translation of all system files

### Changed
- Rewritten as minimal project context system
- Updated install URLs to canonical `raw.githubusercontent.com`

## [1.0.0] — 2026-05-13

### Added
- Restructured system with isolated instructions and team governance
- Systematic change detection and verification (`cortex-sync`)

## [0.1.0] — 2026-05-11

### Added
- Initial release: persistent project memory for AI coding assistants
- MIT license with non-commercial redistribution clause
- `install.sh` — curl-based installer
- Web landing page for GitHub Pages
- README with installation and usage instructions

[Unreleased]: https://github.com/MaverickLBP/cortex/compare/v6.1.3...HEAD
[6.1.3]: https://github.com/MaverickLBP/cortex/compare/v6.1.2...v6.1.3
[6.1.2]: https://github.com/MaverickLBP/cortex/compare/v6.1.1...v6.1.2
[6.1.1]: https://github.com/MaverickLBP/cortex/compare/v6.1.0...v6.1.1
[6.1.0]: https://github.com/MaverickLBP/cortex/compare/v6.0.1...v6.1.0
[6.0.1]: https://github.com/MaverickLBP/cortex/compare/v6.0.0...v6.0.1
[6.0.0]: https://github.com/MaverickLBP/cortex/compare/v5.0.3...v6.0.0
[5.0.3]: https://github.com/MaverickLBP/cortex/compare/v5.0.2...v5.0.3
[5.0.2]: https://github.com/MaverickLBP/cortex/compare/v5.0.1...v5.0.2
[5.0.1]: https://github.com/MaverickLBP/cortex/compare/v5.0.0...v5.0.1
[5.0.0]: https://github.com/MaverickLBP/cortex/compare/v4.2.0...v5.0.0
[4.2.0]: https://github.com/MaverickLBP/cortex/compare/v4.1.0...v4.2.0
[4.1.0]: https://github.com/MaverickLBP/cortex/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/MaverickLBP/cortex/compare/v3.1.0...v4.0.0
[3.1.0]: https://github.com/MaverickLBP/cortex/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/MaverickLBP/cortex/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/MaverickLBP/cortex/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/MaverickLBP/cortex/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/MaverickLBP/cortex/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/MaverickLBP/cortex/releases/tag/v0.1.0
