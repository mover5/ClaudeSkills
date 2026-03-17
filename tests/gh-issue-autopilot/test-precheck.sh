#!/usr/bin/env bash
# Tests for the precheck.sh script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

PRECHECK="$REPO_ROOT/plugins/gh-issue-autopilot/skills/gh-issue-autopilot/precheck.sh"

echo -e "${BOLD}gh-issue-autopilot: Pre-check Script${RESET}"
echo ""

# ── Script exists and is executable ───────────────────────────────

echo -e "${BOLD}Script basics${RESET}"

test_start "precheck exists"
assert "precheck.sh exists" test -f "$PRECHECK"
assert "precheck.sh is executable" test -x "$PRECHECK"

# ── Live tests (require gh auth) ─────────────────────────────────

if gh auth status >/dev/null 2>&1; then

  # ── No work scenario (live check against current repo) ────────────

  echo ""
  echo -e "${BOLD}No-work detection (live)${RESET}"

  # Run precheck from the real repo but with a label that has no issues.
  # Temporarily create a config with an impossible label, then restore.
  TEMP_DIR="$(mktemp -d)"
  trap 'cleanup_temp "$TEMP_DIR"' EXIT

  CONFIG_FILE="$REPO_ROOT/.claude/autopilot-config.json"
  BACKUP_FILE="$TEMP_DIR/autopilot-config.json.bak"

  # Compute runtime dir for backup/restore of active issue files
  REPO_ID=$(gh repo view --json url --jq '.url' | md5sum | cut -c1-12)
  RUNTIME_DIR="/tmp/autopilot-${REPO_ID}"
  mkdir -p "$RUNTIME_DIR"

  # Back up existing config if present
  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
  fi
  mkdir -p "$REPO_ROOT/.claude"
  echo '{"label": "nonexistent-label-xyz-12345"}' > "$CONFIG_FILE"

  # Temporarily move active issue files so precheck sees no work
  for f in "$RUNTIME_DIR"/active-issue-*.txt; do
    [ -f "$f" ] && mv "$f" "${f}.nowork-bak"
  done

  # Run precheck from the repo root (no active issue, no matching issues)
  test_start "exits zero with NO_WORK when no work"
  output="$(cd "$REPO_ROOT" && bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?

  # Restore active issue files
  for f in "$RUNTIME_DIR"/active-issue-*.txt.nowork-bak; do
    [ -f "$f" ] && mv "$f" "${f%.nowork-bak}"
  done

  # Restore config
  if [ -f "$BACKUP_FILE" ]; then
    mv "$BACKUP_FILE" "$CONFIG_FILE"
  else
    rm -f "$CONFIG_FILE"
  fi

  assert_equals "exits zero" "0" "$exit_code"
  assert_contains "outputs NO_WORK" "$output" "NO_WORK"

  # ── Active issue scenario ─────────────────────────────────────────

  echo ""
  echo -e "${BOLD}Active issue detection${RESET}"

  # Create a fake active-issue-auto.txt in the runtime dir (REPO_ID/RUNTIME_DIR already set above)

  # Save and restore state
  HAD_ACTIVE_ISSUE=false
  if [ -f "$RUNTIME_DIR/active-issue-auto.txt" ]; then
    HAD_ACTIVE_ISSUE=true
    cp "$RUNTIME_DIR/active-issue-auto.txt" "$RUNTIME_DIR/active-issue-auto.txt.bak"
  fi

  echo "99 200 issue-99-test" > "$RUNTIME_DIR/active-issue-auto.txt"

  test_start "exits zero when active issue exists"
  output="$(bash "$PRECHECK" 2>&1)" && exit_code=0 || exit_code=$?
  assert_equals "exits zero" "0" "$exit_code"
  assert_contains "outputs ACTIVE_ISSUE" "$output" "ACTIVE_ISSUE"

  # Restore
  if [ "$HAD_ACTIVE_ISSUE" = true ]; then
    mv "$RUNTIME_DIR/active-issue-auto.txt.bak" "$RUNTIME_DIR/active-issue-auto.txt"
  else
    rm -f "$RUNTIME_DIR/active-issue-auto.txt"
  fi

else
  echo ""
  echo -e "${YELLOW}Skipping live tests (gh not authenticated)${RESET}"
fi

echo ""
test_summary "Pre-check Script"
