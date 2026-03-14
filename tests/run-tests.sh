#!/usr/bin/env bash
# Top-level test runner
# Usage: ./run-tests.sh [skill-name]  — run tests for one skill, or all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

OVERALL_PASS=0
OVERALL_FAIL=0
SUITES_RUN=0
FAILED_SUITES=()

run_suite() {
  local script="$1"
  local name
  name="$(basename "$script" .sh)"
  SUITES_RUN=$((SUITES_RUN + 1))

  echo ""
  echo -e "${BOLD}════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  $name${RESET}"
  echo -e "${BOLD}════════════════════════════════════════════════════${RESET}"
  echo ""

  # Run in subshell to isolate counters and state
  if bash "$script"; then
    OVERALL_PASS=$((OVERALL_PASS + 1))
  else
    OVERALL_FAIL=$((OVERALL_FAIL + 1))
    FAILED_SUITES+=("$name")
  fi
}

echo -e "${BOLD}ClaudeSkills Test Runner${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Layer 1: Structure validation (always runs) ───────────────────

run_suite "$SCRIPT_DIR/validate-skills.sh"

# ── Layer 2: Per-skill behavioral tests ───────────────────────────

if [ $# -gt 0 ]; then
  # Run tests for specific skill only
  skill="$1"
  skill_test_dir="$SCRIPT_DIR/$skill"
  if [ ! -d "$skill_test_dir" ]; then
    echo "No tests found for skill: $skill"
    exit 1
  fi
  for test_file in "$skill_test_dir"/test-*.sh; do
    [ -f "$test_file" ] && run_suite "$test_file"
  done
else
  # Run all skill tests
  for skill_test_dir in "$SCRIPT_DIR"/*/; do
    [ -d "$skill_test_dir" ] || continue
    # Skip fixtures directories
    [ "$(basename "$skill_test_dir")" = "fixtures" ] && continue
    for test_file in "$skill_test_dir"/test-*.sh; do
      [ -f "$test_file" ] && run_suite "$test_file"
    done
  done
fi

# ── Overall summary ──────────────────────────────────────────────

echo ""
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
if [ "$OVERALL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  ALL $SUITES_RUN TEST SUITES PASSED${RESET}"
else
  echo -e "${RED}${BOLD}  $OVERALL_FAIL of $SUITES_RUN SUITES FAILED:${RESET}"
  for s in "${FAILED_SUITES[@]}"; do
    echo -e "    ${RED}✗ $s${RESET}"
  done
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

exit "$OVERALL_FAIL"
