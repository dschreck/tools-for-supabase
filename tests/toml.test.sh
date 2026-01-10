#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_FILE="$ROOT_DIR/tests/fixtures/toml/sample.toml"

# shellcheck source=src/lib/test-helpers.sh
source "$ROOT_DIR/src/lib/test-helpers.sh"
init_test_state "$@"

# shellcheck source=src/lib/toml.sh
source "$ROOT_DIR/src/lib/toml.sh"

test_section_key() {
  run_cmd toml_get "$FIXTURE_FILE" "auth.email.template.confirmation" "subject"
  assert_status 0 && \
    assert_equals "Confirm your account"
}

test_dotted_key() {
  run_cmd toml_get "$FIXTURE_FILE" "auth.email.template.recovery" "content_path"
  assert_status 0 && \
    assert_equals "./recovery.html"
}

test_comment_strip() {
  run_cmd toml_get "$FIXTURE_FILE" "auth.email.template.magic_link" "subject"
  assert_status 0 && \
    assert_equals "Magic link sign-in"
}

test_missing_key() {
  run_cmd toml_get "$FIXTURE_FILE" "auth.email.template.magic_link" "missing"
  assert_status 0 && \
    assert_empty
}

run_test "section key" test_section_key
run_test "dotted key" test_dotted_key
run_test "comment strip" test_comment_strip
run_test "missing key" test_missing_key

finish_tests
