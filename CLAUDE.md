# CLAUDE.md

## Project Overview

A Claude Code plugin marketplace called "mover-skillz". Plugins are stored under `plugins/` and distributed via the Claude Code plugin marketplace system.

## Marketplace Structure

```
.claude-plugin/marketplace.json  — marketplace catalog
plugins/<name>/.claude-plugin/plugin.json  — plugin manifest
plugins/<name>/skills/<skill>/SKILL.md  — skill definitions
```

## Versioning

- All plugins use semantic versioning (MAJOR.MINOR.PATCH), starting at 1.0.0
- **When making any change to a plugin, you MUST bump the version in BOTH:**
  - `plugins/<name>/.claude-plugin/plugin.json`
  - `.claude-plugin/marketplace.json`
- The versions in both files MUST match
- Bump patch for fixes, minor for new features, major for breaking changes

## Git Workflow

- Default branch: `main`
- Branch naming: `issue-<number>-<short-description>`
- Always branch from `main` for new work

## Pull Requests

- PR title should reference the issue being resolved (e.g., "Fix #42: short description")
- PR body should include a short summary of what was changed and why
- Link the issue in the PR body using `Closes #<number>`

## Testing

### Running All Tests

```bash
./tests/run-tests.sh
```

### Running Tests for a Specific Plugin

```bash
./tests/run-tests.sh gh-issue-autopilot
```

### Test Structure

- `tests/helpers.sh` — shared test framework (assertions, temp repos, mocks)
- `tests/validate-skills.sh` — Layer 1: structural validation for all plugins (plugin.json, marketplace.json, SKILL.md)
- `tests/<plugin-name>/test-*.sh` — Layer 2: behavioral tests per plugin

### Adding Tests for a New Plugin

Create `tests/<plugin-name>/` and add `test-*.sh` files. They are auto-discovered by the runner.
