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

check_os() {
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
}

install_dependencies() {
    for tool in unrar jq; do
        if ! command -v "$tool" &>/dev/null; then
            echo "'$tool' not found, installing..."
            pkexec pacman -Sy "$tool" --needed
        fi
    done
}

download_files() {
    for file in "${PYGOB_FILES[@]}"; do
        curl -fsSL "https://raw.githubusercontent.com/SteamAutoCracks/DepotDownloaderMod/refs/heads/master/Scripts/pygob/$file" -o "$PYGOB_DIR/$file"
    done
    curl -fsSL "$PY_FILE_URL" -o "$LOCAL_PY_FILE"
}

setup_venv_and_deps() {
    if [[ ! -d "$VENV_DIR" ]]; then
        python3 -m venv "$VENV_DIR"
    fi
    "$PYTHON_BIN" -m pip install --upgrade pip
    TMP_REQS="$(mktemp)"
    curl -fsSL "$REQS_URL" -o "$TMP_REQS"
    "$PYTHON_BIN" -m pip install -r "$TMP_REQS"
    "$PYTHON_BIN" -m pip install pycryptodome
    rm "$TMP_REQS"
}

fetch_game_name() {
    local appid=$1
    local name
    name=$(curl -s "https://store.steampowered.com/api/appdetails?appids=$appid" | jq -r ".\"$appid\".data.name")
    if [[ "$name" == "null" || -z "$name" ]]; then
        echo ""
    else
        echo "$name"
    fi
}

install_game_core() {
    local appid=$1
    local gamename=$2

    find "$BASE_DIR" -type f \( -name "*.bat" -o -name "*.key" -o -name "*.manifest" \) -delete

    printf "%s\n1\n" "$appid" | PYTHONPATH="$BASE_DIR" "$PYTHON_BIN" "$LOCAL_PY_FILE"

    curl -fsSL -o "$RAR_PATH" "$RAR_URL"
    unrar x -o+ "$RAR_PATH" "$BASE_DIR"
    local netdir="$RELEASE_DIR/net9.0"
    find "$netdir" -type f \( -name "*.json" -o -name "*.dll" -o -name "*.exe" \) -exec cp -f {} "$BASE_DIR/" \;
    rm -f "$RAR_PATH"
    rm -rf "$RELEASE_DIR"

    local batfile="$BASE_DIR/${appid}.bat"
    if [[ ! -f "$batfile" ]]; then
        echo "Expected .bat file not found: $batfile"
        exit 1
    fi

    WINEDEBUG=-all wine "$batfile"

    while [ -z "$(ls -A "$DEPOTS_DIR")" ]; do sleep 1; done

    local combined="$DEPOTS_DIR/$appid"
    mkdir -p "$combined"
    shopt -s dotglob
    for d in "$DEPOTS_DIR"/*/ ; do
        [[ "$d" == "$combined/" ]] && continue
        cp -rn "$d"* "$combined/"
    done
    shopt -u dotglob

    for d in "$DEPOTS_DIR"/*; do
        [[ "$d" == "$combined" ]] && continue
        rm -rf "$d"
    done

    steam "steam://rungameid/$appid" & disown

    local target_dir="$STEAM_COMMON/$gamename"
    while [[ ! -d "$target_dir" ]]; do sleep 1; done

    local random_subdir
    random_subdir=$(find "$combined" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [[ -d "$random_subdir" ]]; then
        cp -rf "$random_subdir/"* "$target_dir/"
    fi
}

interactive_cli() {
    check_os
    install_dependencies
    mkdir -p "$BASE_DIR" "$PYGOB_DIR" "$DEPOTS_DIR"
    cd "$BASE_DIR"

    read -rp "Enter Steam App ID: " APP_ID
    if [[ -z "$APP_ID" ]]; then
        echo "You must enter a valid App ID. Exiting."
        exit 1
    fi

    download_files
    setup_venv_and_deps

    GAME_NAME=$(fetch_game_name "$APP_ID")
    if [[ -z "$GAME_NAME" ]]; then
        echo "Could not retrieve game name. Proceeding without it."
        GAME_NAME="UnknownGame_$APP_ID"
    else
        echo "Game detected: $GAME_NAME"
    fi

    install_game_core "$APP_ID" "$GAME_NAME"
    echo "Game installed successfully! Have fun playing."
}

gui_mode() {
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

    for tool in unrar jq yad; do
        if ! command -v "$tool" &>/dev/null; then
            zenity --info --text="'$tool' not found, installing..."
            pkexec pacman -Sy "$tool" --needed
        fi
    done

    mkdir -p "$BASE_DIR" "$PYGOB_DIR" "$DEPOTS_DIR"
    cd "$BASE_DIR"

    APP_ID=$(zenity --entry --title="Enter Steam App ID" --text="Please enter the Steam App ID:" --width=300)
    if [[ -z "$APP_ID" ]]; then
        zenity --error --text="You must enter a valid App ID. Exiting."
        exit 1
    fi

    yad --title="AutoDepot Installer" \
        --text="Installing game...\n\nJust sit back and relax, you'll be notified when the game is installed." \
        --borders=10 \
        --center \
        --width=350 \
        --button=OK &

    download_files
    setup_venv_and_deps

    GAME_NAME=$(curl -s "https://store.steampowered.com/api/appdetails?appids=$APP_ID" | jq -r ".\"$APP_ID\".data.name")
    if [[ "$GAME_NAME" == "null" || -z "$GAME_NAME" ]]; then
        zenity --warning --text="Could not retrieve game name. Proceeding without it."
        GAME_NAME="UnknownGame_$APP_ID"
    else
        zenity --info --text="Game detected: $GAME_NAME"
    fi

    install_game_core "$APP_ID" "$GAME_NAME"

    yad --title="AutoDepot Installer" \
        --text="Game installed successfully!\n\nHave fun playing!" \
        --borders=10 \
        --center \
        --width=350 \
        --button=OK

    echo "[DONE] All steps completed successfully."
}

if [ -t 0 ]; then
    interactive_cli
else
    gui_mode
fi
