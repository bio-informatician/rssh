#!/usr/bin/env bash
# Rakhssh (rssh) — Production Linux Client Installer
# https://github.com/shrm/rssh
set -euo pipefail

VERSION="${RSSH_VERSION:-latest}"
REPO="${RSSH_REPO:-shrm/rssh}"
BASE_URL="https://github.com/${REPO}/releases/${VERSION}/download"

# Determine target architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "❌ Error: Unsupported architecture: $ARCH. Rakhssh client currently supports x86_64 (amd64) and aarch64 (arm64)." >&2
    exit 1
    ;;
esac

# Handle uninstall
if [[ "${1:-}" == "--uninstall" ]]; then
  echo "🗑️  Uninstalling Rakhssh..."
  rm -f "$HOME/.local/bin/rssh"
  if [[ -w "/usr/local/bin/rssh" ]]; then
    rm -f "/usr/local/bin/rssh"
  elif command -v sudo >/dev/null 2>&1 && sudo test -f "/usr/local/bin/rssh"; then
    sudo rm -f "/usr/local/bin/rssh"
  fi
  echo "✔ Rakhssh uninstalled."
  exit 0
fi

# Choose destination: prioritize user-local (~/.local/bin) to remain 100% rootless
if [[ "${1:-}" == "--system" ]] || [[ "$EUID" -eq 0 ]]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
fi

mkdir -p "$INSTALL_DIR"

BIN_NAME="rssh-linux-${ARCH}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "🐎⚡ Installing Rakhssh (rssh) [linux/${ARCH}]..."

# Download binary
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${BASE_URL}/${BIN_NAME}" -o "${TMP_DIR}/rssh"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${TMP_DIR}/rssh" "${BASE_URL}/${BIN_NAME}"
else
  echo "❌ Error: curl or wget is required to install Rakhssh." >&2
  exit 1
fi

# Optional checksum verification
if curl -fsSL "${BASE_URL}/checksums.txt" -o "${TMP_DIR}/checksums.txt" 2>/dev/null; then
  echo "🔒 Verifying SHA-256 checksum..."
  (cd "$TMP_DIR" && grep "${BIN_NAME}" checksums.txt | sed "s/${BIN_NAME}/rssh/" | sha256sum -c -) || {
    echo "❌ Error: Checksum verification failed!" >&2
    exit 1
  }
fi

chmod +x "${TMP_DIR}/rssh"
mv "${TMP_DIR}/rssh" "${INSTALL_DIR}/rssh"

echo "✔ Successfully installed rssh to ${INSTALL_DIR}/rssh"

# PATH check for user-level installation
if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo ""
  echo "⚠️  Notice: $HOME/.local/bin is not in your PATH."
  echo "   Add the following line to your ~/.bashrc or ~/.zshrc:"
  echo '   export PATH="$HOME/.local/bin:$PATH"'
fi

echo ""
echo "Try running:"
echo "   rssh --help"
echo "   rssh host"
