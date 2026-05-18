# cortex-init — Generate the knowledge map (first run)

Generates `.claude/cortex/MAP.md` by scanning the project and documenting every directory and file.

Run this **once** when first setting up CORTEX in a project. For subsequent updates, use `cortex-update` instead.

**Invocation:**
- Claude Code: `/cortex-init`
- OpenCode / Any agent: "run cortex-init"

---

## When to use

- **First time** setting up CORTEX in a project → Use `cortex-init`
- **Project structure changed** (new files, deleted files, renames) → Use `cortex-update`
- **MAP.md format evolved** (new sections added) → Use `cortex-update`

---

## Procedure

### Step 0 — Detect tech stack

Before exploring directories, identify the project's technologies and versions:

1. Check package managers and lock files: `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lockb`
2. Check language/runtime files: `go.mod`, `Cargo.toml`, `requirements.txt`, `pyproject.toml`, `Gemfile`, `pom.xml`, `build.gradle`, `composer.json`
3. Check runtime/version files: `.nvmrc`, `.node-version`, `.python-version`, `.ruby-version`, `Dockerfile`, `docker-compose.yml`
4. Check framework/config files: `tsconfig.json`, `tailwind.config.*`, `vite.config.*`, `next.config.*`, `webpack.config.*`, `Cargo.toml`, `rust-toolchain.toml`
5. Extract **package name and version** from the most relevant dependencies (frameworks, runtimes, major libraries)

### Step 1 — Generate the directory tree

Execute the scanner script:

```bash
bash .claude/cortex/scripts/cortex-init.sh
```

The script prints a complete directory tree of the project (excluding `.git`, `node_modules`, and other common ignored directories).

### Step 2 — Explore and document

Take the tree output and, for **every directory** in the project:

1. Read files inside to understand their purpose
2. Identify:
   - What the directory contains (source code, configuration, tests, etc.)
   - Purpose of each file (utility, component, route, model, script, etc.)
   - Technologies used in each directory
3. Document concisely — focus on **what it is and where to find it**, not how it works internally

For deeply nested or very large directories, examine representative files to infer patterns.

### Step 3 — Write MAP.md

Generate `.claude/cortex/MAP.md` following this format:

```markdown
# Knowledge Map — [Project Name]

> Knowledge layer for AI coding agents.
> MAP.md generated: YYYY-MM-DD
> Keep this file updated as the project evolves.

---

## 🛠 Tech Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| Node.js    | 22.x    | Runtime |
| TypeScript | 5.7.x   | Language |
| React      | 19.x    | UI framework |
| ...        | ...     | ... |

_List only the most relevant technologies. Omit minor/dev-only dependencies unless they define the project architecture._

---

## 📁 src/
_All application source code_

### 📁 src/api/routes/
_REST API route definitions. Each file groups routes by resource._
- `auth.routes.ts` → Authentication endpoints (login, register, logout)
- `users.routes.ts` → User CRUD operations
```

Key rules:
- Use `📁` for directories with an italic description on the same line
- Use `-` with `→` for files: `filename.ext → One-line description of purpose`
- Group related files under their directory
- Be consistent with indentation and formatting
- Every file in the project gets an entry
- Tech Stack table: include only meaningful dependencies (frameworks, runtimes, databases, major libraries). Use `"latest"` or `"N/A"` if version cannot be determined.

### Step 4 — Preserve existing notes

If MAP.md already exists and contains **Notes** (decisions, gotchas, observations), preserve those at the bottom of the new file.

### Step 5 — Notify

Confirm the map was generated and invite the user to review it.
