#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$TARGET_DIR/Vapor.desktop"
DESKTOP_URL="https://raw.githubusercontent.com/dim-ghub/Vapor/refs/heads/main/Vapor.desktop"

SCRIPT_DIR="$HOME/Vapor"
SCRIPT_FILE="$SCRIPT_DIR/Vapor.sh"
SCRIPT_URL="https://raw.githubusercontent.com/dim-ghub/Vapor/refs/heads/main/Vapor.sh"

ICON_URL="https://raw.githubusercontent.com/dim-ghub/Vapor/refs/heads/main/Vapor.svg"
ICON_PATH="$SCRIPT_DIR/Vapor.svg"

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

echo "[INFO] Downloading Vapor.svg icon..."
curl -fsSL "$ICON_URL" -o "$ICON_PATH"

# Edit the Exec and Icon lines in the desktop file
echo "[INFO] Updating Exec and Icon lines in the desktop file..."
sed -i "s|^Exec=.*|Exec=bash $SCRIPT_FILE|" "$DESKTOP_FILE"
sed -i "s|^Icon=.*|Icon=$ICON_PATH|" "$DESKTOP_FILE"

echo "[INFO] Making .desktop file executable..."
chmod +x "$DESKTOP_FILE"

echo "[DONE] Vapor shortcut, script, and icon installed successfully!"
