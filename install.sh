#!/bin/bash
set -e

BIN_LINK="/usr/local/bin/muki"
BASE_URL="https://github.com/protbox/muki/raw/refs/heads/main"

echo "Installing Muki..."

# Download files
echo "Downloading file(s)..."
curl -fsSL $BASE_URL/muki.lua -o "$BIN_LINK"

# Make script executable
chmod +x "$BIN_LINK"

# Fin.
echo "Muki installed successfully. Enjoy."
