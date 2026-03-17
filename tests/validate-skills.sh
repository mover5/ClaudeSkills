#!/usr/bin/env bash
# Layer 1: Structural validation for all plugins and their skills
# Validates that every plugin meets marketplace conventions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

PLUGINS_DIR="$REPO_ROOT/plugins"
MARKETPLACE_FILE="$REPO_ROOT/.claude-plugin/marketplace.json"

echo -e "${BOLD}Layer 1: Plugin & Skill Structure Validation${RESET}"
echo ""

# ── Marketplace validation ──────────────────────────────────────

echo -e "${BOLD}Marketplace: marketplace.json${RESET}"

test_start "marketplace.json exists"
assert "marketplace.json exists" test -f "$MARKETPLACE_FILE"

if [ ! -f "$MARKETPLACE_FILE" ]; then
  echo -e "  ${YELLOW}⚠ Skipping remaining checks (no marketplace.json)${RESET}"
  test_summary "Layer 1 — Structure Validation"
  exit $?
fi

test_start "marketplace.json is valid JSON"
assert "valid JSON" python3 -c "import json; json.load(open('$MARKETPLACE_FILE'))"

marketplace_name="$(python3 -c "import json; print(json.load(open('$MARKETPLACE_FILE'))['name'])")"
test_start "marketplace has name"
assert "has name field" test -n "$marketplace_name"

marketplace_owner="$(python3 -c "import json; print(json.load(open('$MARKETPLACE_FILE'))['owner']['name'])")"
test_start "marketplace has owner"
assert "has owner.name field" test -n "$marketplace_owner"

echo ""

# ── Plugin validation ───────────────────────────────────────────

# Collect all plugin directories
plugin_dirs=()
for dir in "$PLUGINS_DIR"/*/; do
  [ -d "$dir" ] && plugin_dirs+=("$dir")
done

if [ ${#plugin_dirs[@]} -eq 0 ]; then
  echo "No plugin directories found in $PLUGINS_DIR"
  exit 1
fi

for plugin_dir in "${plugin_dirs[@]}"; do
  plugin_name="$(basename "$plugin_dir")"
  echo -e "${BOLD}Plugin: $plugin_name${RESET}"

  # 1. plugin.json exists
  plugin_json="$plugin_dir/.claude-plugin/plugin.json"
  test_start "$plugin_name: plugin.json exists"
  assert "plugin.json exists" test -f "$plugin_json"

  if [ ! -f "$plugin_json" ]; then
    echo -e "  ${YELLOW}⚠ Skipping remaining checks (no plugin.json)${RESET}"
    echo ""
    continue
  fi

  # 2. plugin.json is valid JSON
  test_start "$plugin_name: plugin.json is valid JSON"
  assert "valid JSON" python3 -c "import json; json.load(open('$plugin_json'))"

  # 3. Required fields
  pj_name="$(python3 -c "import json; print(json.load(open('$plugin_json'))['name'])")"
  test_start "$plugin_name: name field"
  assert "has 'name' field" test -n "$pj_name"

  test_start "$plugin_name: name matches directory"
  assert_equals "name matches directory name" "$plugin_name" "$pj_name"

  pj_version="$(python3 -c "import json; print(json.load(open('$plugin_json'))['version'])")"
  test_start "$plugin_name: version field"
  assert "has 'version' field" test -n "$pj_version"

  test_start "$plugin_name: version is semver"
  assert "version matches semver pattern" test "$(echo "$pj_version" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+$')" -gt 0

  pj_desc="$(python3 -c "import json; print(json.load(open('$plugin_json'))['description'])")"
  test_start "$plugin_name: description field"
  assert "has 'description' field" test -n "$pj_desc"

  # 4. Plugin is listed in marketplace.json
  test_start "$plugin_name: listed in marketplace.json"
  assert "listed in marketplace" python3 -c "
import json
m = json.load(open('$MARKETPLACE_FILE'))
assert any(p['name'] == '$plugin_name' for p in m['plugins'])
"

  # 5. Version in marketplace.json matches plugin.json
  test_start "$plugin_name: marketplace version matches plugin.json"
  mp_version="$(python3 -c "
import json
m = json.load(open('$MARKETPLACE_FILE'))
p = next(p for p in m['plugins'] if p['name'] == '$plugin_name')
print(p.get('version', ''))
")"
  assert_equals "versions match" "$pj_version" "$mp_version"

  # 6. Validate skills within the plugin
  skills_dir="$plugin_dir/skills"
  if [ -d "$skills_dir" ]; then
    for skill_dir in "$skills_dir"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name="$(basename "$skill_dir")"
      echo ""
      echo -e "  ${BOLD}Skill: $skill_name${RESET}"

      # SKILL.md exists
      skill_file="$skill_dir/SKILL.md"
      test_start "$plugin_name/$skill_name: SKILL.md exists"
      assert "SKILL.md exists" test -f "$skill_file"

      if [ ! -f "$skill_file" ]; then
        echo -e "    ${YELLOW}⚠ Skipping remaining checks (no SKILL.md)${RESET}"
        continue
      fi

      # Has frontmatter delimiters
      first_line="$(head -1 "$skill_file")"
      test_start "$plugin_name/$skill_name: frontmatter start"
      assert_equals "SKILL.md starts with ---" "---" "$first_line"

      # Extract frontmatter
      frontmatter="$(awk 'NR==1{next} /^---$/{exit} {print}' "$skill_file")"

      # Required frontmatter fields
      test_start "$plugin_name/$skill_name: name field"
      name_val="$(echo "$frontmatter" | grep -E '^name:' | head -1 | sed 's/^name:[[:space:]]*//')"
      assert "has 'name' field" test -n "$name_val"

      test_start "$plugin_name/$skill_name: name matches directory"
      assert_equals "name matches directory name" "$skill_name" "$name_val"

      test_start "$plugin_name/$skill_name: description field"
      desc_val="$(echo "$frontmatter" | grep -E '^description:' | head -1 | sed 's/^description:[[:space:]]*//')"
      assert "has 'description' field" test -n "$desc_val"

      # Description is reasonable length
      test_start "$plugin_name/$skill_name: description length"
      desc_len="${#desc_val}"
      assert "description length > 10 chars" test "$desc_len" -gt 10
      assert "description length < 500 chars" test "$desc_len" -lt 500

      # Body content exists
      body="$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$skill_file")"
      body_lines="$(echo "$body" | grep -c '[^[:space:]]' || true)"
      test_start "$plugin_name/$skill_name: has body content"
      assert "SKILL.md has body content (>5 non-empty lines)" test "$body_lines" -gt 5
    done
  fi

  echo ""
done

# ── Summary ───────────────────────────────────────────────────────

test_summary "Layer 1 — Structure Validation"
