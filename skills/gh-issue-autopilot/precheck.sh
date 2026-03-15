#!/usr/bin/env bash
# Pre-check for gh-issue-autopilot scan.
# Runs before the full scan to avoid unnecessary Claude token usage.
# Exit 0 = work to do (proceed with scan), exit 1 = no work (skip scan).
#
# Checks:
# 1. If an active issue exists → work to do (need to check PR status)
# 2. If open issues with the configured label exist → work to do
# 3. Otherwise → no work
set -euo pipefail

# Compute runtime dir
REPO_ID=$(gh repo view --json url --jq '.url' | md5sum | cut -c1-12)
RUNTIME_DIR="/tmp/autopilot-${REPO_ID}"

# Check for active issue (PR monitoring needed)
if [ -f "$RUNTIME_DIR/active-issue.txt" ]; then
  echo "ACTIVE_ISSUE"
  exit 0
fi

# Read label from config
CONFIG_FILE=".claude/autopilot-config.json"
LABEL="Claude"
if [ -f "$CONFIG_FILE" ]; then
  PARSED=$(grep -o '"label"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null \
    | head -1 \
    | sed 's/.*"label"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
  if [ -n "$PARSED" ]; then
    LABEL="$PARSED"
  fi
fi

# Check for open issues with the label
COUNT=$(gh issue list --label "$LABEL" --state open --json number --jq 'length')
if [ "$COUNT" -gt 0 ]; then
  echo "ISSUES_FOUND:$COUNT"
  exit 0
fi

echo "NO_WORK"
exit 1
