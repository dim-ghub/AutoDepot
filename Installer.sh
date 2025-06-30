#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$TARGET_DIR/AutoDepot.desktop"
DESKTOP_URL="https://raw.githubusercontent.com/dim-ghub/AutoDepot/refs/heads/main/AutoDepot.desktop"

echo "[INFO] Creating applications directory if needed..."
mkdir -p "$TARGET_DIR"

echo "[INFO] Downloading AutoDepot.desktop..."
curl -fsSL "$DESKTOP_URL" -o "$DESKTOP_FILE"

echo "[INFO] Making .desktop file executable..."
chmod +x "$DESKTOP_FILE"

echo "[DONE] AutoDepot shortcut installed successfully!"
