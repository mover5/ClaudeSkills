#!/usr/bin/env bash
# Tests for label configuration (reading/writing autopilot-config.json)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Label Configuration${RESET}"
echo ""

# Use a temp directory to simulate a repo's .claude/ dir
TEMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TEMP_DIR/.claude"
CONFIG_FILE="$CONFIG_DIR/autopilot-config.json"
trap 'cleanup_temp "$TEMP_DIR"' EXIT

# ── Default label ─────────────────────────────────────────────────

echo -e "${BOLD}Default label when no config exists${RESET}"

test_start "no config file"
assert "config file does not exist initially" test ! -f "$CONFIG_FILE"

# Simulate reading the label (same logic the skill uses)
get_label() {
  local cfg="$1"
  if [ -f "$cfg" ]; then
    local match
    match="$(grep -o '"label"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" || true)"
    if [ -n "$match" ]; then
      echo "$match" | head -1 | sed 's/.*"label"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
    else
      echo ""
    fi
  else
    echo "Claude"
  fi
}

label="$(get_label "$CONFIG_FILE")"
assert_equals "default label is 'Claude'" "Claude" "$label"

# ── Write a label ────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Writing a custom label${RESET}"

mkdir -p "$CONFIG_DIR"
echo '{"label": "autopilot"}' > "$CONFIG_FILE"

test_start "custom label"
label="$(get_label "$CONFIG_FILE")"
assert_equals "reads custom label" "autopilot" "$label"

# ── Update label ──────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Updating an existing label${RESET}"

echo '{"label": "bot-ready"}' > "$CONFIG_FILE"

test_start "updated label"
label="$(get_label "$CONFIG_FILE")"
assert_equals "reads updated label" "bot-ready" "$label"

# ── Label with spaces ────────────────────────────────────────────

echo ""
echo -e "${BOLD}Label with spaces${RESET}"

echo '{"label": "Ready For Claude"}' > "$CONFIG_FILE"

test_start "label with spaces"
label="$(get_label "$CONFIG_FILE")"
assert_equals "reads label with spaces" "Ready For Claude" "$label"

# ── Empty config file ────────────────────────────────────────────

echo ""
echo -e "${BOLD}Empty/malformed config${RESET}"

echo '{}' > "$CONFIG_FILE"
test_start "empty config object"
label="$(get_label "$CONFIG_FILE")"
assert_equals "falls back to empty string for missing key" "" "$label"

echo ""
test_summary "Label Configuration"
