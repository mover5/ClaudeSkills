#!/usr/bin/env bash
set -euo pipefail

# ClaudeSkills installer
# Symlinks all skills from this repo into ~/.claude/skills/
# Usage: ./install.sh [skill-name]  — install one skill, or all if no argument

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If running from a git worktree, resolve to the main working tree
# so symlinks always point to the permanent repo location.
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
  MAIN_WORKTREE="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
  if [ "$MAIN_WORKTREE" != "$(git rev-parse --show-toplevel)" ]; then
    echo "Warning: running from a git worktree. Using main repo: $MAIN_WORKTREE"
    SCRIPT_DIR="$MAIN_WORKTREE"
  fi
fi

SKILLS_SRC="$SCRIPT_DIR/skills"
SKILLS_DST="$HOME/.claude/skills"

mkdir -p "$SKILLS_DST"

install_skill() {
  local skill_name="$1"
  local src="$SKILLS_SRC/$skill_name"
  local dst="$SKILLS_DST/$skill_name"

  if [ ! -d "$src" ]; then
    echo "Error: skill '$skill_name' not found in $SKILLS_SRC"
    return 1
  fi

  if [ -L "$dst" ]; then
    echo "  Updating symlink: $skill_name"
    rm "$dst"
  elif [ -d "$dst" ]; then
    echo "  Replacing existing directory: $skill_name"
    rm -rf "$dst"
  else
    echo "  Installing: $skill_name"
  fi

  ln -s "$src" "$dst"
  echo "  -> $dst -> $src"
}

if [ $# -gt 0 ]; then
  # Install specific skill(s)
  for skill in "$@"; do
    install_skill "$skill"
  done
else
  # Install all skills
  echo "Installing all skills from $SKILLS_SRC"
  echo ""
  for skill_dir in "$SKILLS_SRC"/*/; do
    skill_name="$(basename "$skill_dir")"
    install_skill "$skill_name"
  done
fi

echo ""
echo "Done. Restart Claude Code to pick up changes."
