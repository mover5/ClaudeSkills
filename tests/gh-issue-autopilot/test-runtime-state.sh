#!/usr/bin/env bash
# Tests for runtime state management (active-issue.txt, runtime dir)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Runtime State Management${RESET}"
echo ""

TEMP_DIR="$(mktemp -d)"
trap 'cleanup_temp "$TEMP_DIR"' EXIT

# ── Runtime dir derivation ────────────────────────────────────────

echo -e "${BOLD}Runtime directory derivation${RESET}"

# Simulate REPO_ID computation
compute_repo_id() {
  echo "$1" | md5sum | cut -c1-12
}

test_start "repo ID is deterministic"
id1="$(compute_repo_id "https://github.com/user/repo")"
id2="$(compute_repo_id "https://github.com/user/repo")"
assert_equals "same URL produces same ID" "$id1" "$id2"

test_start "different repos get different IDs"
id3="$(compute_repo_id "https://github.com/user/other-repo")"
assert "different URLs produce different IDs" test "$id1" != "$id3"

test_start "ID is 12 chars"
assert_equals "ID length is 12" "12" "${#id1}"

# ── Active issue file ────────────────────────────────────────────

echo ""
echo -e "${BOLD}Active issue tracking${RESET}"

RUNTIME_DIR="$TEMP_DIR/autopilot-test"
mkdir -p "$RUNTIME_DIR"
ACTIVE_FILE="$RUNTIME_DIR/active-issue.txt"

# Parse active issue (same logic the skill uses)
parse_active_issue() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "NONE"
    return
  fi
  cat "$file"
}

test_start "no active issue initially"
result="$(parse_active_issue "$ACTIVE_FILE")"
assert_equals "returns NONE when no file" "NONE" "$result"

# Write auto mode active issue
echo "42 101 issue-42-fix-bug" > "$ACTIVE_FILE"
test_start "auto mode active issue"
result="$(parse_active_issue "$ACTIVE_FILE")"
assert_contains "contains issue number" "$result" "42"
assert_contains "contains PR number" "$result" "101"
assert_contains "contains branch name" "$result" "issue-42-fix-bug"
assert_not_contains "no MANUAL flag" "$result" "MANUAL"

# Write manual mode active issue
echo "42 101 issue-42-fix-bug MANUAL" > "$ACTIVE_FILE"
test_start "manual mode active issue"
result="$(parse_active_issue "$ACTIVE_FILE")"
assert_contains "contains MANUAL flag" "$result" "MANUAL"

# Parse fields
read -r issue_num pr_num branch_name mode <<< "$(cat "$ACTIVE_FILE")"
assert_equals "issue number parsed" "42" "$issue_num"
assert_equals "PR number parsed" "101" "$pr_num"
assert_equals "branch name parsed" "issue-42-fix-bug" "$branch_name"
assert_equals "mode parsed" "MANUAL" "$mode"

# ── Cleanup active issue ─────────────────────────────────────────

echo ""
echo -e "${BOLD}Cleanup${RESET}"

test_start "remove active issue"
rm -f "$ACTIVE_FILE"
assert "active issue file removed" test ! -f "$ACTIVE_FILE"
result="$(parse_active_issue "$ACTIVE_FILE")"
assert_equals "returns NONE after cleanup" "NONE" "$result"

# ── Cron ID file ─────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Cron ID tracking${RESET}"

CRON_FILE="$RUNTIME_DIR/cron-id.txt"

test_start "no cron ID initially"
assert "cron file does not exist" test ! -f "$CRON_FILE"

echo "cron_abc123" > "$CRON_FILE"
test_start "cron ID written"
assert "cron file exists" test -f "$CRON_FILE"
cron_id="$(cat "$CRON_FILE")"
assert_equals "cron ID matches" "cron_abc123" "$cron_id"

rm -f "$CRON_FILE"
test_start "cron ID removed"
assert "cron file removed" test ! -f "$CRON_FILE"

echo ""
test_summary "Runtime State Management"
