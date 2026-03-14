#!/usr/bin/env bash
# Layer 1: Structural validation for all skills
# Validates that every skill directory meets required conventions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

SKILLS_DIR="$REPO_ROOT/skills"

echo -e "${BOLD}Layer 1: Skill Structure Validation${RESET}"
echo ""

# Collect all skill directories
skill_dirs=()
for dir in "$SKILLS_DIR"/*/; do
  [ -d "$dir" ] && skill_dirs+=("$dir")
done

if [ ${#skill_dirs[@]} -eq 0 ]; then
  echo "No skill directories found in $SKILLS_DIR"
  exit 1
fi

# ── Per-skill checks ──────────────────────────────────────────────

for skill_dir in "${skill_dirs[@]}"; do
  skill_name="$(basename "$skill_dir")"
  echo -e "${BOLD}Skill: $skill_name${RESET}"

  # 1. SKILL.md exists
  skill_file="$skill_dir/SKILL.md"
  test_start "$skill_name: SKILL.md exists"
  assert "SKILL.md exists" test -f "$skill_file"

  if [ ! -f "$skill_file" ]; then
    echo -e "  ${YELLOW}⚠ Skipping remaining checks (no SKILL.md)${RESET}"
    echo ""
    continue
  fi

  # 2. Has frontmatter delimiters
  first_line="$(head -1 "$skill_file")"
  test_start "$skill_name: frontmatter start"
  assert_equals "SKILL.md starts with ---" "---" "$first_line"

  # Extract frontmatter (between first and second ---)
  frontmatter="$(sed -n '1,/^---$/{ /^---$/d; p; }' "$skill_file" | tail -n +1)"
  # More robust: get everything between line 2 and next ---
  frontmatter="$(awk 'NR==1{next} /^---$/{exit} {print}' "$skill_file")"

  # 3. Required frontmatter fields
  test_start "$skill_name: name field"
  name_val="$(echo "$frontmatter" | grep -E '^name:' | head -1 | sed 's/^name:[[:space:]]*//')"
  assert "has 'name' field" test -n "$name_val"

  test_start "$skill_name: name matches directory"
  assert_equals "name matches directory name" "$skill_name" "$name_val"

  test_start "$skill_name: description field"
  desc_val="$(echo "$frontmatter" | grep -E '^description:' | head -1 | sed 's/^description:[[:space:]]*//')"
  assert "has 'description' field" test -n "$desc_val"

  # 4. Description is reasonable length (not empty, not absurdly long)
  test_start "$skill_name: description length"
  desc_len="${#desc_val}"
  assert "description length > 10 chars" test "$desc_len" -gt 10
  assert "description length < 500 chars" test "$desc_len" -lt 500

  # 5. Body content exists (something after frontmatter)
  body="$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$skill_file")"
  body_lines="$(echo "$body" | grep -c '[^[:space:]]' || true)"
  test_start "$skill_name: has body content"
  assert "SKILL.md has body content (>5 non-empty lines)" test "$body_lines" -gt 5

  echo ""
done

# ── Install/uninstall round-trip ──────────────────────────────────

echo -e "${BOLD}Install / Uninstall Round-Trip${RESET}"

# Save original state
SKILLS_DST="$HOME/.claude/skills"
original_links=()
for skill_dir in "${skill_dirs[@]}"; do
  skill_name="$(basename "$skill_dir")"
  if [ -L "$SKILLS_DST/$skill_name" ]; then
    original_links+=("$skill_name:$(readlink "$SKILLS_DST/$skill_name")")
  fi
done

# Test install
install_output="$("$REPO_ROOT/install.sh" 2>&1)"
for skill_dir in "${skill_dirs[@]}"; do
  skill_name="$(basename "$skill_dir")"
  test_start "install: $skill_name"
  assert "symlink created for $skill_name" test -L "$SKILLS_DST/$skill_name"

  if [ -L "$SKILLS_DST/$skill_name" ]; then
    link_target="$(readlink "$SKILLS_DST/$skill_name")"
    assert "symlink points to skills/$skill_name" test "$link_target" = "$SKILLS_DIR/$skill_name"
  fi
done

# Test uninstall
uninstall_output="$("$REPO_ROOT/uninstall.sh" 2>&1)"
for skill_dir in "${skill_dirs[@]}"; do
  skill_name="$(basename "$skill_dir")"
  test_start "uninstall: $skill_name"
  assert "symlink removed for $skill_name" test ! -L "$SKILLS_DST/$skill_name"
done

# Restore original symlinks
for entry in "${original_links[@]}"; do
  skill_name="${entry%%:*}"
  link_target="${entry#*:}"
  ln -sf "$link_target" "$SKILLS_DST/$skill_name"
done

# Re-install if skills were installed before (likely, since user is developing)
if [ ${#original_links[@]} -gt 0 ]; then
  "$REPO_ROOT/install.sh" >/dev/null 2>&1
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────

test_summary "Layer 1 — Structure Validation"
