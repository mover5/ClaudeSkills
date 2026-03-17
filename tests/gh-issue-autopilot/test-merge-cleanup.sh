#!/usr/bin/env bash
# Tests for post-merge cleanup behavior (branch checkout, pull, file removal)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Post-Merge Cleanup${RESET}"
echo ""

TEMP_DIR="$(mktemp -d)"
trap 'cleanup_temp "$TEMP_DIR"' EXIT

RUNTIME_DIR="$TEMP_DIR/autopilot-test"
mkdir -p "$RUNTIME_DIR"
AUTO_FILE="$RUNTIME_DIR/active-issue-auto.txt"
MANUAL_FILE="$RUNTIME_DIR/active-issue-manual.txt"
CRON_FILE="$RUNTIME_DIR/cron-id.txt"
CRON_TS_FILE="$RUNTIME_DIR/cron-created-at.txt"

# ── SKILL.md cleanup instructions ─────────────────────────────────

SKILL_MD="$REPO_ROOT/plugins/gh-issue-autopilot/skills/gh-issue-autopilot/SKILL.md"

echo -e "${BOLD}Cleanup instructions in SKILL.md${RESET}"

test_start "SKILL.md exists"
assert "SKILL.md exists" test -f "$SKILL_MD"

SKILL_CONTENT="$(cat "$SKILL_MD")"

test_start "manual mode: checkout default branch on cleanup"
assert_contains "manual mode checks out default branch" "$SKILL_CONTENT" "git checkout \$DEFAULT_BRANCH && git pull origin \$DEFAULT_BRANCH"

test_start "manual mode cleanup explicitly mentioned"
assert_contains "manual mode cleanup is documented" "$SKILL_CONTENT" "Manual mode"

test_start "automatic mode: pull if on default branch"
assert_contains "auto mode pulls on default branch" "$SKILL_CONTENT" "git pull origin \$DEFAULT_BRANCH"

test_start "automatic mode: skip pull if on another branch"
assert_contains "auto mode skips pull on other branch" "$SKILL_CONTENT" "skip the pull"

# ── Manual mode cleanup: active issue file ────────────────────────

echo ""
echo -e "${BOLD}Manual mode cleanup: file management${RESET}"

echo "17 301 issue-17-merge-cleanup" > "$MANUAL_FILE"
echo "cron_xyz" > "$CRON_FILE"
echo "1710000000" > "$CRON_TS_FILE"

test_start "manual active issue file exists before cleanup"
assert "manual file exists" test -f "$MANUAL_FILE"

# Parse active issue
read -r issue_num pr_num branch_name <<< "$(cat "$MANUAL_FILE")"
test_start "parse manual active issue fields"
assert_equals "issue number" "17" "$issue_num"
assert_equals "PR number" "301" "$pr_num"
assert_equals "branch name" "issue-17-merge-cleanup" "$branch_name"

# Simulate cleanup: remove active issue file
rm -f "$MANUAL_FILE"
test_start "manual active issue file removed after cleanup"
assert "manual file removed" test ! -f "$MANUAL_FILE"

# Simulate cleanup: remove cron files (manual mode stops cron)
rm -f "$CRON_FILE" "$CRON_TS_FILE"
test_start "cron files removed after manual cleanup"
assert "cron ID file removed" test ! -f "$CRON_FILE"
assert "cron timestamp file removed" test ! -f "$CRON_TS_FILE"

# ── Auto mode cleanup: active issue file ──────────────────────────

echo ""
echo -e "${BOLD}Automatic mode cleanup: file management${RESET}"

echo "42 501 issue-42-fix-bug" > "$AUTO_FILE"

test_start "auto active issue file exists before cleanup"
assert "auto file exists" test -f "$AUTO_FILE"

read -r issue_num pr_num branch_name <<< "$(cat "$AUTO_FILE")"
test_start "parse auto active issue fields"
assert_equals "issue number" "42" "$issue_num"
assert_equals "PR number" "501" "$pr_num"
assert_equals "branch name" "issue-42-fix-bug" "$branch_name"

# Simulate cleanup: remove active issue file only (cron continues for auto mode)
rm -f "$AUTO_FILE"
test_start "auto active issue file removed after cleanup"
assert "auto file removed" test ! -f "$AUTO_FILE"

# ── Git branch cleanup simulation ────────────────────────────────

echo ""
echo -e "${BOLD}Branch cleanup in a real git repo${RESET}"

REPO_DIR="$(create_temp_repo)"

# Create a feature branch
git -C "$REPO_DIR" checkout -b issue-99-test-feature --quiet
echo "feature" > "$REPO_DIR/feature.txt"
git -C "$REPO_DIR" add . && git -C "$REPO_DIR" commit -m "feature" --quiet

test_start "feature branch exists"
branches="$(git -C "$REPO_DIR" branch)"
assert_contains "feature branch listed" "$branches" "issue-99-test-feature"

test_start "currently on feature branch"
current="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
assert_equals "on feature branch" "issue-99-test-feature" "$current"

# Simulate manual mode cleanup: checkout default branch
git -C "$REPO_DIR" checkout main --quiet
test_start "manual cleanup: switched to default branch"
current="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
assert_equals "now on main" "main" "$current"

# Delete the feature branch
git -C "$REPO_DIR" branch -D issue-99-test-feature --quiet 2>/dev/null || true
test_start "feature branch deleted"
branches="$(git -C "$REPO_DIR" branch)"
assert_not_contains "feature branch gone" "$branches" "issue-99-test-feature"

rm -rf "$REPO_DIR"

echo ""
test_summary "Post-Merge Cleanup"
