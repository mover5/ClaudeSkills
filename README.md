# ClaudeSkills

A collection of custom skills for [Claude Code](https://claude.com/claude-code).

## Skills

| Skill | Description |
|-------|-------------|
| [gh-issue-autopilot](skills/gh-issue-autopilot/) | Solve GitHub Issues automatically or interactively. Supports autopilot loop mode, single-issue manual mode, repo setup, and label config. |

## Installation

```bash
git clone https://github.com/mover5/ClaudeSkills.git
cd ClaudeSkills
./install.sh
```

This symlinks all skills into `~/.claude/skills/` so they're available in every Claude Code session.

### Install a specific skill

```bash
./install.sh gh-issue-autopilot
```

### Update

Pull the latest and re-run install (symlinks already point to the repo, so a `git pull` is usually enough):

```bash
cd ClaudeSkills
git pull
```

### Uninstall

```bash
./uninstall.sh              # all skills
./uninstall.sh gh-issue-autopilot  # specific skill
```

## Adding a new skill

1. Create a directory under `skills/` with the skill name
2. Add a `SKILL.md` file following the [Claude Code skill format](https://docs.anthropic.com/en/docs/claude-code/skills)
3. Run `./install.sh <skill-name>` to symlink it
