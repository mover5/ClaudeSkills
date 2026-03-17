#!/usr/bin/env bash
# Pre-check for gh-issue-autopilot scan.
# Runs before the full scan to avoid unnecessary Claude token usage.
# Always exits 0 on success. The output string indicates the result:
#   OUTSIDE_ACTIVE_HOURS — skip scan (outside configured hours)
#   ACTIVE_ISSUE:<mode>  — work to do (PR monitoring needed)
#   ISSUES_FOUND:<count> — work to do (new issues to pick up)
#   NO_WORK              — skip scan (nothing to do)
# A non-zero exit indicates an unexpected error (e.g., gh CLI failure).
#
# Checks:
# 0. If outside configured active hours → no work (skip before any API calls)
# 1. If an active issue exists → work to do (need to check PR status)
# 2. If open issues with the configured label exist → work to do
# 3. Otherwise → no work
set -euo pipefail

# ── Active hours check (before any API calls) ──────────────────────
# Uses CURRENT_HOUR env var if set (for testing), otherwise system local time.
CONFIG_FILE=".claude/autopilot-config.json"
if [ -f "$CONFIG_FILE" ]; then
  AH_START=$(grep -o '"start"[[:space:]]*:[[:space:]]*[0-9]\+' "$CONFIG_FILE" 2>/dev/null \
    | head -1 | sed 's/.*:[[:space:]]*//' || true)
  AH_END=$(grep -o '"end"[[:space:]]*:[[:space:]]*[0-9]\+' "$CONFIG_FILE" 2>/dev/null \
    | head -1 | sed 's/.*:[[:space:]]*//' || true)

  # Only enforce if both start and end are present (activeHours is configured)
  if [ -n "$AH_START" ] && [ -n "$AH_END" ]; then
    HOUR="${CURRENT_HOUR:-$(date +%-H)}"

    if [ "$AH_START" -eq "$AH_END" ]; then
      # Zero-width window: always outside
      echo "OUTSIDE_ACTIVE_HOURS"
      exit 0
    elif [ "$AH_START" -lt "$AH_END" ]; then
      # Normal range (e.g., 9-17)
      if [ "$HOUR" -lt "$AH_START" ] || [ "$HOUR" -ge "$AH_END" ]; then
        echo "OUTSIDE_ACTIVE_HOURS"
        exit 0
      fi
    else
      # Overnight range (e.g., 22-6): active when hour >= start OR hour < end
      if [ "$HOUR" -lt "$AH_START" ] && [ "$HOUR" -ge "$AH_END" ]; then
        echo "OUTSIDE_ACTIVE_HOURS"
        exit 0
      fi
    fi
  fi
fi

# Compute runtime dir
REPO_ID=$(gh repo view --json url --jq '.url' | md5sum | cut -c1-12)
RUNTIME_DIR="/tmp/autopilot-${REPO_ID}"

# Check for active issues (PR monitoring needed)
if [ -f "$RUNTIME_DIR/active-issue-auto.txt" ]; then
  echo "ACTIVE_ISSUE:auto"
  exit 0
fi
if [ -f "$RUNTIME_DIR/active-issue-manual.txt" ]; then
  echo "ACTIVE_ISSUE:manual"
  exit 0
fi

# Read label from config (CONFIG_FILE already set above)
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
exit 0
