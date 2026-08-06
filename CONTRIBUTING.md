# Contributing to CORTEX

Thank you for your interest in contributing. CORTEX is designed to be lightweight and agent-agnostic — contributions that keep it that way are always welcome.

## How to contribute

### Reporting bugs

- Check the [issue tracker](https://github.com/MaverickLBP/cortex/issues) to avoid duplicates.
- Open a new issue with:
  - A clear title and description.
  - Steps to reproduce the problem.
  - Expected vs. actual behaviour.
  - Your environment (OS, agent used — Claude Code, OpenCode, etc.).

### Suggesting features

- Open an issue with the `enhancement` label.
- Describe the problem you're trying to solve, not just the solution you have in mind.
- Keep CORTEX's philosophy in mind: **no runtime dependencies, Markdown-first, agent-agnostic**.

### Pull requests

1. Fork the repository.
2. Create a branch from `main` with a descriptive name:
   ```
   git checkout -b fix/install-cortex-sync
   git checkout -b feat/add-cortex-diff
   ```
3. Make your changes. Follow the existing style and conventions.
4. Test your changes:
   - Run `bash -n install.sh install-workspace-bridge.sh` to validate bash syntax.
   - Test the installer: `bash install.sh --source /path/to/cortex --agent claude /tmp/test-project`
   - Test the workspace bridge: `bash install-workspace-bridge.sh --file /path/to/workspace.code-workspace`
   - Verify commands are copied to `.claude/commands/` and/or `.opencode/commands/` per agent.
5. Commit with a conventional commit message:
   ```
   feat: add cortex-diff command
   fix: install cortex-sync in install.sh
   docs: update README with new badges
   ```
6. Open a pull request against `main`.

## Development workflow

### Local testing

To test changes without pushing:

```bash
# Install CORTEX from your local copy into a test project (Claude Code)
bash install.sh --source /path/to/cortex --agent claude /tmp/test-project

# Verify the installed files
ls -la /tmp/test-project/.cortex/
ls -la /tmp/test-project/.claude/commands/
ls -la /tmp/test-project/.claude/hooks/
jq . /tmp/test-project/.claude/settings.json

# Test OpenCode installation
bash install.sh --source /path/to/cortex --agent opencode /tmp/test-project-oc
ls -la /tmp/test-project-oc/.opencode/commands/
jq . /tmp/test-project-oc/opencode.json

# Test the workspace bridge (requires a .code-workspace file)
bash install-workspace-bridge.sh --file /path/to/project.code-workspace
cat /path/to/.cortex-workspace.json

# Test the hook directly
echo '{"cwd":"/tmp/test-project"}' | bash /tmp/test-project/.claude/hooks/cortex-session.sh | jq .
```

### Adding a new command

1. Create the command definition in `.cortex/commands/<command-name>.md` with frontmatter `description:` field.
2. Add the copy block to `install.sh` for **both agent dirs**:
   - `.claude/commands/<command-name>.md` (Claude Code)
   - `.opencode/commands/<command-name>.md` (OpenCode)
3. Document the command in `SYSTEM.md` if it changes agent behaviour.
4. Update `CHANGELOG.md` under `[Unreleased]`.

### Updating MAP.md format

If you change the MAP.md template or structure:

1. Update `cortex-map.sh` and `cortex-sync.md` to reflect the new format.
2. Bump the version in `SYSTEM.md`.
3. Add an entry to `CHANGELOG.md`.

## Commit message conventions

We use [Conventional Commits](https://www.conventionalcommits.org/):

| Type       | When to use                          |
|------------|--------------------------------------|
| `feat`     | New feature or command               |
| `fix`      | Bug fix                              |
| `docs`     | Documentation changes                |
| `refactor` | Code restructuring, no behaviour change |
| `i18n`     | Translations                         |
| `chore`    | Maintenance, tooling, CI             |

## Philosophy

CORTEX follows three rules:

1. **No runtime dependencies** — It's Markdown and bash. Nothing more.
2. **Agent-agnostic knowledge** — `.cortex/` is shared; agent-specific config lives in `.claude/` or `.opencode/`.
3. **Living documentation** — MAP.md is maintained by the agent, not by hand.

If your contribution respects these rules, it will be welcome.
