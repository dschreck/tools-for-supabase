#!/usr/bin/env bash
#
# Lint Supabase email templates for common syntax and usage issues.
#
# Usage:
#   lint-supabase-template.sh [options] [template-name]
#
# Examples:
#   lint-supabase-template.sh confirmation
#   lint-supabase-template.sh --templates-dir ./supabase/templates recovery
#   lint-supabase-template.sh --file ./supabase/templates/magiclink.html
#   lint-supabase-template.sh --all
#
# Install:
#   chmod +x lint-supabase-template.sh
#   mv lint-supabase-template.sh ~/.bin/
#   # Ensure ~/.bin is in your PATH

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

TEMPLATE_NAME="confirmation"
TEMPLATES_DIR="supabase/templates"
FILE_PATH=""
VALIDATE_ALL=false
STRICT=false
USE_EMOJI=true
MODE="auto"

ERRORS=()
WARNINGS=()
FOUND_VARIABLES=()

LABEL_OK="✅"
LABEL_WARN="⚠️"
LABEL_ERR="❌"
LABEL_INFO="🔍"
LABEL_TIP="💡"

print_help() {
  cat <<HELP_EOF
${SCRIPT_NAME} - Lint Supabase email templates

Usage:
  ${SCRIPT_NAME} [options] [template-name]

Options:
  -t, --template NAME     Template name (without .html). Default: confirmation
  -d, --templates-dir DIR Templates directory. Default: supabase/templates
  -f, --file PATH         Validate a specific HTML file (overrides template name)
  --all                   Validate all .html templates in templates dir
  -m, --mode MODE         Mode: auto, full, or fragment. Default: auto
  --strict                Treat warnings as errors (exit 1)
  --no-emoji              Disable emoji output (plain text)
  -h, --help              Show this help message

Examples:
  ${SCRIPT_NAME} confirmation
  ${SCRIPT_NAME} --templates-dir ./supabase/templates recovery
  ${SCRIPT_NAME} --file ./supabase/templates/magiclink.html
  ${SCRIPT_NAME} --all
  ${SCRIPT_NAME} --mode fragment partial
HELP_EOF
}

set_labels() {
  if [[ "$USE_EMOJI" == "true" ]]; then
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

add_error() {
  ERRORS+=("$1")
}

add_warning() {
  WARNINGS+=("$1")
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

count_matches() {
  local pattern="$1"
  local text="$2"
  local count
  count=$( (grep -oE "$pattern" <<< "$text" || true) | wc -l | tr -d ' ' )
  printf '%s' "${count:-0}"
}

count_literal() {
  local needle="$1"
  local text="$2"
  local count
  count=$( (grep -oF "$needle" <<< "$text" || true) | wc -l | tr -d ' ' )
  printf '%s' "${count:-0}"
}

extract_template_variables() {
  local html="$1"
  local var

  FOUND_VARIABLES=()
  while IFS= read -r var; do
    if [[ -n "$var" ]]; then
      FOUND_VARIABLES+=("$var")
    fi
  done < <(
    (grep -oE '\{\{[-]?[[:space:]]*\.[A-Za-z0-9_]+[[:space:]]*[-]?\}\}' <<< "$html" || true) \
      | sed -E 's/\{\{[-]?[[:space:]]*\.//; s/[[:space:]]*[-]?\}\}//' \
      | sort -u
  )
}

check_basic_html_structure() {
  local html="$1"

  if ! grep -q '<!DOCTYPE' <<< "$html"; then
    add_error 'Missing DOCTYPE declaration'
  fi

  if ! grep -q '<html' <<< "$html"; then
    add_error 'Missing <html> opening tag'
  fi

  if ! grep -q '</html>' <<< "$html"; then
    add_error 'Missing </html> closing tag'
  fi

  if ! grep -q '<body' <<< "$html"; then
    add_error 'Missing <body> opening tag'
  fi

  if ! grep -q '</body>' <<< "$html"; then
    add_error 'Missing </body> closing tag'
  fi
}

resolve_mode() {
  local html="$1"

  if [[ "$MODE" == "auto" ]]; then
    if grep -qi '<!DOCTYPE' <<< "$html" || grep -qi '<html' <<< "$html"; then
      printf 'full'
    else
      printf 'fragment'
    fi
    return 0
  fi

  printf '%s' "$MODE"
}

validate_mode() {
  case "$MODE" in
    auto|full|fragment)
      return 0
      ;;
    *)
      printf '%s Invalid mode: %s (use auto, full, or fragment)\n' "$LABEL_ERR" "$MODE" >&2
      exit 2
      ;;
  esac
}

check_required_variables() {
  local required_vars=("SiteURL" "TokenHash")
  local var_name

  for var_name in "${required_vars[@]}"; do
    if ! array_contains "$var_name" "${FOUND_VARIABLES[@]}"; then
      add_warning "Template variable {{ .${var_name} }} not found (may be optional)"
    fi
  done
}

check_unclosed_tags() {
  local html="$1"
  local common_tags=("div" "p" "a" "h1" "h2" "h3" "span")
  local tag open_count close_count

  for tag in "${common_tags[@]}"; do
    open_count=$(count_matches "<${tag}[^>]*>" "$html")
    close_count=$(count_matches "</${tag}[[:space:]]*>" "$html")
    if [[ "$open_count" != "$close_count" ]]; then
      add_warning "Possible unclosed <${tag}> tag: ${open_count} opening, ${close_count} closing"
    fi
  done
}

get_template_specific_vars() {
  case "$1" in
    email_change)
      echo "NewEmail"
      ;;
    email_changed_notification)
      echo "OldEmail"
      ;;
    phone_changed_notification)
      echo "Phone OldPhone"
      ;;
    identity_linked_notification|identity_unlinked_notification)
      echo "Provider"
      ;;
    mfa_factor_enrolled_notification|mfa_factor_unenrolled_notification)
      echo "FactorType"
      ;;
    *)
      echo ""
      ;;
  esac
}

templates_for_specific_var() {
  case "$1" in
    NewEmail)
      echo "email_change"
      ;;
    OldEmail)
      echo "email_changed_notification"
      ;;
    Phone|OldPhone)
      echo "phone_changed_notification"
      ;;
    Provider)
      echo "identity_linked_notification identity_unlinked_notification"
      ;;
    FactorType)
      echo "mfa_factor_enrolled_notification mfa_factor_unenrolled_notification"
      ;;
    *)
      echo ""
      ;;
  esac
}

check_template_variables() {
  local valid_variables=(
    "ConfirmationURL"
    "Token"
    "TokenHash"
    "SiteURL"
    "RedirectTo"
    "Data"
    "Email"
    "NewEmail"
    "OldEmail"
    "Phone"
    "OldPhone"
    "Provider"
    "FactorType"
  )

  local var_name valid_list
  for var_name in "${FOUND_VARIABLES[@]}"; do
    if ! array_contains "$var_name" "${valid_variables[@]}"; then
      valid_list=$(printf '%s, ' "${valid_variables[@]}")
      valid_list=${valid_list%, }
      add_error "Invalid template variable: {{ .${var_name} }}. Valid variables are: ${valid_list}"
    fi
  done
}

check_template_specific_variables() {
  local template_name="$1"
  local all_specific_vars=("NewEmail" "OldEmail" "Phone" "OldPhone" "Provider" "FactorType")
  local allowed_specific_vars
  local var_name valid_templates valid_list

  allowed_specific_vars=( $(get_template_specific_vars "$template_name") )

  for var_name in "${FOUND_VARIABLES[@]}"; do
    if array_contains "$var_name" "${all_specific_vars[@]}"; then
      if ! array_contains "$var_name" "${allowed_specific_vars[@]}"; then
        valid_templates=( $(templates_for_specific_var "$var_name") )
        valid_list=$(printf '%s, ' "${valid_templates[@]}")
        valid_list=${valid_list%, }
        add_error "Template-specific variable {{ .${var_name} }} is not valid for template \"${template_name}\". This variable is only available in: ${valid_list}"
      fi
    fi
  done
}

check_links() {
  local html="$1"
  if grep -q 'href="{{' <<< "$html"; then
    if ! array_contains "SiteURL" "${FOUND_VARIABLES[@]}"; then
      add_warning 'Link found but {{ .SiteURL }} may be missing'
    fi
  fi
}

check_unescaped_ampersands() {
  local html="$1"
  if grep -q '&' <<< "$html" && ! grep -q '&amp;' <<< "$html" && grep -q '&type=' <<< "$html"; then
    if grep -qE '&[^a-z]' <<< "$html"; then
      add_warning 'Found unescaped & characters (should be &amp; in some contexts)'
    fi
  fi
}

check_template_blocks() {
  local html="$1"
  local block
  local open_braces close_braces open_double close_double

  while IFS= read -r block; do
    if [[ -n "$block" ]]; then
      open_braces=$(count_literal '{' "$block")
      close_braces=$(count_literal '}' "$block")

      if [[ "$open_braces" != "$close_braces" ]]; then
        add_error "Unbalanced braces in template block: ${block}"
      fi

      open_double=$(count_literal '{{' "$block")
      if [[ "$open_double" -gt 1 ]]; then
        add_error "Multiple {{ in template block: ${block}"
      fi

      close_double=$(count_literal '}}' "$block")
      if [[ "$close_double" -gt 1 ]]; then
        add_error "Multiple }} in template block: ${block}"
      fi
    fi
  done < <((grep -oE '\{\{[-]?[^}]*[-]?\}\}' <<< "$html" || true))
}

print_success() {
  local template_name="$1"
  local var_list=""
  local var

  printf '\n%s Validating template: %s\n\n' "$LABEL_INFO" "${template_name}.html"
  printf '%s No syntax errors found!\n\n' "$LABEL_OK"
  printf 'Template checks look good.\n'

  if [[ ${#FOUND_VARIABLES[@]} -gt 0 ]]; then
    for var in "${FOUND_VARIABLES[@]}"; do
      if [[ -z "$var_list" ]]; then
        var_list="{{ .${var} }}"
      else
        var_list="${var_list}, {{ .${var} }}"
      fi
    done
    printf 'Found %s template variable(s): %s\n' "${#FOUND_VARIABLES[@]}" "$var_list"
  else
    printf 'Found 0 template variable(s): none\n'
  fi
}

print_findings() {
  local template_name="$1"

  printf '\n%s Validating template: %s\n\n' "$LABEL_INFO" "${template_name}.html"

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf '%s Errors found:\n\n' "$LABEL_ERR" >&2
    printf '%s\n' "${ERRORS[@]/#/  - }" >&2
    printf '\n' >&2
  fi

  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '%s Warnings:\n\n' "$LABEL_WARN" >&2
    printf '%s\n' "${WARNINGS[@]/#/  - }" >&2
    printf '\n' >&2
  fi

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf '%s Tip: Check Supabase auth logs for detailed error messages:\n' "$LABEL_TIP" >&2
    printf '   supabase logs --service auth\n\n' >&2
  fi
}

lint_template() {
  local template_name="$1"
  local template_path="$2"
  local exit_code=0

  if [[ ! -f "$template_path" ]]; then
    printf '%s Template file not found: %s\n' "$LABEL_ERR" "$template_path" >&2
    return 1
  fi

  ERRORS=()
  WARNINGS=()
  FOUND_VARIABLES=()

  local html
  html="$(<"$template_path")"
  local template_mode
  template_mode="$(resolve_mode "$html")"

  if [[ "$template_mode" == "full" ]]; then
    check_basic_html_structure "$html"
  elif [[ "$template_mode" == "fragment" ]]; then
    if grep -qi '<!DOCTYPE' <<< "$html" || grep -qi '<html' <<< "$html"; then
      add_warning 'Fragment mode enabled but document tags found; consider --mode full'
    fi
  fi
  extract_template_variables "$html"
  check_required_variables
  check_unclosed_tags "$html"
  check_template_variables
  check_template_specific_variables "$template_name"
  check_links "$html"
  check_unescaped_ampersands "$html"
  check_template_blocks "$html"

  if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    print_success "$template_name"
    return 0
  fi

  print_findings "$template_name"

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    exit_code=1
  elif [[ "$STRICT" == "true" && ${#WARNINGS[@]} -gt 0 ]]; then
    exit_code=1
  fi

  if [[ "$exit_code" -eq 0 ]]; then
    printf '%s No critical errors found. Warnings are informational.\n\n' "$LABEL_OK" >&2
  fi

  return "$exit_code"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--template)
        TEMPLATE_NAME="$2"
        shift 2
        ;;
      -d|--templates-dir)
        TEMPLATES_DIR="$2"
        shift 2
        ;;
      -f|--file)
        FILE_PATH="$2"
        shift 2
        ;;
      --all)
        VALIDATE_ALL=true
        shift
        ;;
      -m|--mode)
        MODE="$2"
        shift 2
        ;;
      --strict)
        STRICT=true
        shift
        ;;
      --no-emoji)
        USE_EMOJI=false
        set_labels
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
        printf '%s Unknown option: %s\n\n' "$LABEL_ERR" "$1" >&2
        print_help >&2
        exit 2
        ;;
      *)
        TEMPLATE_NAME="$1"
        shift
        ;;
    esac
  done
}

main() {
  set_labels
  parse_args "$@"
  set_labels
  validate_mode

  if [[ -n "$FILE_PATH" && "$VALIDATE_ALL" == "true" ]]; then
    printf '%s --file and --all are mutually exclusive.\n' "$LABEL_ERR" >&2
    exit 2
  fi

  if [[ "$VALIDATE_ALL" == "true" && -n "$TEMPLATE_NAME" && "$TEMPLATE_NAME" != "confirmation" ]]; then
    printf '%s --all ignores a specific template name.\n' "$LABEL_WARN" >&2
  fi

  if [[ -n "$FILE_PATH" ]]; then
    local template_name
    template_name="$(basename "$FILE_PATH")"
    template_name="${template_name%.html}"
    lint_template "$template_name" "$FILE_PATH"
    exit $?
  fi

  if [[ "$VALIDATE_ALL" == "true" ]]; then
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
      printf '%s Templates directory not found: %s\n' "$LABEL_ERR" "$TEMPLATES_DIR" >&2
      exit 1
    fi

    local exit_code=0
    local found_any=false
    local file

    while IFS= read -r -d '' file; do
      found_any=true
      local template_name
      template_name="$(basename "$file")"
      template_name="${template_name%.html}"
      if ! lint_template "$template_name" "$file"; then
        exit_code=1
      fi
    done < <(find "$TEMPLATES_DIR" -maxdepth 1 -type f -name '*.html' -print0)

    if [[ "$found_any" == "false" ]]; then
      printf '%s No .html templates found in %s\n' "$LABEL_ERR" "$TEMPLATES_DIR" >&2
      exit 1
    fi

    exit "$exit_code"
  fi

  local template_path
  template_path="${TEMPLATES_DIR}/${TEMPLATE_NAME}.html"
  lint_template "$TEMPLATE_NAME" "$template_path"
}

main "$@"
