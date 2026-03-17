#!/usr/bin/env bash
# Shared test helpers

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
PLUGINS_DIR="$REPO_ROOT/plugins"

# Counters
_PASS=0
_FAIL=0
_TOTAL=0
_CURRENT_TEST=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# Start a named test
test_start() {
  _CURRENT_TEST="$1"
  _TOTAL=$((_TOTAL + 1))
}

# Assert a condition is true
assert() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    _PASS=$((_PASS + 1))
    echo -e "  ${GREEN}✓${RESET} $description"
  else
    _FAIL=$((_FAIL + 1))
    echo -e "  ${RED}✗${RESET} $description"
  fi
}

# Assert a string contains a substring
assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _PASS=$((_PASS + 1))
    echo -e "  ${GREEN}✓${RESET} $description"
  else
    _FAIL=$((_FAIL + 1))
    echo -e "  ${RED}✗${RESET} $description — expected to contain: '$needle'"
  fi
}

# Assert a string does NOT contain a substring
assert_not_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    _PASS=$((_PASS + 1))
    echo -e "  ${GREEN}✓${RESET} $description"
  else
    _FAIL=$((_FAIL + 1))
    echo -e "  ${RED}✗${RESET} $description — expected NOT to contain: '$needle'"
  fi
}

# Assert two values are equal
assert_equals() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    _PASS=$((_PASS + 1))
    echo -e "  ${GREEN}✓${RESET} $description"
  else
    _FAIL=$((_FAIL + 1))
    echo -e "  ${RED}✗${RESET} $description — expected: '$expected', got: '$actual'"
  fi
}

# Assert a file exists
assert_file_exists() {
  local description="$1"
  local filepath="$2"
  if [ -e "$filepath" ]; then
    _PASS=$((_PASS + 1))
    echo -e "  ${GREEN}✓${RESET} $description"
  else
    _FAIL=$((_FAIL + 1))
    echo -e "  ${RED}✗${RESET} $description — file not found: $filepath"
  fi
}

# Assert a file does not exist
assert_file_not_exists() {
  local description="$1"
  local filepath="$2"
  if [ ! -e "$filepath" ]; then
    _PASS=$((_PASS + 1))
    echo -e "  ${GREEN}✓${RESET} $description"
  else
    _FAIL=$((_FAIL + 1))
    echo -e "  ${RED}✗${RESET} $description — file should not exist: $filepath"
  fi
}

# Print test suite summary and return exit code
test_summary() {
  local suite_name="${1:-Tests}"
  echo ""
  if [ "$_FAIL" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}$suite_name: All $_PASS assertions passed${RESET}"
  else
    echo -e "${RED}${BOLD}$suite_name: $_FAIL failed, $_PASS passed${RESET}"
  fi
  return "$_FAIL"
}

# Create a temporary git repo for testing
create_temp_repo() {
  local tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -b main --quiet
  git -C "$tmp" config user.email "test@test.com"
  git -C "$tmp" config user.name "Test"
  echo "test" > "$tmp/README.md"
  git -C "$tmp" add . && git -C "$tmp" commit -m "init" --quiet
  echo "$tmp"
}

# Clean up a temp directory
cleanup_temp() {
  if [ -n "${1:-}" ] && [ -d "$1" ]; then
    rm -rf "$1"
  fi
}

# Create a mock gh binary directory with a configurable mock
# Usage: MOCK_DIR=$(create_gh_mock); export PATH="$MOCK_DIR:$PATH"
# Then write responses: echo '{"key":"val"}' > "$MOCK_DIR/gh-responses/repo-view"
create_gh_mock() {
  local mock_dir
  mock_dir="$(mktemp -d)"
  local responses_dir="$mock_dir/gh-responses"
  mkdir -p "$responses_dir"

  cat > "$mock_dir/gh" << 'GHEOF'
#!/usr/bin/env bash
# Mock gh CLI — reads canned responses from $GH_MOCK_RESPONSES_DIR
RESPONSES_DIR="${GH_MOCK_RESPONSES_DIR:-}"
if [ -z "$RESPONSES_DIR" ]; then
  echo "error: GH_MOCK_RESPONSES_DIR not set" >&2
  exit 1
fi

# Build a response key from the command args
# e.g., "gh repo view --json name" -> "repo-view"
# e.g., "gh issue list --label Claude" -> "issue-list"
key="${1:-unknown}-${2:-unknown}"
response_file="$RESPONSES_DIR/$key"

if [ -f "$response_file" ]; then
  cat "$response_file"
else
  echo "mock gh: no response for '$key' (looked for $response_file)" >&2
  exit 1
fi
GHEOF
  chmod +x "$mock_dir/gh"

  echo "$mock_dir"
}
