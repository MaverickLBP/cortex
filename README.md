# CORTEX — Context-Oriented Runtime Technical Experience

**Persistent project memory for AI coding assistants.**

CORTEX is a self-feeding knowledge system that lives inside your project's `.claude/` directory. It gives any AI agent — Claude Code, OpenCode, Cursor, etc. — persistent context across sessions: decisions, gotchas, patterns, architecture, and session state.

When you work, CORTEX silently learns. When you return, CORTEX remembers.

---

## How it works

```
your-project/
├── CLAUDE.md              ← "This project uses CORTEX → .claude/CLAUDE.md"
└── .claude/               ← CORTEX system
    ├── CLAUDE.md          ← Full system instructions (loaded by agent)
    ├── settings.json      ← Claude Code hooks
    ├── commands/          ← Slash commands (/cortex-init, etc.)
    └── cortex/            ← Persistent knowledge base
        ├── map/           ← Architecture, dependencies
        ├── memory/        ← Decisions, gotchas, patterns
        ├── ops/           ← Environment, workflows, onboarding
        ├── state/         ← Scope, tech debt
        └── sessions/      ← Session state and context
```

CORTEX provides:

| Capability | Description |
|------------|-------------|
| **🧠 Persistent memory** | Decisions, gotchas, and patterns survive across sessions |
| **⚡ Autonomous logging** | The agent records technical decisions without being asked |
| **🔍 Preflight checks** | Before starting a task, CORTEX checks for relevant context |
| **📋 Session management** | Save, load, and close work sessions with full context |
| **🌐 Agent-agnostic** | Works with Claude Code, OpenCode, Cursor, and any AI coding agent |
| **🔌 Slash commands** | Claude Code: `/cortex-init`, `/cortex-preflight`, `/cortex-session-new`, etc. |

---

## Installation

### Option A: Copy manually

```bash
# From your project root:
# 1. Copy CLAUDE.md to your project root
curl -O https://raw.githubusercontent.com/MaverickLBP/cortex/main/CLAUDE.md

# 2. Copy .claude/ to your project
git clone https://github.com/MaverickLBP/cortex.git /tmp/cortex
cp -r /tmp/cortex/.claude ./
rm -rf /tmp/cortex
```

### Option B: Git submodule

```bash
git submodule add https://github.com/MaverickLBP/cortex.git .cortex
cp .cortex/CLAUDE.md .
cp -r .cortex/.claude .
```

### Option C: Just the loader

If your project already has a `CLAUDE.md`, just add this line at the top:

```markdown
This project uses **CORTEX** for persistent project memory.
→ Load `.claude/CLAUDE.md` for the complete system instructions.
```

Then copy `.claude/` into your project as above.

---

## Quick start

Once installed, just start working. New sessions track your work automatically:

```
User: "Nueva sesión: refactor auth module"
Agent: Creates session S001, loads context, begins work.
```

When you come back after a break:

```
User: "Carga sesión S001"
Agent: Restores full context — last step, active files, blockers.
```

Manual commands are available for seeding the knowledge base:

| Command | Description |
|---------|-------------|
| `/cortex-init` | Explore project and generate architecture, dependencies, workflows |
| `/cortex-preflight` | Check relevant decisions, gotchas, tech debt before a task |
| `/cortex-sync` | Resync MAP and OPS after structural changes |
| `/cortex-onboard` | Generate onboarding document for new developers |
| `/cortex-session-new` | Create a new work session |
| `/cortex-session-save` | Save current session state |
| `/cortex-session-load` | Restore a paused session |
| `/cortex-session-list` | List all sessions |
| `/cortex-session-close` | Close a completed session |

---

## Compatibility

| Agent | Status | Notes |
|-------|--------|-------|
| **Claude Code** | ✅ Full | Slash commands, settings hooks, CLAUDE.md |
| **OpenCode** | ✅ Full | Natural language commands, CLAUDE.md |
| **Cursor** | ✅ Full | CLAUDE.md supported |
| **GitHub Copilot** | ✅ Partial | CLAUDE.md instructions, no slash commands |
| **Any agent** | ✅ Basic | Reads CLAUDE.md, follows path instructions |

---

## Requirements

- An AI coding assistant that reads `CLAUDE.md` (all major ones do)
- For Claude Code: version 4.0+ (for slash commands support)

---

## License

MIT with Non-Commercial Redistribution — see [LICENSE](./LICENSE).

You are free to use CORTEX as a development tool in any project, including
commercial projects. You may NOT sell, sublicense, or charge for the Software
itself.
