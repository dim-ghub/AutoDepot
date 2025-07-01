#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$TARGET_DIR/Vapor.desktop"
DESKTOP_URL="https://raw.githubusercontent.com/dim-ghub/Vapor/refs/heads/main/Vapor.desktop"

SCRIPT_DIR="$HOME/Vapor"
SCRIPT_FILE="$SCRIPT_DIR/Vapor.sh"
SCRIPT_URL="https://raw.githubusercontent.com/dim-ghub/Vapor/refs/heads/main/Vapor.sh"

echo "[INFO] Creating applications directory if needed..."
mkdir -p "$TARGET_DIR"

echo "[INFO] Downloading Vapor.desktop..."
curl -fsSL "$DESKTOP_URL" -o "$DESKTOP_FILE"

echo "[INFO] Creating Vapor directory if needed..."
mkdir -p "$SCRIPT_DIR"

echo "[INFO] Downloading Vapor.sh script..."
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_FILE"

echo "[INFO] Making Vapor.sh executable..."
chmod +x "$SCRIPT_FILE"

# Edit the Exec line in the desktop file to point to the local script with absolute path
echo "[INFO] Updating Exec line in the desktop file..."
sed -i "s|^Exec=.*|Exec=bash $SCRIPT_FILE|" "$DESKTOP_FILE"

echo "[INFO] Making .desktop file executable..."
chmod +x "$DESKTOP_FILE"

echo "[DONE] Vapor shortcut and script installed successfully!"
