#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_PATH="$ROOT_DIR/src/update-email-templates.sh"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures/update"

# shellcheck source=src/lib/test-helpers.sh
source "$ROOT_DIR/src/lib/test-helpers.sh"
init_test_state "$@"

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

test_missing_env() {
  run_cmd env -i PATH="$STUB_DIR:$PATH" bash "$SCRIPT_PATH" --config "$FIXTURES_DIR/config.toml"
  assert_status 1 && \
    assert_contains "SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF"
}

test_missing_template_inputs() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=ref \
    PATH="$STUB_DIR:$PATH" bash -c "cd \"$tmp_dir\" && bash \"$SCRIPT_PATH\""
  assert_status 1 && \
    assert_contains "No complete template inputs found"
  rm -rf "$tmp_dir"
}

test_missing_dir() {
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=ref \
    PATH="$STUB_DIR:$PATH" bash "$SCRIPT_PATH" --templates-dir "$FIXTURES_DIR/missing-dir" \
    --confirmation-subject "Confirm" --recovery-subject "Recover" --magic-link-subject "Magic"
  assert_status 1 && \
    assert_contains "Templates directory not found"
}

test_missing_files() {
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=ref \
    PATH="$STUB_DIR:$PATH" bash "$SCRIPT_PATH" --templates-dir "$FIXTURES_DIR/missing" \
    --confirmation-subject "Confirm" --recovery-subject "Recover" --magic-link-subject "Magic"
  assert_status 1 && \
    assert_contains "Expected templates not found"
}

test_success() {
  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=project \
    PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash "$SCRIPT_PATH" --config "$FIXTURES_DIR/config.toml"

  assert_status 0 && \
    assert_contains "Email templates updated successfully" && \
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

  assert_status 0 && \
    assert_file_contains "${CURL_LOG_FILE}.data" "mailer_subjects_confirmation" && \
    assert_file_not_contains "${CURL_LOG_FILE}.data" "mailer_subjects_recovery" && \
    assert_file_not_contains "${CURL_LOG_FILE}.data" "mailer_subjects_magic_link"
}

test_api_failure() {
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=project \
    PATH="$STUB_DIR:$PATH" CURL_STATUS=500 CURL_BODY="{\"error\":\"nope\"}" \
    bash "$SCRIPT_PATH" --config "$FIXTURES_DIR/config.toml"

  assert_status 1 && \
    assert_contains "Failed to update templates (status 500)" && \
    assert_contains "nope"
}

test_project_ref_from_file() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  mkdir -p "$tmp_dir/.supabase"
  printf 'file-project\n' > "$tmp_dir/.supabase/project-ref"

  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash -c "cd \"$tmp_dir\" && bash \"$SCRIPT_PATH\" --config \"$FIXTURES_DIR/config.toml\""

  assert_status 0 && \
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

  assert_status 0 && \
    assert_file_contains "$CURL_LOG_FILE" "https://api.supabase.com/v1/projects/flag-project/config/auth"

  rm -rf "$tmp_dir"
}

test_no_emoji_flag() {
  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=project \
    PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash "$SCRIPT_PATH" --no-emoji --config "$FIXTURES_DIR/config.toml"

  assert_status 0 && \
    assert_contains "OK" && \
    assert_contains "INFO" && \
    assert_not_contains "✅" && \
    assert_not_contains "🔍"
}

test_emoji_default() {
  rm -f "$CURL_LOG_FILE" "${CURL_LOG_FILE}.data"
  run_cmd env SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=project \
    PATH="$STUB_DIR:$PATH" CURL_LOG_FILE="$CURL_LOG_FILE" \
    bash "$SCRIPT_PATH" --config "$FIXTURES_DIR/config.toml"

  assert_status 0 && \
    assert_contains "✅" && \
    assert_contains "🔍" && \
    assert_not_contains "OK" && \
    assert_not_contains "INFO"
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
run_test "no emoji flag" test_no_emoji_flag
run_test "emoji default" test_emoji_default

finish_tests
