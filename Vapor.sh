#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/Vapor"
VENV_DIR="$BASE_DIR/venv"
PYGOB_DIR="$BASE_DIR/pygob"
DEPOTS_DIR="$BASE_DIR/depots"
PYTHON_BIN="$VENV_DIR/bin/python"
ENCODED_REQS_URL="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL1N0ZWFtQXV0b0NyYWNrcy9EZXBvdERvd25sb2FkZXJNb2QvcmVmcy9oZWFkcy9tYXN0ZXIvU2NyaXB0cy9yZXF1aXJlbWVudHMudHh0"
REQS_URL=$(echo "$ENCODED_REQS_URL" | base64 --decode)
ENCODED_PY_FILE_URL="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL1N0ZWFtQXV0b0NyYWNrcy9EZXBvdERvd25sb2FkZXJNb2QvcmVmcy9oZWFkcy9tYXN0ZXIvU2NyaXB0cy9zdG9yYWdlX2RlcG90ZG93bmxvYWRlcm1vZC5weQ=="
PY_FILE_URL=$(echo "$ENCODED_PY_FILE_URL" | base64 --decode)
LOCAL_PY_FILE="$BASE_DIR/storage_depotdownloadermod.py"
RAR_PATH="$BASE_DIR/Release.rar"
RELEASE_DIR="$BASE_DIR/Release"

PYGOB_FILES=(
    "__init__.py"
    "dumper.py"
    "encoder.py"
    "loader.py"
    "types.py"
)

get_latest_release_rar_url() {
    local encoded_url="aHR0cHM6Ly9hcGkuZ2l0aHViLmNvbS9yZXBvcy9TdGVhbUF1dG9DcmFja3MvRGVwb3REb3dubG9hZGVyTW9kL3JlbGVhc2VzL2xhdGVzdA=="
    local decoded_url
    decoded_url=$(echo "$encoded_url" | base64 --decode)
    curl -s "$decoded_url" | jq -r '.assets[] | select(.name=="Release.rar") | .browser_download_url'
}

get_steam_libraries() {
    local vdf_file="$HOME/.local/share/Steam/config/libraryfolders.vdf"
    if [[ ! -f "$vdf_file" ]]; then
        echo "Error: Steam VDF file not found at $vdf_file" >&2
        exit 1
    fi

    local paths=()
    local inside_number_block=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^\"([0-9]+)\"[[:space:]]*\{$ ]]; then
            inside_number_block=1
            continue
        elif [[ "$line" =~ ^\}$ && $inside_number_block -eq 1 ]]; then
            inside_number_block=0
            continue
        fi
        if (( inside_number_block == 1 )) && [[ "$line" =~ \"path\"[[:space:]]+\"([^\"]+)\" ]]; then
            paths+=("${BASH_REMATCH[1]}")
        fi
    done < "$vdf_file"

    if (( ${#paths[@]} == 0 )); then
        while IFS= read -r line; do
            if [[ "$line" =~ \"path\"[[:space:]]+\"([^\"]+)\" ]]; then
                paths+=("${BASH_REMATCH[1]}")
            fi
        done < "$vdf_file"
    fi

    if (( ${#paths[@]} == 0 )); then
        echo "No Steam library paths found in $vdf_file" >&2
        exit 1
    fi

    for p in "${paths[@]}"; do
        echo "$p"
    done
}

find_target_dir() {
    local game="$1"
    while true; do
        for path in $(get_steam_libraries); do
            local fullpath="$path/steamapps/common/$game"
            if [[ -d "$fullpath" ]]; then
                echo "$fullpath"
                return 0
            fi
        done
        sleep 1
    done
}

download_files() {
    local base_url_encoded="aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL1N0ZWFtQXV0b0NyYWNrcy9EZXBvdERvd25sb2FkZXJNb2QvcmVmcy9oZWFkcy9tYXN0ZXIvU2NyaXB0cy9weWdvYg=="
    local base_url
    base_url=$(echo "$base_url_encoded" | base64 --decode)

    for file in "${PYGOB_FILES[@]}"; do
        curl -fsSL "${base_url}/${file}" -o "$PYGOB_DIR/$file"
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

    rm -rf "$DEPOTS_DIR"/*

    printf "%s\n1\n" "$appid" | PYTHONPATH="$BASE_DIR" "$PYTHON_BIN" "$LOCAL_PY_FILE"

    local rar_url
    rar_url=$(get_latest_release_rar_url)
    if [[ -z "$rar_url" ]]; then
        echo "Failed to get latest Release.rar URL" >&2
        exit 1
    fi

    curl -fsSL -o "$RAR_PATH" "$rar_url"
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

    local combined="$DEPOTS_DIR/$gamename"
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

    local target_dir
    target_dir=$(find_target_dir "$gamename")

    local random_subdir
    random_subdir=$(find "$combined" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [[ -d "$random_subdir" ]]; then
        cp -rf "$random_subdir/"* "$target_dir/"
    fi
}

interactive_cli() {
    mkdir -p "$BASE_DIR" "$PYGOB_DIR" "$DEPOTS_DIR"
    cd "$BASE_DIR"

    read -rp "Enter a Steam App ID or game name: " input
    [[ -z "$input" ]] && echo "You must enter a valid input. Exiting." && exit 1

    local APP_ID GAME_NAME

    if [[ "$input" =~ ^[0-9]+$ ]]; then
        APP_ID="$input"
        GAME_NAME=$(fetch_game_name "$APP_ID")
        [[ -z "$GAME_NAME" ]] && echo "Could not retrieve game name. Exiting." && exit 1
    else
        local term
        term=$(printf "%s" "$input" | jq -sRr @uri)
        mapfile -t results < <(
            curl -s "https://store.steampowered.com/api/storesearch/?term=$term&cc=us&l=en" \
            | jq -r '.items[] | "\(.id)::\(.name)"'
        )

        [[ ${#results[@]} -eq 0 ]] && echo "No results found. Try a different name." && exit 1

        echo "Select a game:"
        for i in "${!results[@]}"; do
            echo "$((i+1))) ${results[i]##*::}"
        done
        read -rp "Choice [1-${#results[@]}]: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] || exit 1
        ((choice--))
        [[ $choice -lt 0 || $choice -ge ${#results[@]} ]] && exit 1

        APP_ID="${results[choice]%%::*}"
        GAME_NAME="${results[choice]##*::}"
    fi

    echo "Installing: $GAME_NAME (AppID: $APP_ID)"

    download_files
    setup_venv_and_deps
    install_game_core "$APP_ID" "$GAME_NAME"

    echo "Game installed successfully! Have fun playing."
}

install_slssteam() {
    cd "$HOME" || exit 1

    rm -rf SLSsteam

    local git_url_encoded="aHR0cHM6Ly9naXRodWIuY29tL0FjZVNMUy9TTFNzdGVhbQ=="
    local git_url
    git_url=$(echo "$git_url_encoded" | base64 --decode)

    git clone "$git_url"
    cd SLSsteam || exit 1

    make

    mkdir -p ~/.local/share/SLSsteam
    cp bin/SLSsteam.so ~/.local/share/SLSsteam/SLSsteam.so

    local patch_line='export LD_AUDIT="$HOME/.local/share/SLSsteam/SLSsteam.so"'

    pkexec bash -c "
      sed -i '/LD_AUDIT=.*SLSsteam.so/d' /usr/bin/steam
      sed -i '2i $patch_line' /usr/bin/steam
    "

    cd "$HOME" || exit 1
    rm -rf SLSsteam

    zenity --info --text="SLSsteam installed and /usr/bin/steam patched successfully!" --width=300 --height=100
}

patch_with_steamless() {
    mkdir -p "$BASE_DIR"
    local libraries=($(get_steam_libraries))
    local games=()

    for lib in "${libraries[@]}"; do
        local manifest_dir="$lib/steamapps"
        for mf in "$manifest_dir"/appmanifest_*.acf; do
            [[ -f "$mf" ]] || continue
            local appid name
            appid=$(grep '"appid"' "$mf" | grep -oE '[0-9]+')
            name=$(grep '"name"' "$mf" | head -n1 | sed -E 's/.*"name"[[:space:]]+"([^"]+)".*/\1/')
            [[ -n "$appid" && -n "$name" ]] && games+=("$appid::$name")
        done
    done

    if [[ ${#games[@]} -eq 0 ]]; then
        if [ -t 0 ]; then
            echo "No installed Steam games found."
        else
            zenity --error --text="No installed Steam games found."
        fi
        return
    fi

    local selection=""
    local selected_appid=""
    if [ -t 0 ]; then
        echo "Select a game to patch:"
        for i in "${!games[@]}"; do
            echo "$((i+1))) ${games[i]##*::}"
        done
        read -rp "Choice: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] || return
        ((choice--))
        [[ $choice -lt 0 || $choice -ge ${#games[@]} ]] && return
        selection="${games[choice]##*::}"
        selected_appid="${games[choice]%%::*}"
    else
        selection=$(zenity --list --title="Select Game" --column="Game" --width=500 --height=400 "${games[@]##*::}")
        [[ -z "$selection" ]] && return
        for g in "${games[@]}"; do
            if [[ "${g##*::}" == "$selection" ]]; then
                selected_appid="${g%%::*}"
                break
            fi
        done
        [[ -z "$selected_appid" ]] && zenity --error --text="App ID not found." && return
    fi

    local game_dir=""
    for lib in "${libraries[@]}"; do
        for d in "$lib/steamapps/common/"*; do
            [[ -d "$d" ]] || continue
            if [[ "$(basename "$d")" == "$selection" ]]; then
                game_dir="$d"
                break 2
            fi
        done
    done

    if [[ -z "$game_dir" ]]; then
        if [ -t 0 ]; then
            echo "Could not find game folder for '$selection'"
        else
            zenity --error --text="Could not find game folder for '$selection'"
        fi
        return 1
    fi

    cd "$BASE_DIR" || return 1

    local steamless_url_encoded="aHR0cHM6Ly9naXRodWIuY29tL2F0b20wcy9TdGVhbWxlc3MvcmVsZWFzZXMvZG93bmxvYWQvdjMuMS4wLjUvU3RlYW1sZXNzLnYzLjEuMC41Li0uYnkuYXRvbTBzLnppcA=="
    local steamless_url
    steamless_url=$(echo "$steamless_url_encoded" | base64 --decode)

    if ! curl -fL --retry 3 --retry-delay 2 -o steamless.zip "$steamless_url"; then
        if [ -t 0 ]; then
            echo "Error: Failed to download Steamless from $steamless_url"
        else
            zenity --error --text="Failed to download Steamless from:\n$steamless_url"
        fi
        return 1
    fi

    rm -rf steamless
    mkdir -p steamless
    if ! unzip -o steamless.zip -d steamless > /dev/null; then
        if [ -t 0 ]; then
            echo "Error: Failed to unzip steamless.zip"
        else
            zenity --error --text="Failed to unzip steamless.zip"
        fi
        return 1
    fi

    rm -f steamless.zip

    if [[ ! -f steamless/Steamless.CLI.exe ]]; then
        if [ -t 0 ]; then
            echo "Error: Steamless.CLI.exe not found after extraction"
        else
            zenity --error --text="Steamless.CLI.exe not found in extracted files"
        fi
        return 1
    fi

    mapfile -t exe_list < <(find "$game_dir" -type f -iname "*.exe")

    if [[ ${#exe_list[@]} -eq 0 ]]; then
        if [ -t 0 ]; then
            echo "No .exe files found in game folder."
        else
            zenity --error --text="No .exe files found in game folder."
        fi
        return 1
    fi

    local exe_choice=""
    if [ -t 0 ]; then
        echo "Available EXE files:"
        for i in "${!exe_list[@]}"; do
            echo "$((i+1))) ${exe_list[i]}"
        done
        read -rp "Choice: " exe_index
        [[ "$exe_index" =~ ^[0-9]+$ ]] || return
        ((exe_index--))
        exe_choice="${exe_list[exe_index]}"
    else
        exe_choice=$(zenity --list --title="Choose EXE to Patch" \
            --text="Select an .exe to patch using Steamless" \
            --column="Executable Path" \
            --width=700 --height=400 "${exe_list[@]}")
        [[ -z "$exe_choice" ]] && return
    fi

    WINEDEBUG=-all wine "$BASE_DIR/steamless/Steamless.CLI.exe" "$exe_choice"

    if [[ -f "$exe_choice.unpacked.exe" ]]; then
        mv "$exe_choice" "$exe_choice.bak"
        mv "$exe_choice.unpacked.exe" "$exe_choice"
        if [ -t 0 ]; then
            echo "Executable unpacked and patched successfully!"
        else
            zenity --info --text="Executable unpacked and patched successfully!"
        fi
    else
        if [ -t 0 ]; then
            echo "Unpacking failed. No output file created."
        else
            zenity --error --text="Unpacking failed. No output file created."
        fi
    fi
}

patch_with_goldberg() {
    mkdir -p "$BASE_DIR"

    local goldberg_url_encoded="aHR0cHM6Ly9naXRsYWIuY29tL01yX0dvbGRiZXJnL2dvbGRiZXJnX2VtdWxhdG9yLy0vam9icy80MjQ3ODExMzEwL2FydGlmYWN0cy9kb3dubG9hZA=="
    local goldberg_url
    goldberg_url=$(echo "$goldberg_url_encoded" | base64 --decode)

    local goldberg_zip="$BASE_DIR/Goldberg.zip"
    local goldberg_dir="$BASE_DIR/Goldberg"
    local find_interfaces_script="$goldberg_dir/linux/tools/find_interfaces.sh"

    rm -rf "$goldberg_dir"
    mkdir -p "$goldberg_dir"

    if ! curl -L -o "$goldberg_zip" "$goldberg_url"; then
        [ -t 0 ] && echo "Failed to download Goldberg archive." || zenity --error --text="Failed to download Goldberg archive."
        return 1
    fi

    unzip -q "$goldberg_zip" -d "$goldberg_dir"
    rm -f "$goldberg_zip"

    local libraries=($(get_steam_libraries))
    local games=()

    for lib in "${libraries[@]}"; do
        for mf in "$lib/steamapps/appmanifest_"*.acf; do
            [[ -f "$mf" ]] || continue
            local appid name
            appid=$(grep '"appid"' "$mf" | grep -oE '[0-9]+')
            name=$(grep '"name"' "$mf" | head -n1 | sed -E 's/.*"name"[[:space:]]+"([^"]+)".*/\1/')
            [[ -n "$appid" && -n "$name" ]] && games+=("$appid::$name")
        done
    done

    if [[ ${#games[@]} -eq 0 ]]; then
        [ -t 0 ] && echo "No installed Steam games found." || zenity --error --text="No installed Steam games found."
        return
    fi

    local selected_appid="" selection=""
    if [ -t 0 ]; then
        echo "Select a game to patch with Goldberg:"
        for i in "${!games[@]}"; do
            echo "$((i+1))) ${games[i]##*::}"
        done
        read -rp "Choice: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] || return
        ((choice--))
        [[ $choice -lt 0 || $choice -ge ${#games[@]} ]] && return
        selection="${games[choice]##*::}"
        selected_appid="${games[choice]%%::*}"
    else
        selection=$(zenity --list --title="Select Game to Patch with Goldberg" --column="Game" --width=500 --height=400 "${games[@]##*::}")
        [[ -z "$selection" ]] && return
        for g in "${games[@]}"; do
            if [[ "${g##*::}" == "$selection" ]]; then
                selected_appid="${g%%::*}"
                break
            fi
        done
        [[ -z "$selected_appid" ]] && zenity --error --text="App ID not found." && return
    fi

    local game_dir=""
    for lib in "${libraries[@]}"; do
        for d in "$lib/steamapps/common/"*; do
            [[ -d "$d" ]] || continue
            if [[ "$(basename "$d")" == "$selection" ]]; then
                game_dir="$d"
                break 2
            fi
        done
    done

    if [[ -z "$game_dir" ]]; then
        [ -t 0 ] && echo "Could not find game folder for '$selection'" || zenity --error --text="Could not find game folder for '$selection'"
        return 1
    fi

    local dll_file
    dll_file=$(find "$game_dir" -type f \( -iname "steam_api.dll" -o -iname "steam_api64.dll" \) | head -n 1)

    if [[ -z "$dll_file" ]]; then
        [ -t 0 ] && echo "No Steam API DLL file found inside game directory." || zenity --error --text="No Steam API DLL file found inside game directory."
        return 1
    fi

    if [[ ! -x "$find_interfaces_script" ]]; then
        [ -t 0 ] && echo "Warning: find_interfaces.sh script not found or not executable." || zenity --warning --text="Warning: find_interfaces.sh script not found or not executable."
    else
        sh "$find_interfaces_script" "$dll_file" > "$(dirname "$dll_file")/steam_interfaces.txt"
    fi

    cp -f "$dll_file" "$dll_file.bak"
    cp -f "$goldberg_dir/$(basename "$dll_file")" "$dll_file"

    if [[ -z "$selected_appid" ]]; then
        if [ -t 0 ]; then
            read -rp "AppID not found automatically. Enter AppID for '$selection': " selected_appid
            if [[ -z "$selected_appid" ]]; then
                echo "No AppID provided. Aborting."
                return 1
            fi
        else
            selected_appid=$(zenity --entry --title="Enter AppID" --text="AppID not found automatically for $selection. Please enter AppID:" --width=300)
            if [[ -z "$selected_appid" ]]; then
                zenity --error --text="No AppID provided. Aborting."
                return 1
            fi
        fi
    fi

    echo "$selected_appid" > "$(dirname "$dll_file")/steam_appid.txt"

    [ -t 0 ] && echo "Goldberg emulator patched '$selection' successfully." || zenity --info --text="Goldberg emulator patched '$selection' successfully." --width=350 --height=100
}

setup_sme() {
    local sme_dir="$BASE_DIR/SME"
    local repo_url="https://github.com/tralph3/Steam-Metadata-Editor.git"

    rm -rf "$sme_dir"
    if ! git clone "$repo_url" "$sme_dir"; then
        if [[ -t 1 ]]; then
            echo "[ERROR] Failed to clone SME"
        else
            zenity --error --text="[ERROR] Failed to clone SME" --no-wrap
        fi
        return 1
    fi

    find "$sme_dir" -mindepth 1 -maxdepth 1 ! -name src -exec rm -rf {} +
    mv "$sme_dir/src/"* "$sme_dir/"
    rm -rf "$sme_dir/src"

    if [[ -t 1 ]]; then
        echo "[INFO] SME setup complete at $sme_dir"
    else
        zenity --info --text="[INFO] SME setup complete at $sme_dir" --no-wrap
    fi
}

run_sme() {
    if ! /usr/bin/env python3 "$BASE_DIR/SME/main.py" "$@"; then
        if [[ -t 1 ]]; then
            echo "[ERROR] Failed to run SME"
        else
            zenity --error --text="[ERROR] Failed to run SME" --no-wrap
        fi
        return 1
    fi
}

gui_install_game() {
    mkdir -p "$BASE_DIR" "$PYGOB_DIR" "$DEPOTS_DIR"
    cd "$BASE_DIR"

    local input
    input=$(zenity --entry --title="Enter Game" --text="Enter a Steam App ID or game name:" --width=300)
    [[ -z "$input" ]] && zenity --error --text="Input required. Exiting." && exit 1

    local APP_ID GAME_NAME

    if [[ "$input" =~ ^[0-9]+$ ]]; then
        APP_ID="$input"
        GAME_NAME=$(fetch_game_name "$APP_ID")
        [[ -z "$GAME_NAME" ]] && zenity --error --text="Could not retrieve game name. Exiting." && exit 1
    else
        local term
        term=$(printf "%s" "$input" | jq -sRr @uri)
        mapfile -t results < <(
            curl -s "https://store.steampowered.com/api/storesearch/?term=$term&cc=us&l=en" \
            | jq -r '.items[] | "\(.id)::\(.name)"'
        )

        [[ ${#results[@]} -eq 0 ]] && zenity --error --text="No results found. Try a different name." && exit 1

        local choice
        choice=$(zenity --list --title="Select Game" --column="Game" "${results[@]##*::}")
        [[ -z "$choice" ]] && zenity --error --text="No game selected." && exit 1

        for r in "${results[@]}"; do
            if [[ "${r##*::}" == "$choice" ]]; then
                APP_ID="${r%%::*}"
                GAME_NAME="$choice"
                break
            fi
        done
    fi

    yad --title="Vapor Installer" \
        --text="Installing game...\n\nJust sit back and relax, you'll be notified when the game is installed." \
        --borders=10 --center --width=350 --button=OK &

    download_files
    setup_venv_and_deps
    install_game_core "$APP_ID" "$GAME_NAME"

    yad --title="Vapor Installer" \
        --text="Game installed successfully!\n\nHave fun playing!" \
        --borders=10 --center --width=350 --button=OK

    echo "[DONE] All steps completed successfully."
}

gui_menu() {
    local choice
    choice=$(zenity --list \
        --title="Vapor Menu" \
        --column="Option" --column="Description" \
        --width=450 --height=300 \
        --hide-column=0 \
        1 "Download & install game by Steam App ID" \
        2 "Install SLSsteam" \
        3 "Patch with Steamless" \
        4 "Patch with Goldberg" \
        5 "Install Steam Metadata Editor" \
        6 "Run Steam Metadata Editor")

    if [[ -z "$choice" ]]; then
        exit 0
    fi

    case "$choice" in
        1) gui_install_game ;;
        2) install_slssteam ;;
        3) patch_with_steamless ;;
        4) patch_with_goldberg ;;
        5) setup_sme ;;
        6) run_sme ;;
        *) zenity --error --text="No valid option selected. Exiting." --width=300 --height=100; exit 1 ;;
    esac
}

if [ -t 0 ]; then
    main_menu() {
        while true; do
            echo "==== Vapor Menu ===="
            echo "1) Download & install game by Steam App ID"
            echo "2) Install SLSsteam"
            echo "3) Patch with Steamless"
            echo "4) Patch with Goldberg"
            echo "5) Install Steam Metadata Editor"
            echo "6) Run Steam Metadata Editor"
            echo "7) Exit"
            echo "========================"
            read -rp "Choose an option [1-7]: " choice
            case "$choice" in
                1) interactive_cli ;;
                2) install_slssteam ;;
                3) patch_with_steamless ;;
                4) patch_with_goldberg ;;
                5) setup_sme ;;
                6) run_sme ;;
                7) echo "Exiting."; exit 0 ;;
                *) echo "Invalid choice. Try again." ;;
            esac
        done
    }
    main_menu
else
    gui_menu
fi
