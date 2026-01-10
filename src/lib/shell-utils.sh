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

log_plain() {
  local message="$1"
  local stream="${2:-stdout}"
  if [[ "$stream" == "stderr" ]]; then
    printf '%s\n' "$message" >&2
  else
    printf '%s\n' "$message"
  fi
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

# Cross-platform sed in-place editing
# Usage: sed_inplace "s|pattern|replacement|" file
sed_inplace() {
  local expression="$1"
  local file="$2"
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$expression" "$file"
  else
    sed -i.bak "$expression" "$file"
    rm -f "${file}.bak"
  fi
}

# Read and clean project reference from file
# Removes carriage returns and newlines
read_project_ref_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  local ref
  ref=$(<"$file")
  ref="${ref//$'\r'/}"
  ref="${ref//$'\n'/}"
  printf '%s' "$ref"
}

# Resolve project reference from config.toml or project-ref file
# Checks .supabase/config.toml first, then .supabase/project-ref
# Returns the project ref via stdout, or empty string if not found
resolve_project_ref_from_config() {
  local config_toml="${1:-.supabase/config.toml}"
  local project_ref_file="${2:-.supabase/project-ref}"
  local ref=""
  
  if [[ -f "$config_toml" ]]; then
    ref=$(grep '^project_id' "$config_toml" | cut -d'"' -f2 || true)
  fi
  
  if [[ -z "$ref" && -f "$project_ref_file" ]]; then
    ref=$(read_project_ref_file "$project_ref_file")
  fi
  
  if [[ -n "$ref" ]]; then
    printf '%s' "$ref"
  fi
}
