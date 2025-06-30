#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$TARGET_DIR/AutoDepot.desktop"
DESKTOP_URL="https://raw.githubusercontent.com/dim-ghub/AutoDepot/refs/heads/main/AutoDepot.desktop"

SCRIPT_DIR="$HOME/AutoDepot"
SCRIPT_FILE="$SCRIPT_DIR/AutoDepot.sh"
SCRIPT_URL="https://raw.githubusercontent.com/dim-ghub/AutoDepot/refs/heads/main/AutoDepot.sh"

echo "[INFO] Creating applications directory if needed..."
mkdir -p "$TARGET_DIR"

echo "[INFO] Downloading AutoDepot.desktop..."
curl -fsSL "$DESKTOP_URL" -o "$DESKTOP_FILE"

echo "[INFO] Creating AutoDepot directory if needed..."
mkdir -p "$SCRIPT_DIR"

echo "[INFO] Downloading AutoDepot.sh script..."
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_FILE"

echo "[INFO] Making AutoDepot.sh executable..."
chmod +x "$SCRIPT_FILE"

# Edit the Exec line in the desktop file to point to the local script with absolute path
echo "[INFO] Updating Exec line in the desktop file..."
sed -i "s|^Exec=.*|Exec=bash $SCRIPT_FILE|" "$DESKTOP_FILE"

echo "[INFO] Making .desktop file executable..."
chmod +x "$DESKTOP_FILE"

echo "[DONE] AutoDepot shortcut and script installed successfully!"
