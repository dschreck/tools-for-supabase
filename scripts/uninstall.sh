#!/usr/bin/env bash
#
# Uninstall tools-for-supabase
# Removes installation directory and all supabase-* command shims
#
# Usage:
#   bash scripts/uninstall.sh
#
# Licensed under the MIT License. Copyright (c) 2026 David Schreck 
# https://github.com/dschreck/tools-for-supabase
# 

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="${HOME}/.local/share/tools-for-supabase"
BIN_DIR="${HOME}/.local/bin"
USE_EMOJI=true

# shellcheck source=src/lib/shell-utils.sh
source "$SCRIPT_DIR/../src/lib/shell-utils.sh"

print_help() {
  cat <<HELP_EOF
${SCRIPT_NAME} - Uninstall tools-for-supabase

Usage:
  ${SCRIPT_NAME} [options]

Options:
  -h, --help    Show this help message

Description:
  Uninstalls tools-for-supabase by removing:
  - The installation directory (~/.local/share/tools-for-supabase)
  - All supabase-* command shims from ~/.local/bin

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --help
HELP_EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf '%s Unknown option: %s\n\n' "${LABEL_ERR:-ERROR}" "$1" >&2
        print_help >&2
        exit 2
        ;;
      *)
        printf '%s Unexpected argument: %s\n\n' "${LABEL_ERR:-ERROR}" "$1" >&2
        print_help >&2
        exit 2
        ;;
    esac
    shift
  done
}

main() {
  init_labels "$USE_EMOJI"
  parse_args "$@"

  log_info "Uninstalling tools-for-supabase"
  printf '\n'


# nuekeshims
shim_count=0
for shim in "$BIN_DIR"/supabase-*; do
  [[ -f "$shim" ]] || continue
  rm -f "$shim"
  shim_count=$((shim_count + 1))
done

if [[ $shim_count -gt 0 ]]; then
  log_info "Removed $shim_count command shim(s)"
else
  log_info "No command shims found to remove"
fi


# nuke install
if [[ -d "$INSTALL_ROOT" ]]; then
  log_info "Removing installation directory"
  rm -rf "$INSTALL_ROOT"
  log_ok "Removed $INSTALL_ROOT"
else
  log_info "Installation directory not found: $INSTALL_ROOT"
fi


log_ok "Uninstalled tools-for-supabase"
}

main "$@"