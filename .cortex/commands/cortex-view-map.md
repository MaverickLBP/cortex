---
description: Display the current project knowledge map (MAP.md).
---

# cortex-view-map — View the knowledge map

Display the current project knowledge map (MAP.md) in a readable format.

With optional filter:
- `/cortex-view-map src/api` — show only the section for a specific directory
- `/cortex-view-map database` — filter by keyword or path

---

## Procedure

### Without filter

Read `.cortex/MAP.md` and present its contents to the user. Format it cleanly, preserving the directory structure, file lists, and descriptions.

### With filter

If the user provides a path or keyword, locate the matching section(s) in MAP.md and display only those, including the parent hierarchy for context.

### If MAP.md is empty or missing

Inform the user the map has not been generated yet and suggest running `/cortex-init` first.
