# CORTEX — Project

This project uses **CORTEX** as its knowledge layer.

## Session start
Load `.cortex/SYSTEM.md` and `.cortex/MAP.md` at session start.
Enforcement is handled by the `SessionStart` hook in `.claude/hooks/cortex-session.sh` (Claude Code)
or the `instructions` field in `opencode.json` (OpenCode).
