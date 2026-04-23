#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are intentionally set for use by sourcing scripts
# Shared constants, paths, colors, and logging utilities.
# Source this file at the top of every script: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

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
        # shellcheck disable=SC2015  # Intentional: die() always exits, so C never runs unexpectedly
        [[ -n "$hint" ]] && die "'$cmd' not found. $hint" || die "'$cmd' not found."
    fi
}

# confirm "Message" → exits if user types anything other than y/Y/yes/YES
confirm() {
    local msg="$1"
    read -rp "${YELLOW}${msg} [y/N]${RESET} " ans
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
    GAME_EXE="${WINE_PREFIX}/drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe"
}
