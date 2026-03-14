# CLAUDE.md

## Project Overview

A collection of custom skills for Claude Code. Skills are stored under `skills/` and symlinked into `~/.claude/skills/` via `install.sh`.

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

### Running Tests for a Specific Skill

```bash
./tests/run-tests.sh gh-issue-autopilot
```

### Test Structure

- `tests/helpers.sh` — shared test framework (assertions, temp repos, mocks)
- `tests/validate-skills.sh` — Layer 1: structural validation for all skills (SKILL.md, frontmatter, install/uninstall)
- `tests/<skill-name>/test-*.sh` — Layer 2: behavioral tests per skill

### Adding Tests for a New Skill

Create `tests/<skill-name>/` and add `test-*.sh` files. They are auto-discovered by the runner.
