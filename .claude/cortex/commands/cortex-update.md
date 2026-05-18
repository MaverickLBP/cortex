# cortex-update — Update the knowledge map

Updates `.claude/cortex/MAP.md` when the project structure changes or when the MAP.md format evolves. Unlike `cortex-init`, this command **preserves all existing content** and only adds, removes, or updates what has changed.

Run this when:
- New files or directories are added to the project
- Files are deleted or renamed
- The MAP.md format gains new sections (e.g. Tech Stack, Architecture, etc.)
- You want to refresh the map without losing custom notes

**Invocation:**
- Claude Code: `/cortex-update`
- OpenCode / Any agent: "run cortex-update"

---

## Procedure

### Step 1 — Read existing MAP.md

Read the current `.claude/cortex/MAP.md` and identify:
1. All existing sections (Tech Stack, directory entries, Notes, etc.)
2. The current format/template being used
3. Any custom content the user has added

### Step 2 — Generate the directory tree

Execute the scanner script:

```bash
bash .claude/cortex/scripts/cortex-init.sh
```

The script prints a complete directory tree of the project (excluding `.git`, `node_modules`, and other common ignored directories).

### Step 3 — Compare and identify changes

Compare the current MAP.md against the tree output:
- **New directories/files** → Add entries
- **Deleted directories/files** → Remove entries
- **Renamed/moved files** → Update paths
- **Unchanged entries** → Preserve as-is

### Step 4 — Detect missing sections

Check if the current MAP.md is missing any sections that the latest `cortex-init` format defines:
- `## 🛠 Tech Stack` (if not present, detect and add it)
- Any other standard sections defined in `cortex-init.md`

For each missing section:
1. Detect the required information (e.g. scan `package.json` for Tech Stack)
2. Insert the section in the correct position (Tech Stack goes after the header, before directory entries)
3. Preserve all existing content around it

### Step 5 — Write updated MAP.md

Write the updated `.claude/cortex/MAP.md`:
- Update the generation date in the header
- Preserve all existing Notes and custom content
- Add new entries for new files/directories
- Remove entries for deleted files/directories
- Add any missing standard sections
- Keep the same formatting style as the existing file

### Step 6 — Report changes

Summarize what was updated:
- Number of new entries added
- Number of entries removed
- New sections added (if any)
- Any files that could not be documented

Example:
> "MAP.md updated, sir. 12 new entries added, 3 removed. Tech Stack section added. Notes preserved."
