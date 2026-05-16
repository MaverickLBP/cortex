# cortex-init — Generate the knowledge map

Generates `.claude/cortex/MAP.md` by scanning the project and documenting every directory and file.

Run this **once** when first setting up CORTEX in a project, or when the project structure changes significantly.

**Invocation:**
- Claude Code: `/cortex-init`
- OpenCode / Any agent: "run cortex-init"

---

## Procedure

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

### Step 4 — Preserve existing notes

If MAP.md already exists and contains **Notes** (decisions, gotchas, observations), preserve those at the bottom of the new file.

### Step 5 — Notify

Confirm the map was generated and invite the user to review it.
