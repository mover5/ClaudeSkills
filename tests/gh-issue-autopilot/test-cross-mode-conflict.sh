#!/usr/bin/env bash
# Tests for cross-mode conflict prevention
# Ensures auto and manual modes cannot work on the same issue simultaneously
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Cross-Mode Conflict Prevention${RESET}"
echo ""

TEMP_DIR="$(mktemp -d)"
trap 'cleanup_temp "$TEMP_DIR"' EXIT

RUNTIME_DIR="$TEMP_DIR/autopilot-test"
mkdir -p "$RUNTIME_DIR"
AUTO_FILE="$RUNTIME_DIR/active-issue-auto.txt"
MANUAL_FILE="$RUNTIME_DIR/active-issue-manual.txt"

# ── Helper: check for conflict ────────────────────────────────────

# Simulates the conflict check logic from the skill.
# Writes "CONFLICT" or "OK" to stdout.
check_conflict() {
  local mode="$1"        # "auto" or "manual"
  local issue_number="$2"

  if [ "$mode" = "manual" ]; then
    local other_file="$RUNTIME_DIR/active-issue-auto.txt"
  else
    local other_file="$RUNTIME_DIR/active-issue-manual.txt"
  fi

  if [ ! -f "$other_file" ]; then
    echo "OK"
    return
  fi

  local other_issue
  read -r other_issue _ _ <<< "$(cat "$other_file")"
  if [ "$other_issue" = "$issue_number" ]; then
    echo "CONFLICT"
    return
  fi

  echo "OK"
}

# ── No conflict when other mode is idle ───────────────────────────

echo -e "${BOLD}No conflict when other mode is idle${RESET}"

test_start "manual mode: no conflict when auto is idle"
result="$(check_conflict "manual" "42")"
assert_equals "no conflict" "OK" "$result"

test_start "auto mode: no conflict when manual is idle"
result="$(check_conflict "auto" "42")"
assert_equals "no conflict" "OK" "$result"

# ── Conflict when same issue ──────────────────────────────────────

echo ""
echo -e "${BOLD}Conflict detected on same issue${RESET}"

# Auto is working on issue 42
echo "42 101 issue-42-fix-bug" > "$AUTO_FILE"

test_start "manual mode: conflict when auto has same issue"
result="$(check_conflict "manual" "42")"
assert_equals "conflict detected" "CONFLICT" "$result"

rm -f "$AUTO_FILE"

# Manual is working on issue 42
echo "42 101 issue-42-fix-bug" > "$MANUAL_FILE"

test_start "auto mode: conflict when manual has same issue"
result="$(check_conflict "auto" "42")"
assert_equals "conflict detected" "CONFLICT" "$result"

rm -f "$MANUAL_FILE"

# ── No conflict when different issues ─────────────────────────────

echo ""
echo -e "${BOLD}No conflict on different issues${RESET}"

# Auto is working on issue 42
echo "42 101 issue-42-fix-bug" > "$AUTO_FILE"

test_start "manual mode: no conflict when auto has different issue"
result="$(check_conflict "manual" "99")"
assert_equals "no conflict" "OK" "$result"

# Manual is working on issue 99
echo "99 202 issue-99-add-feature" > "$MANUAL_FILE"

test_start "auto mode: no conflict when manual has different issue"
result="$(check_conflict "auto" "42")"
assert_equals "no conflict" "OK" "$result"

# ── Both modes active on different issues ─────────────────────────

echo ""
echo -e "${BOLD}Both modes active on different issues${RESET}"

test_start "both modes can be active simultaneously"
assert "auto file exists" test -f "$AUTO_FILE"
assert "manual file exists" test -f "$MANUAL_FILE"

test_start "no conflict between different active issues"
result_manual="$(check_conflict "manual" "99")"
result_auto="$(check_conflict "auto" "42")"
assert_equals "manual 99 vs auto 42: no conflict" "OK" "$result_manual"
assert_equals "auto 42 vs manual 99: no conflict" "OK" "$result_auto"

# ── Conflict after mode switch ────────────────────────────────────

echo ""
echo -e "${BOLD}Conflict when both modes target same issue${RESET}"

# Both try to work on issue 42
echo "42 101 issue-42-fix-bug" > "$AUTO_FILE"
echo "42 303 issue-42-fix-bug" > "$MANUAL_FILE"

test_start "conflict when both modes have same issue"
result_manual="$(check_conflict "manual" "42")"
result_auto="$(check_conflict "auto" "42")"
assert_equals "manual detects conflict with auto" "CONFLICT" "$result_manual"
assert_equals "auto detects conflict with manual" "CONFLICT" "$result_auto"

# ── Cleanup restores no-conflict state ────────────────────────────

echo ""
echo -e "${BOLD}Cleanup restores no-conflict state${RESET}"

rm -f "$AUTO_FILE"
test_start "no conflict after auto cleanup"
result="$(check_conflict "manual" "42")"
assert_equals "manual mode: no conflict" "OK" "$result"

rm -f "$MANUAL_FILE"
test_start "no conflict after manual cleanup"
result="$(check_conflict "auto" "42")"
assert_equals "auto mode: no conflict" "OK" "$result"

echo ""
test_summary "Cross-Mode Conflict Prevention"
