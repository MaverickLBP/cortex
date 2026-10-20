# CORTEX — Finding things

This project keeps a folder map: one short description per folder, in `.cortex/map/`.

- Before searching the repository for where something lives, ask the map first:
  `bash .cortex/scripts/cortex-map.sh --find <term>` (matches folder paths and descriptions).
- Try a couple of terms (domain word, synonym, the other language used in the code) before falling
  back to grep/find.
- If the folder you expect is not in the map, the map may be stale: search normally and mention it.
- Before proposing code or structure, read `.cortex/PROJECT.md` (stack and conventions).
- Never edit anything under `.cortex/` by hand.
