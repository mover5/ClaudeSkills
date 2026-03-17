---
name: gh-issue-autopilot
description: Solve GitHub Issues automatically or interactively. No args = autopilot loop (worktree). Issue number = interactive mode. Also supports setup, label config, and stop.
model: haiku
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent, Skill, CronCreate, CronDelete, CronList
argument-hint: "[<issue-number> | stop | setup | label <name> | interval <minutes> | model <name> | hours <start>-<end>]"
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
  "activeHours": { "start": 9, "end": 17 }
}
```

The `activeHours` field is optional. When omitted, scanning is always active.

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
- `cron-created-at.txt` — stores the Unix timestamp when the current cron job was created (used for renewal)

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

### Step 2: Check CLAUDE.md

Read the project's `CLAUDE.md` (if it exists) and check for sections that enhance this skill. Report which are present and which are missing:

1. **Testing section** — Should document how to run the full test suite (command or script). Look for headings like `## Testing`, `## Running Tests`, `### Running All Tests`, or content containing `test` commands.
2. **PR conventions** — Should document how PRs should be formatted (title style, body template). Look for headings like `## PR`, `## Pull Request`, or content mentioning PR format/template.
3. **Git workflow** — Should document the main branch name and branching conventions. Look for headings like `## Git`, `## Workflow`, `## Branch`.
4. **Issue conventions** — Optional. Should document custom rules for processing issues (e.g., label meanings, title conventions, scoping rules, extra scrutiny for certain labels). Look for headings like `## Issue Conventions`, `## Issue`, or content mentioning issue processing rules. This section is pseudo-free form: each repo can specify its own instructions for how to interpret and handle issues.

### Step 3: Offer to help

For any missing CLAUDE.md sections, **offer to help the user write them**. If the user accepts:

- **Testing section**: Ask what commands run the test suite, then write a `## Testing` section with a `### Running All Tests` subsection containing the command(s).
- **PR conventions**: Ask about their preferred PR title/body style, then write a `## Pull Requests` section.
- **Git workflow**: Detect the default branch and write a `## Git Workflow` section documenting it.
- **Issue conventions**: Ask the user how they want issues to be processed — for example, whether certain labels indicate skill-scoped work, whether specific title patterns carry meaning, or whether some labels should trigger extra scrutiny or specific processes. Write a `## Issue Conventions` section with their instructions.

If `CLAUDE.md` doesn't exist at all, offer to create one with all three sections.

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
6. **Validate cron state (session restart safety):** If `$RUNTIME_DIR/cron-id.txt` exists, the file may be left over from a previous Claude session. Validate it by calling CronList and checking whether the stored cron ID appears in the results. If the ID is **not found** (stale), remove both `$RUNTIME_DIR/cron-id.txt` and `$RUNTIME_DIR/cron-created-at.txt` — they are invalid. Log: "Cleared stale cron state from a previous session."
7. Run the scan logic below **immediately** (don't wait for the first cron tick).
8. Schedule a recurring cron job using the configured interval with the prompt: `/gh-issue-autopilot scan`
9. Store the cron job ID by writing to `$RUNTIME_DIR/cron-id.txt`.
10. Record the creation time: `date +%s > $RUNTIME_DIR/cron-created-at.txt`
11. Tell the user that autopilot will automatically renew its scanning schedule to run indefinitely (no 3-day limit).

### Stopping (`/gh-issue-autopilot stop`)

1. Compute `REPO_ID` and `RUNTIME_DIR`.
2. Read the cron job ID from `$RUNTIME_DIR/cron-id.txt`.
3. **Validate before deleting:** Call CronList and check whether the stored cron ID exists in the current session. If it exists, cancel it with CronDelete. If it does not exist (stale from a previous session), skip the CronDelete — the job is already gone.
4. Remove `$RUNTIME_DIR/cron-id.txt` and `$RUNTIME_DIR/cron-created-at.txt`.
5. Tell the user autopilot has stopped.
6. Do NOT do anything else.

### Scanning (`/gh-issue-autopilot scan` — triggered by cron, or the initial scan on start)

**Step 0 — Pre-check (token-saving gate):**
Run the pre-check script as the very first action. This avoids burning tokens on multiple tool calls when there's nothing to do:
```bash
bash "$(dirname "$(readlink -f ~/.claude/skills/gh-issue-autopilot/SKILL.md)")/precheck.sh"
```
- If it exits **non-zero**: say "No work found." and **stop immediately**. Do not run any other commands. This also covers active hours — if the current time is outside configured active hours, the pre-check exits non-zero with `OUTSIDE_ACTIVE_HOURS`.
- If it exits **zero**: proceed with the cron renewal check and then triage below.

**Step 0.5 — Cron Validation & Renewal (keeps autopilot running beyond 3 days):**

CronCreate jobs are session-specific and auto-expire after 3 days. To support indefinite scanning and handle session restarts gracefully, the scan must validate the cron job and renew it before expiry. Check on every scan invocation:

1. Compute `REPO_ID` and `RUNTIME_DIR`.
2. **Validate cron is still active in this session:** Call CronList and check whether the cron ID stored in `$RUNTIME_DIR/cron-id.txt` appears in the results.
   - If the cron ID is **not found** (stale from a previous session or expired), the cron job no longer exists. Immediately create a replacement:
     a. Read the interval from `.claude/autopilot-config.json` (default: `5` minutes).
     b. Create a new cron job with CronCreate using the same interval and prompt: `/gh-issue-autopilot scan`
     c. Write the new cron job ID to `$RUNTIME_DIR/cron-id.txt`.
     d. Write the current timestamp to `$RUNTIME_DIR/cron-created-at.txt`: `date +%s > $RUNTIME_DIR/cron-created-at.txt`
     e. Log: "Replaced stale cron job (previous session or expired). Scanning continues."
     f. Skip the age-based renewal check below (the cron is freshly created).
   - If the cron ID **is found**, proceed to the age-based renewal check.
3. Read `$RUNTIME_DIR/cron-created-at.txt`. If the file doesn't exist, skip renewal (the cron was just created).
4. Compare the stored timestamp to the current time: `CRON_AGE=$(( $(date +%s) - $(cat $RUNTIME_DIR/cron-created-at.txt) ))`
5. If `CRON_AGE` is greater than **172800** seconds (2 days), the cron job is approaching expiry. Renew it:
   a. Read the old cron job ID from `$RUNTIME_DIR/cron-id.txt`.
   b. Delete the old cron job with CronDelete.
   c. Read the interval from `.claude/autopilot-config.json` (default: `5` minutes).
   d. Create a new cron job with CronCreate using the same interval and prompt: `/gh-issue-autopilot scan`
   e. Write the new cron job ID to `$RUNTIME_DIR/cron-id.txt`.
   f. Write the current timestamp to `$RUNTIME_DIR/cron-created-at.txt`: `date +%s > $RUNTIME_DIR/cron-created-at.txt`
   g. Log: "Renewed cron job to extend scanning beyond the 3-day limit."
6. If `CRON_AGE` is 2 days or less, do nothing — the cron is still fresh.

This validation-then-renewal approach ensures that:
- **New session, stale files:** The cron is detected as missing and recreated automatically.
- **Same session, approaching expiry:** The cron is renewed before the 3-day limit.
- **Same session, still fresh:** No action needed.

**Step 1 — Triage (runs on Haiku via the `model: haiku` frontmatter):**

This skill runs on Haiku to keep scanning costs low. Perform the triage directly — no subagent needed.

1. Compute `REPO_ID` and `RUNTIME_DIR`.
2. Detect the default branch: `DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')`
3. Read the label from `.claude/autopilot-config.json` (default: `Claude`).
4. Check if there is already an active issue being worked on. Check **both** `$RUNTIME_DIR/active-issue-auto.txt` and `$RUNTIME_DIR/active-issue-manual.txt`. If either exists, read it and check the PR:
   - Run `gh pr view <PR_NUMBER> --json state,mergedAt,reviews,comments` to check the PR.
   - **IMPORTANT: You MUST examine the `reviews` and `comments` arrays in the response.** Do not just check `state`. Look for comments or reviews authored by someone other than yourself that arrived after your last comment. Any such comment means there is feedback to address.
   - **Also fetch inline review comments** (comments left on specific code lines), which are NOT included in the `gh pr view` response. Fetch them separately:
     ```bash
     gh api repos/{owner}/{repo}/pulls/{pr_number}/comments
     ```
     If any inline comments are authored by someone other than the bot, treat them as unaddressed feedback just like regular review comments.
   - If the PR state is CLOSED/MERGED **and** `mergedAt` is **not null**: the PR was merged. Proceed to **After Merge** cleanup (see below). If it was `active-issue-auto.txt`, loop back to step 5 to check for the next issue. If it was `active-issue-manual.txt`, stop after cleanup.
   - If the PR state is CLOSED/MERGED **and** `mergedAt` is **null**: the PR was closed without merging. Report "PR #N was closed without merging." Remove the active issue file (since there is nothing more to do), but do **NOT** delete branches or run merge cleanup. If it was `active-issue-auto.txt`, loop back to step 5 to check for the next issue. If it was `active-issue-manual.txt`, stop.
   - If the PR is **still open with unaddressed review comments, PR comments, or inline review comments**: proceed to **Step 2** with action `ADDRESS_REVIEWS`. Pass the PR number, branch name, and the content of all comments (including inline) to the subagent.
   - If the PR is **still open with no new comments to address**: say "PR still open, no action needed." and **stop**. Do not pick up another issue.
5. If no active issue (neither file exists), scan for the next issue to work on:
   ```
   gh issue list --label "<LABEL>" --state open --json number,title,body,labels --limit 1
   ```
6. If no issues found: say "No open issues with the <LABEL> label found." and **stop**.
7. **Cross-mode conflict check**: If an issue is found, check `$RUNTIME_DIR/active-issue-manual.txt`. If it exists and its issue number matches the found issue, **skip it** — say "Issue #N is being handled in manual mode, skipping." and **stop**. Do not pick up another issue.
8. If an issue is found and no conflict: proceed to **Step 2** with action `SOLVE`.

**Step 2 — Implementation (escalate to configured model):**

When triage identifies work that requires code changes (`SOLVE` or `ADDRESS_REVIEWS`), read the `model` field from `.claude/autopilot-config.json` (default: `opus`). Launch a subagent using the Agent tool with that model. This is the only phase that uses the more capable model.

- **`ADDRESS_REVIEWS`** — Launch the subagent with a prompt to: check out the PR branch in a worktree, read the review comments, address them, commit, and push. Include the PR number, branch name, and a summary of the review feedback in the prompt. Then stop.
- **`SOLVE`** — First, fetch all issue comments: `gh issue view <NUMBER> --json number,title,body,labels,comments`. Also read the project's `CLAUDE.md` and check for an `## Issue Conventions` section. If present, include those conventions in the subagent prompt so the agent can apply any repo-specific rules (e.g., label-based scoping, title conventions, extra scrutiny). Launch the subagent with a prompt to work on the issue **inside a worktree**. Include the issue number, title, body, labels, **all issue comments**, any issue conventions from CLAUDE.md, the default branch name, and `REPO_ID` in the prompt. The agent should:
   a. **Update the default branch to latest before creating the worktree** (prevents merge conflicts from working on stale code): `git fetch origin $DEFAULT_BRANCH && git branch -f $DEFAULT_BRANCH origin/$DEFAULT_BRANCH`
   b. Create a worktree: `git worktree add /tmp/autopilot-worktree-${REPO_ID} -b issue-<NUMBER>-<short-description> $DEFAULT_BRANCH`
   c. All subsequent work (reading code, editing, building, testing) happens in the worktree
   d. Implement the fix (read code, understand the problem, write the solution, write tests)
   e. Run the full test suite as documented in the project's CLAUDE.md
   f. Commit and push the branch (from the worktree)
   g. Create a PR targeting `$DEFAULT_BRANCH`, following the project's PR conventions (see CLAUDE.md)
   h. Write the issue number, PR number, and branch name to `$RUNTIME_DIR/active-issue-auto.txt` in the format: `ISSUE_NUMBER PR_NUMBER BRANCH_NAME`
   i. Clean up the worktree: `git worktree remove /tmp/autopilot-worktree-${REPO_ID}`
   j. Tell the user what issue you picked up and link to the PR

### After Merge (cleanup)

When a PR is confirmed merged, determine which mode owns it by checking which active issue file exists (`active-issue-auto.txt` or `active-issue-manual.txt`):
1. Read the branch name from the active issue file.
2. Detect the default branch and ensure it is up to date:
   - **Manual mode** (`active-issue-manual.txt`): The user is likely still on the feature branch. Always check out the default branch and pull latest: `git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH`
   - **Automatic mode** (`active-issue-auto.txt`): If the repo is currently on the default branch, pull latest: `git pull origin $DEFAULT_BRANCH`. If on another branch (manual work in progress), skip the pull — don't disrupt manual work.
3. Delete the local branch: `git branch -D <branch>`
4. Delete the remote branch: `git push origin --delete <branch>` (ignore errors if already deleted)
5. Remove the active issue file.
6. If the file was `active-issue-manual.txt`: stop the cron job, remove `$RUNTIME_DIR/cron-id.txt` and `$RUNTIME_DIR/cron-created-at.txt`, tell the user the issue is fully resolved. Do NOT scan for more issues.
7. If the file was `active-issue-auto.txt`: tell the user the issue is complete and continue scanning for the next issue (go back to Scanning Step 1, triage).

---

## Manual Mode (`/gh-issue-autopilot <number>`)

Interactive, single-issue mode. More collaborative during planning and implementation, then monitors the PR automatically. Runs in the **main repo working directory** (no worktree).

### Phase 1: Setup

1. Compute `REPO_ID` and `RUNTIME_DIR`.
2. Detect the default branch: `DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')`
3. **Cross-mode conflict check**: Read `$RUNTIME_DIR/active-issue-auto.txt`. If it exists and its issue number matches `<NUMBER>`, **error out**: tell the user "Issue #N is already being worked on by automatic mode. Wait for it to finish or stop autopilot first." and **stop**. Do not proceed.
4. Fetch the issue (including all comments): `gh issue view <NUMBER> --json number,title,body,labels,comments`
5. Read the project's `CLAUDE.md` and check for an `## Issue Conventions` section. If present, these conventions must be passed to the implementation subagent and applied when processing the issue (e.g., label-based scoping, title conventions, extra scrutiny rules).
6. Pull the latest from the default branch: `git checkout $DEFAULT_BRANCH && git pull`
7. Create and checkout a new branch: `git checkout -b issue-<NUMBER>-<short-description>`

### Phase 2 & 3: Planning and Implementation (escalate to configured model)

Since this skill runs on Haiku for cost efficiency, the interactive planning and implementation phases require escalation to a more capable model. **Do not attempt planning or implementation on Haiku.**

Read the `model` field from `.claude/autopilot-config.json` (default: `opus`). Launch a subagent using the Agent tool with that model. Pass it the issue details (number, title, body, labels, **all issue comments**), any issue conventions from CLAUDE.md, the branch name, and instruct it to:

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
5. **Clean up stale cron state:** If `$RUNTIME_DIR/cron-id.txt` exists, call CronList to check whether the stored ID is still valid. If it is valid, delete it with CronDelete (replacing it with a new one). If it is stale, just remove both files. This prevents leftover state from a previous session from causing confusion.
6. Schedule a recurring cron job using the configured interval with the prompt: `/gh-issue-autopilot scan`
7. Store the cron job ID by writing to `$RUNTIME_DIR/cron-id.txt`.
8. Record the creation time: `date +%s > $RUNTIME_DIR/cron-created-at.txt`
9. Tell the user the PR is created and monitoring has started.

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
- **Apply issue conventions.** If the project's CLAUDE.md contains an `## Issue Conventions` section, follow those rules when processing issues. This may include label-based scoping, title-based routing, or extra scrutiny for certain issue types.
- **PR screenshots.** If the change involves UX, follow the PR screenshot workflow from the project's CLAUDE.md (if documented).
- **Be thorough.** Read relevant code before making changes. Write tests for new features.
- **Handle PR feedback.** If the PR has review comments, address them before moving on.
- **Never close or delete a PR.** Subagents may create PRs, push commits, and leave comments, but closing or deleting a PR is reserved for human reviewers only.
