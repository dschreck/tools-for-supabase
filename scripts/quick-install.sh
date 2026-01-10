#!/usr/bin/env bash
set -euo pipefail

echo "▶ tools-for-supabase quick installer"
echo "▶ https://github.com/dschreck/tools-for-supabase"
echo
echo "⚠️  Review this script before running:"
echo "    curl -fsSL tools.keylogger.lol | less"
echo

for i in 3 2 1; do
  printf "\r▶ Running installer in %d... " "$i"
  sleep 1
done
printf "\r▶ Running installer...      \n"
echo

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/tools-for-supabase}"

# ----------------------------
# Prerequisites
# ----------------------------

require() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

install_just() {
  echo "▶ Installing just"

  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    curl -fsSL https://just.systems/install.sh | bash -s -- --to "$HOME/.local/bin"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install just
  else
    echo "❌ Unsupported OS for automatic just install"
    echo "Install just manually: https://just.systems"
    exit 1
  fi
}

require git || {
  echo "❌ git is required"
  exit 1
}

if ! require just; then
  install_just
fi

# Ensure ~/.local/bin is in PATH for this shell
export PATH="$HOME/.local/bin:$PATH"

# ----------------------------
# Clone or update repo
# ----------------------------

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "▶ Updating existing install"
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "▶ Cloning repository"
  git clone https://github.com/dschreck/tools-for-supabase.git "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ----------------------------
# Delegate to Justfile
# ----------------------------

echo
echo "▶ Running just install"
just install

echo
echo "✅ tools-for-supabase installed successfully"
