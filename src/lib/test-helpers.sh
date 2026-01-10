#!/usr/bin/env bash
#
# Test helpers for shell scripts.
#
# Licensed under the MIT License. Copyright (c) 2026 David Schreck 
# https://github.com/dschreck/tools-for-supabase
# 

init_test_state() {
  PASS_COUNT=0
  FAIL_COUNT=0
  CMD_OUTPUT=""
  CMD_STATUS=0
  FILTERS=("$@")
}

run_cmd() {
  CMD_OUTPUT=""
  CMD_STATUS=0
  set +e
  CMD_OUTPUT=$("$@" 2>&1)
  CMD_STATUS=$?
  set -e
}

assert_status() {
  local expected="$1"

  if [[ "$CMD_STATUS" -ne "$expected" ]]; then
    printf 'Expected exit %s, got %s\n' "$expected" "$CMD_STATUS"
    printf '%s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

assert_contains() {
  local needle="$1"

  if ! grep -Fq "$needle" <<< "$CMD_OUTPUT"; then
    printf 'Missing output: %s\n' "$needle"
    printf '%s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

assert_not_contains() {
  local needle="$1"

  if grep -Fq "$needle" <<< "$CMD_OUTPUT"; then
    printf 'Unexpected output: %s\n' "$needle"
    printf '%s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

assert_equals() {
  local expected="$1"

  if [[ "$CMD_OUTPUT" != "$expected" ]]; then
    printf 'Expected output: %s\n' "$expected"
    printf 'Actual output: %s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

assert_empty() {
  if [[ -n "$CMD_OUTPUT" ]]; then
    printf 'Expected empty output, got: %s\n' "$CMD_OUTPUT"
    return 1
  fi

  return 0
}

assert_file_contains() {
  local file="$1"
  local needle="$2"

  if [[ ! -f "$file" ]]; then
    printf 'Missing file: %s\n' "$file"
    return 1
  fi

  if ! grep -Fq "$needle" "$file"; then
    printf 'Missing in %s: %s\n' "$file" "$needle"
    printf '%s\n' "$(cat "$file")"
    return 1
  fi

  return 0
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"

  if [[ ! -f "$file" ]]; then
    printf 'Missing file: %s\n' "$file"
    return 1
  fi

  if grep -Fq "$needle" "$file"; then
    printf 'Unexpected in %s: %s\n' "$file" "$needle"
    printf '%s\n' "$(cat "$file")"
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

finish_tests() {
  printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    exit 1
  fi
}
