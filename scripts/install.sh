#!/usr/bin/env bash
#
# Install tools-for-supabase to ~/.local/share/tools-for-supabase
# and create supabase-* command shims in ~/.local/bin
#
# Usage:
#   bash scripts/install.sh
#
# Licensed under the MIT License. Copyright (c) 2026 David Schreck 
# https://github.com/dschreck/tools-for-supabase
# 

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values (can be overridden via command-line options)
REPO_URL="https://github.com/dschreck/tools-for-supabase.git"
INSTALL_ROOT="${HOME}/.local/share/tools-for-supabase"
BIN_DIR="${HOME}/.local/bin"
USE_EMOJI=true

# shellcheck source=src/lib/shell-utils.sh
source "$SCRIPT_DIR/../src/lib/shell-utils.sh"

print_help() {
  cat <<HELP_EOF
${SCRIPT_NAME} - Install tools-for-supabase

Usage:
  ${SCRIPT_NAME} [options]

Options:
  --repo-url URL          Repository URL to clone (default: https://github.com/dschreck/tools-for-supabase.git)
  --install-root PATH     Installation directory (default: ~/.local/share/tools-for-supabase)
  --bin-dir PATH          Directory for command shims (default: ~/.local/bin)
  --use-emoji BOOL        Enable/disable emoji output (default: true)
  -h, --help              Show this help message

Description:
  Installs tools-for-supabase to ~/.local/share/tools-for-supabase and creates
  supabase-* command shims in ~/.local/bin.

  The installer will:
  - Clone/update the repository
  - Create a .env file from .env.example
  - Prompt for Supabase access token and project reference ID
  - Create supabase-* command shims
  - Check if ~/.local/bin is in your PATH

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --help
  ${SCRIPT_NAME} --install-root /opt/tools-for-supabase --bin-dir /usr/local/bin
  ${SCRIPT_NAME} --use-emoji false
HELP_EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-url=*)
        REPO_URL="${1#*=}"
        shift
        ;;
      --repo-url)
        REPO_URL="$2"
        shift 2
        ;;
      --install-root=*)
        INSTALL_ROOT="${1#*=}"
        shift
        ;;
      --install-root)
        INSTALL_ROOT="$2"
        shift 2
        ;;
      --bin-dir=*)
        BIN_DIR="${1#*=}"
        shift
        ;;
      --bin-dir)
        BIN_DIR="$2"
        shift 2
        ;;
      --use-emoji=*)
        USE_EMOJI="${1#*=}"
        shift
        ;;
      --use-emoji)
        USE_EMOJI="$2"
        shift 2
        ;;
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
  done
}

main() {
  parse_args "$@"
  
  # Expand tilde in paths
  INSTALL_ROOT="${INSTALL_ROOT/#\~/$HOME}"
  BIN_DIR="${BIN_DIR/#\~/$HOME}"
  
  # Set derived variables after INSTALL_ROOT may have been overridden
  ENV_FILE="${INSTALL_ROOT}/.env"
  ENV_EXAMPLE="${INSTALL_ROOT}/.env.example"
  
  init_labels "$USE_EMOJI"

  log_info "Installing tools-for-supabase"
  printf '\n'

# ----------------------------
# Check prerequisites
# ----------------------------

if ! command -v git >/dev/null 2>&1; then
  log_error "git is required but not found. Please install git first."
  exit 1
fi

# ----------------------------
# Clone / Update
# ----------------------------

mkdir -p "$INSTALL_ROOT" "$BIN_DIR"

if [[ -d "$INSTALL_ROOT/.git" ]]; then
  log_info "Updating existing installation"
  if ! git -C "$INSTALL_ROOT" pull --ff-only; then
    log_warn "Failed to pull updates. You may need to resolve conflicts manually."
  fi
else
  log_info "Cloning repository"
  if ! git clone "$REPO_URL" "$INSTALL_ROOT"; then
    log_error "Failed to clone repository"
    exit 1
  fi
fi

# ----------------------------
# Environment setup
# ----------------------------

if [[ ! -f "$ENV_FILE" ]]; then
  printf '\n'
  if [[ ! -f "$ENV_EXAMPLE" ]]; then
    log_error ".env.example not found in installation directory: $ENV_EXAMPLE"
    log_tip "The repository should include a .env.example file"
    exit 1
  fi
  log_info "Creating .env file from .env.example"
  cp "$ENV_EXAMPLE" "$ENV_FILE"
else
  printf '\n'
  log_info ".env already exists — not overwriting"
fi

# Auto-fill SUPABASE_PROJECT_REF if possible
if ! grep -q "^SUPABASE_PROJECT_REF=" "$ENV_FILE" || grep -q "^SUPABASE_PROJECT_REF=$" "$ENV_FILE"; then
  ref=""
  ref=$(resolve_project_ref_from_config ".supabase/config.toml" ".supabase/project-ref")
  
  if [[ -n "$ref" ]]; then
    log_info "Detected SUPABASE_PROJECT_REF=$ref"
    sed_inplace "s|^SUPABASE_PROJECT_REF=.*|SUPABASE_PROJECT_REF=$ref|" "$ENV_FILE"
  fi
fi

# Prompt for missing values
prompt_if_missing() {
  local key="$1"
  local prompt="$2"
  local secret="${3:-false}"

  if ! grep -q "^$key=" "$ENV_FILE" || grep -q "^$key=$" "$ENV_FILE"; then
    printf '\n'
    local value=""
    if [[ "$secret" == "true" ]]; then
      read -rsp "$prompt: " value
      printf '\n'
    else
      read -rp "$prompt: " value
    fi
    if [[ -n "$value" ]]; then
      sed_inplace "s|^$key=.*|$key=$value|" "$ENV_FILE"
    fi
  fi
}

prompt_if_missing "SUPABASE_ACCESS_TOKEN" "Enter Supabase access token" true
prompt_if_missing "SUPABASE_PROJECT_REF" "Enter Supabase project reference ID" false

# shims go here

printf '\n'
log_info "Installing supabase subcommands"

tool_count=0
for tool in "$INSTALL_ROOT"/src/*.sh; do
  [[ -f "$tool" ]] || continue
  
  name="$(basename "$tool" .sh)"
  shim="$BIN_DIR/supabase-$name"

  cat > "$shim" <<SHIM_EOF
#!/usr/bin/env bash
set -euo pipefail
export \$(grep -v '^#' "$ENV_FILE" | xargs)
exec "$INSTALL_ROOT/src/$name.sh" "\$@"
SHIM_EOF

  chmod +x "$shim"
  printf '  %s supabase %s\n' "$LABEL_OK" "$name"
  tool_count=$((tool_count + 1))
done

if [[ $tool_count -eq 0 ]]; then
  log_warn "No tools found to install"
else
  log_info "Installed $tool_count subcommand(s)"
fi

if ! echo "$PATH" | grep -qF "$BIN_DIR"; then
  printf '\n'
  log_warn "$BIN_DIR is not in your PATH"
  printf '\n'
  log_tip "Add this to your shell config (~/.bashrc, ~/.zshrc, etc.):"
  log_plain '  export PATH="$HOME/.local/bin:$PATH"'
  printf '\n'
fi

printf '\n'
log_ok "Installation complete"
printf '\n'
log_info "Next steps:"
log_plain "  1. Review $ENV_FILE"
log_plain "  2. Ensure $BIN_DIR is in your PATH"
log_plain "  3. Run: supabase lint-templates"
printf '\n'
}

main "$@"