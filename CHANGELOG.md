# Changelog

All notable changes to CORTEX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/MaverickLBP/cortex/compare/v5.0.0...HEAD
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
