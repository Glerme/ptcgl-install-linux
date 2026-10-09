#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are intentionally set for use by sourcing scripts
# Shared constants, paths, colors, and logging utilities.
# Source this file at the top of every script: source "$(dirname "$0")/lib/common.sh"
#
# NOTE: This file does NOT set -euo pipefail. Each caller script must opt in
# explicitly by adding "set -euo pipefail" at its own top level.

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; RESET='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
step()    { echo -e "\n${BOLD}▶ $*${RESET}"; }

# ── Lutris Flatpak constants ───────────────────────────────────────────────────
LUTRIS_FLATPAK="net.lutris.Lutris"
LUTRIS_CONFIG_ID="ptcgl-linux"

# ── Game / prefix constants ────────────────────────────────────────────────────
GAME_TITLE="Pokemon TCG Live"
APP_NAME="ptcgl"
PREFIX_PARENT="${HOME}/Games/Lutris/pokemon-tcg-live"
WINE_PREFIX="${PREFIX_PARENT}/pfx"
GAME_EXE="${WINE_PREFIX}/drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe"

# ── URI handler constants ──────────────────────────────────────────────────────
HANDLER_BIN="${HOME}/.local/bin/ptcgl-uri-handler"
HANDLER_DESKTOP="${HOME}/.local/share/applications/ptcgl-handler.desktop"

# ── State file (written by install.sh, sourced by other scripts) ───────────────
STATE_DIR="${HOME}/.config/ptcgl-linux"
STATE_FILE="${STATE_DIR}/state"

# ── Utility functions ──────────────────────────────────────────────────────────

# require_cmd CMD [install_hint]
require_cmd() {
    local cmd="$1" hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        if [[ -n "$hint" ]]; then
            die "'$cmd' not found. $hint"
        else
            die "'$cmd' not found."
        fi
    fi
}

# confirm "Message" → exits if user types anything other than y/Y/yes/YES
confirm() {
    local msg="$1" ans
    printf '%b' "${YELLOW}${msg} [y/N]${RESET} "
    read -r ans
    [[ "${ans,,}" =~ ^(y|yes)$ ]] || { info "Aborted."; exit 0; }
}

# Keep all prefix-dependent paths in sync, including when migrating an old install.
set_prefix_paths() {
    WINE_PREFIX="${PREFIX_PARENT}/pfx"
    GAME_EXE="${WINE_PREFIX}/drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe"
}

load_state() {
    [[ -f "$STATE_FILE" ]] || die "State file not found at $STATE_FILE. Run ./install.sh first."
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    [[ "${LAUNCHER:-}" == lutris ]] \
        || die "This installation uses the old launcher. Run ./install.sh to migrate to Lutris."
    set_prefix_paths
    PROTON_BIN="${PROTON_ROOT}/proton"
}

# Execute helpers with the Python in the Lutris Flatpak and its UMU runtime.
lutris_helper() {
    flatpak run --command=python3 "$LUTRIS_FLATPAK" \
        "${SCRIPT_DIR}/lib/lutris_bridge.py" "$@"
}
