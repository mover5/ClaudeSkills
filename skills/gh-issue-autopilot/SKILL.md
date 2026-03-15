---
name: gh-issue-autopilot
description: Solve GitHub Issues automatically or interactively. No args = autopilot loop (worktree). Issue number = interactive mode. Also supports setup, label config, issue conventions, and stop.
model: haiku
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent, Skill, CronCreate, CronDelete
argument-hint: "[<issue-number> | stop | setup | label <name> | interval <minutes> | model <name> | hours <start>-<end> | issue-conventions]"
---

# GitHub Issue Autopilot

Solve GitHub Issues either automatically (loop mode in a worktree) or interactively (single-issue mode in the main repo). The two modes are **independent** and can run concurrently.

## Invocation

- `/gh-issue-autopilot` — **Automatic mode.** Start the autopilot loop scanning for labeled issues every 5 minutes. Runs in a git worktree.
- `/gh-issue-autopilot <number>` — **Manual mode.** Interactively solve a single GitHub issue by number. Runs in the main repo.
- `/gh-issue-autopilot stop` — Stop the autopilot loop and cancel the recurring scan.
- `/gh-issue-autopilot setup` — Check prerequisites and help configure the repo for this skill.
- `/gh-issue-autopilot label <name>` — Set the GitHub issue label used by automatic mode (default: `Claude`).
- `/gh-issue-autopilot interval <minutes>` — Set the scan interval in minutes (default: `5`).
- `/gh-issue-autopilot model <name>` — Set the model used for implementation subagents (default: `opus`). Accepts: `opus`, `sonnet`, or `haiku`.
- `/gh-issue-autopilot hours <start>-<end>` — Set active hours for scanning (e.g., `9-17` for 9 AM to 5 PM). Use `hours off` to disable (scan anytime). Supports overnight ranges (e.g., `22-6`).
- `/gh-issue-autopilot issue-conventions` — Interactively configure issue conventions (label-based scoping rules, title pattern rules). Guides the user through adding, viewing, and removing convention rules.

## Argument Routing

Parse the argument to determine the mode:
- No argument → **Automatic mode**
- `stop` → **Stop**
- `scan` → **Scan** (internal, triggered by cron)
- `setup` → **Setup**
- `label ...` → **Label config** (everything after `label ` is the label name)
- `interval ...` → **Interval config** (everything after `interval ` is the number of minutes)
- `model ...` → **Model config** (everything after `model ` is the model name)
- `hours ...` → **Hours config** (everything after `hours ` is the range, e.g., `9-17` or `off`)
- `issue-conventions` → **Issue Conventions config** (interactive configuration of issue convention rules)
- A number (e.g., `123`) → **Manual mode** for that issue number
- Anything else → treat as automatic mode

## File Storage

Two categories of files, stored in different locations:

### Config (persistent, per-repo)

Stored in the repo's `.claude/` directory. Persists across sessions.

- **Config file**: `.claude/autopilot-config.json`

```json
{
  "label": "Claude",
  "interval": 5,
  "model": "opus",
  "activeHours": { "start": 9, "end": 17 },
  "issueConventions": {
    "labelRules": [
      {
        "label": "security",
        "action": "extra-scrutiny",
        "instructions": "Require thorough security review. Check for injection, auth bypass, and data exposure."
      },
      {
        "label": "gh-issue-autopilot",
        "action": "scope",
        "instructions": "Scope all work to the skills/gh-issue-autopilot/ directory and its tests."
      }
    ],
    "titleRules": [
      {
        "pattern": "^\\[URGENT\\]",
        "action": "priority",
        "instructions": "Treat as high priority. Solve before other labeled issues."
      }
    ]
  }
}
```

The `activeHours` field is optional. When omitted, scanning is always active.

The `issueConventions` field is optional. When omitted, no special convention rules are applied. See the **Issue Conventions** section below for details.

### Runtime state (ephemeral, per-repo)

Stored in `/tmp/autopilot-<REPO_HASH>/` where `<REPO_HASH>` is derived from the repo's remote URL to avoid collisions between repos. Compute it once at the start of any operation:

```bash
REPO_ID=$(gh repo view --json url --jq '.url' | md5sum | cut -c1-12)
RUNTIME_DIR="/tmp/autopilot-${REPO_ID}"
mkdir -p "$RUNTIME_DIR"
```

Runtime files inside `$RUNTIME_DIR`:
- `active-issue-auto.txt` — tracks the automatic mode's current issue (`ISSUE_NUMBER PR_NUMBER BRANCH_NAME`)
- `active-issue-manual.txt` — tracks the manual mode's current issue (`ISSUE_NUMBER PR_NUMBER BRANCH_NAME`)
- `cron-id.txt` — stores the CronCreate job ID

### Cross-mode conflict prevention

Before either mode starts work on an issue, it must check whether the other mode is already working on the same issue number:

- **Manual mode**: Before starting, read `$RUNTIME_DIR/active-issue-auto.txt`. If it exists and contains the same issue number, **error out** and tell the user that automatic mode is already working on that issue.
- **Automatic mode**: Before picking up an issue, read `$RUNTIME_DIR/active-issue-manual.txt`. If it exists and contains the same issue number, **skip that issue** and log that it's being handled manually.

### Detecting the default branch

Never hardcode `master` or `main`. Always detect the repo's default branch dynamically:
```
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```
Cache the result in a shell variable for the duration of the operation.

### Label configuration (`/gh-issue-autopilot label <name>`)

1. Read the current config from `.claude/autopilot-config.json` (or start with defaults).
2. Set the `label` field to the provided name.
3. Write the updated config back to `.claude/autopilot-config.json`.
4. Tell the user the label has been updated.
5. When scanning for issues, always read the label from this config. Pass the label as-is to `gh issue list --label`, which is already case-insensitive.

### Interval configuration (`/gh-issue-autopilot interval <minutes>`)

1. Read the current config from `.claude/autopilot-config.json` (or start with defaults).
2. Validate that the provided value is a positive integer (minimum 1).
3. Set the `interval` field to the provided number.
4. Write the updated config back to `.claude/autopilot-config.json`.
5. Tell the user the interval has been updated.
6. Note: if autopilot is already running, the user must stop and restart it for the new interval to take effect.

### Model configuration (`/gh-issue-autopilot model <name>`)

Controls which model is used for implementation subagents. The skill itself always runs on Haiku for cheap triage/orchestration. Only the implementation phase (solving issues, addressing reviews) uses this model.

1. Read the current config from `.claude/autopilot-config.json` (or start with defaults).
2. Validate that the provided value is one of: `opus`, `sonnet`, `haiku`.
3. Set the `model` field to the provided name.
4. Write the updated config back to `.claude/autopilot-config.json`.
5. Tell the user the implementation model has been updated.

### Active hours configuration (`/gh-issue-autopilot hours <start>-<end>`)

Controls when scanning is active. Outside active hours, the pre-check script exits immediately without making any API calls or spending tokens. Uses the system's local time.

1. Read the current config from `.claude/autopilot-config.json` (or start with defaults).
2. If the argument is `off`, remove the `activeHours` field from the config (scanning becomes always active).
3. Otherwise, parse the argument as `<start>-<end>` where both are integers 0-23.
4. Validate that both start and end are integers in the range 0-23.
5. Set the `activeHours` field to `{"start": <start>, "end": <end>}`.
6. Write the updated config back to `.claude/autopilot-config.json`.
7. Tell the user the active hours have been updated.
8. Note: the change takes effect on the next scan cycle. No restart required.

**Range behavior:**
- Normal range (start < end): active from start up to (but not including) end. E.g., `9-17` means 9:00 AM through 4:59 PM.
- Overnight range (start > end): active from start through midnight and from midnight up to end. E.g., `22-6` means 10:00 PM through 5:59 AM.
- Same values (start == end): scanning is effectively disabled (zero-width window).
- No `activeHours` in config: scanning is always active (default behavior).

### Issue Conventions configuration (`/gh-issue-autopilot issue-conventions`)

Issue conventions let you define rules that change how the autopilot processes issues based on their labels or title patterns. This is useful for:
- **Scoping work** to specific directories when an issue is tagged with a skill/component label
- **Adding extra scrutiny** for issues labeled with `security`, `breaking-change`, etc.
- **Prioritizing issues** whose titles match certain patterns (e.g., `[URGENT]`)
- **Adding custom instructions** that get passed to the implementation subagent

Convention rules are stored in `.claude/autopilot-config.json` under the `issueConventions` key.

#### Rule types

**Label rules** (`issueConventions.labelRules`): Triggered when an issue has a matching label (case-insensitive match).

Each label rule has:
- `label` (string, required): The GitHub label name to match.
- `action` (string, required): One of `scope`, `extra-scrutiny`, `priority`, or `custom`.
- `instructions` (string, required): Free-text instructions passed to the implementation subagent.

**Title rules** (`issueConventions.titleRules`): Triggered when an issue's title matches a regex pattern.

Each title rule has:
- `pattern` (string, required): A regex pattern to match against the issue title.
- `action` (string, required): One of `scope`, `extra-scrutiny`, `priority`, or `custom`.
- `instructions` (string, required): Free-text instructions passed to the implementation subagent.

#### Actions

- **`scope`**: Restricts the implementation subagent's work to specific directories or files. The `instructions` field should describe the scope (e.g., "Scope all work to the skills/gh-issue-autopilot/ directory and its tests.").
- **`extra-scrutiny`**: Adds extra review requirements. The `instructions` field describes what to scrutinize (e.g., "Require thorough security review. Check for injection, auth bypass, and data exposure.").
- **`priority`**: Marks the issue as high priority. When multiple labeled issues exist, priority issues are solved first. The `instructions` field can add context.
- **`custom`**: A catch-all for any other convention. The `instructions` are passed directly to the subagent.

#### Applying conventions during scanning

When triage picks up an issue (Step 1 of Scanning), before launching the implementation subagent:

1. Read `issueConventions` from `.claude/autopilot-config.json`.
2. Fetch the issue's labels: `gh issue view <NUMBER> --json labels --jq '.labels[].name'`
3. For each label rule, check if the issue has a matching label (case-insensitive). Collect all matching rules.
4. For each title rule, check if the issue title matches the regex pattern. Collect all matching rules.
5. If any `priority` rules match and there are multiple candidate issues, prefer priority issues.
6. Concatenate the `instructions` from all matching rules into an `## Issue Conventions` section and include it in the subagent prompt. This gives the subagent specific guidance for this issue.

#### Interactive configuration

When the user runs `/gh-issue-autopilot issue-conventions`, present the current conventions (if any) and offer these options:

1. **View current rules** — Display all label rules and title rules in a readable format.
2. **Add a label rule** — Ask for: label name, action (scope/extra-scrutiny/priority/custom), instructions.
3. **Add a title rule** — Ask for: regex pattern, action, instructions.
4. **Remove a rule** — List all rules with indices and ask which to remove.
5. **Done** — Exit the configuration.

After each add/remove, write the updated config back to `.claude/autopilot-config.json`.

---

## Setup (`/gh-issue-autopilot setup`)

Run a series of checks and guide the user through any missing prerequisites. Present results as a checklist.

### Step 1: Check prerequisites

Run these checks and report pass/fail for each:

1. **`gh` CLI installed**: `gh --version`
2. **`gh` authenticated**: `gh auth status`
3. **Repo detected**: `gh repo view --json name,owner --jq '.owner.login + "/" + .name'`
4. **Push access**: `gh repo view --json viewerPermission --jq '.viewerPermission'` (should be WRITE or ADMIN)
5. **Default branch detected**: `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`
6. **Git worktree support**: `git worktree list` (just confirm it doesn't error)
7. **Current label**: Read from `.claude/autopilot-config.json` or show default (`Claude`)
8. **Label exists in repo**: `gh label list --json name --jq '.[].name'` — check if the configured label exists (case-insensitive). If not, offer to create it.
9. **Scan interval**: Read from `.claude/autopilot-config.json` or show default (`5` minutes)
10. **Implementation model**: Read from `.claude/autopilot-config.json` or show default (`opus`). This is the model used for subagents that solve issues and address reviews. Explain that the skill runs on Haiku for triage and only escalates to this model for implementation. Ask the user if they'd like to change it (options: `opus`, `sonnet`, `haiku`).
11. **Active hours**: Read from `.claude/autopilot-config.json`. If `activeHours` is set, show the configured range (e.g., `9-17`). If not set, show "always active (no restriction)". Ask the user if they'd like to configure active hours.
12. **Issue conventions**: Read from `.claude/autopilot-config.json`. If `issueConventions` is set, show the number of label rules and title rules configured. If not set, show "no issue conventions configured". Offer to run `/gh-issue-autopilot issue-conventions` to configure them. Briefly explain that issue conventions let you add label-based scoping rules (e.g., tag issues with a skill label to restrict work to that skill's directory) and title-pattern rules (e.g., `[URGENT]` prefix for priority).

### Step 2: Check CLAUDE.md

Read the project's `CLAUDE.md` (if it exists) and check for sections that enhance this skill. Report which are present and which are missing:

1. **Testing section** — Should document how to run the full test suite (command or script). Look for headings like `## Testing`, `## Running Tests`, `### Running All Tests`, or content containing `test` commands.
2. **PR conventions** — Should document how PRs should be formatted (title style, body template). Look for headings like `## PR`, `## Pull Request`, or content mentioning PR format/template.
3. **Git workflow** — Should document the main branch name and branching conventions. Look for headings like `## Git`, `## Workflow`, `## Branch`.
4. **Issue conventions** — Should document how issues should be labeled, titled, or categorized for this project. Look for headings like `## Issue`, `## Issue Convention`, or content mentioning issue labels, issue templates, or issue triage. This section helps the autopilot understand project-specific issue handling rules.

### Step 3: Offer to help

For any missing CLAUDE.md sections, **offer to help the user write them**. If the user accepts:

- **Testing section**: Ask what commands run the test suite, then write a `## Testing` section with a `### Running All Tests` subsection containing the command(s).
- **PR conventions**: Ask about their preferred PR title/body style, then write a `## Pull Requests` section.
- **Git workflow**: Detect the default branch and write a `## Git Workflow` section documenting it.
- **Issue conventions**: Ask how the user wants issues to be categorized (e.g., labels per skill/component, priority labels, special title prefixes). Then write a `## Issue Conventions` section documenting the rules. Also offer to configure matching `issueConventions` rules in `.claude/autopilot-config.json` so the autopilot enforces them automatically.

If `CLAUDE.md` doesn't exist at all, offer to create one with all sections.

Always show the user what you plan to write and get approval before modifying CLAUDE.md.

---

## Automatic Mode (no arguments)

Fully autonomous. Scans for issues, solves them, sends PRs, waits for merge, cleans up, repeats.

**IMPORTANT: Automatic mode must always run in a git worktree** to avoid conflicting with any manual work happening in the main repo. Use the `EnterWorktree` tool or `git worktree add` to create an isolated working copy before making any changes. All file reads, edits, builds, and tests for automatic mode happen inside the worktree.

### Starting

1. Tell the user autopilot is starting.
2. Compute `REPO_ID` and `RUNTIME_DIR` (see File Storage above).
3. Detect the default branch: `DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')`
4. Read the label from `.claude/autopilot-config.json` (default: `Claude`).
5. Read the interval from `.claude/autopilot-config.json` (default: `5` minutes).
6. Run the scan logic below **immediately** (don't wait for the first cron tick).
7. Schedule a recurring cron job using the configured interval with the prompt: `/gh-issue-autopilot scan`
8. Store the cron job ID by writing to `$RUNTIME_DIR/cron-id.txt`.

### Stopping (`/gh-issue-autopilot stop`)

1. Compute `REPO_ID` and `RUNTIME_DIR`.
2. Read the cron job ID from `$RUNTIME_DIR/cron-id.txt`.
3. Cancel it with CronDelete.
4. Remove the file.
5. Tell the user autopilot has stopped.
6. Do NOT do anything else.

### Scanning (`/gh-issue-autopilot scan` — triggered by cron, or the initial scan on start)

**Step 0 — Pre-check (token-saving gate):**
Run the pre-check script as the very first action. This avoids burning tokens on multiple tool calls when there's nothing to do:
```bash
bash "$(dirname "$(readlink -f ~/.claude/skills/gh-issue-autopilot/SKILL.md)")/precheck.sh"
```
- If it exits **non-zero**: say "No work found." and **stop immediately**. Do not run any other commands. This also covers active hours — if the current time is outside configured active hours, the pre-check exits non-zero with `OUTSIDE_ACTIVE_HOURS`.
- If it exits **zero**: proceed with the triage below.

**Step 1 — Triage (runs on Haiku via the `model: haiku` frontmatter):**

This skill runs on Haiku to keep scanning costs low. Perform the triage directly — no subagent needed.

1. Compute `REPO_ID` and `RUNTIME_DIR`.
2. Detect the default branch: `DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')`
3. Read the label from `.claude/autopilot-config.json` (default: `Claude`).
4. Check if there is already an active issue being worked on. Check **both** `$RUNTIME_DIR/active-issue-auto.txt` and `$RUNTIME_DIR/active-issue-manual.txt`. If either exists, read it and check the PR:
   - Run `gh pr view <PR_NUMBER> --json state,reviews,comments` to check the PR.
   - **IMPORTANT: You MUST examine the `reviews` and `comments` arrays in the response.** Do not just check `state`. Look for comments or reviews authored by someone other than yourself that arrived after your last comment. Any such comment means there is feedback to address.
   - If the PR is **merged**: proceed to **After Merge** cleanup (see below). If it was `active-issue-auto.txt`, loop back to step 5 to check for the next issue. If it was `active-issue-manual.txt`, stop after cleanup.
   - If the PR is **still open with unaddressed review comments or PR comments**: proceed to **Step 2** with action `ADDRESS_REVIEWS`. Pass the PR number, branch name, and the content of the comments to the subagent.
   - If the PR is **still open with no new comments to address**: say "PR still open, no action needed." and **stop**. Do not pick up another issue.
5. If no active issue (neither file exists), scan for the next issue to work on:
   ```
   gh issue list --label "<LABEL>" --state open --json number,title,body --limit 1
   ```
6. If no issues found: say "No open issues with the <LABEL> label found." and **stop**.
7. **Cross-mode conflict check**: If an issue is found, check `$RUNTIME_DIR/active-issue-manual.txt`. If it exists and its issue number matches the found issue, **skip it** — say "Issue #N is being handled in manual mode, skipping." and **stop**. Do not pick up another issue.
8. If an issue is found and no conflict: proceed to **Step 2** with action `SOLVE`.

**Step 2 — Implementation (escalate to configured model):**

When triage identifies work that requires code changes (`SOLVE` or `ADDRESS_REVIEWS`), read the `model` field from `.claude/autopilot-config.json` (default: `opus`). Launch a subagent using the Agent tool with that model. This is the only phase that uses the more capable model.

**Before launching the subagent**, apply issue conventions (see "Applying conventions during scanning" in the Issue Conventions section above). If any convention rules match the issue, include the collected instructions in the subagent prompt under an `## Issue Conventions` heading. This ensures the subagent respects scoping rules, extra scrutiny requirements, and any other project-specific conventions.

- **`ADDRESS_REVIEWS`** — Launch the subagent with a prompt to: check out the PR branch in a worktree, read the review comments, address them, commit, and push. Include the PR number, branch name, and a summary of the review feedback in the prompt. Also include any applicable issue convention instructions. Then stop.
- **`SOLVE`** — Launch the subagent with a prompt to work on the issue **inside a worktree**. Include the issue number, title, body, the default branch name, `REPO_ID`, and any applicable issue convention instructions in the prompt. The agent should:
   a. Create a worktree: `git worktree add /tmp/autopilot-worktree-${REPO_ID} -b issue-<NUMBER>-<short-description> $DEFAULT_BRANCH`
   b. All subsequent work (reading code, editing, building, testing) happens in the worktree
   c. Implement the fix (read code, understand the problem, write the solution, write tests)
   d. Run the full test suite as documented in the project's CLAUDE.md
   e. Commit and push the branch (from the worktree)
   f. Create a PR targeting `$DEFAULT_BRANCH`, following the project's PR conventions (see CLAUDE.md)
   g. Write the issue number, PR number, and branch name to `$RUNTIME_DIR/active-issue-auto.txt` in the format: `ISSUE_NUMBER PR_NUMBER BRANCH_NAME`
   h. Clean up the worktree: `git worktree remove /tmp/autopilot-worktree-${REPO_ID}`
   i. Tell the user what issue you picked up and link to the PR

### After Merge (cleanup)

When a PR is confirmed merged, determine which mode owns it by checking which active issue file exists (`active-issue-auto.txt` or `active-issue-manual.txt`):
1. Read the branch name from the active issue file.
2. Detect the default branch. If the repo is currently on the default branch, pull latest. If on another branch (manual work), skip the pull — don't disrupt manual work.
3. Delete the local branch: `git branch -D <branch>`
4. Delete the remote branch: `git push origin --delete <branch>` (ignore errors if already deleted)
5. Remove the active issue file.
6. If the file was `active-issue-manual.txt`: stop the cron job, remove `$RUNTIME_DIR/cron-id.txt`, tell the user the issue is fully resolved. Do NOT scan for more issues.
7. If the file was `active-issue-auto.txt`: tell the user the issue is complete and continue scanning for the next issue (go back to Scanning Step 1, triage).

---

## Manual Mode (`/gh-issue-autopilot <number>`)

Interactive, single-issue mode. More collaborative during planning and implementation, then monitors the PR automatically. Runs in the **main repo working directory** (no worktree).

### Phase 1: Setup

1. Compute `REPO_ID` and `RUNTIME_DIR`.
2. Detect the default branch: `DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')`
3. **Cross-mode conflict check**: Read `$RUNTIME_DIR/active-issue-auto.txt`. If it exists and its issue number matches `<NUMBER>`, **error out**: tell the user "Issue #N is already being worked on by automatic mode. Wait for it to finish or stop autopilot first." and **stop**. Do not proceed.
4. Fetch the issue: `gh issue view <NUMBER> --json number,title,body,labels`
5. Pull the latest from the default branch: `git checkout $DEFAULT_BRANCH && git pull`
6. Create and checkout a new branch: `git checkout -b issue-<NUMBER>-<short-description>`

### Phase 2 & 3: Planning and Implementation (escalate to configured model)

Since this skill runs on Haiku for cost efficiency, the interactive planning and implementation phases require escalation to a more capable model. **Do not attempt planning or implementation on Haiku.**

Read the `model` field from `.claude/autopilot-config.json` (default: `opus`). Launch a subagent using the Agent tool with that model. Pass it the issue details (number, title, body), the branch name, and instruct it to:

1. Read and analyze the relevant code to understand the problem.
2. **Present a plan to the user** — describe what you intend to change and why. Include:
   - Which files will be modified or created
   - The approach and any trade-offs
   - What tests you plan to add
3. **Wait for the user to approve or adjust the plan** before writing any code.
4. Implement the fix according to the approved plan.
5. After each significant change, **briefly tell the user what you did** so they can course-correct.
6. Run the full test suite as documented in the project's CLAUDE.md.
7. If tests fail, fix them and re-run. Show the user what went wrong and how you fixed it.
8. Once tests pass, **ask the user if they're ready to send the PR**, or if they want further changes.

### Phase 4: PR and Monitoring (automatic)

1. Commit and push the branch.
2. Create a PR targeting `$DEFAULT_BRANCH`, following the project's PR conventions (see CLAUDE.md).
3. Write the issue number and PR number to `$RUNTIME_DIR/active-issue-manual.txt` in the format: `ISSUE_NUMBER PR_NUMBER BRANCH_NAME`
4. Read the interval from `.claude/autopilot-config.json` (default: `5` minutes).
5. Schedule a recurring cron job using the configured interval with the prompt: `/gh-issue-autopilot scan`
6. Store the cron job ID by writing to `$RUNTIME_DIR/cron-id.txt`.
7. Tell the user the PR is created and monitoring has started.

From this point, the scan loop handles PR review comments and post-merge cleanup. Because the active issue file contains `MANUAL`, the scan loop will clean up and stop after this issue is done — it will NOT scan for more issues.

---

## Important Rules

- **One issue at a time per mode.** Automatic mode and manual mode are independent, but each mode handles only one issue at a time.
- **No duplicate work across modes.** Before starting work on an issue, always check the other mode's active issue file. Never allow both modes to work on the same issue number simultaneously.
- **Automatic mode always uses a worktree.** Never modify files in the main repo from automatic mode.
- **Never hardcode the default branch.** Always detect it with `gh repo view`.
- **Full completion.** An issue is not done until its PR is merged and branches are cleaned up.
- **Test everything.** Always run the full test suite before committing.
- **Follow project conventions.** Use the patterns from CLAUDE.md and the context/ docs for implementation.
- **PR screenshots.** If the change involves UX, follow the PR screenshot workflow from the project's CLAUDE.md (if documented).
- **Be thorough.** Read relevant code before making changes. Write tests for new features.
- **Handle PR feedback.** If the PR has review comments, address them before moving on.
