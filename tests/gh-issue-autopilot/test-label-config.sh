#!/usr/bin/env bash
# Tests for config (label + interval) in autopilot-config.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Config (Label + Interval)${RESET}"
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

# ══════════════════════════════════════════════════════════════════
# Interval configuration
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Interval Configuration ──${RESET}"
echo ""

# Simulate reading the interval (same logic the skill uses)
get_interval() {
  local cfg="$1"
  if [ -f "$cfg" ]; then
    local match
    match="$(grep -o '"interval"[[:space:]]*:[[:space:]]*[0-9]\+' "$cfg" || true)"
    if [ -n "$match" ]; then
      echo "$match" | head -1 | sed 's/.*"interval"[[:space:]]*:[[:space:]]*//'
    else
      echo "5"
    fi
  else
    echo "5"
  fi
}

# ── Default interval ─────────────────────────────────────────────

echo -e "${BOLD}Default interval when no config exists${RESET}"

rm -f "$CONFIG_FILE"
test_start "default interval"
interval="$(get_interval "$CONFIG_FILE")"
assert_equals "default interval is 5" "5" "$interval"

# ── Custom interval ──────────────────────────────────────────────

echo ""
echo -e "${BOLD}Custom interval${RESET}"

echo '{"label": "Claude", "interval": 15}' > "$CONFIG_FILE"
test_start "custom interval"
interval="$(get_interval "$CONFIG_FILE")"
assert_equals "reads interval 15" "15" "$interval"

# ── Interval only (no label) ─────────────────────────────────────

echo ""
echo -e "${BOLD}Interval without label${RESET}"

echo '{"interval": 30}' > "$CONFIG_FILE"
test_start "interval without label"
interval="$(get_interval "$CONFIG_FILE")"
assert_equals "reads interval 30" "30" "$interval"

# ── Missing interval falls back to default ────────────────────────

echo ""
echo -e "${BOLD}Missing interval in config${RESET}"

echo '{"label": "Claude"}' > "$CONFIG_FILE"
test_start "missing interval key"
interval="$(get_interval "$CONFIG_FILE")"
assert_equals "falls back to 5" "5" "$interval"

# ── Both fields together ─────────────────────────────────────────

echo ""
echo -e "${BOLD}Both label and interval${RESET}"

echo '{"label": "bot-ready", "interval": 10}' > "$CONFIG_FILE"
test_start "both fields"
label="$(get_label "$CONFIG_FILE")"
interval="$(get_interval "$CONFIG_FILE")"
assert_equals "label is bot-ready" "bot-ready" "$label"
assert_equals "interval is 10" "10" "$interval"

echo ""
test_summary "Config (Label + Interval)"
