#!/usr/bin/env bash
# Tests for install/uninstall specific to gh-issue-autopilot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

echo -e "${BOLD}gh-issue-autopilot: Install Integration${RESET}"
echo ""

SKILLS_DST="$HOME/.claude/skills"
SKILL_NAME="gh-issue-autopilot"
SKILL_SRC="$REPO_ROOT/skills/$SKILL_NAME"
SKILL_DST="$SKILLS_DST/$SKILL_NAME"

# Save original state
ORIGINAL_LINK=""
if [ -L "$SKILL_DST" ]; then
  ORIGINAL_LINK="$(readlink "$SKILL_DST")"
fi

restore_original() {
  if [ -n "$ORIGINAL_LINK" ]; then
    ln -sf "$ORIGINAL_LINK" "$SKILL_DST"
  fi
}
trap 'restore_original' EXIT

# ── Install single skill ─────────────────────────────────────────

echo -e "${BOLD}Single skill install${RESET}"

# Remove if exists
rm -f "$SKILL_DST" 2>/dev/null || true

test_start "install single skill"
output="$("$REPO_ROOT/install.sh" "$SKILL_NAME" 2>&1)"
assert "symlink created" test -L "$SKILL_DST"
assert_contains "output mentions skill name" "$output" "$SKILL_NAME"

# Verify SKILL.md is accessible through symlink
test_start "SKILL.md accessible via symlink"
assert "SKILL.md readable" test -f "$SKILL_DST/SKILL.md"

# ── Reinstall (update) ───────────────────────────────────────────

echo ""
echo -e "${BOLD}Reinstall (update)${RESET}"

test_start "reinstall overwrites cleanly"
output="$("$REPO_ROOT/install.sh" "$SKILL_NAME" 2>&1)"
assert "symlink still exists" test -L "$SKILL_DST"
assert_contains "output mentions updating" "$output" "Updating"

# ── Uninstall ─────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Uninstall${RESET}"

test_start "uninstall single skill"
output="$("$REPO_ROOT/uninstall.sh" "$SKILL_NAME" 2>&1)"
assert "symlink removed" test ! -L "$SKILL_DST"
assert_contains "output mentions removed" "$output" "Removed"

# ── Uninstall when not installed ──────────────────────────────────

echo ""
echo -e "${BOLD}Uninstall when not installed${RESET}"

test_start "uninstall missing skill"
output="$("$REPO_ROOT/uninstall.sh" "$SKILL_NAME" 2>&1)"
assert_contains "output mentions skipped" "$output" "Skipped"

echo ""
test_summary "Install Integration"
