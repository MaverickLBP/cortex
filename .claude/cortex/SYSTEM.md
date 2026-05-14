# CORTEX — System Instructions

> System file. **Do not modify manually.**
> To change project context, edit `context.md`.
> Version: 2.0.0

---

## 1. Context loading

When starting a session, the assistant MUST load `.claude/cortex/context.md` and use its contents as the project reference. This file contains the tech stack, directory structure, conventions, commands, and project notes.

## 2. Using the context

- **Stack:** use the listed technologies. Do not propose dependencies already covered by the existing stack.
- **Structure:** locate files using the directory map before resorting to filesystem search tools. This avoids unnecessary disk reads.
- **Conventions:** new code must follow documented patterns and rules.
- **Commands:** use the exact commands for common tasks (dev, test, build, lint, etc.). Do not improvise flags or paths.
- **Notes:** consult this section before working in areas with documented gotchas or decisions.

## 3. Context maintenance

The assistant MUST keep `context.md` updated autonomously:

| Situation | Action |
|-----------|--------|
| Stack, structure or commands no longer reflect the project reality | Update the corresponding section |
| An undocumented gotcha, trap or unexpected behavior is discovered | Add a dated entry in **Notes** |
| A non-obvious technical decision is made (architecture, library, approach) | Add a dated entry in **Notes** with rationale and discarded alternatives |
| A recurring pattern is detected in 2+ places in the codebase | Document it in **Conventions** |

These updates need not be announced. The assistant performs them silently as part of normal operation.

## 4. Compatibility with other systems

CORTEX lives exclusively in `.claude/cortex/`. Other systems may coexist in `.claude/` without interference. Each system has its own `SYSTEM.md` which the assistant loads according to the root `CLAUDE.md` references.

## 5. System structure

```
.claude/cortex/
├── SYSTEM.md       ← This file. Behaviour instructions.
└── context.md      ← Project data. The only editable file.
```
