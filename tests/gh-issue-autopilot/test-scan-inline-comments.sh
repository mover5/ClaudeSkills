#!/usr/bin/env bash
# Tests that SKILL.md documents inline review comment detection during scan triage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

SKILL_FILE="$REPO_ROOT/skills/gh-issue-autopilot/SKILL.md"

echo -e "${BOLD}gh-issue-autopilot: Inline Review Comment Detection${RESET}"
echo ""

# ── SKILL.md documents inline review comment fetching ─────────────

echo -e "${BOLD}SKILL.md scan triage documentation${RESET}"

SKILL_CONTENT="$(cat "$SKILL_FILE")"

test_start "documents inline review comment API endpoint"
assert_contains \
  "mentions pulls/{pr}/comments API endpoint" \
  "$SKILL_CONTENT" \
  "pulls/{pr}/comments"

test_start "documents that inline comments are separate from reviews/comments"
assert_contains \
  "notes inline comments are NOT in reviews or comments fields" \
  "$SKILL_CONTENT" \
  "NOT included in the \`reviews\` or \`comments\` fields"

test_start "documents filtering out bot's own inline comments"
assert_contains \
  "filters out Bot user type" \
  "$SKILL_CONTENT" \
  '.user.type != "Bot"'

test_start "documents filtering out own login for inline comments"
assert_contains \
  "filters out own login" \
  "$SKILL_CONTENT" \
  ".user.login"

test_start "inline comments trigger ADDRESS_REVIEWS"
assert_contains \
  "inline review comments trigger ADDRESS_REVIEWS" \
  "$SKILL_CONTENT" \
  "inline review comments"

test_start "ADDRESS_REVIEWS subagent reads inline comments"
assert_contains \
  "ADDRESS_REVIEWS prompt includes inline review comments" \
  "$SKILL_CONTENT" \
  "including inline review comments"

echo ""
test_summary "Inline Review Comment Detection"
