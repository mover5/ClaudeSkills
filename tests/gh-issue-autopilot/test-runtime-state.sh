#!/usr/bin/env bash
# Tests for runtime state management (active-issue-auto.txt, active-issue-manual.txt, runtime dir)
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

# ── Active issue files ────────────────────────────────────────────

echo ""
echo -e "${BOLD}Active issue tracking (separate files per mode)${RESET}"

RUNTIME_DIR="$TEMP_DIR/autopilot-test"
mkdir -p "$RUNTIME_DIR"
AUTO_FILE="$RUNTIME_DIR/active-issue-auto.txt"
MANUAL_FILE="$RUNTIME_DIR/active-issue-manual.txt"

# Parse active issue (same logic the skill uses)
parse_active_issue() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "NONE"
    return
  fi
  cat "$file"
}

test_start "no active issue initially (auto)"
result="$(parse_active_issue "$AUTO_FILE")"
assert_equals "returns NONE when no auto file" "NONE" "$result"

test_start "no active issue initially (manual)"
result="$(parse_active_issue "$MANUAL_FILE")"
assert_equals "returns NONE when no manual file" "NONE" "$result"

# Write auto mode active issue
echo "42 101 issue-42-fix-bug" > "$AUTO_FILE"
test_start "auto mode active issue"
result="$(parse_active_issue "$AUTO_FILE")"
assert_contains "contains issue number" "$result" "42"
assert_contains "contains PR number" "$result" "101"
assert_contains "contains branch name" "$result" "issue-42-fix-bug"

# Parse auto mode fields
read -r issue_num pr_num branch_name <<< "$(cat "$AUTO_FILE")"
assert_equals "issue number parsed" "42" "$issue_num"
assert_equals "PR number parsed" "101" "$pr_num"
assert_equals "branch name parsed" "issue-42-fix-bug" "$branch_name"

# Write manual mode active issue
echo "99 202 issue-99-add-feature" > "$MANUAL_FILE"
test_start "manual mode active issue"
result="$(parse_active_issue "$MANUAL_FILE")"
assert_contains "contains issue number" "$result" "99"
assert_contains "contains PR number" "$result" "202"
assert_contains "contains branch name" "$result" "issue-99-add-feature"

# Parse manual mode fields
read -r issue_num pr_num branch_name <<< "$(cat "$MANUAL_FILE")"
assert_equals "issue number parsed" "99" "$issue_num"
assert_equals "PR number parsed" "202" "$pr_num"
assert_equals "branch name parsed" "issue-99-add-feature" "$branch_name"

# Both modes can be active simultaneously on different issues
test_start "both modes active simultaneously"
assert "auto file exists" test -f "$AUTO_FILE"
assert "manual file exists" test -f "$MANUAL_FILE"

# ── Cleanup active issues ────────────────────────────────────────

echo ""
echo -e "${BOLD}Cleanup${RESET}"

test_start "remove auto active issue"
rm -f "$AUTO_FILE"
assert "auto file removed" test ! -f "$AUTO_FILE"
result="$(parse_active_issue "$AUTO_FILE")"
assert_equals "returns NONE after auto cleanup" "NONE" "$result"

test_start "manual file unaffected by auto cleanup"
assert "manual file still exists" test -f "$MANUAL_FILE"

test_start "remove manual active issue"
rm -f "$MANUAL_FILE"
assert "manual file removed" test ! -f "$MANUAL_FILE"
result="$(parse_active_issue "$MANUAL_FILE")"
assert_equals "returns NONE after manual cleanup" "NONE" "$result"

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
