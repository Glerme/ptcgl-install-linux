#!/usr/bin/env bash
# Troubleshooting: deletes the pokemon/ and Unity/ cache directories inside
# the Wine prefix. Fixes: daily quests stuck, game unresponsive/frozen on home page.
# Usage: ./reset.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

load_state  # sets WINE_PREFIX

LOCAL_LOW="${WINE_PREFIX}/drive_c/users/steamuser/AppData/LocalLow"
POKEMON_DIR="${LOCAL_LOW}/The Pokémon Company International/pokemon"
UNITY_DIR="${LOCAL_LOW}/The Pokémon Company International/Unity"

echo -e "${YELLOW}This will delete cached game data to fix common issues.${RESET}"
echo -e "Paths to be removed:"
echo -e "  ${BOLD}${POKEMON_DIR}${RESET}"
echo -e "  ${BOLD}${UNITY_DIR}${RESET}"
echo ""
echo -e "Your account and deck data are stored on the Pokemon servers — this is safe."
echo ""
confirm "Proceed with reset?"

local_removed=0

if [[ -d "$POKEMON_DIR" ]]; then
    rm -rf "$POKEMON_DIR"
    success "Removed: ${POKEMON_DIR}"
    local_removed=1
else
    info "Not found (skipping): ${POKEMON_DIR}"
fi

if [[ -d "$UNITY_DIR" ]]; then
    rm -rf "$UNITY_DIR"
    success "Removed: ${UNITY_DIR}"
    local_removed=1
else
    info "Not found (skipping): ${UNITY_DIR}"
fi

if [[ $local_removed -eq 0 ]]; then
    info "Nothing to remove — directories were already absent."
else
    success "Reset complete. Launch the game again with ./launch.sh"
fi
