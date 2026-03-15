#!/usr/bin/env bash
# Tests for issue conventions configuration in autopilot-config.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Issue Conventions${RESET}"
echo ""

# Use a temp directory to simulate a repo's .claude/ dir
TEMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TEMP_DIR/.claude"
CONFIG_FILE="$CONFIG_DIR/autopilot-config.json"
trap 'cleanup_temp "$TEMP_DIR"' EXIT

# ══════════════════════════════════════════════════════════════════
# Helper functions (mirror the logic the skill would use)
# ══════════════════════════════════════════════════════════════════

# Get the number of label rules configured
get_label_rules_count() {
  local cfg="$1"
  if [ -f "$cfg" ]; then
    # Extract labelRules array and count entries by counting "label" keys
    local count
    count="$(grep -o '"label"[[:space:]]*:' "$cfg" 2>/dev/null | wc -l || echo 0)"
    # Subtract 1 for the top-level "label" key if it exists
    local has_top_label
    has_top_label="$(grep -c '"label"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" 2>/dev/null || echo 0)"
    # The top-level label has a string value, labelRules labels also have string values
    # We need a better approach: count entries inside labelRules array
    # Use python-free approach: count occurrences of "action" inside the file
    # since only rule objects have "action" fields
    # But title rules also have action. So count all actions.
    # Better: parse with grep for label rules specifically
    echo "$count"
  else
    echo "0"
  fi
}

# Read label rules as lines of "label|action|instructions"
get_label_rules() {
  local cfg="$1"
  if [ ! -f "$cfg" ]; then
    return
  fi
  # Simple extraction: find labelRules entries
  # Each rule has label, action, instructions
  # Use a state machine approach with grep
  local in_label_rules=false
  local brace_depth=0
  local current_label="" current_action="" current_instructions=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '"labelRules"'; then
      in_label_rules=true
      continue
    fi
    if [ "$in_label_rules" = true ]; then
      # Check for end of labelRules array
      if echo "$line" | grep -q '^\s*\]'; then
        in_label_rules=false
        continue
      fi
      # Extract fields
      local label_match action_match instr_match
      label_match="$(echo "$line" | grep -o '"label"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"label"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
      action_match="$(echo "$line" | grep -o '"action"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"action"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
      instr_match="$(echo "$line" | grep -o '"instructions"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"instructions"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"

      [ -n "$label_match" ] && current_label="$label_match"
      [ -n "$action_match" ] && current_action="$action_match"
      [ -n "$instr_match" ] && current_instructions="$instr_match"

      # If we have all three, output and reset
      if [ -n "$current_label" ] && [ -n "$current_action" ] && [ -n "$current_instructions" ]; then
        echo "${current_label}|${current_action}|${current_instructions}"
        current_label="" current_action="" current_instructions=""
      fi
    fi
  done < "$cfg"
}

# Read title rules as lines of "pattern<TAB>action<TAB>instructions"
# Uses TAB as delimiter since patterns may contain pipe characters
get_title_rules() {
  local cfg="$1"
  if [ ! -f "$cfg" ]; then
    return
  fi
  local in_title_rules=false
  local current_pattern="" current_action="" current_instructions=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '"titleRules"'; then
      in_title_rules=true
      continue
    fi
    if [ "$in_title_rules" = true ]; then
      if echo "$line" | grep -q '^\s*\]'; then
        in_title_rules=false
        continue
      fi
      local pattern_match action_match instr_match
      pattern_match="$(echo "$line" | grep -o '"pattern"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"pattern"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
      action_match="$(echo "$line" | grep -o '"action"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"action"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
      instr_match="$(echo "$line" | grep -o '"instructions"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"instructions"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"

      [ -n "$pattern_match" ] && current_pattern="$pattern_match"
      [ -n "$action_match" ] && current_action="$action_match"
      [ -n "$instr_match" ] && current_instructions="$instr_match"

      if [ -n "$current_pattern" ] && [ -n "$current_action" ] && [ -n "$current_instructions" ]; then
        printf '%s\t%s\t%s\n' "$current_pattern" "$current_action" "$current_instructions"
        current_pattern="" current_action="" current_instructions=""
      fi
    fi
  done < "$cfg"
}

# Check if issueConventions exists in config
has_issue_conventions() {
  local cfg="$1"
  if [ -f "$cfg" ] && grep -q '"issueConventions"' "$cfg" 2>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

# Match label rules against an issue's labels (case-insensitive)
# Args: config_file label1 label2 ...
match_label_rules() {
  local cfg="$1"
  shift
  local issue_labels=("$@")
  local rules
  rules="$(get_label_rules "$cfg")"

  while IFS='|' read -r rule_label rule_action rule_instructions; do
    [ -z "$rule_label" ] && continue
    local lower_rule_label
    lower_rule_label="$(echo "$rule_label" | tr '[:upper:]' '[:lower:]')"
    for issue_label in "${issue_labels[@]}"; do
      local lower_issue_label
      lower_issue_label="$(echo "$issue_label" | tr '[:upper:]' '[:lower:]')"
      if [ "$lower_rule_label" = "$lower_issue_label" ]; then
        echo "${rule_action}|${rule_instructions}"
      fi
    done
  done <<< "$rules"
}

# Match title rules against an issue title
# Args: config_file "issue title"
match_title_rules() {
  local cfg="$1"
  local title="$2"
  local rules
  rules="$(get_title_rules "$cfg")"

  while IFS=$'\t' read -r rule_pattern rule_action rule_instructions; do
    [ -z "$rule_pattern" ] && continue
    # Unescape JSON double-backslashes to single backslashes for regex
    local unescaped_pattern
    unescaped_pattern="$(echo "$rule_pattern" | sed 's/\\\\/\\/g')"
    if echo "$title" | grep -qE "$unescaped_pattern"; then
      echo "${rule_action}|${rule_instructions}"
    fi
  done <<< "$rules"
}

# ══════════════════════════════════════════════════════════════════
# Tests: No config / empty config
# ══════════════════════════════════════════════════════════════════

echo -e "${BOLD}── No Config File ──${RESET}"
echo ""

test_start "no config file"
assert_equals "no config means no conventions" "false" "$(has_issue_conventions "$CONFIG_FILE")"

rules="$(get_label_rules "$CONFIG_FILE")"
assert_equals "no label rules from missing config" "" "$rules"

rules="$(get_title_rules "$CONFIG_FILE")"
assert_equals "no title rules from missing config" "" "$rules"

echo ""
echo -e "${BOLD}── Empty Config ──${RESET}"
echo ""

mkdir -p "$CONFIG_DIR"
echo '{"label": "Claude"}' > "$CONFIG_FILE"

test_start "config without issueConventions"
assert_equals "no conventions in basic config" "false" "$(has_issue_conventions "$CONFIG_FILE")"

# ══════════════════════════════════════════════════════════════════
# Tests: Config with label rules
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Label Rules ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "Claude",
  "issueConventions": {
    "labelRules": [
      {
        "label": "security",
        "action": "extra-scrutiny",
        "instructions": "Require thorough security review."
      },
      {
        "label": "gh-issue-autopilot",
        "action": "scope",
        "instructions": "Scope work to skills/gh-issue-autopilot/ directory."
      }
    ],
    "titleRules": []
  }
}
JSONEOF

test_start "has issue conventions"
assert_equals "conventions present" "true" "$(has_issue_conventions "$CONFIG_FILE")"

test_start "reads label rules"
rules="$(get_label_rules "$CONFIG_FILE")"
line_count="$(echo "$rules" | grep -c '.' || true)"
assert_equals "two label rules found" "2" "$line_count"

test_start "first label rule content"
first_rule="$(echo "$rules" | head -1)"
assert_contains "first rule has security label" "$first_rule" "security"
assert_contains "first rule has extra-scrutiny action" "$first_rule" "extra-scrutiny"
assert_contains "first rule has instructions" "$first_rule" "security review"

test_start "second label rule content"
second_rule="$(echo "$rules" | tail -1)"
assert_contains "second rule has autopilot label" "$second_rule" "gh-issue-autopilot"
assert_contains "second rule has scope action" "$second_rule" "scope"

# ══════════════════════════════════════════════════════════════════
# Tests: Config with title rules
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Title Rules ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "Claude",
  "issueConventions": {
    "labelRules": [],
    "titleRules": [
      {
        "pattern": "^\\[URGENT\\]",
        "action": "priority",
        "instructions": "Treat as high priority."
      },
      {
        "pattern": "^\\[RFC\\]",
        "action": "custom",
        "instructions": "This is a request for comments, not a direct implementation task."
      }
    ]
  }
}
JSONEOF

test_start "reads title rules"
rules="$(get_title_rules "$CONFIG_FILE")"
line_count="$(echo "$rules" | grep -c '.' || true)"
assert_equals "two title rules found" "2" "$line_count"

test_start "first title rule content"
first_rule="$(echo "$rules" | head -1)"
assert_contains "first rule has URGENT pattern" "$first_rule" "URGENT"
assert_contains "first rule has priority action" "$first_rule" "priority"

test_start "second title rule content"
second_rule="$(echo "$rules" | tail -1)"
assert_contains "second rule has RFC pattern" "$second_rule" "RFC"
assert_contains "second rule has custom action" "$second_rule" "custom"

# ══════════════════════════════════════════════════════════════════
# Tests: Label matching (case-insensitive)
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Label Matching ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "Claude",
  "issueConventions": {
    "labelRules": [
      {
        "label": "Security",
        "action": "extra-scrutiny",
        "instructions": "Check for vulnerabilities."
      },
      {
        "label": "gh-issue-autopilot",
        "action": "scope",
        "instructions": "Scope to autopilot skill."
      }
    ],
    "titleRules": []
  }
}
JSONEOF

test_start "exact label match"
matches="$(match_label_rules "$CONFIG_FILE" "Security")"
assert_contains "matches Security label" "$matches" "extra-scrutiny"

test_start "case-insensitive label match"
matches="$(match_label_rules "$CONFIG_FILE" "security")"
assert_contains "matches security (lowercase)" "$matches" "extra-scrutiny"

test_start "no match for unrelated label"
matches="$(match_label_rules "$CONFIG_FILE" "bug")"
assert_equals "no match for bug label" "" "$matches"

test_start "multiple labels, one matches"
matches="$(match_label_rules "$CONFIG_FILE" "bug" "security" "enhancement")"
match_count="$(echo "$matches" | grep -c '.' || true)"
assert_equals "one match from multiple labels" "1" "$match_count"

test_start "multiple labels, multiple matches"
matches="$(match_label_rules "$CONFIG_FILE" "security" "gh-issue-autopilot")"
match_count="$(echo "$matches" | grep -c '.' || true)"
assert_equals "two matches from matching labels" "2" "$match_count"

# ══════════════════════════════════════════════════════════════════
# Tests: Title matching
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Title Matching ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "Claude",
  "issueConventions": {
    "labelRules": [],
    "titleRules": [
      {
        "pattern": "^\\[URGENT\\]",
        "action": "priority",
        "instructions": "High priority issue."
      },
      {
        "pattern": "security|vulnerability",
        "action": "extra-scrutiny",
        "instructions": "Security-related title."
      }
    ]
  }
}
JSONEOF

test_start "title matches URGENT pattern"
matches="$(match_title_rules "$CONFIG_FILE" "[URGENT] Fix login crash")"
assert_contains "matches URGENT prefix" "$matches" "priority"

test_start "title does not match URGENT in middle"
matches="$(match_title_rules "$CONFIG_FILE" "Fix URGENT login crash")"
# The pattern is ^\\[URGENT\\], so URGENT in the middle should NOT match
# But the second rule might match if "security" appears
assert_not_contains "no priority match for non-prefix" "$matches" "priority"

test_start "title matches security keyword"
matches="$(match_title_rules "$CONFIG_FILE" "Fix security vulnerability in auth")"
assert_contains "matches security keyword" "$matches" "extra-scrutiny"

test_start "title matches vulnerability keyword"
matches="$(match_title_rules "$CONFIG_FILE" "Patch vulnerability in API")"
assert_contains "matches vulnerability keyword" "$matches" "extra-scrutiny"

test_start "title with no matching pattern"
matches="$(match_title_rules "$CONFIG_FILE" "Add new feature for dashboard")"
assert_equals "no matches for unrelated title" "" "$matches"

# ══════════════════════════════════════════════════════════════════
# Tests: Combined label + title rules
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Combined Rules ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "Claude",
  "issueConventions": {
    "labelRules": [
      {
        "label": "gh-issue-autopilot",
        "action": "scope",
        "instructions": "Scope to autopilot."
      }
    ],
    "titleRules": [
      {
        "pattern": "^\\[URGENT\\]",
        "action": "priority",
        "instructions": "High priority."
      }
    ]
  }
}
JSONEOF

test_start "both label and title match"
label_matches="$(match_label_rules "$CONFIG_FILE" "gh-issue-autopilot")"
title_matches="$(match_title_rules "$CONFIG_FILE" "[URGENT] Fix autopilot bug")"
assert_contains "label rule matches" "$label_matches" "scope"
assert_contains "title rule matches" "$title_matches" "priority"

# Combine instructions (as the skill would do)
all_instructions=""
while IFS='|' read -r action instructions; do
  [ -n "$instructions" ] && all_instructions="${all_instructions}${instructions} "
done <<< "$label_matches"
while IFS='|' read -r action instructions; do
  [ -n "$instructions" ] && all_instructions="${all_instructions}${instructions} "
done <<< "$title_matches"

test_start "combined instructions"
assert_contains "combined has scope instruction" "$all_instructions" "Scope to autopilot"
assert_contains "combined has priority instruction" "$all_instructions" "High priority"

# ══════════════════════════════════════════════════════════════════
# Tests: Empty issueConventions
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Empty Issue Conventions ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "Claude",
  "issueConventions": {
    "labelRules": [],
    "titleRules": []
  }
}
JSONEOF

test_start "empty conventions"
assert_equals "conventions present but empty" "true" "$(has_issue_conventions "$CONFIG_FILE")"

rules="$(get_label_rules "$CONFIG_FILE")"
assert_equals "no label rules" "" "$rules"

rules="$(get_title_rules "$CONFIG_FILE")"
assert_equals "no title rules" "" "$rules"

# ══════════════════════════════════════════════════════════════════
# Tests: Config with only issueConventions (no other fields affected)
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Conventions alongside other config ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "bot-ready",
  "interval": 10,
  "model": "sonnet",
  "activeHours": {"start": 9, "end": 17},
  "issueConventions": {
    "labelRules": [
      {
        "label": "frontend",
        "action": "scope",
        "instructions": "Scope to src/frontend/ directory."
      }
    ],
    "titleRules": [
      {
        "pattern": "^\\[WIP\\]",
        "action": "custom",
        "instructions": "Skip this issue, it is work in progress."
      }
    ]
  }
}
JSONEOF

test_start "conventions alongside other config"
# Verify other config fields are unaffected
label="$(grep -o '"label"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -1 | sed 's/.*"label"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
assert_equals "label field intact" "bot-ready" "$label"

interval="$(grep -o '"interval"[[:space:]]*:[[:space:]]*[0-9]\+' "$CONFIG_FILE" | head -1 | sed 's/.*"interval"[[:space:]]*:[[:space:]]*//')"
assert_equals "interval field intact" "10" "$interval"

# And conventions still work
assert_equals "conventions still present" "true" "$(has_issue_conventions "$CONFIG_FILE")"
label_rules="$(get_label_rules "$CONFIG_FILE")"
assert_contains "frontend rule present" "$label_rules" "frontend"

title_rules="$(get_title_rules "$CONFIG_FILE")"
assert_contains "WIP rule present" "$title_rules" "WIP"

# ══════════════════════════════════════════════════════════════════
# Tests: Action types
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}── Action Types ──${RESET}"
echo ""

cat > "$CONFIG_FILE" << 'JSONEOF'
{
  "label": "Claude",
  "issueConventions": {
    "labelRules": [
      {
        "label": "scope-test",
        "action": "scope",
        "instructions": "Scope instructions."
      },
      {
        "label": "scrutiny-test",
        "action": "extra-scrutiny",
        "instructions": "Scrutiny instructions."
      },
      {
        "label": "priority-test",
        "action": "priority",
        "instructions": "Priority instructions."
      },
      {
        "label": "custom-test",
        "action": "custom",
        "instructions": "Custom instructions."
      }
    ],
    "titleRules": []
  }
}
JSONEOF

test_start "scope action"
matches="$(match_label_rules "$CONFIG_FILE" "scope-test")"
assert_contains "scope action found" "$matches" "scope"

test_start "extra-scrutiny action"
matches="$(match_label_rules "$CONFIG_FILE" "scrutiny-test")"
assert_contains "extra-scrutiny action found" "$matches" "extra-scrutiny"

test_start "priority action"
matches="$(match_label_rules "$CONFIG_FILE" "priority-test")"
assert_contains "priority action found" "$matches" "priority"

test_start "custom action"
matches="$(match_label_rules "$CONFIG_FILE" "custom-test")"
assert_contains "custom action found" "$matches" "custom"

echo ""
test_summary "Issue Conventions"
