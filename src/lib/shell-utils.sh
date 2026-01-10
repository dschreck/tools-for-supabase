#!/usr/bin/env bash
#
# Shared shell helpers.
#
# Licensed under the MIT License. Copyright (c) 2026 David Schreck 
# https://github.com/dschreck/tools-for-supabase
# 


require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    local label="${LABEL_ERR:-ERROR}"
    printf '%s Error: Required command not found: %s\n' "$label" "$1" >&2
    exit 1
  fi
}

init_labels() {
  local use_emoji="${1:-${USE_EMOJI:-true}}"

  if [[ "$use_emoji" == "true" ]]; then
    LABEL_OK="✅"
    LABEL_WARN="⚠️"
    LABEL_ERR="❌"
    LABEL_INFO="🔍"
    LABEL_TIP="💡"
  else
    LABEL_OK="OK"
    LABEL_WARN="WARN"
    LABEL_ERR="ERROR"
    LABEL_INFO="INFO"
    LABEL_TIP="TIP"
  fi
}

log_line() {
  local label="$1"
  local message="$2"
  local stream="${3:-stdout}"

  if [[ "$stream" == "stderr" ]]; then
    printf '%s %s\n' "$label" "$message" >&2
  else
    printf '%s %s\n' "$label" "$message"
  fi
}

log_ok() {
  log_line "${LABEL_OK:-OK}" "$1"
}

log_info() {
  log_line "${LABEL_INFO:-INFO}" "$1" "${2:-stdout}"
}

log_warn() {
  log_line "${LABEL_WARN:-WARN}" "$1" "stderr"
}

log_error() {
  log_line "${LABEL_ERR:-ERROR}" "$1" "stderr"
}

log_tip() {
  log_line "${LABEL_TIP:-TIP}" "$1" "stderr"
}

add_error() {
  if declare -p ERRORS >/dev/null 2>&1; then
    ERRORS+=("$1")
  else
    log_error "$1"
  fi
}

add_warning() {
  if declare -p WARNINGS >/dev/null 2>&1; then
    WARNINGS+=("$1")
  else
    log_warn "$1"
  fi
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}
