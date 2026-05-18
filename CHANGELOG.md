# Changelog

All notable changes to CORTEX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `install-workspace-bridge.sh` — generates a CLAUDE.md bridge from `.code-workspace` files for multi-project workspaces
- Interactive mode in `install.sh` — prompts for project path when run without arguments

### Changed
- `cortex-workspace.sh` renamed to `install-workspace-bridge.sh` and simplified (single purpose: bridge generation)
- Workspace bridge reduced to a single prompt for the `.code-workspace` file path

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

[Unreleased]: https://github.com/MaverickLBP/cortex/compare/v3.1.0...HEAD
[3.1.0]: https://github.com/MaverickLBP/cortex/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/MaverickLBP/cortex/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/MaverickLBP/cortex/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/MaverickLBP/cortex/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/MaverickLBP/cortex/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/MaverickLBP/cortex/releases/tag/v0.1.0
