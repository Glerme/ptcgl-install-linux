#!/usr/bin/env bash
# Main installer for Pokémon TCG Live on Linux.
# Usage: ./install.sh [/path/to/PokemonTCGLiveInstaller.msi]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/deps.sh"
source "${SCRIPT_DIR}/lib/proton.sh"

# ── 1. Dependency check ────────────────────────────────────────────────────────
install_deps

# ── 2. Install Heroic via Flatpak ─────────────────────────────────────────────
step "Installing Heroic Games Launcher (Flatpak)"
if flatpak info --user "$HEROIC_FLATPAK" &>/dev/null; then
    success "Heroic already installed"
else
    flatpak install --user -y flathub "$HEROIC_FLATPAK" \
        || die "Failed to install Heroic via Flatpak."
    success "Heroic installed"
fi

# Ensure Heroic config dirs exist (Heroic creates them on first GUI launch,
# but we need them now for our scripts).
mkdir -p "$HEROIC_CONFIG" "$HEROIC_TOOLS" "$HEROIC_GAMES_CONFIG" \
    "$(dirname "$HEROIC_SIDELOAD_LIB")"

# ── 3. Download Proton-GE-Latest ───────────────────────────────────────────────
install_proton_ge  # sets and exports PROTON_VERSION
PROTON_ROOT="${HEROIC_TOOLS}/${PROTON_VERSION}"
PROTON_BIN="${PROTON_ROOT}/proton"

# ── 4. Locate MSI installer ────────────────────────────────────────────────────
step "Locating MSI installer"
MSI_PATH="${1:-}"

if [[ -z "$MSI_PATH" ]]; then
    local_msi="${HOME}/Downloads/PokemonTCGLiveInstaller.msi"
    if [[ -f "$local_msi" ]]; then
        MSI_PATH="$local_msi"
        info "Found MSI at ${MSI_PATH}"
    else
        read -rp "Enter full path to PokemonTCGLiveInstaller.msi: " MSI_PATH
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

# ── 6. Write Heroic sideload entry ────────────────────────────────────────────
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

# ── 7. Write state file ────────────────────────────────────────────────────────
step "Saving install state"
mkdir -p "$STATE_DIR"
cat > "$STATE_FILE" <<EOF
# Generated by install.sh — do not edit manually
PROTON_VERSION="${PROTON_VERSION}"
PREFIX_PARENT="${PREFIX_PARENT}"
EOF
success "State file written: ${STATE_FILE}"

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
echo -e "  Launch via Heroic:  ${BOLD}flatpak run ${HEROIC_FLATPAK}${RESET}"
echo -e "  Launch directly:    ${BOLD}./launch.sh${RESET}"
echo ""
echo -e "  First-time login: click 'Login' in game, complete in browser."
echo -e "  The auth callback is handled automatically."
echo ""
