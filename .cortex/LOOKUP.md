# CORTEX — Finding things

This project keeps a folder map: one short description per folder, in `.cortex/map/`.

- Before searching the repository for where something lives, ask the map first:
  `bash .cortex/scripts/cortex-map.sh --find <term>` (matches folder paths and descriptions).
- Several terms narrow the search: a folder must match all of them. Pair a domain word with a kind
  word (`--find incident redux`, `--find invoice styles`). Synonyms go in separate calls, which can
  share one command: `--find i18n; --find translation`.
- A line ending in `(+N subfolders match)` stands for its whole subtree; add a term to see inside it.
- Try a couple of terms (domain word, synonym, the other language used in the code) before falling
  back to grep/find.
- Once the map names a folder, open that folder and read it. Do not repeat a repository-wide search
  to confirm what the map already told you.
- If the folder you expect is not in the map, the map may be stale: search normally and mention it.
- Before proposing code or structure, read `.cortex/PROJECT.md` (stack and conventions).
- Never edit anything under `.cortex/` by hand.
