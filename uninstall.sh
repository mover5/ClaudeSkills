#!/usr/bin/env bash
set -euo pipefail

# ClaudeSkills uninstaller
# Removes symlinks from ~/.claude/skills/ that point to this repo
# Usage: ./uninstall.sh [skill-name]  — uninstall one skill, or all if no argument

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
SKILLS_DST="$HOME/.claude/skills"

uninstall_skill() {
  local skill_name="$1"
  local dst="$SKILLS_DST/$skill_name"

  if [ -L "$dst" ]; then
    local target
    target="$(readlink "$dst")"
    if [[ "$target" == "$SKILLS_SRC"* ]]; then
      rm "$dst"
      echo "  Removed: $skill_name"
    else
      echo "  Skipped: $skill_name (symlink points elsewhere: $target)"
    fi
  elif [ -d "$dst" ]; then
    echo "  Skipped: $skill_name (not a symlink — remove manually if intended)"
  else
    echo "  Skipped: $skill_name (not installed)"
  fi
}

if [ $# -gt 0 ]; then
  for skill in "$@"; do
    uninstall_skill "$skill"
  done
else
  echo "Uninstalling all skills managed by this repo"
  echo ""
  for skill_dir in "$SKILLS_SRC"/*/; do
    skill_name="$(basename "$skill_dir")"
    uninstall_skill "$skill_name"
  done
fi

echo ""
echo "Done."
