#!/usr/bin/env bash
# Tests for git worktree operations used by automatic mode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Worktree Operations${RESET}"
echo ""

TEMP_REPO=""
WORKTREE_DIR=""
trap 'cleanup_worktree' EXIT

cleanup_worktree() {
  if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
    git -C "$TEMP_REPO" worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
  fi
  cleanup_temp "$TEMP_REPO"
}

# ── Create test repo ──────────────────────────────────────────────

TEMP_REPO="$(create_temp_repo)"
WORKTREE_DIR="$TEMP_REPO-worktree"

echo -e "${BOLD}Worktree creation${RESET}"

test_start "create worktree"
git -C "$TEMP_REPO" worktree add "$WORKTREE_DIR" -b issue-1-test main 2>/dev/null
assert "worktree directory created" test -d "$WORKTREE_DIR"
assert "worktree has files" test -f "$WORKTREE_DIR/README.md"

test_start "worktree on correct branch"
branch="$(git -C "$WORKTREE_DIR" branch --show-current)"
assert_equals "branch is issue-1-test" "issue-1-test" "$branch"

# ── Changes in worktree are isolated ──────────────────────────────

echo ""
echo -e "${BOLD}Worktree isolation${RESET}"

echo "worktree change" > "$WORKTREE_DIR/new-file.txt"
git -C "$WORKTREE_DIR" add . && git -C "$WORKTREE_DIR" commit -m "worktree commit" --quiet

test_start "main repo unaffected"
assert "new file not in main repo" test ! -f "$TEMP_REPO/new-file.txt"

test_start "main repo still on main branch"
main_branch="$(git -C "$TEMP_REPO" branch --show-current)"
assert_equals "main repo on main" "main" "$main_branch"

# ── Working directory inside worktree ─────────────────────────────

echo ""
echo -e "${BOLD}Worktree working directory (cd into worktree)${RESET}"

# Recreate worktree for cd tests (previous one is still active)
test_start "git commands from worktree cwd use worktree branch"
cwd_branch="$(cd "$WORKTREE_DIR" && git branch --show-current)"
assert_equals "cwd shows worktree branch" "issue-1-test" "$cwd_branch"

test_start "git commands from main repo cwd use main branch"
main_cwd_branch="$(cd "$TEMP_REPO" && git branch --show-current)"
assert_equals "cwd shows main branch" "main" "$main_cwd_branch"

test_start "commits from worktree cwd go to worktree branch"
(cd "$WORKTREE_DIR" && echo "cwd-test" > cwd-file.txt && git add . && git commit -m "cwd commit" --quiet)
assert "cwd file exists in worktree" test -f "$WORKTREE_DIR/cwd-file.txt"
assert "cwd file not in main repo" test ! -f "$TEMP_REPO/cwd-file.txt"

test_start "returning to main repo dir after worktree work"
result_branch="$(cd "$WORKTREE_DIR" && echo "in worktree" > /dev/null && cd "$TEMP_REPO" && git branch --show-current)"
assert_equals "back in main repo branch" "main" "$result_branch"

# ── SKILL.md documents cd into worktree ──────────────────────────

echo ""
echo -e "${BOLD}SKILL.md worktree cd instructions${RESET}"

SKILL_FILE="$REPO_ROOT/skills/gh-issue-autopilot/SKILL.md"

test_start "SKILL.md instructs subagent to cd into worktree"
assert "contains cd into worktree instruction" grep -q "Change directory into the worktree" "$SKILL_FILE"

test_start "SKILL.md instructs subagent to cd back to main repo"
assert "contains cd back instruction" grep -q "Change directory back to the main repo" "$SKILL_FILE"

test_start "SKILL.md important rules mention cd requirement"
assert "rules mention cd into worktree" grep -q "cd.*into the worktree directory after creating it" "$SKILL_FILE"

# ── Worktree cleanup ─────────────────────────────────────────────

echo ""
echo -e "${BOLD}Worktree cleanup${RESET}"

test_start "remove worktree"
git -C "$TEMP_REPO" worktree remove "$WORKTREE_DIR" --force 2>/dev/null
assert "worktree directory removed" test ! -d "$WORKTREE_DIR"
WORKTREE_DIR=""  # prevent double cleanup in trap

test_start "branch still exists after worktree removal"
branch_exists="$(git -C "$TEMP_REPO" branch --list "issue-1-test")"
assert "branch still exists" test -n "$branch_exists"

test_start "can delete branch after worktree removal"
git -C "$TEMP_REPO" branch -D issue-1-test --quiet 2>/dev/null
branch_exists="$(git -C "$TEMP_REPO" branch --list "issue-1-test")"
assert "branch deleted" test -z "$branch_exists"

echo ""
test_summary "Worktree Operations"
