#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/AutoDepot"
VENV_DIR="$BASE_DIR/venv"
PYGOB_DIR="$BASE_DIR/pygob"
DEPOTS_DIR="$BASE_DIR/depots"
PYTHON_BIN="$VENV_DIR/bin/python"
REQS_URL="https://raw.githubusercontent.com/SteamAutoCracks/DepotDownloaderMod/refs/heads/master/Scripts/requirements.txt"
PY_FILE_URL="https://raw.githubusercontent.com/SteamAutoCracks/DepotDownloaderMod/refs/heads/master/Scripts/storage_depotdownloadermod.py"
LOCAL_PY_FILE="$BASE_DIR/storage_depotdownloadermod.py"
RAR_URL="https://github.com/SteamAutoCracks/DepotDownloaderMod/releases/download/DepotDownloaderMod_3.4.0.2/Release.rar"
RAR_PATH="$BASE_DIR/Release.rar"
RELEASE_DIR="$BASE_DIR/Release"
STEAM_COMMON="$HOME/.local/share/Steam/steamapps/common"

PYGOB_FILES=(
    "__init__.py"
    "dumper.py"
    "encoder.py"
    "loader.py"
    "types.py"
)

# Check if on Arch Linux
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "arch" ]]; then
        echo "This script is intended for Arch Linux only."
        exit 1
    fi
else
    echo "Cannot detect OS. Exiting."
    exit 1
fi

mkdir -p "$BASE_DIR" "$PYGOB_DIR" "$DEPOTS_DIR"

# Install unrar and jq if not present
for tool in unrar jq; do
    if ! command -v "$tool" &>/dev/null; then
        echo "[INFO] '$tool' not found, installing..."
        pkexec pacman -Sy "$tool" --needed
    else
        echo "[INFO] '$tool' is already installed."
    fi
done

# Download pygob files
echo "[INFO] Downloading pygob module files..."
for file in "${PYGOB_FILES[@]}"; do
    curl -fsSL "https://raw.githubusercontent.com/SteamAutoCracks/DepotDownloaderMod/refs/heads/master/Scripts/pygob/$file" -o "$PYGOB_DIR/$file"
done

# Download the main Python script locally
echo "[INFO] Downloading main python script..."
curl -fsSL "$PY_FILE_URL" -o "$LOCAL_PY_FILE"

# Create venv if missing
if [[ ! -d "$VENV_DIR" ]]; then
    echo "[INFO] Creating python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Upgrade pip and install dependencies
"$PYTHON_BIN" -m pip install --upgrade pip
TMP_REQS="$(mktemp)"
curl -fsSL "$REQS_URL" -o "$TMP_REQS"
"$PYTHON_BIN" -m pip install -r "$TMP_REQS"
"$PYTHON_BIN" -m pip install pycryptodome
rm "$TMP_REQS"

# Prompt user for appid
read -rp "Enter the appid: " APP_ID

# Get game name from Steam API
GAME_NAME=$(curl -s "https://store.steampowered.com/api/appdetails?appids=$APP_ID" | jq -r ".\"$APP_ID\".data.name")
if [[ "$GAME_NAME" == "null" || -z "$GAME_NAME" ]]; then
    echo "[WARN] Could not retrieve game name. Proceeding without it."
    GAME_NAME="UnknownGame_$APP_ID"
else
    echo "[INFO] Game detected: $GAME_NAME"
fi

# Clean up any old .bat, .key, and .manifest files
echo "[INFO] Cleaning up old .bat, .key, and .manifest files..."
find "$BASE_DIR" -type f \( -name "*.bat" -o -name "*.key" -o -name "*.manifest" \) -delete

# Run the Python script with appid and 1 as stdin
echo "[INFO] Running Python script..."
printf "%s\n1\n" "$APP_ID" | PYTHONPATH="$BASE_DIR" "$PYTHON_BIN" "$LOCAL_PY_FILE"

# --- PREPARE .NET RUNTIME BEFORE .BAT ---
echo "[INFO] Downloading Release.rar..."
curl -fsSL -o "$RAR_PATH" "$RAR_URL"

echo "[INFO] Extracting Release.rar..."
unrar x -o+ "$RAR_PATH" "$BASE_DIR"

NET_DIR="$RELEASE_DIR/net9.0"
echo "[INFO] Copying .json, .dll, and .exe files from net9.0 to $BASE_DIR..."
find "$NET_DIR" -type f \( -name "*.json" -o -name "*.dll" -o -name "*.exe" \) -exec cp -f {} "$BASE_DIR/" \;

echo "[INFO] Cleaning up extracted files..."
rm -f "$RAR_PATH"
rm -rf "$RELEASE_DIR"

# --- RUN THE .BAT FILE ---
BAT_FILE="$BASE_DIR/${APP_ID}.bat"
if [[ -f "$BAT_FILE" ]]; then
    echo "[INFO] Running $BAT_FILE..."
    WINEDEBUG=-all wine "$BAT_FILE"
else
    echo "[ERROR] Expected .bat file not found: $BAT_FILE"
    exit 1
fi

# --- WAIT FOR DEPOTS TO POPULATE ---
echo "[INFO] Waiting for depots to populate..."
while [ -z "$(ls -A "$DEPOTS_DIR")" ]; do
    sleep 1
done

# --- MERGE DEPOT FOLDERS ---
COMBINED_DIR="$DEPOTS_DIR/$APP_ID"
mkdir -p "$COMBINED_DIR"

echo "[INFO] Merging depots into $COMBINED_DIR..."
shopt -s dotglob
for d in "$DEPOTS_DIR"/*/ ; do
    [[ "$d" == "$COMBINED_DIR/" ]] && continue
    cp -rn "$d"* "$COMBINED_DIR/"
done
shopt -u dotglob

# --- CLEANUP UNUSED DEPOT FOLDERS ---
echo "[INFO] Removing all other folders in depots except $APP_ID..."
for d in "$DEPOTS_DIR"/*; do
    [[ "$d" == "$COMBINED_DIR" ]] && continue
    rm -rf "$d"
done

# --- LAUNCH GAME AND DISOWN STEAM ---
echo "[INFO] Launching game through Steam..."
steam "steam://rungameid/$APP_ID" & disown

# --- WAIT FOR GAME INSTALL FOLDER ---
TARGET_GAME_DIR="$STEAM_COMMON/$GAME_NAME"
echo "[INFO] Waiting for game folder: $TARGET_GAME_DIR"
while [[ ! -d "$TARGET_GAME_DIR" ]]; do
    sleep 1
done
echo "[INFO] Game directory detected."

# --- MOVE EXTRACTED CONTENT INTO GAME DIR ---
echo "[INFO] Searching for random-numbered subdir in $COMBINED_DIR..."
RANDOM_SUBDIR=$(find "$COMBINED_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [[ -d "$RANDOM_SUBDIR" ]]; then
    echo "[INFO] Moving contents of $RANDOM_SUBDIR to $TARGET_GAME_DIR..."
    cp -rf "$RANDOM_SUBDIR/"* "$TARGET_GAME_DIR/"
else
    echo "[WARN] No subfolder found inside $COMBINED_DIR"
fi

echo "[DONE] All steps completed successfully."

notify-send "Game installed. Have fun!"
