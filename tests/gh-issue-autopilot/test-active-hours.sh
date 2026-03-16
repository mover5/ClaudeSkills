#!/usr/bin/env bash
# Tests for active hours configuration and precheck enforcement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

PRECHECK="$REPO_ROOT/skills/gh-issue-autopilot/precheck.sh"

echo -e "${BOLD}gh-issue-autopilot: Active Hours${RESET}"
echo ""

# Use a temp directory to simulate a repo's .claude/ dir
TEMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TEMP_DIR/.claude"
CONFIG_FILE="$CONFIG_DIR/autopilot-config.json"
trap 'cleanup_temp "$TEMP_DIR"' EXIT

# ══════════════════════════════════════════════════════════════════
# Config parsing tests
# ══════════════════════════════════════════════════════════════════

echo -e "${BOLD}── Config Parsing ──${RESET}"
echo ""

# Helper: extract activeHours start/end using the same grep logic as precheck.sh
get_active_hours_start() {
  local cfg="$1"
  if [ -f "$cfg" ]; then
    local match
    match="$(grep -o '"start"[[:space:]]*:[[:space:]]*[0-9]\+' "$cfg" 2>/dev/null \
      | head -1 | sed 's/.*:[[:space:]]*//' || true)"
    echo "${match:-}"
  fi
}

get_active_hours_end() {
  local cfg="$1"
  if [ -f "$cfg" ]; then
    local match
    match="$(grep -o '"end"[[:space:]]*:[[:space:]]*[0-9]\+' "$cfg" 2>/dev/null \
      | head -1 | sed 's/.*:[[:space:]]*//' || true)"
    echo "${match:-}"
  fi
}

# ── No config file ──────────────────────────────────────────────

echo -e "${BOLD}No config file${RESET}"

test_start "no config"
start="$(get_active_hours_start "$CONFIG_FILE")"
end_val="$(get_active_hours_end "$CONFIG_FILE")"
assert_equals "start is empty" "" "$start"
assert_equals "end is empty" "" "$end_val"

# ── Config without activeHours ──────────────────────────────────

echo ""
echo -e "${BOLD}Config without activeHours${RESET}"

mkdir -p "$CONFIG_DIR"
echo '{"label": "Claude", "interval": 5}' > "$CONFIG_FILE"

test_start "no activeHours field"
start="$(get_active_hours_start "$CONFIG_FILE")"
end_val="$(get_active_hours_end "$CONFIG_FILE")"
assert_equals "start is empty" "" "$start"
assert_equals "end is empty" "" "$end_val"

# ── Config with activeHours ─────────────────────────────────────

echo ""
echo -e "${BOLD}Config with activeHours${RESET}"

echo '{"label": "Claude", "activeHours": {"start": 9, "end": 17}}' > "$CONFIG_FILE"

test_start "standard active hours"
start="$(get_active_hours_start "$CONFIG_FILE")"
end_val="$(get_active_hours_end "$CONFIG_FILE")"
assert_equals "start is 9" "9" "$start"
assert_equals "end is 17" "17" "$end_val"

# ── Overnight range ─────────────────────────────────────────────

echo ""
echo -e "${BOLD}Overnight range${RESET}"

echo '{"activeHours": {"start": 22, "end": 6}}' > "$CONFIG_FILE"

test_start "overnight active hours"
start="$(get_active_hours_start "$CONFIG_FILE")"
end_val="$(get_active_hours_end "$CONFIG_FILE")"
assert_equals "start is 22" "22" "$start"
assert_equals "end is 6" "6" "$end_val"

# ── Zero hour values ────────────────────────────────────────────

echo ""
echo -e "${BOLD}Zero hour values${RESET}"

echo '{"activeHours": {"start": 0, "end": 0}}' > "$CONFIG_FILE"

test_start "start and end both zero"
start="$(get_active_hours_start "$CONFIG_FILE")"
end_val="$(get_active_hours_end "$CONFIG_FILE")"
assert_equals "start is 0" "0" "$start"
assert_equals "end is 0" "0" "$end_val"

# ══════════════════════════════════════════════════════════════════
# Precheck integration tests (using CURRENT_HOUR override)
# ══════════════════════════════════════════════════════════════════

# These tests require gh auth to run (precheck.sh calls gh)
if gh auth status >/dev/null 2>&1; then

  echo ""
  echo -e "${BOLD}── Precheck Active Hours Enforcement (live) ──${RESET}"
  echo ""

  # Save and restore real config
  REAL_CONFIG="$REPO_ROOT/.claude/autopilot-config.json"
  BACKUP_FILE="$TEMP_DIR/autopilot-config.json.bak"
  if [ -f "$REAL_CONFIG" ]; then
    cp "$REAL_CONFIG" "$BACKUP_FILE"
  fi
  mkdir -p "$REPO_ROOT/.claude"

  # Compute runtime dir and temporarily hide active issue files
  REPO_ID=$(gh repo view --json url --jq '.url' | md5sum | cut -c1-12)
  RUNTIME_DIR="/tmp/autopilot-${REPO_ID}"
  mkdir -p "$RUNTIME_DIR"
  for f in "$RUNTIME_DIR"/active-issue-*.txt; do
    [ -f "$f" ] && mv "$f" "${f}.hours-bak"
  done

  restore_state() {
    # Restore active issue files
    for f in "$RUNTIME_DIR"/active-issue-*.txt.hours-bak; do
      [ -f "$f" ] && mv "$f" "${f%.hours-bak}"
    done
    # Restore config
    if [ -f "$BACKUP_FILE" ]; then
      mv "$BACKUP_FILE" "$REAL_CONFIG"
    else
      rm -f "$REAL_CONFIG"
    fi
  }
  trap 'restore_state; cleanup_temp "$TEMP_DIR"' EXIT

  # Use a label that won't match any real issues
  BASE_CONFIG='{"label": "nonexistent-label-xyz-99999"'

  # ── No activeHours: precheck should NOT block on hours ────────

  echo -e "${BOLD}No activeHours configured${RESET}"

  echo "${BASE_CONFIG}}" > "$REAL_CONFIG"

  test_start "no activeHours does not block"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=3 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  # Should exit zero with NO_WORK output (no matching issues, but NOT because of hours)
  assert_equals "exits zero (no work)" "0" "$exit_code"
  assert_contains "output is NO_WORK (not hours)" "$output" "NO_WORK"

  # ── Normal range: inside active hours ─────────────────────────

  echo ""
  echo -e "${BOLD}Normal range (9-17): inside${RESET}"

  echo "${BASE_CONFIG}, \"activeHours\": {\"start\": 9, \"end\": 17}}" > "$REAL_CONFIG"

  test_start "hour 12 inside 9-17"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=12 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_equals "exits zero (no work, but not hours)" "0" "$exit_code"
  assert_contains "output is NO_WORK" "$output" "NO_WORK"

  test_start "hour 9 inside 9-17 (boundary)"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=9 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is NO_WORK" "$output" "NO_WORK"

  # ── Normal range: outside active hours ────────────────────────

  echo ""
  echo -e "${BOLD}Normal range (9-17): outside${RESET}"

  test_start "hour 5 outside 9-17"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=5 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_equals "exits zero" "0" "$exit_code"
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  test_start "hour 17 outside 9-17 (boundary, end is exclusive)"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=17 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  test_start "hour 23 outside 9-17"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=23 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  # ── Overnight range: inside active hours ──────────────────────

  echo ""
  echo -e "${BOLD}Overnight range (22-6): inside${RESET}"

  echo "${BASE_CONFIG}, \"activeHours\": {\"start\": 22, \"end\": 6}}" > "$REAL_CONFIG"

  test_start "hour 23 inside 22-6"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=23 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is NO_WORK" "$output" "NO_WORK"

  test_start "hour 0 inside 22-6"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=0 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is NO_WORK" "$output" "NO_WORK"

  test_start "hour 3 inside 22-6"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=3 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is NO_WORK" "$output" "NO_WORK"

  test_start "hour 22 inside 22-6 (boundary)"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=22 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is NO_WORK" "$output" "NO_WORK"

  # ── Overnight range: outside active hours ─────────────────────

  echo ""
  echo -e "${BOLD}Overnight range (22-6): outside${RESET}"

  test_start "hour 10 outside 22-6"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=10 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  test_start "hour 6 outside 22-6 (boundary, end is exclusive)"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=6 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  test_start "hour 15 outside 22-6"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=15 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  # ── Same start and end (always disabled) ──────────────────────

  echo ""
  echo -e "${BOLD}Same start and end (12-12): always disabled${RESET}"

  echo "${BASE_CONFIG}, \"activeHours\": {\"start\": 12, \"end\": 12}}" > "$REAL_CONFIG"

  test_start "hour 12 outside 12-12"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=12 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  test_start "hour 0 outside 12-12"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=0 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"

  # ── Active hours + active issue (active issue takes precedence) ─

  echo ""
  echo -e "${BOLD}Active issue overrides active hours${RESET}"

  # Set hours that would block (9-17, current hour 3 = outside)
  echo "${BASE_CONFIG}, \"activeHours\": {\"start\": 9, \"end\": 17}}" > "$REAL_CONFIG"

  # But create an active issue file — should still be blocked by hours
  # because the hours check runs BEFORE the active issue check
  test_start "outside hours blocks even with active issue"
  echo "99 200 issue-99-test" > "$RUNTIME_DIR/active-issue-auto.txt"
  output="$(cd "$REPO_ROOT" && CURRENT_HOUR=3 bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_contains "output is OUTSIDE_ACTIVE_HOURS" "$output" "OUTSIDE_ACTIVE_HOURS"
  rm -f "$RUNTIME_DIR/active-issue-auto.txt"

else
  echo ""
  echo -e "${YELLOW}Skipping live precheck tests (gh not authenticated)${RESET}"
fi

echo ""
test_summary "Active Hours"
