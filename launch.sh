#!/usr/bin/env bash
# Launches Pokemon TCG Live directly without the Heroic GUI.
# Loads PROTON_VERSION from the state file written by install.sh.
# Usage: ./launch.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

load_state  # sets PROTON_VERSION, PROTON_ROOT, PROTON_BIN, WINE_PREFIX, GAME_EXE

[[ -f "$GAME_EXE" ]] || die "Game executable not found: ${GAME_EXE}\nRun ./install.sh first."
[[ -f "$PROTON_BIN" ]] || die "Proton binary not found: ${PROTON_BIN}\nRun ./install.sh first."

info "Launching ${GAME_TITLE} with Proton-GE ${PROTON_VERSION}..."

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$FAKE_STEAM_COMPAT"
export STEAM_COMPAT_DATA_PATH="$PREFIX_PARENT"
export WINE_CPU_TOPOLOGY="2:0,1"

exec "$PROTON_BIN" run "$GAME_EXE"
