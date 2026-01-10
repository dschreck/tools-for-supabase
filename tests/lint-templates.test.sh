#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_PATH="$ROOT_DIR/src/lint-templates.sh"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures"

# shellcheck source=src/lib/test-helpers.sh
source "$ROOT_DIR/src/lib/test-helpers.sh"
init_test_state "$@"

test_valid_template() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --file "$FIXTURES_DIR/valid.html"
  assert_status 0 && \
    assert_contains "No syntax errors found"
}

test_invalid_variable() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --file "$FIXTURES_DIR/invalid-variable.html"
  assert_status 1 && \
    assert_contains "Invalid template variable"
}

test_template_specific_variable() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --file "$FIXTURES_DIR/template-specific.html"
  assert_status 1 && \
    assert_contains "Template-specific variable"
}

test_warnings_non_strict() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --file "$FIXTURES_DIR/warnings.html"
  assert_status 0 && \
    assert_contains "Warnings"
}

test_warnings_strict() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --strict --file "$FIXTURES_DIR/warnings.html"
  assert_status 1 && \
    assert_contains "Warnings"
}

test_invalid_mode() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --mode nope --file "$FIXTURES_DIR/valid.html"
  assert_status 2 && \
    assert_contains "Invalid mode"
}

test_all_templates() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --templates-dir "$FIXTURES_DIR/all" --all
  assert_status 0 && \
    assert_contains "Validating template"
}

test_no_emoji_flag() {
  run_cmd bash "$SCRIPT_PATH" --no-emoji --file "$FIXTURES_DIR/valid.html"
  assert_status 0 && \
    assert_contains "INFO" && \
    assert_contains "OK" && \
    assert_not_contains "🔍" && \
    assert_not_contains "✅"
}

test_emoji_default() {
  run_cmd bash "$SCRIPT_PATH" --file "$FIXTURES_DIR/valid.html"
  assert_status 0 && \
    assert_contains "🔍" && \
    assert_contains "✅" && \
    assert_not_contains "INFO" && \
    assert_not_contains "OK"
}

run_test "valid template" test_valid_template
run_test "invalid variable" test_invalid_variable
run_test "template-specific variable" test_template_specific_variable
run_test "warnings non-strict" test_warnings_non_strict
run_test "warnings strict" test_warnings_strict
run_test "invalid mode" test_invalid_mode
run_test "--all" test_all_templates
run_test "no emoji flag" test_no_emoji_flag
run_test "emoji default" test_emoji_default

finish_tests
