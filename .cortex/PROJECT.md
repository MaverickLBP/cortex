# Project — CORTEX

## Tech Stack

| Technology | Version | Purpose | Source |
|------------|---------|---------|--------|
| Bash | 4+ | Scanner, map writer, hooks, installers | extension histogram |
| Markdown | N/A | Knowledge files and command definitions | extension histogram |
| jq | any | JSON handling in hooks and installer | required by hooks |

_CORTEX has no runtime dependencies: it is a knowledge layer built from Markdown files and bash scripts._

## Conventions

- Agent-agnostic knowledge and scripts live in `.cortex/`; they are always committed.
- Claude Code specifics live in `.claude/`; OpenCode specifics in `.opencode/` and `opencode.json`.
- Scripts go in `.cortex/scripts/`, one responsibility each, invoked as `bash <script>`.
- Command definitions go in `.cortex/commands/` and are copied to the agent directories by the installer.
- Hooks go in `.claude/hooks/`, one file per hook event, and must exit 0 on every error path.
- Test harnesses go in `tests/`, are plain bash, and require no Claude session to run.
- Design specs go in `docs/superpowers/specs/`, implementation plans in `docs/superpowers/plans/` (both gitignored, local-only).
- `.cortex/MAP.md` is a folder-level map, written only by `.cortex/scripts/cortex-map.sh` (`--set`/`--remove`/`--drift`/`--validate`). Never hand-edit it — its indentation is structural, not cosmetic.

## Notes

_None yet._
