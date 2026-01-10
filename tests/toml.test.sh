#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_FILE="$ROOT_DIR/tests/fixtures/toml/sample.toml"

PASS_COUNT=0
FAIL_COUNT=0
CMD_OUTPUT=""
CMD_STATUS=0
FILTERS=("$@")

# shellcheck source=src/lib/toml.sh
source "$ROOT_DIR/src/lib/toml.sh"

run_cmd() {
  CMD_OUTPUT=""
  CMD_STATUS=0
  set +e
  CMD_OUTPUT="$(toml_get "$@")"
  CMD_STATUS=$?
  set -e
}

assert_status() {
  local expected="$1"
  local name="$2"

  if [[ "$CMD_STATUS" -ne "$expected" ]]; then
    printf 'Expected exit %s, got %s\n' "$expected" "$CMD_STATUS"
    printf '%s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

assert_equals() {
  local expected="$1"
  local name="$2"

  if [[ "$CMD_OUTPUT" != "$expected" ]]; then
    printf 'Expected output: %s\n' "$expected"
    printf 'Actual output: %s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

assert_empty() {
  local name="$1"

  if [[ -n "$CMD_OUTPUT" ]]; then
    printf 'Expected empty output, got: %s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

run_test() {
  local name="$1"
  shift

  if [[ ${#FILTERS[@]} -gt 0 ]]; then
    local filter
    local matches=false
    for filter in "${FILTERS[@]}"; do
      if [[ "$name" == *"$filter"* ]]; then
        matches=true
        break
      fi
    done

    if [[ "$matches" == "false" ]]; then
      printf 'skip - %s\n' "$name"
      return 0
    fi
  fi

  if "$@"; then
    printf 'ok - %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'not ok - %s\n' "$name"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

test_section_key() {
  run_cmd "$FIXTURE_FILE" "auth.email.template.confirmation" "subject"
  assert_status 0 "section key" && \
    assert_equals "Confirm your account" "section key"
}

test_dotted_key() {
  run_cmd "$FIXTURE_FILE" "auth.email.template.recovery" "content_path"
  assert_status 0 "dotted key" && \
    assert_equals "./recovery.html" "dotted key"
}

test_comment_strip() {
  run_cmd "$FIXTURE_FILE" "auth.email.template.magic_link" "subject"
  assert_status 0 "comment strip" && \
    assert_equals "Magic link sign-in" "comment strip"
}

test_missing_key() {
  run_cmd "$FIXTURE_FILE" "auth.email.template.magic_link" "missing"
  assert_status 0 "missing key" && \
    assert_empty "missing key"
}

run_test "section key" test_section_key
run_test "dotted key" test_dotted_key
run_test "comment strip" test_comment_strip
run_test "missing key" test_missing_key

printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
