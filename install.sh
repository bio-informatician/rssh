#!/usr/bin/env bash
# Rakhssh (rssh) — Production Linux Client Installer
# https://github.com/shrm/rssh
set -euo pipefail

VERSION="${RSSH_VERSION:-latest}"
REPO="${RSSH_REPO:-shrm/rssh}"

if [[ "$VERSION" == "latest" ]]; then
  BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
  BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

# Detect architecture
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

# Destination: user-local by default for 100% rootless security
if [[ "${1:-}" == "--system" ]] || [[ "$EUID" -eq 0 ]]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
fi

mkdir -p "$INSTALL_DIR"

BIN_NAME="rssh-linux-${ARCH}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "🐎⚡ Downloading Rakhssh (${VERSION}) [linux/${ARCH}]..."

# Download binary and checksum
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${BASE_URL}/${BIN_NAME}" -o "${TMP_DIR}/${BIN_NAME}"
  echo "🔒 Downloading SHA-256 checksums..."
  curl -fsSL "${BASE_URL}/checksums.txt" -o "${TMP_DIR}/checksums.txt" || {
    echo "❌ Error: Mandatory checksums.txt could not be retrieved from release. Failing closed for security." >&2
    exit 1
  }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${TMP_DIR}/${BIN_NAME}" "${BASE_URL}/${BIN_NAME}"
  echo "🔒 Downloading SHA-256 checksums..."
  wget -qO "${TMP_DIR}/checksums.txt" "${BASE_URL}/checksums.txt" || {
    echo "❌ Error: Mandatory checksums.txt could not be retrieved from release. Failing closed for security." >&2
    exit 1
  }
else
  echo "❌ Error: curl or wget is required to install Rakhssh." >&2
  exit 1
fi

# Mandatory checksum verification (fail-closed)
echo "🔍 Verifying binary integrity against checksums.txt..."
(cd "$TMP_DIR" && grep "${BIN_NAME}" checksums.txt | sha256sum -c -) || {
  echo "❌ Error: Cryptographic checksum mismatch! Binary may be corrupt or tampered." >&2
  exit 1
}

chmod +x "${TMP_DIR}/${BIN_NAME}"
mv "${TMP_DIR}/${BIN_NAME}" "${INSTALL_DIR}/rssh"

echo "✔ Successfully installed rssh to ${INSTALL_DIR}/rssh"

if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo ""
  echo "⚠️  Notice: $HOME/.local/bin is not in your PATH."
  echo "   Add the following line to your ~/.bashrc or ~/.zshrc:"
  echo '   export PATH="$HOME/.local/bin:$PATH"'
fi

echo ""
echo "Try running:"
echo "   rssh --help"
