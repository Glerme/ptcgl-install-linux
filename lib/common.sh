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

# ── Heroic Flatpak constants ───────────────────────────────────────────────────
HEROIC_FLATPAK="com.heroicgameslauncher.hgl"
HEROIC_CONFIG="${HOME}/.var/app/${HEROIC_FLATPAK}/config/heroic"
HEROIC_TOOLS="${HEROIC_CONFIG}/tools/proton"
HEROIC_GAMES_CONFIG="${HEROIC_CONFIG}/GamesConfig"
HEROIC_SIDELOAD_LIB="${HEROIC_CONFIG}/sideload_apps/library.json"

# ── Game / prefix constants ────────────────────────────────────────────────────
GAME_TITLE="Pokemon TCG Live"
APP_NAME="ptcgl"
# Heroic default prefix location (STEAM_COMPAT_DATA_PATH for proton runners)
PREFIX_PARENT="${HOME}/Games/Heroic/Prefixes/default/${GAME_TITLE}"
# Proton creates pfx/ inside PREFIX_PARENT as the actual Wine prefix
WINE_PREFIX="${PREFIX_PARENT}/pfx"
# Actual game executable path inside the Wine prefix
# NOTE: path contains spaces — always use "$GAME_EXE" (double-quoted) at call sites
GAME_EXE="${WINE_PREFIX}/drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe"
# Windows-style path used when calling msiexec (C:\ root)
MSI_INSTALL_DIR_WIN='C:\ptcgl_install'

# ── URI handler constants ──────────────────────────────────────────────────────
HANDLER_BIN="${HOME}/.local/bin/ptcgl-uri-handler"
HANDLER_DESKTOP="${HOME}/.local/share/applications/ptcgl-handler.desktop"

# ── State file (written by install.sh, sourced by other scripts) ───────────────
STATE_DIR="${HOME}/.config/ptcgl-linux"
STATE_FILE="${STATE_DIR}/state"

# ── Fake Steam compat dir (Proton needs this env var to exist) ─────────────────
FAKE_STEAM_COMPAT="${STATE_DIR}/steam-compat"

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

# load_state — sources STATE_FILE; dies with helpful message if not installed.
# Re-derives all paths that depend on PREFIX_PARENT so that scripts work
# even if the prefix was moved (or if common.sh defaults differ from saved state).
load_state() {
    [[ -f "$STATE_FILE" ]] || die "State file not found at $STATE_FILE. Run ./install.sh first."
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    PROTON_ROOT="${HEROIC_TOOLS}/${PROTON_VERSION}"
    PROTON_BIN="${PROTON_ROOT}/proton"
    # Re-derive downstream paths in case PREFIX_PARENT was overridden by state file
    WINE_PREFIX="${PREFIX_PARENT}/pfx"
    # NOTE: path contains spaces — always use "$GAME_EXE" (double-quoted) at call sites
    GAME_EXE="${WINE_PREFIX}/drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe"
}
