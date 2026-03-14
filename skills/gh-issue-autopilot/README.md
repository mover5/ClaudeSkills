# gh-issue-autopilot

A Claude Code skill that solves GitHub issues automatically or interactively.

## Modes

| Command | Mode | Description |
|---------|------|-------------|
| `/gh-issue-autopilot` | Automatic | Scans for labeled issues every 5 minutes, solves them, sends PRs, and monitors until merge. Runs in a git worktree. |
| `/gh-issue-autopilot <number>` | Manual | Interactively solve a single issue — plans the approach, gets your approval, implements, and sends a PR. Runs in the main repo. |
| `/gh-issue-autopilot setup` | Setup | Checks prerequisites (`gh` CLI, auth, permissions, labels) and helps configure your repo. |
| `/gh-issue-autopilot stop` | Stop | Stops the autopilot scanning loop. |
| `/gh-issue-autopilot label <name>` | Config | Sets the issue label that autopilot scans for (default: `Claude`). |

## How It Works

### Automatic Mode

1. Scans for open issues with the configured label (default: `Claude`)
2. Creates a git worktree to work in isolation
3. Reads the codebase, implements a fix, writes tests
4. Runs the full test suite
5. Opens a PR and monitors it every 5 minutes
6. Responds to review comments and cleans up after merge
7. Picks up the next labeled issue

### Manual Mode

1. Fetches the issue and creates a branch
2. Analyzes the code and presents a plan for approval
3. Implements the fix interactively (you can course-correct)
4. Runs tests, opens a PR, and monitors until merge

## Setup

Run `/gh-issue-autopilot setup` in your repo to check prerequisites:

- `gh` CLI installed and authenticated
- Push access to the repo
- Issue label exists (creates it if missing)
- `CLAUDE.md` has testing, PR, and git workflow sections

## Configuration

Stored in `.claude/autopilot-config.json`:

```json
{
  "label": "Claude"
}
```

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [GitHub CLI](https://cli.github.com/) (`gh`) — installed and authenticated
- Write or admin access to the target repo
