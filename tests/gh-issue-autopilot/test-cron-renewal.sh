#!/usr/bin/env bash
# Tests for cron renewal logic (supports scanning durations longer than 3 days)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Cron Renewal${RESET}"
echo ""

TEMP_DIR="$(mktemp -d)"
trap 'cleanup_temp "$TEMP_DIR"' EXIT

RUNTIME_DIR="$TEMP_DIR/autopilot-test"
mkdir -p "$RUNTIME_DIR"

# ── Helpers ──────────────────────────────────────────────────────

# Compute cron age in seconds (same logic the skill uses)
compute_cron_age() {
  local ts_file="$1"
  local current_time="$2"
  if [ ! -f "$ts_file" ]; then
    echo "0"
    return
  fi
  local created_at
  created_at="$(cat "$ts_file")"
  echo "$(( current_time - created_at ))"
}

# Check if renewal is needed (threshold = 172800 seconds = 2 days)
# Returns "yes" or "no" as text for easy testing
check_renewal() {
  local age="$1"
  if [ "$age" -gt 172800 ]; then
    echo "yes"
  else
    echo "no"
  fi
}

# ══════════════════════════════════════════════════════════════════
# cron-created-at.txt file management
# ══════════════════════════════════════════════════════════════════

echo -e "${BOLD}── Cron Timestamp File ──${RESET}"
echo ""

CRON_ID_FILE="$RUNTIME_DIR/cron-id.txt"
CRON_TS_FILE="$RUNTIME_DIR/cron-created-at.txt"

# ── No timestamp file initially ──────────────────────────────────

echo -e "${BOLD}Initial state${RESET}"

test_start "no cron-created-at.txt initially"
assert "timestamp file does not exist" test ! -f "$CRON_TS_FILE"

# ── Write timestamp on cron creation ─────────────────────────────

echo ""
echo -e "${BOLD}Writing timestamp on cron creation${RESET}"

NOW="$(date +%s)"
echo "$NOW" > "$CRON_TS_FILE"
echo "cron_job_001" > "$CRON_ID_FILE"

test_start "timestamp file written"
assert_file_exists "cron-created-at.txt exists" "$CRON_TS_FILE"
assert_file_exists "cron-id.txt exists" "$CRON_ID_FILE"

stored_ts="$(cat "$CRON_TS_FILE")"
assert_equals "stored timestamp matches" "$NOW" "$stored_ts"

# ══════════════════════════════════════════════════════════════════
# Cron age calculation
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Cron Age Calculation ──${RESET}"
echo ""

# ── Fresh cron (just created) ────────────────────────────────────

echo -e "${BOLD}Fresh cron (age = 0)${RESET}"

test_start "fresh cron does not need renewal"
age="$(compute_cron_age "$CRON_TS_FILE" "$NOW")"
assert_equals "age is 0" "0" "$age"
result="$(check_renewal "$age")"
assert_equals "does not need renewal" "no" "$result"

# ── Cron at 1 day old ────────────────────────────────────────────

echo ""
echo -e "${BOLD}Cron at 1 day old (86400s)${RESET}"

ONE_DAY_LATER=$(( NOW + 86400 ))

test_start "1-day-old cron does not need renewal"
age="$(compute_cron_age "$CRON_TS_FILE" "$ONE_DAY_LATER")"
assert_equals "age is 86400" "86400" "$age"
result="$(check_renewal "$age")"
assert_equals "does not need renewal" "no" "$result"

# ── Cron at exactly 2 days old (boundary) ────────────────────────

echo ""
echo -e "${BOLD}Cron at exactly 2 days (172800s, boundary)${RESET}"

TWO_DAYS_LATER=$(( NOW + 172800 ))

test_start "2-day-old cron does not need renewal (boundary)"
age="$(compute_cron_age "$CRON_TS_FILE" "$TWO_DAYS_LATER")"
assert_equals "age is 172800" "172800" "$age"
result="$(check_renewal "$age")"
assert_equals "does not need renewal at boundary" "no" "$result"

# ── Cron at 2 days + 1 second (just past threshold) ─────────────

echo ""
echo -e "${BOLD}Cron at 2 days + 1 second (172801s, past threshold)${RESET}"

PAST_THRESHOLD=$(( NOW + 172801 ))

test_start "cron past 2-day threshold needs renewal"
age="$(compute_cron_age "$CRON_TS_FILE" "$PAST_THRESHOLD")"
assert_equals "age is 172801" "172801" "$age"
result="$(check_renewal "$age")"
assert_equals "needs renewal" "yes" "$result"

# ── Cron at 2.5 days old ────────────────────────────────────────

echo ""
echo -e "${BOLD}Cron at 2.5 days (216000s)${RESET}"

TWO_HALF_DAYS=$(( NOW + 216000 ))

test_start "2.5-day-old cron needs renewal"
age="$(compute_cron_age "$CRON_TS_FILE" "$TWO_HALF_DAYS")"
assert_equals "age is 216000" "216000" "$age"
result="$(check_renewal "$age")"
assert_equals "needs renewal" "yes" "$result"

# ── Cron at 3 days old (would have expired without renewal) ─────

echo ""
echo -e "${BOLD}Cron at 3 days (259200s, would expire without renewal)${RESET}"

THREE_DAYS=$(( NOW + 259200 ))

test_start "3-day-old cron needs renewal"
age="$(compute_cron_age "$CRON_TS_FILE" "$THREE_DAYS")"
assert_equals "age is 259200" "259200" "$age"
result="$(check_renewal "$age")"
assert_equals "needs renewal" "yes" "$result"

# ══════════════════════════════════════════════════════════════════
# Renewal simulation (file updates)
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Renewal Simulation ──${RESET}"
echo ""

# Simulate what happens during renewal: update cron ID and timestamp

echo -e "${BOLD}Simulate cron renewal${RESET}"

OLD_CRON_ID="$(cat "$CRON_ID_FILE")"
NEW_CRON_ID="cron_job_002"
RENEWAL_TIME=$(( NOW + 172801 ))

# Renewal: write new cron ID and timestamp
echo "$NEW_CRON_ID" > "$CRON_ID_FILE"
echo "$RENEWAL_TIME" > "$CRON_TS_FILE"

test_start "cron ID updated after renewal"
current_id="$(cat "$CRON_ID_FILE")"
assert_equals "new cron ID stored" "$NEW_CRON_ID" "$current_id"
assert "old and new cron IDs differ" test "$OLD_CRON_ID" != "$current_id"

test_start "timestamp updated after renewal"
current_ts="$(cat "$CRON_TS_FILE")"
assert_equals "new timestamp stored" "$RENEWAL_TIME" "$current_ts"

test_start "renewed cron is fresh again"
age="$(compute_cron_age "$CRON_TS_FILE" "$RENEWAL_TIME")"
assert_equals "age is 0 after renewal" "0" "$age"
result="$(check_renewal "$age")"
assert_equals "does not need renewal" "no" "$result"

# After renewal, 2 more days should not trigger renewal
AFTER_RENEWAL_2DAYS=$(( RENEWAL_TIME + 172800 ))
test_start "renewed cron still fresh at 2 days"
age="$(compute_cron_age "$CRON_TS_FILE" "$AFTER_RENEWAL_2DAYS")"
assert_equals "age is 172800" "172800" "$age"
result="$(check_renewal "$age")"
assert_equals "does not need renewal at boundary" "no" "$result"

# But 2 days + 1 second after renewal should trigger again
AFTER_RENEWAL_PAST=$(( RENEWAL_TIME + 172801 ))
test_start "renewed cron needs renewal again after 2+ days"
age="$(compute_cron_age "$CRON_TS_FILE" "$AFTER_RENEWAL_PAST")"
assert_equals "age is 172801" "172801" "$age"
result="$(check_renewal "$age")"
assert_equals "needs renewal again" "yes" "$result"

# ══════════════════════════════════════════════════════════════════
# Cleanup on stop
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Cleanup on Stop ──${RESET}"
echo ""

test_start "both files exist before cleanup"
assert_file_exists "cron-id.txt exists" "$CRON_ID_FILE"
assert_file_exists "cron-created-at.txt exists" "$CRON_TS_FILE"

# Simulate stop: remove both files
rm -f "$CRON_ID_FILE" "$CRON_TS_FILE"

test_start "both files removed on stop"
assert_file_not_exists "cron-id.txt removed" "$CRON_ID_FILE"
assert_file_not_exists "cron-created-at.txt removed" "$CRON_TS_FILE"

# ══════════════════════════════════════════════════════════════════
# Missing timestamp file (graceful handling)
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Missing Timestamp File ──${RESET}"
echo ""

test_start "missing timestamp file returns age 0"
age="$(compute_cron_age "$CRON_TS_FILE" "$(date +%s)")"
assert_equals "age is 0 when no file" "0" "$age"
result="$(check_renewal "$age")"
assert_equals "does not need renewal when no file" "no" "$result"

# ══════════════════════════════════════════════════════════════════
# Session restart scenarios (stale cron state detection)
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Session Restart Scenarios ──${RESET}"
echo ""

# Simulate: cron files left over from a previous session.
# In a new session, CronList would return no matching ID.
# The skill should detect the stale ID and clean up.

# Helper: check if a cron ID is "valid" given a list of known IDs.
# Simulates what CronList validation does.
cron_id_is_valid() {
  local stored_id="$1"
  local known_ids="$2"  # space-separated list of valid IDs
  for id in $known_ids; do
    if [ "$stored_id" = "$id" ]; then
      echo "valid"
      return
    fi
  done
  echo "stale"
}

# ── Stale cron ID from previous session ──────────────────────────

echo -e "${BOLD}Stale cron ID from previous session${RESET}"

echo "old_session_cron_123" > "$CRON_ID_FILE"
echo "1700000000" > "$CRON_TS_FILE"

# New session has different cron IDs (or none)
CURRENT_SESSION_CRONS="new_session_cron_456 new_session_cron_789"

test_start "detect stale cron ID from previous session"
stored_id="$(cat "$CRON_ID_FILE")"
result="$(cron_id_is_valid "$stored_id" "$CURRENT_SESSION_CRONS")"
assert_equals "stale cron detected" "stale" "$result"

# Simulate cleanup: when stale, remove both files
if [ "$result" = "stale" ]; then
  rm -f "$CRON_ID_FILE" "$CRON_TS_FILE"
fi

test_start "stale cron files cleaned up"
assert_file_not_exists "cron-id.txt removed" "$CRON_ID_FILE"
assert_file_not_exists "cron-created-at.txt removed" "$CRON_TS_FILE"

# ── Valid cron ID in same session ────────────────────────────────

echo ""
echo -e "${BOLD}Valid cron ID in current session${RESET}"

echo "new_session_cron_456" > "$CRON_ID_FILE"
echo "$(date +%s)" > "$CRON_TS_FILE"

test_start "detect valid cron ID in current session"
stored_id="$(cat "$CRON_ID_FILE")"
result="$(cron_id_is_valid "$stored_id" "$CURRENT_SESSION_CRONS")"
assert_equals "cron is valid" "valid" "$result"

test_start "valid cron files preserved"
assert_file_exists "cron-id.txt kept" "$CRON_ID_FILE"
assert_file_exists "cron-created-at.txt kept" "$CRON_TS_FILE"

# ── Empty session (no cron jobs at all) ──────────────────────────

echo ""
echo -e "${BOLD}Stale ID with empty session (no crons running)${RESET}"

echo "leftover_cron_999" > "$CRON_ID_FILE"
echo "1700000000" > "$CRON_TS_FILE"

EMPTY_SESSION_CRONS=""

test_start "detect stale cron ID with no active crons"
stored_id="$(cat "$CRON_ID_FILE")"
result="$(cron_id_is_valid "$stored_id" "$EMPTY_SESSION_CRONS")"
assert_equals "stale cron detected" "stale" "$result"

# Cleanup
rm -f "$CRON_ID_FILE" "$CRON_TS_FILE"

test_start "stale files cleaned up (empty session)"
assert_file_not_exists "cron-id.txt removed" "$CRON_ID_FILE"
assert_file_not_exists "cron-created-at.txt removed" "$CRON_TS_FILE"

# ── No cron files at all (fresh start) ──────────────────────────

echo ""
echo -e "${BOLD}Fresh start with no cron state files${RESET}"

rm -f "$CRON_ID_FILE" "$CRON_TS_FILE"

test_start "no cron files is a clean state"
assert_file_not_exists "no cron-id.txt" "$CRON_ID_FILE"
assert_file_not_exists "no cron-created-at.txt" "$CRON_TS_FILE"

# After fresh start, new cron is created and files are written
echo "fresh_cron_001" > "$CRON_ID_FILE"
echo "$(date +%s)" > "$CRON_TS_FILE"

test_start "new cron files created after fresh start"
assert_file_exists "cron-id.txt created" "$CRON_ID_FILE"
assert_file_exists "cron-created-at.txt created" "$CRON_TS_FILE"

# Final cleanup
rm -f "$CRON_ID_FILE" "$CRON_TS_FILE"

echo ""
test_summary "Cron Renewal"
