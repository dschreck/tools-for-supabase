#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_PATH="$ROOT_DIR/src/update-email-templates.sh"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures/update"

PASS_COUNT=0
FAIL_COUNT=0
CMD_OUTPUT=""
CMD_STATUS=0
FILTERS=("$@")

STUB_DIR=$(mktemp -d)
CURL_LOG_FILE="$STUB_DIR/curl.log"

cleanup() {
  rm -rf "$STUB_DIR"
}
trap cleanup EXIT

cat <<'STUB_EOF' > "$STUB_DIR/curl"
#!/usr/bin/env bash
set -euo pipefail

log_file="${CURL_LOG_FILE:-}"
if [[ -n "$log_file" ]]; then
  printf '%s\n' "$*" >> "$log_file"
  args=("$@")
  for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "--data" ]]; then
      payload="${args[$((i + 1))]}"
      printf '%s' "$payload" > "${log_file}.data"
      break
    fi
  done
fi

status="${CURL_STATUS:-200}"
body="${CURL_BODY:-{\"ok\":true}}"

printf '%s\n' "$body"
printf '%s' "$status"
STUB_EOF
chmod +x "$STUB_DIR/curl"

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

test_missing_env() {
  run_cmd env -i PATH="$STUB_DIR:$PATH" bash "$SCRIPT_PATH" --config "$FIXTURES_DIR/config.toml"
  assert_status 1 "missing env" && \
    assert_contains "SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF" "missing env"
}

test_missing_template_inputs() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=ref \
    PATH="$STUB_DIR:$PATH" bash -c "cd \"$tmp_dir\" && bash \"$SCRIPT_PATH\""
  assert_status 1 "missing template inputs" && \
    assert_contains "No complete template inputs found" "missing template inputs"
  rm -rf "$tmp_dir"
}

test_missing_dir() {
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=ref \
    PATH="$STUB_DIR:$PATH" bash "$SCRIPT_PATH" --templates-dir "$FIXTURES_DIR/missing-dir" \
    --confirmation-subject "Confirm" --recovery-subject "Recover" --magic-link-subject "Magic"
  assert_status 1 "missing dir" && \
    assert_contains "Templates directory not found" "missing dir"
}

test_missing_files() {
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=ref \
    PATH="$STUB_DIR:$PATH" bash "$SCRIPT_PATH" --templates-dir "$FIXTURES_DIR/missing" \
    --confirmation-subject "Confirm" --recovery-subject "Recover" --magic-link-subject "Magic"
  assert_status 1 "missing files" && \
    assert_contains "Expected templates not found" "missing files"
}

test_success() {
  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=project \
    PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash "$SCRIPT_PATH" --config "$FIXTURES_DIR/config.toml"

  assert_status 0 "success" && \
    assert_contains "Email templates updated successfully" "success" && \
    assert_file_contains "$CURL_LOG_FILE" "https://api.supabase.com/v1/projects/project/config/auth" && \
    assert_file_contains "${CURL_LOG_FILE}.data" "mailer_subjects_confirmation" && \
    assert_file_contains "${CURL_LOG_FILE}.data" "Confirm your account"
}

test_partial_update() {
  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=project \
    PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash "$SCRIPT_PATH" \
    --confirmation-subject "Confirm" \
    --confirmation-template "$FIXTURES_DIR/confirmation.html"

  assert_status 0 "partial update" && \
    assert_file_contains "${CURL_LOG_FILE}.data" "mailer_subjects_confirmation" && \
    assert_file_not_contains "${CURL_LOG_FILE}.data" "mailer_subjects_recovery" && \
    assert_file_not_contains "${CURL_LOG_FILE}.data" "mailer_subjects_magic_link"
}

test_api_failure() {
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=project \
    PATH="$STUB_DIR:$PATH" CURL_STATUS=500 CURL_BODY="{\"error\":\"nope\"}" \
    bash "$SCRIPT_PATH" --config "$FIXTURES_DIR/config.toml"

  assert_status 1 "api failure" && \
    assert_contains "Failed to update templates (status 500)" "api failure" && \
    assert_contains "nope" "api failure"
}

test_project_ref_from_file() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  mkdir -p "$tmp_dir/.supabase"
  printf 'file-project\n' > "$tmp_dir/.supabase/project-ref"

  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash -c "cd \"$tmp_dir\" && bash \"$SCRIPT_PATH\" --config \"$FIXTURES_DIR/config.toml\""

  assert_status 0 "project ref from file" && \
    assert_file_contains "$CURL_LOG_FILE" "https://api.supabase.com/v1/projects/file-project/config/auth"

  rm -rf "$tmp_dir"
}

test_project_ref_flag_overrides_file() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  mkdir -p "$tmp_dir/.supabase"
  printf 'file-project\n' > "$tmp_dir/.supabase/project-ref"

  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash -c "cd \"$tmp_dir\" && bash \"$SCRIPT_PATH\" --config \"$FIXTURES_DIR/config.toml\" --project-ref flag-project"

  assert_status 0 "project ref flag overrides file" && \
    assert_file_contains "$CURL_LOG_FILE" "https://api.supabase.com/v1/projects/flag-project/config/auth"

  rm -rf "$tmp_dir"
}

run_test "missing env" test_missing_env
run_test "missing template inputs" test_missing_template_inputs
run_test "missing dir" test_missing_dir
run_test "missing files" test_missing_files
run_test "success" test_success
run_test "partial update" test_partial_update
run_test "api failure" test_api_failure
run_test "project ref from file" test_project_ref_from_file
run_test "project ref flag overrides file" test_project_ref_flag_overrides_file

printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
