---
description: Generate the knowledge map (first run). Scans the project and writes .cortex/MAP.md.
---

# cortex-init — Generate the knowledge map (first run)

Generates `.cortex/MAP.md` by scanning the project and documenting every directory and file.

Run this **once** when first setting up CORTEX in a project. For subsequent updates, use `cortex-update` instead.

---

## When to use

- **First time** setting up CORTEX in a project → Use `cortex-init`
- **Project structure changed** (new files, deleted files, renames) → Use `cortex-update`
- **MAP.md format evolved** (new sections added) → Use `cortex-update`

---

## Procedure

### Step 0 — Detect tech stack (best-effort cascade, never blocks)

Detect technologies using a degrading cascade. Every level is optional; nothing here blocks map generation. Tag each entry with its source.

1. **Known manifest** — parse recognised manifests (`package.json`, `pom.xml`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `composer.json`, `Gemfile`, `pubspec.yaml`) for name + key deps + versions.
2. **Unknown manifest** — if a manifest-looking file has no parser (`mix.exs`, `deno.json`, `build.zig`, `*.csproj`), record that it exists without deep parsing.
3. **Extension histogram (universal floor)** — run:
   ```bash
   bash .cortex/scripts/cortex-scan.sh --files | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -15
   ```
   Dominant extensions reveal the language(s) on any repo. This guarantees the Tech Stack table is never empty.
4. **Toolchain signals** — `.nvmrc`, `.tool-versions`, `.ruby-version`, Dockerfile `FROM`, CI files — to refine versions.

Unknown version → `latest`/`N/A`. Never treat missing detection as an error.

### Step 1 — Partition into areas

Run the area partitioner (it also writes `.cortex/maps/index.json`):

```bash
bash .cortex/scripts/cortex-areas.sh
```

The partitioner uses `cortex-scan.sh` internally, which respects your project's `.gitignore` to exclude files and directories you don't want documented.

- Output `FLAT <n>` → the repo is small (≤ 150 files). Generate a **single flat `MAP.md`** documenting every file directly (as before). Skip Step 2; go to Step 3 (flat variant).
- Output `AREA <root> <n>` lines → the repo is large. Proceed with hierarchical generation.

### Step 2 — Generate per-area sub-maps (hierarchical only)

For **each area** listed by `cortex-areas.sh`, independently:

1. List the area's files:
   ```bash
   bash .cortex/scripts/cortex-scan.sh --files | grep -E '^<area-root>/'
   ```
2. Read enough of each file to state its purpose in one line. Because an area is bounded (~≤ 60 files) you can reach **every** file — do not summarise at directory level.
3. Write `.cortex/maps/<area>.md` (filename from the manifest's `map` field). Format:
   ```markdown
   # Area map — <area-root>/

   > Loaded on demand. Part of the CORTEX hierarchical map.

   - `path/to/file.ext` → one-line purpose. Key funcs: `foo()`, `bar()`.
   ```
   Include key/public functions or exports where they help the agent go straight to the file.
4. **Log coverage** for the area: files found vs documented. The count of undocumented files must be 0, or list them explicitly.

### Step 3 — Write the root index (`MAP.md`)

`MAP.md` is the always-loaded index. It must contain:

- **Tech Stack** table (Step 0), each row tagged with its source.
- **100% of directories** described (what each contains, its purpose) — never omit a directory.
- **Project conventions** — where utilities/services/tests/components/etc. live (so new files are placed correctly without loading a sub-map).
- **Area pointers** — for each area: `detail for <root>/ → .cortex/<map>`.

For a **flat** repo, `MAP.md` documents every file directly and there is no `maps/` directory.

Format rules: `📁` for directories with an italic description; `-` + `→` for files; be consistent.

### Step 4 — Preserve existing Notes

If `MAP.md` already exists and contains **Notes**, preserve them at the bottom.

### Step 5 — Notify

Confirm the map was generated (flat or hierarchical, area count, total files documented) and invite review.
