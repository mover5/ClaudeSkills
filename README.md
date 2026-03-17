# ClaudeSkills

A plugin marketplace for [Claude Code](https://claude.com/claude-code).

## Plugins

| Plugin | Description |
|--------|-------------|
| [gh-issue-autopilot](plugins/gh-issue-autopilot/) | Solve GitHub Issues automatically or interactively. Supports autopilot loop mode, single-issue manual mode, repo setup, and label config. |

## Installation

Add the marketplace to Claude Code:

```
/plugin marketplace add mover5/ClaudeSkills
```

Then install a plugin:

```
/plugin install gh-issue-autopilot@mover-skillz
```

## Updates

Plugins are versioned with semver. To get the latest versions:

```
/plugin marketplace update mover-skillz
```

Or enable auto-update in `/plugin` > Marketplaces > mover-skillz.

## Adding a new plugin

1. Create a directory under `plugins/<plugin-name>/`
2. Add `.claude-plugin/plugin.json` with name, description, version, and author
3. Add skills under `plugins/<plugin-name>/skills/<skill-name>/SKILL.md`
4. Add the plugin entry to `.claude-plugin/marketplace.json`
