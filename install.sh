#!/usr/bin/env bash
# Main installer for Pokémon TCG Live on Linux.
# Usage: ./install.sh [--launcher heroic|lutris] [/path/to/PokemonTCGLiveInstaller.msi]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/deps.sh"
source "${SCRIPT_DIR}/lib/proton.sh"

MSI_PATH=""
LAUNCHER=""
while (( $# )); do
    case "$1" in
        --launcher)
            [[ $# -ge 2 ]] || die "--launcher requires heroic or lutris"
            case "$2" in
                heroic|lutris) LAUNCHER="$2" ;;
                *) die "Invalid launcher: $2 (expected heroic or lutris)" ;;
            esac
            shift 2
            ;;
        -*) die "Unknown option: $1" ;;
        *)
            [[ -z "$MSI_PATH" ]] || die "Only one MSI path is accepted."
            MSI_PATH="$1"
            shift
            ;;
    esac
done
if [[ -z "$LAUNCHER" && -t 0 ]]; then
    read -rp "Launcher [heroic/lutris] (heroic): " LAUNCHER
fi
LAUNCHER="${LAUNCHER:-heroic}"
case "$LAUNCHER" in
    heroic|lutris) ;;
    *) die "Invalid launcher: $LAUNCHER (expected heroic or lutris)" ;;
esac

# Preserve a previously saved prefix when refreshing or switching launchers.
if [[ -f "$STATE_FILE" ]]; then
    selected_launcher="$LAUNCHER"
    load_state
    LAUNCHER="$selected_launcher"
fi

# ── 1. Dependency check ────────────────────────────────────────────────────────
install_deps

# ── 2. Install selected launcher via Flatpak ───────────────────────────────────
if [[ "$LAUNCHER" == heroic ]]; then
    LAUNCHER_FLATPAK="$HEROIC_FLATPAK"
    mkdir -p "$HEROIC_CONFIG" "$HEROIC_TOOLS" "$HEROIC_GAMES_CONFIG" \
        "$(dirname "$HEROIC_SIDELOAD_LIB")"
else
    LAUNCHER_FLATPAK="$LUTRIS_FLATPAK"
fi
step "Installing $LAUNCHER (Flatpak)"
if flatpak info --user "$LAUNCHER_FLATPAK" &>/dev/null; then
    success "$LAUNCHER already installed"
else
    flatpak install --user -y flathub "$LAUNCHER_FLATPAK" \
        || die "Failed to install $LAUNCHER via Flatpak."
    success "$LAUNCHER installed"
fi

# ── 3. Download Proton-GE-Latest ───────────────────────────────────────────────
if [[ "$LAUNCHER" == heroic ]]; then
    install_proton_ge "$HEROIC_TOOLS"
else
    install_proton_ge "$LUTRIS_PROTON_TOOLS"
fi
PROTON_BIN="${PROTON_ROOT}/proton"
mkdir -p "$FAKE_STEAM_COMPAT"

if [[ -f "$GAME_EXE" ]]; then
    success "Game already installed — refreshing launcher and Proton only"
else
    # ── 4. Locate MSI installer ────────────────────────────────────────────────────
    step "Locating MSI installer"

    if [[ -z "$MSI_PATH" ]]; then
        local_msi="${HOME}/Downloads/PokemonTCGLiveInstaller.msi"
        if [[ -f "$local_msi" ]]; then
            MSI_PATH="$local_msi"
            info "Found MSI at ${MSI_PATH}"
        else
            read -rp "Enter full path to PokemonTCGLiveInstaller.msi: " MSI_PATH
            MSI_PATH="${MSI_PATH/#\~/$HOME}"
        fi
    fi

    [[ -f "$MSI_PATH" ]] || die "MSI not found at: ${MSI_PATH}"
    [[ "${MSI_PATH,,}" == *.msi ]] || die "File does not appear to be an MSI: ${MSI_PATH}"
    success "Using MSI: ${MSI_PATH}"

    # ── 5. Initialize Wine prefix + install game ───────────────────────────────────
    step "Setting up Wine prefix and installing game"

    mkdir -p "$PREFIX_PARENT" "$FAKE_STEAM_COMPAT"

    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$FAKE_STEAM_COMPAT"
    export STEAM_COMPAT_DATA_PATH="$PREFIX_PARENT"

    # First proton invocation initializes the prefix (creates pfx/, sets up DXVK/VKD3D).
    info "Initializing Wine prefix with Proton-GE ${PROTON_VERSION} ..."
    "$PROTON_BIN" run wineboot --init \
        || warn "wineboot --init returned non-zero (often harmless; continuing)"

    # Copy MSI into the prefix so msiexec can find it at a Windows path (C:\)
    MSI_STAGING="${WINE_PREFIX}/drive_c/ptcgl_install"
    mkdir -p "$MSI_STAGING"
    cp "$MSI_PATH" "${MSI_STAGING}/installer.msi"

    info "Running MSI installer (this will take 1-3 minutes) ..."
    "$PROTON_BIN" run msiexec /i 'C:\ptcgl_install\installer.msi' /passive /norestart \
        || warn "msiexec returned non-zero — checking if game installed anyway..."

    # Verify the exe is in place
    if [[ ! -f "$GAME_EXE" ]]; then
        error "Game exe not found at expected path:"
        error "  ${GAME_EXE}"
        error ""
        error "Possible causes:"
        error "  1. MSI install failed silently — try without /passive (run manually)."
        error "  2. Game installed to a different path — check inside ${WINE_PREFIX}/drive_c/"
        die "Installation verification failed."
    fi
    success "Game installed: ${GAME_EXE}"

    # Cleanup staging dir
    rm -rf "$MSI_STAGING"

fi

# ── 6. Write Heroic sideload entry ────────────────────────────────────────────
if [[ "$LAUNCHER" == heroic ]]; then
    step "Registering game in Heroic"

    # library.json must be valid JSON with .games array
    if [[ ! -f "$HEROIC_SIDELOAD_LIB" ]] || ! jq -e '.games' "$HEROIC_SIDELOAD_LIB" &>/dev/null; then
        echo '{"games": []}' > "$HEROIC_SIDELOAD_LIB"
    fi

    # Remove any existing entry for this app to avoid duplicates
    jq --arg app "$APP_NAME" '.games = [.games[] | select(.app_name != $app)]' \
        "$HEROIC_SIDELOAD_LIB" > "${HEROIC_SIDELOAD_LIB}.tmp" \
        && mv "${HEROIC_SIDELOAD_LIB}.tmp" "$HEROIC_SIDELOAD_LIB"

    # Add fresh entry
    jq --arg app "$APP_NAME" \
       --arg title "$GAME_TITLE" \
       --arg exe "$GAME_EXE" \
       '.games += [{
           "runner": "sideload",
           "app_name": $app,
           "title": $title,
           "art_cover": "",
           "art_square": "",
           "art_background": "",
           "is_installed": true,
           "install": { "executable": $exe, "platform": "Windows" },
           "canRunOffline": true
       }]' \
        "$HEROIC_SIDELOAD_LIB" > "${HEROIC_SIDELOAD_LIB}.tmp" \
        && mv "${HEROIC_SIDELOAD_LIB}.tmp" "$HEROIC_SIDELOAD_LIB"

    success "Sideload entry added to Heroic library"

    # GamesConfig/<app_name>.json — wine version + env vars for Heroic launcher
    GAME_CONFIG_FILE="${HEROIC_GAMES_CONFIG}/${APP_NAME}.json"
    cat > "$GAME_CONFIG_FILE" <<EOF
{
  "${APP_NAME}": {
    "wineVersion": {
      "bin": "${PROTON_BIN}",
      "name": "${PROTON_VERSION}",
      "type": "proton",
      "dir": "${PROTON_ROOT}/"
    },
    "winePrefix": "${PREFIX_PARENT}",
    "enviromentOptions": [
      { "key": "WINE_CPU_TOPOLOGY", "value": "2:0,1" },
      { "key": "STEAM_COMPAT_CLIENT_INSTALL_PATH", "value": "${FAKE_STEAM_COMPAT}" }
    ],
    "launcherArgs": ""
  }
}
EOF
    success "Heroic game config written: ${GAME_CONFIG_FILE}"

else
    step "Registering game in Lutris"
    mkdir -p "$LUTRIS_GAMES_DIR" "$LUTRIS_DATA"
    # Lutris' Linux runner launches Proton directly; its database API avoids an interactive installer.
    jq -n --arg proton "$PROTON_BIN" --arg exe "$GAME_EXE" \
        --arg prefix "$WINE_PREFIX" --arg parent "$PREFIX_PARENT" \
        --arg steam "$FAKE_STEAM_COMPAT" --arg title "$GAME_TITLE" '
        {name: $title, runner: "linux",
         game: {exe: $proton, args: ("run " + ($exe | @sh)), prefix: $prefix,
                working_dir: ($exe | split("/") | .[:-1] | join("/"))},
         system: {env: {WINE_CPU_TOPOLOGY: "2:0,1", WINEPREFIX: $prefix,
                       STEAM_COMPAT_DATA_PATH: $parent,
                       STEAM_COMPAT_CLIENT_INSTALL_PATH: $steam}}}' \
        > "$LUTRIS_GAMES_DIR/$APP_NAME.yml"
    # JSON is valid YAML, and preserves quotes and Unicode in user paths.
    flatpak run --command=python3 "$LUTRIS_FLATPAK" -c '
import sys
sys.path.insert(0, "/app/lib/lutris")
from lutris import settings
from lutris.database.schema import syncdb
from lutris.database.games import add_or_update
settings.DB_PATH = sys.argv[1]
syncdb()
add_or_update(name=sys.argv[2], slug=sys.argv[3], runner="linux",
              installed=1, configpath=sys.argv[3])
' "$LUTRIS_DATA/pga.db" "$GAME_TITLE" "$APP_NAME" \
        || die "Failed to register game in Lutris database."
    success "Lutris game config written: $LUTRIS_GAMES_DIR/$APP_NAME.yml"
fi

# ── 7. Write state file ────────────────────────────────────────────────────────
step "Saving install state"
mkdir -p "$STATE_DIR"
{
    echo '# Generated by install.sh — do not edit manually'
    printf 'LAUNCHER=%q\nPROTON_ROOT=%q\nPROTON_VERSION=%q\nPREFIX_PARENT=%q\n' \
        "$LAUNCHER" "$PROTON_ROOT" "$PROTON_VERSION" "$PREFIX_PARENT"
} > "$STATE_FILE"
success "State file written: ${STATE_FILE}"

cleanup_old_proton "$(dirname "$PROTON_ROOT")"

# ── 8. Register URI handler ────────────────────────────────────────────────────
step "Registering tpcitcgapp:// URI handler"
"${SCRIPT_DIR}/register-handler.sh" \
    || warn "URI handler registration failed — login will require manual steps."

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  PTCGL installed successfully!${RESET}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo ""
echo -e "  Launch via $LAUNCHER:  ${BOLD}flatpak run ${LAUNCHER_FLATPAK}${RESET}"
echo -e "  Launch directly:    ${BOLD}./launch.sh${RESET}"
echo ""
echo -e "  First-time login: click 'Login' in game, complete in browser."
echo -e "  The auth callback is handled automatically."
echo ""
