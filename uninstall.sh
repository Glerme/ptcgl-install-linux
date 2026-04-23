#!/usr/bin/env bash
# Removes all PTCGL Linux installer artifacts.
# Usage: ./uninstall.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

echo -e "${RED}${BOLD}PTCGL Linux Uninstaller${RESET}"
echo ""
echo "This will remove:"
echo "  - Game prefix (Wine/Proton data + game files)"
echo "  - Heroic sideload library entry"
echo "  - Heroic game config (GamesConfig/ptcgl.json)"
echo "  - tpcitcgapp:// URI handler"
echo "  - State file"
echo ""
echo -e "${YELLOW}Proton-GE and Heroic itself will NOT be removed (you may want them for other games).${RESET}"
echo ""
confirm "Continue with uninstall?"

# ── Load state (best-effort; may not exist if install failed mid-way) ──────────
if [[ -f "$STATE_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
fi

# ── Remove Heroic sideload entry ───────────────────────────────────────────────
step "Removing Heroic sideload entry"
if [[ -f "$HEROIC_SIDELOAD_LIB" ]]; then
    jq --arg app "$APP_NAME" '.games = [.games[] | select(.app_name != $app)]' \
        "$HEROIC_SIDELOAD_LIB" > "${HEROIC_SIDELOAD_LIB}.tmp" \
        && mv "${HEROIC_SIDELOAD_LIB}.tmp" "$HEROIC_SIDELOAD_LIB"
    success "Removed ${APP_NAME} from Heroic library"
else
    info "Heroic sideload library not found — skipping"
fi

GAME_CONFIG_FILE="${HEROIC_GAMES_CONFIG}/${APP_NAME}.json"
if [[ -f "$GAME_CONFIG_FILE" ]]; then
    rm -f "$GAME_CONFIG_FILE"
    success "Removed ${GAME_CONFIG_FILE}"
fi

# ── Remove URI handler ─────────────────────────────────────────────────────────
step "Removing tpcitcgapp:// URI handler"
if [[ -f "$HANDLER_BIN" ]]; then
    rm -f "$HANDLER_BIN"
    success "Removed ${HANDLER_BIN}"
fi
if [[ -f "$HANDLER_DESKTOP" ]]; then
    rm -f "$HANDLER_DESKTOP"
    success "Removed ${HANDLER_DESKTOP}"
fi

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
fi
xdg-mime default "" x-scheme-handler/tpcitcgapp 2>/dev/null || true
success "URI handler deregistered"

# ── Remove game prefix ─────────────────────────────────────────────────────────
step "Removing game prefix"
if [[ -d "$PREFIX_PARENT" ]]; then
    echo -e "${RED}WARNING: This permanently deletes the entire Wine prefix at:${RESET}"
    echo -e "  ${BOLD}${PREFIX_PARENT}${RESET}"
    echo ""
    confirm "Delete Wine prefix (all local game data will be lost)?"
    rm -rf "$PREFIX_PARENT"
    success "Prefix removed"
else
    info "Prefix directory not found — already removed or never created"
fi

# ── Remove state dir ───────────────────────────────────────────────────────────
if [[ -d "$STATE_DIR" ]]; then
    rm -rf "$STATE_DIR"
    success "State dir removed: ${STATE_DIR}"
fi

# ── Optionally remove Heroic Flatpak ──────────────────────────────────────────
echo ""
read -rp "Remove Heroic Games Launcher Flatpak? [y/N] " ans
if [[ "${ans,,}" =~ ^(y|yes)$ ]]; then
    if flatpak uninstall --user -y "$HEROIC_FLATPAK" 2>/dev/null; then
        success "Heroic removed"
    else
        warn "Could not remove Heroic (may not be installed)"
    fi
fi

echo ""
success "Uninstall complete."
