#!/usr/bin/env bash
#
# Update Supabase email templates via the Management API.
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=your-token SUPABASE_PROJECT_REF=your-project-ref \
#     bash src/update-email-templates.sh
#
# Optional:
#   SUPABASE_CONFIG_PATH=./supabase/config.toml
#   TEMPLATES_DIR=./supabase/templates
#
# Get your access token from: https://supabase.com/dashboard/account/tokens
# Get your project ref from: Supabase Dashboard -> Project Settings -> General -> Reference ID
#
# Licensed under the MIT License. Copyright (c) 2026 David Schreck 
# https://github.com/dschreck/tools-for-supabase
# 

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${TEMPLATES_DIR:-}"
SUPABASE_CONFIG_PATH="${SUPABASE_CONFIG_PATH:-}"
SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
SUPABASE_PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
PROJECT_REF_FILE="${PROJECT_REF_FILE:-.supabase/project-ref}"
USE_EMOJI=true
CONFIRMATION_SUBJECT=""
RECOVERY_SUBJECT=""
MAGIC_LINK_SUBJECT=""
CONFIRMATION_TEMPLATE_PATH=""
RECOVERY_TEMPLATE_PATH=""
MAGIC_LINK_TEMPLATE_PATH=""
CONFIG_DIR=""
CONFIG_ROOT=""
TEMPLATES_TO_UPDATE=()
USED_TEMPLATES_DIR=false
CONFIRMATION_HTML=""
RECOVERY_HTML=""
MAGIC_LINK_HTML=""
PAYLOAD=""
PAYLOAD_ENTRIES=0

# shellcheck source=src/lib/shell-utils.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/shell-utils.sh"
# shellcheck source=src/lib/toml.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toml.sh"

print_help() {
  cat <<HELP_EOF
${SCRIPT_NAME} - Update Supabase email templates

Usage:
  SUPABASE_ACCESS_TOKEN=your-token SUPABASE_PROJECT_REF=your-project-ref ${SCRIPT_NAME}

Options:
  -c, --config PATH         Supabase config.toml path (default: supabase/config.toml if present)
  -d, --templates-dir DIR   Templates directory (optional)
  -p, --project-ref REF    Supabase project reference ID (overrides env/file)
  --confirmation-subject   Subject/title for confirmation email
  --recovery-subject        Subject/title for recovery email
  --magic-link-subject      Subject/title for magic link email
  --confirmation-template   Path to confirmation HTML template
  --recovery-template       Path to recovery HTML template
  --magic-link-template     Path to magic link HTML template
  --no-emoji                Disable emoji output (plain text)
  -h, --help               Show this help message

Environment:
  SUPABASE_ACCESS_TOKEN    Supabase personal access token (required)
  SUPABASE_PROJECT_REF     Supabase project reference ID (required unless PROJECT_REF_FILE exists)
  SUPABASE_CONFIG_PATH     Supabase config.toml path (optional)
  TEMPLATES_DIR            Templates directory (optional)
  PROJECT_REF_FILE         File to read the project ref from (optional)
HELP_EOF
}

template_label() {
  case "$1" in
    confirmation)
      printf 'Confirmation email'
      ;;
    recovery)
      printf 'Recovery email'
      ;;
    magic_link)
      printf 'Magic link email'
      ;;
  esac
}

resolve_config_path() {
  local path="$1"

  if [[ -z "$path" ]]; then
    return 0
  fi

  if [[ "$path" == /* ]]; then
    printf '%s' "$path"
    return 0
  fi

  local normalized="${path#./}"

  if [[ -n "$CONFIG_ROOT" && "$normalized" == supabase/* ]]; then
    printf '%s/%s' "$CONFIG_ROOT" "$normalized"
  elif [[ -n "$CONFIG_DIR" ]]; then
    printf '%s/%s' "$CONFIG_DIR" "$normalized"
  else
    printf '%s' "$path"
  fi
}

load_template_from_config() {
  local name="$1"
  local subject_var="$2"
  local path_var="$3"
  local section_base
  local subject=""
  local path=""

  for section_base in auth.email.template auth.email.templates; do
    if [[ -z "$subject" ]]; then
      subject="$(toml_get "$SUPABASE_CONFIG_PATH" "${section_base}.${name}" "subject")"
    fi
    if [[ -z "$path" ]]; then
      path="$(toml_get "$SUPABASE_CONFIG_PATH" "${section_base}.${name}" "content_path")"
      if [[ -z "$path" ]]; then
        path="$(toml_get "$SUPABASE_CONFIG_PATH" "${section_base}.${name}" "template_path")"
      fi
      if [[ -z "$path" ]]; then
        path="$(toml_get "$SUPABASE_CONFIG_PATH" "${section_base}.${name}" "path")"
      fi
    fi
  done

  if [[ -n "$subject" && -z "${!subject_var}" ]]; then
    printf -v "$subject_var" '%s' "$subject"
  fi

  if [[ -n "$path" && -z "${!path_var}" ]]; then
    path="$(resolve_config_path "$path")"
    printf -v "$path_var" '%s' "$path"
  fi
}

apply_template_dir_defaults() {
  if [[ -z "$TEMPLATES_DIR" ]]; then
    return 0
  fi

  if [[ -n "$CONFIRMATION_SUBJECT" && -z "$CONFIRMATION_TEMPLATE_PATH" ]]; then
    CONFIRMATION_TEMPLATE_PATH="${TEMPLATES_DIR}/confirmation.html"
    USED_TEMPLATES_DIR=true
  fi
  if [[ -n "$RECOVERY_SUBJECT" && -z "$RECOVERY_TEMPLATE_PATH" ]]; then
    RECOVERY_TEMPLATE_PATH="${TEMPLATES_DIR}/recovery.html"
    USED_TEMPLATES_DIR=true
  fi
  if [[ -n "$MAGIC_LINK_SUBJECT" && -z "$MAGIC_LINK_TEMPLATE_PATH" ]]; then
    MAGIC_LINK_TEMPLATE_PATH="${TEMPLATES_DIR}/magiclink.html"
    USED_TEMPLATES_DIR=true
  fi
}

validate_template_inputs() {
  local partial=()

  TEMPLATES_TO_UPDATE=()

  if [[ -n "$CONFIRMATION_SUBJECT" && -n "$CONFIRMATION_TEMPLATE_PATH" ]]; then
    TEMPLATES_TO_UPDATE+=("confirmation")
  elif [[ -n "$CONFIRMATION_SUBJECT" ]]; then
    partial+=("confirmation template: --confirmation-template or [auth.email.template.confirmation].content_path")
  elif [[ -n "$CONFIRMATION_TEMPLATE_PATH" ]]; then
    partial+=("confirmation subject: --confirmation-subject or [auth.email.template.confirmation].subject")
  fi

  if [[ -n "$RECOVERY_SUBJECT" && -n "$RECOVERY_TEMPLATE_PATH" ]]; then
    TEMPLATES_TO_UPDATE+=("recovery")
  elif [[ -n "$RECOVERY_SUBJECT" ]]; then
    partial+=("recovery template: --recovery-template or [auth.email.template.recovery].content_path")
  elif [[ -n "$RECOVERY_TEMPLATE_PATH" ]]; then
    partial+=("recovery subject: --recovery-subject or [auth.email.template.recovery].subject")
  fi

  if [[ -n "$MAGIC_LINK_SUBJECT" && -n "$MAGIC_LINK_TEMPLATE_PATH" ]]; then
    TEMPLATES_TO_UPDATE+=("magic_link")
  elif [[ -n "$MAGIC_LINK_SUBJECT" ]]; then
    partial+=("magic link template: --magic-link-template or [auth.email.template.magic_link].content_path")
  elif [[ -n "$MAGIC_LINK_TEMPLATE_PATH" ]]; then
    partial+=("magic link subject: --magic-link-subject or [auth.email.template.magic_link].subject")
  fi

  if [[ ${#TEMPLATES_TO_UPDATE[@]} -eq 0 ]]; then
    log_error "No complete template inputs found."
    if [[ -n "$SUPABASE_CONFIG_PATH" ]]; then
      log_info "Checked config: $SUPABASE_CONFIG_PATH" "stderr"
    fi
    if [[ ${#partial[@]} -gt 0 ]]; then
      log_warn "Incomplete entries:"
      printf '  - %s\n' "${partial[@]}" >&2
    fi
    log_tip "Provide --config or pass --{confirmation,recovery,magic-link}-{subject,template}."
    exit 1
  fi

  if [[ ${#partial[@]} -gt 0 ]]; then
    log_warn "Skipping incomplete template inputs:"
    printf '  - %s\n' "${partial[@]}" >&2
  fi
}

resolve_default_config_path() {
  if [[ -z "$SUPABASE_CONFIG_PATH" && -f "supabase/config.toml" ]]; then
    SUPABASE_CONFIG_PATH="supabase/config.toml"
  fi
}

load_config_templates() {
  if [[ -z "$SUPABASE_CONFIG_PATH" ]]; then
    return 0
  fi

  if [[ ! -f "$SUPABASE_CONFIG_PATH" ]]; then
    log_error "Config file not found: $SUPABASE_CONFIG_PATH"
    exit 1
  fi

  CONFIG_DIR="$(cd "$(dirname "$SUPABASE_CONFIG_PATH")" && pwd)"
  CONFIG_ROOT="$CONFIG_DIR"
  if [[ "$(basename "$CONFIG_DIR")" == "supabase" ]]; then
    CONFIG_ROOT="$(cd "$CONFIG_DIR/.." && pwd)"
  fi

  load_template_from_config "confirmation" CONFIRMATION_SUBJECT CONFIRMATION_TEMPLATE_PATH
  load_template_from_config "recovery" RECOVERY_SUBJECT RECOVERY_TEMPLATE_PATH
  load_template_from_config "magic_link" MAGIC_LINK_SUBJECT MAGIC_LINK_TEMPLATE_PATH
  if [[ -z "$MAGIC_LINK_SUBJECT" || -z "$MAGIC_LINK_TEMPLATE_PATH" ]]; then
    load_template_from_config "magiclink" MAGIC_LINK_SUBJECT MAGIC_LINK_TEMPLATE_PATH
  fi
}

resolve_project_ref() {
  if [[ -z "$SUPABASE_PROJECT_REF" && -f "$PROJECT_REF_FILE" ]]; then
    SUPABASE_PROJECT_REF="$(<"$PROJECT_REF_FILE")"
    SUPABASE_PROJECT_REF="${SUPABASE_PROJECT_REF//$'\r'/}"
    SUPABASE_PROJECT_REF="${SUPABASE_PROJECT_REF//$'\n'/}"
  fi
}

ensure_auth_env() {
  if [[ -z "$SUPABASE_ACCESS_TOKEN" || -z "$SUPABASE_PROJECT_REF" ]]; then
    log_error "SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF are required (env, --project-ref, or $PROJECT_REF_FILE)"
    printf '\n' >&2
    print_help >&2
    exit 1
  fi
}

ensure_templates_dir() {
  if [[ "$USED_TEMPLATES_DIR" == "true" && ! -d "$TEMPLATES_DIR" ]]; then
    log_error "Templates directory not found: $TEMPLATES_DIR"
    exit 1
  fi
}

ensure_template_files() {
  local missing_files=()

  if array_contains "confirmation" "${TEMPLATES_TO_UPDATE[@]}"; then
    [[ -f "$CONFIRMATION_TEMPLATE_PATH" ]] || missing_files+=("$CONFIRMATION_TEMPLATE_PATH")
  fi
  if array_contains "recovery" "${TEMPLATES_TO_UPDATE[@]}"; then
    [[ -f "$RECOVERY_TEMPLATE_PATH" ]] || missing_files+=("$RECOVERY_TEMPLATE_PATH")
  fi
  if array_contains "magic_link" "${TEMPLATES_TO_UPDATE[@]}"; then
    [[ -f "$MAGIC_LINK_TEMPLATE_PATH" ]] || missing_files+=("$MAGIC_LINK_TEMPLATE_PATH")
  fi

  if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_error "Expected templates not found."
    log_info "Missing required files:" "stderr"
    printf '  - %s\n' "${missing_files[@]}" >&2
    exit 1
  fi
}

read_template_files() {
  CONFIRMATION_HTML=""
  RECOVERY_HTML=""
  MAGIC_LINK_HTML=""

  if array_contains "confirmation" "${TEMPLATES_TO_UPDATE[@]}"; then
    CONFIRMATION_HTML="$(<"$CONFIRMATION_TEMPLATE_PATH")"
  fi
  if array_contains "recovery" "${TEMPLATES_TO_UPDATE[@]}"; then
    RECOVERY_HTML="$(<"$RECOVERY_TEMPLATE_PATH")"
  fi
  if array_contains "magic_link" "${TEMPLATES_TO_UPDATE[@]}"; then
    MAGIC_LINK_HTML="$(<"$MAGIC_LINK_TEMPLATE_PATH")"
  fi
}

append_payload() {
  local key="$1"
  local value="$2"

  if (( PAYLOAD_ENTRIES > 0 )); then
    PAYLOAD+=$',\n'
  fi
  PAYLOAD+="  \"${key}\": \"$(json_escape "$value")\""
  PAYLOAD_ENTRIES=$((PAYLOAD_ENTRIES + 1))
}

build_payload() {
  PAYLOAD="{"
  PAYLOAD_ENTRIES=0

  if array_contains "confirmation" "${TEMPLATES_TO_UPDATE[@]}"; then
    append_payload "mailer_subjects_confirmation" "$CONFIRMATION_SUBJECT"
    append_payload "mailer_templates_confirmation_content" "$CONFIRMATION_HTML"
  fi
  if array_contains "recovery" "${TEMPLATES_TO_UPDATE[@]}"; then
    append_payload "mailer_subjects_recovery" "$RECOVERY_SUBJECT"
    append_payload "mailer_templates_recovery_content" "$RECOVERY_HTML"
  fi
  if array_contains "magic_link" "${TEMPLATES_TO_UPDATE[@]}"; then
    append_payload "mailer_subjects_magic_link" "$MAGIC_LINK_SUBJECT"
    append_payload "mailer_templates_magic_link_content" "$MAGIC_LINK_HTML"
  fi

  PAYLOAD+=$'\n}\n'
}

send_request() {
  local response status body

  response=$(curl -sS -w '\n%{http_code}' \
    -X PATCH "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_REF}/config/auth" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD")

  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ -z "$status" || ! "$status" =~ ^[0-9]+$ ]]; then
    log_error "Unexpected response from API."
    printf '%s\n' "$response" >&2
    exit 1
  fi

  if (( status < 200 || status >= 300 )); then
    log_error "Failed to update templates (status $status)"
    if [[ -n "$body" ]]; then
      printf '%s\n' "$body" >&2
    fi
    exit 1
  fi
}

print_success() {
  log_ok "Email templates updated successfully."
  printf '\n'
  log_info "Updated templates:"
  local template_name
  for template_name in "${TEMPLATES_TO_UPDATE[@]}"; do
    printf '  - %s\n' "$(template_label "$template_name")"
  done
  printf '\n'
  log_info "Templates will be used for all new emails sent from Supabase Auth."
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--config)
        SUPABASE_CONFIG_PATH="$2"
        shift 2
        ;;
      -d|--templates-dir)
        TEMPLATES_DIR="$2"
        shift 2
        ;;
      -p|--project-ref)
        SUPABASE_PROJECT_REF="$2"
        shift 2
        ;;
      --confirmation-subject|--confirmation-title)
        CONFIRMATION_SUBJECT="$2"
        shift 2
        ;;
      --recovery-subject|--recovery-title)
        RECOVERY_SUBJECT="$2"
        shift 2
        ;;
      --magic-link-subject|--magiclink-subject|--magic-link-title|--magiclink-title)
        MAGIC_LINK_SUBJECT="$2"
        shift 2
        ;;
      --confirmation-template)
        CONFIRMATION_TEMPLATE_PATH="$2"
        shift 2
        ;;
      --recovery-template)
        RECOVERY_TEMPLATE_PATH="$2"
        shift 2
        ;;
      --magic-link-template|--magiclink-template)
        MAGIC_LINK_TEMPLATE_PATH="$2"
        shift 2
        ;;
      --no-emoji)
        USE_EMOJI=false
        init_labels "$USE_EMOJI"
        shift
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -* )
        log_error "Unknown option: $1"
        printf '\n' >&2
        print_help >&2
        exit 2
        ;;
      *)
        log_error "Unexpected argument: $1"
        printf '\n' >&2
        print_help >&2
        exit 2
        ;;
    esac
  done
}

main() {
  init_labels "$USE_EMOJI"
  parse_args "$@"
  init_labels "$USE_EMOJI"

  resolve_default_config_path
  load_config_templates
  apply_template_dir_defaults
  validate_template_inputs
  resolve_project_ref
  ensure_auth_env
  require_cmd curl
  ensure_templates_dir
  ensure_template_files
  read_template_files
  build_payload
  send_request
  print_success
}

main "$@"
