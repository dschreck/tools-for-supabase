#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_PATH="$ROOT_DIR/lint-templates.sh"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures"

PASS_COUNT=0
FAIL_COUNT=0
CMD_OUTPUT=""
CMD_STATUS=0
FILTERS=("$@")

run_cmd() {
  CMD_OUTPUT=""
  CMD_STATUS=0
  set +e
  CMD_OUTPUT=$(bash "$SCRIPT_PATH" "$@" 2>&1)
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

assert_contains() {
  local needle="$1"
  local name="$2"

  if ! grep -Fq "$needle" <<< "$CMD_OUTPUT"; then
    printf 'Missing output: %s\n' "$needle"
    printf '%s\n' "$CMD_OUTPUT"
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

test_valid_template() {
  run_cmd --no-emoji --file "$FIXTURES_DIR/valid.html"
  assert_status 0 "valid template" && \
    assert_contains "No syntax errors found" "valid template"
}

test_invalid_variable() {
  run_cmd --no-emoji --file "$FIXTURES_DIR/invalid-variable.html"
  assert_status 1 "invalid variable" && \
    assert_contains "Invalid template variable" "invalid variable"
}

test_template_specific_variable() {
  run_cmd --no-emoji --file "$FIXTURES_DIR/template-specific.html"
  assert_status 1 "template-specific variable" && \
    assert_contains "Template-specific variable" "template-specific variable"
}

test_warnings_non_strict() {
  run_cmd --no-emoji --file "$FIXTURES_DIR/warnings.html"
  assert_status 0 "warnings non-strict" && \
    assert_contains "Warnings" "warnings non-strict"
}

test_warnings_strict() {
  run_cmd --no-emoji --strict --file "$FIXTURES_DIR/warnings.html"
  assert_status 1 "warnings strict" && \
    assert_contains "Warnings" "warnings strict"
}

test_invalid_mode() {
  run_cmd --no-emoji --mode nope --file "$FIXTURES_DIR/valid.html"
  assert_status 2 "invalid mode" && \
    assert_contains "Invalid mode" "invalid mode"
}

test_all_templates() {
  run_cmd --no-emoji --templates-dir "$FIXTURES_DIR/all" --all
  assert_status 0 "--all" && \
    assert_contains "Validating template" "--all"
}

run_test "valid template" test_valid_template
run_test "invalid variable" test_invalid_variable
run_test "template-specific variable" test_template_specific_variable
run_test "warnings non-strict" test_warnings_non_strict
run_test "warnings strict" test_warnings_strict
run_test "invalid mode" test_invalid_mode
run_test "--all" test_all_templates

printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
