#!/bin/sh
set -e

# Detect OS and architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  linux) OS="linux" ;;
  darwin) OS="darwin" ;;
  *) echo "Unsupported operating system: $OS"; exit 1 ;;
esac

BIN_URL="${RSSH_DOWNLOAD_URL:-https://github.com/shrm/rssh/releases/latest/download}/rssh-${OS}-${ARCH}"
DEST="/usr/local/bin/rssh"

echo "Downloading Rakhssh (rssh) for ${OS}-${ARCH}..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$BIN_URL" -o "$DEST" || curl -fsSL "$BIN_URL" -o "./rssh"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$DEST" "$BIN_URL" || wget -qO "./rssh" "$BIN_URL"
fi

if [ -f "$DEST" ]; then
  chmod +x "$DEST"
  echo "✔ Rakhssh installed successfully to $DEST"
elif [ -f "./rssh" ]; then
  chmod +x "./rssh"
  echo "✔ Rakhssh downloaded to ./rssh"
fi
