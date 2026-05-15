# cortex-init — Generate project context

Generates `.claude/cortex/context.md` by scanning the project.
Run this once when first setting up CORTEX in a new project.
Afterwards, `context.md` is maintained automatically by the agent and via git.

Claude Code: `/cortex-init`
OpenCode / others: "run cortex-init"

---

## Procedure

### 1. Detect the tech stack

Read dependency manifests in order of likelihood:
- `package.json` — Node.js / TypeScript / JavaScript
- `Cargo.toml` — Rust
- `pyproject.toml` or `requirements.txt` — Python
- `go.mod` — Go
- `Gemfile` — Ruby
- `pom.xml` or `build.gradle` — Java / Kotlin

For each dependency found, extract name and version. Identify:
- Language runtime (Node.js, Python, Rust, Go, etc.)
- Framework (Next.js, React, Django, Axum, etc.)
- Database / ORM (PostgreSQL, Prisma, Drizzle, etc.)
- Testing tools (Vitest, Jest, pytest, etc.)
- CI/CD configuration (GitHub Actions, etc.)

### 2. Map the directory structure

Explore the project root to a depth of 2–3 levels. Identify main directories:

| Directory | Typical purpose |
|-----------|----------------|
| `src/` or `app/` | Source code |
| `tests/` or `__tests__/` | Tests |
| `docs/` | Documentation |
| `scripts/` or `bin/` | Utility scripts |
| `config/` | Configuration files |
| `infra/` or `deploy/` | Infrastructure / deployment |

Use `ls <dir>` or glob patterns — do not use `find` or `tree` unless necessary.

### 3. Extract conventions

Examine existing code files for:
- Naming conventions (camelCase, snake_case, PascalCase)
- File organisation (colocated tests, feature folders, flat structure)
- Import/require style (relative vs absolute paths, index re-exports)
- Configuration files: `.eslintrc`, `.prettierrc`, `tsconfig.json`, `rustfmt.toml`, `editorconfig`

Check 3–5 representative source files to infer patterns.

### 4. Extract commands

Read build/run configuration files:
- `package.json` → `scripts` section
- `Makefile` → targets
- `Justfile` or `Taskfile.yml` → tasks
- `Dockerfile` or `docker-compose.yml` → build/run commands

List exact commands for: development server, testing, building, linting/formatting, deploying.

### 5. Write context.md

Generate `.claude/cortex/context.md` with the standard sections:

```
# Project Context

## Tech stack
[table of technologies with versions and purpose]

## Project structure
[directory tree with descriptions]

## Conventions
[naming, organisation, patterns]

## Commands
[exact commands for dev, test, build, lint, deploy]

## Notes
[empty, ready for future entries]
```

If `context.md` already exists with content in the **Notes** section, preserve that content.

### 6. Notify the user

Confirm the file was generated and ask the user to review it, especially the **Purpose** column in the tech stack and any missing directories.
