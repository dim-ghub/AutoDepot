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
        zenity --error --text="This script is intended for Arch Linux only."
        exit 1
    fi
else
    zenity --error --text="Cannot detect OS. Exiting."
    exit 1
fi

# Ensure dependencies jq, unrar, yad
for tool in unrar jq yad; do
    if ! command -v "$tool" &>/dev/null; then
        zenity --info --text="'$tool' not found, installing..."
        pkexec pacman -Sy "$tool" --needed
    fi
done

mkdir -p "$BASE_DIR" "$PYGOB_DIR" "$DEPOTS_DIR"
cd "$BASE_DIR"

# Prompt for App ID with zenity
APP_ID=$(zenity --entry \
    --title="Enter Steam App ID" \
    --text="Please enter the Steam App ID:" \
    --width=300)

if [[ -z "$APP_ID" ]]; then
    zenity --error --text="You must enter a valid App ID. Exiting."
    exit 1
fi

# Show warning dialog that closing won't stop installation
yad --title="AutoDepot Installer" \
    --text="Installing game...\n\nJust sit back and relax, you'll be notified when the game is installed." \
    --borders=10 \
    --center \
    --width=350 \
    --button=OK

function install_game() {
    # Download pygob files
    for file in "${PYGOB_FILES[@]}"; do
        curl -fsSL "https://raw.githubusercontent.com/SteamAutoCracks/DepotDownloaderMod/refs/heads/master/Scripts/pygob/$file" -o "$PYGOB_DIR/$file"
    done

    # Download main python script
    curl -fsSL "$PY_FILE_URL" -o "$LOCAL_PY_FILE"

    # Create venv if missing
    if [[ ! -d "$VENV_DIR" ]]; then
        python3 -m venv "$VENV_DIR"
    fi

    # Upgrade pip and install dependencies
    "$PYTHON_BIN" -m pip install --upgrade pip
    TMP_REQS="$(mktemp)"
    curl -fsSL "$REQS_URL" -o "$TMP_REQS"
    "$PYTHON_BIN" -m pip install -r "$TMP_REQS"
    "$PYTHON_BIN" -m pip install pycryptodome
    rm "$TMP_REQS"

    # Get game name from Steam API
    GAME_NAME=$(curl -s "https://store.steampowered.com/api/appdetails?appids=$APP_ID" | jq -r ".\"$APP_ID\".data.name")
    if [[ "$GAME_NAME" == "null" || -z "$GAME_NAME" ]]; then
        zenity --warning --text="Could not retrieve game name. Proceeding without it."
        GAME_NAME="UnknownGame_$APP_ID"
    fi

    # Clean up old .bat, .key, and .manifest files
    find "$BASE_DIR" -type f \( -name "*.bat" -o -name "*.key" -o -name "*.manifest" \) -delete

    # Run the Python script with appid and 1 as stdin
    printf "%s\n1\n" "$APP_ID" | PYTHONPATH="$BASE_DIR" "$PYTHON_BIN" "$LOCAL_PY_FILE"

    # Download Release.rar and extract runtime files
    curl -fsSL -o "$RAR_PATH" "$RAR_URL"
    unrar x -o+ "$RAR_PATH" "$BASE_DIR"
    NET_DIR="$RELEASE_DIR/net9.0"
    find "$NET_DIR" -type f \( -name "*.json" -o -name "*.dll" -o -name "*.exe" \) -exec cp -f {} "$BASE_DIR/" \;
    rm -f "$RAR_PATH"
    rm -rf "$RELEASE_DIR"

    # Run the .bat file
    BAT_FILE="$BASE_DIR/${APP_ID}.bat"
    if [[ -f "$BAT_FILE" ]]; then
        WINEDEBUG=-all wine "$BAT_FILE"
    else
        zenity --error --text="Expected .bat file not found: $BAT_FILE"
        kill "$YAD_PID" 2>/dev/null || true
        exit 1
    fi

    # Wait for depots folder population
    while [ -z "$(ls -A "$DEPOTS_DIR")" ]; do
        sleep 1
    done

    # Merge depot folders
    COMBINED_DIR="$DEPOTS_DIR/$APP_ID"
    mkdir -p "$COMBINED_DIR"
    shopt -s dotglob
    for d in "$DEPOTS_DIR"/*/ ; do
        [[ "$d" == "$COMBINED_DIR/" ]] && continue
        cp -rn "$d"* "$COMBINED_DIR/"
    done
    shopt -u dotglob

    # Remove all other folders except combined
    for d in "$DEPOTS_DIR"/*; do
        [[ "$d" == "$COMBINED_DIR" ]] && continue
        rm -rf "$d"
    done

    # Launch Steam game and disown process
    steam "steam://rungameid/$APP_ID" & disown

    # Wait for game install folder
    TARGET_GAME_DIR="$STEAM_COMMON/$GAME_NAME"
    while [[ ! -d "$TARGET_GAME_DIR" ]]; do
        sleep 1
    done

    # Move extracted content into game folder
    RANDOM_SUBDIR=$(find "$COMBINED_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [[ -d "$RANDOM_SUBDIR" ]]; then
        cp -rf "$RANDOM_SUBDIR/"* "$TARGET_GAME_DIR/"
    fi
}

install_game

kill "$YAD_PID" 2>/dev/null || true

# Show completion dialog with yad
yad --title="AutoDepot Installer" \
    --text="Game installed successfully!\n\nHave fun playing!" \
    --borders=10 \
    --center \
    --width=350 \
    --button=OK

echo "[DONE] All steps completed successfully."
