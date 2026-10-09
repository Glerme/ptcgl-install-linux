#!/usr/bin/env bash
# Launch through Lutris, or deliver an OAuth callback in the same Wine prefix.
# Usage: ./launch.sh [--direct | tpcitcgapp://callback?code=...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

[[ $# -le 1 ]] || die "Usage: ./launch.sh [--direct | tpcitcgapp://URL]"
MODE="${1:-}"
case "$MODE" in
    ''|--direct|tpcitcgapp://*) ;;
    *) die "Usage: ./launch.sh [--direct | tpcitcgapp://URL]" ;;
esac

load_state
require_cmd flatpak "Run ./install.sh first."
[[ -f "$GAME_EXE" ]] || die "Game executable not found: ${GAME_EXE}\nRun ./install.sh first."
[[ -f "$PROTON_BIN" ]] || die "Proton binary not found: ${PROTON_BIN}\nRun ./install.sh first."

if [[ -z "$MODE" ]]; then
    info "Launching ${GAME_TITLE} through Lutris..."
    exec flatpak run "$LUTRIS_FLATPAK" "lutris:rungame/${APP_NAME}"
fi

# A fresh flatpak/UMU invocation creates another container. Enter the actual
# game container and use its environment, wineserver, and Proton instead.
if [[ "$MODE" == tpcitcgapp://* ]]; then
    log_callback() {
        printf '%(%Y-%m-%dT%H:%M:%S%z)T %s\n' -1 "$*" >> "${STATE_DIR}/callback.log"
    }
    log_callback "Callback received"
    callback_helper="${SCRIPT_DIR}/lib/callback.py"
    instances=$(flatpak ps --columns=instance,application) \
        || die "Could not query running Flatpak sessions."
    while read -r instance application; do
        [[ "$application" == "$LUTRIS_FLATPAK" ]] || continue
        if flatpak enter "$instance" /usr/bin/python3 "$callback_helper" \
            --prefix "$WINE_PREFIX" --exe "$GAME_EXE" --probe 2>/dev/null; then
            log_callback "Entering game session ${instance}"
            if flatpak enter "$instance" /usr/bin/python3 "$callback_helper" \
                --prefix "$WINE_PREFIX" --exe "$GAME_EXE" "$MODE"; then
                log_callback "Callback process completed"
                exit 0
            else
                status=$?
                log_callback "Callback process failed (exit ${status})"
                exit "$status"
            fi
        fi
    done <<< "$instances"
    log_callback "Running game session not found"
    die "Running PTCGL session not found. Open the game through Lutris and try logging in again."
fi

command=(flatpak run --command=python3 "$LUTRIS_FLATPAK"
    "${SCRIPT_DIR}/lib/lutris_bridge.py" run
    --proton-root "$PROTON_ROOT" --prefix "$WINE_PREFIX"
    "$GAME_EXE")
info "Launching ${GAME_TITLE} with Lutris's UMU runtime..."
exec "${command[@]}"
