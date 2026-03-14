#!/usr/bin/env bash
# Tests for branch naming conventions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Branch Naming${RESET}"
echo ""

# Branch name generation logic (mirrors what the skill should do)
generate_branch_name() {
  local issue_number="$1"
  local title="$2"
  # Lowercase, replace non-alphanumeric with hyphens, collapse multiple hyphens, trim
  local slug
  slug="$(echo "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/-\+/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c1-40)"
  echo "issue-${issue_number}-${slug}"
}

# ── Basic branch names ────────────────────────────────────────────

echo -e "${BOLD}Basic branch name generation${RESET}"

test_start "simple title"
name="$(generate_branch_name 42 "Fix login bug")"
assert_equals "simple title" "issue-42-fix-login-bug" "$name"

test_start "title with special chars"
name="$(generate_branch_name 7 "Add @mentions & #tags support")"
assert_equals "special chars replaced" "issue-7-add-mentions-tags-support" "$name"

test_start "title with extra spaces"
name="$(generate_branch_name 99 "  lots   of   spaces  ")"
assert_equals "spaces collapsed" "issue-99-lots-of-spaces" "$name"

test_start "uppercase title"
name="$(generate_branch_name 1 "URGENT FIX FOR PROD")"
assert_equals "lowercased" "issue-1-urgent-fix-for-prod" "$name"

# ── Long titles get truncated ─────────────────────────────────────

echo ""
echo -e "${BOLD}Long title truncation${RESET}"

test_start "long title"
name="$(generate_branch_name 123 "This is a very long issue title that should be truncated to keep branch names reasonable")"
assert "branch name length <= 52" test "${#name}" -le 52  # issue-123- = 10 chars + 40 max slug
assert_contains "starts with issue-123-" "$name" "issue-123-"

# ── Edge cases ────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Edge cases${RESET}"

test_start "numeric title"
name="$(generate_branch_name 5 "404 error on page 2")"
assert_equals "numeric title" "issue-5-404-error-on-page-2" "$name"

test_start "single word title"
name="$(generate_branch_name 10 "Crash")"
assert_equals "single word" "issue-10-crash" "$name"

# ── All branch names start with issue-N ───────────────────────────

echo ""
echo -e "${BOLD}Branch name format${RESET}"

for num in 1 42 999 1234; do
  test_start "prefix for issue #$num"
  name="$(generate_branch_name "$num" "test")"
  assert_contains "starts with issue-$num-" "$name" "issue-${num}-"
done

echo ""
test_summary "Branch Naming"
