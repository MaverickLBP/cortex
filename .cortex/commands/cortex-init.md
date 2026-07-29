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

Areas partition files **disjointly**: when a parent directory has its own files AND an oversized child directory that got promoted to its own area, both appear as separate entries in `.cortex/maps/index.json`, and each area's `files` count is *exclusive* of any deeper area's files. So an area's file listing must exclude anything owned by a deeper nested area — otherwise the same files get documented twice and the coverage count in step 4 won't reconcile with the manifest.

For **each area** listed by `cortex-areas.sh`, independently:

1. List the area's files, **excluding any deeper nested area's files**:
   - First check `.cortex/maps/index.json` for any *other* area whose `root` nests under this area's root (i.e. `other.root` starts with `<this-area-root>/`). Collect all such deeper roots.
   - **General case** (area root is a real path, not `.`):
     ```bash
     # List this area's OWN files (excluding any deeper nested area's files)
     bash .cortex/scripts/cortex-scan.sh --files | grep -E '^<area-root>/' \
       | grep -vE '^<deeper-area-root-1>/|^<deeper-area-root-2>/'   # one -vE clause per deeper area, if any
     ```
     If no other area nests under this one, drop the `grep -v` entirely and just use `grep -E '^<area-root>/'`.
   - **Root/`_misc` case** (area root is `"."`, map `maps/_misc.md`): the general `<area-root>/` pattern doesn't apply — `cortex-scan.sh --files` output has no `./` prefix, so `grep -E '^\./'` would match nothing. `_misc` is **not** just root-level loose files — it is a catch-all for every documentable file not claimed by any *other* (promoted) area's root, which also includes files inside a top-level directory that fell below `CORTEX_MERGE_MIN` and was never promoted to its own area. Read `.cortex/maps/index.json`, collect every other area's `root` value (i.e. every area except `_misc` itself), and exclude each of their prefixes:
     ```bash
     # For the root-level "_misc" area (root "."): all files EXCLUDING every
     # other area's root prefix (read .cortex/maps/index.json for the full
     # list of area roots first).
     bash .cortex/scripts/cortex-scan.sh --files \
       | grep -vE '^<area-root-1>/|^<area-root-2>/|...'   # one -vE clause per REAL area in index.json
     ```
     This correctly drops files inside promoted areas while keeping both root-level loose files and files inside any top-level directory that never got promoted (sub-`MERGE_MIN` directories) — exactly what `cortex-areas.sh` itself counts into `_misc`. If there are no other areas, drop the `grep -v` entirely and just use the raw `--files` output.
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
- **Full pointer coverage** — if a directory's description names specific subfolders individually (e.g. a "notable subfolders" bullet list), **every named subfolder must be followed by its own `detail for <path>/ → .cortex/<map>` line**, not just the folders that got promoted to their own area. Resolve the target by longest-root-prefix match against `.cortex/maps/index.json`: if the subfolder is itself an area, point to its own map; if it isn't (too small to promote), point to the nearest ancestor area's map that actually contains it. Never name a subfolder in prose without also saying where it's documented — a reader should never have to guess which sub-map covers a path they saw mentioned.

For a **flat** repo, `MAP.md` documents every file directly and there is no `maps/` directory.

Format rules: `📁` for directories with an italic description; `-` + `→` for files; be consistent.

### Step 3b — Verify pointer coverage

Before moving on, re-scan the `MAP.md` you just wrote: for every subfolder path named in a bullet list, confirm a `detail for` line resolves it (either its own or an ancestor's). If any are missing, add them now — don't leave this for a future pass. This is the same defect class as an undocumented file: a path mentioned but not pointed anywhere.

### Step 4 — Preserve existing Notes

If `MAP.md` already exists and contains **Notes**, preserve them at the bottom.

### Step 5 — Notify

Confirm the map was generated (flat or hierarchical, area count, total files documented) and invite review.
