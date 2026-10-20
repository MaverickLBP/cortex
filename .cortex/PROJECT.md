# Project — CORTEX

## Tech Stack

| Technology | Version | Purpose | Source |
|------------|---------|---------|--------|
| Bash | 3.2+ | Scanner, map writer, hooks, installers | extension histogram |
| Markdown | N/A | Knowledge files and command definitions | extension histogram |
| jq | any | JSON handling in hooks and installer | required by hooks |
| HTML/CSS/JS | N/A | Static project website in `docs/` | extension histogram |

_CORTEX has no runtime dependencies: it is a knowledge layer built from Markdown files and bash scripts._

## Conventions

- Agent-agnostic knowledge and scripts live in `.cortex/`; they are always committed.
- Claude Code specifics live in `.claude/`; OpenCode specifics in `.opencode/` and `opencode.json`.
- Scripts go in `.cortex/scripts/`, one responsibility each, invoked as `bash <script>`.
- Command definitions go in `.cortex/commands/` and are copied to the agent directories by the installer.
- Hooks go in `.claude/hooks/`, one file per hook event, and must exit 0 on every error path.
- Test harnesses go in `tests/`, are plain bash, and require no Claude session to run.
- Design specs go in `docs/superpowers/specs/`, implementation plans in `docs/superpowers/plans/` (both gitignored, local-only).
- The folder map lives in `.cortex/map/`, one `<folder>.cortex` file per folder, written only by `.cortex/scripts/cortex-map.sh` (`--set`/`--find`/`--reconcile`/`--drift`). Never hand-edit it.

## Notes

_None yet._
