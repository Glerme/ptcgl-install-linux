# PTCGL Linux Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create plug-and-play bash scripts that install and configure Pokémon TCG Live on any Linux distro using Heroic (Flatpak) + Proton-GE.

**Architecture:** `lib/common.sh` defines all shared constants and utility functions; `lib/deps.sh` handles OS-agnostic dependency installation (flatpak + jq); `lib/proton.sh` downloads Proton-GE-Latest from GitHub; `install.sh` orchestrates everything; `register-handler.sh` registers the `tpcitcgapp://` URI handler for transparent login; `launch.sh`, `reset.sh`, `uninstall.sh` handle lifecycle.

**Tech Stack:** Bash 5+, Flatpak (Heroic), Proton-GE-Latest (Wine layer), jq (JSON editing), xdg-utils (URI handler registration), curl/tar (downloads).

---

## Prefix Structure (Critical)

When using Proton-GE's `proton run`, it expects:
- `STEAM_COMPAT_DATA_PATH` = parent directory (e.g., `~/Games/Heroic/Prefixes/default/Pokemon TCG Live`)
- Actual Wine prefix = `$STEAM_COMPAT_DATA_PATH/pfx/`
- Game exe = `$STEAM_COMPAT_DATA_PATH/pfx/drive_c/users/steamuser/.../Pokemon TCG Live.exe`

Heroic with `type: "proton"` uses the same pattern: `winePrefix` = STEAM_COMPAT_DATA_PATH.

## State File

After install, `~/.config/ptcgl-linux/state` is sourced by all other scripts:
```bash
PROTON_VERSION="GE-Proton9-27"
PROTON_ROOT="$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/proton/GE-Proton9-27"
PREFIX_PARENT="$HOME/Games/Heroic/Prefixes/default/Pokemon TCG Live"
```

---

## File Map

| File | Responsibility |
|------|---------------|
| `lib/common.sh` | Constants, colors, logging functions, shared path definitions |
| `lib/deps.sh` | Detect OS package manager, install flatpak + jq if missing |
| `lib/proton.sh` | Download Proton-GE-Latest from GitHub API, extract to Heroic tools dir |
| `install.sh` | Main orchestrator: deps → Heroic → Proton-GE → prefix init → MSI install → Heroic sideload → handler |
| `register-handler.sh` | Write `ptcgl-uri-handler` script + `.desktop` file, register via xdg-mime |
| `launch.sh` | Direct launch wrapper (no Heroic GUI needed) with WINE_CPU_TOPOLOGY |
| `reset.sh` | Delete `pokemon/` and `Unity/` in LocalLow for troubleshooting |
| `uninstall.sh` | Remove all: prefix, Heroic entry, URI handler, state |

---

## Task 1: Project Structure + lib/common.sh

**Files:**
- Create: `lib/common.sh`
- Create: `lib/deps.sh` (empty stub)
- Create: `lib/proton.sh` (empty stub)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p /home/gui/Documents/projetos/ptcgl-linux/lib
mkdir -p /home/gui/Documents/projetos/ptcgl-linux/assets
```

- [ ] **Step 2: Create lib/common.sh**

```bash
#!/usr/bin/env bash
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
```

- [ ] **Step 3: Create empty stubs for lib/deps.sh and lib/proton.sh**

Create `lib/deps.sh`:
```bash
#!/usr/bin/env bash
# Installs system dependencies needed before install.sh can run.
# Sourced by install.sh — do not call directly.
```

Create `lib/proton.sh`:
```bash
#!/usr/bin/env bash
# Downloads and extracts Proton-GE-Latest from GitHub into Heroic's tools dir.
# Exports PROTON_VERSION after completion.
```

- [ ] **Step 4: Verify shellcheck passes on common.sh**

```bash
shellcheck --shell=bash lib/common.sh
```
Expected: no errors (install shellcheck with `sudo apt install shellcheck` if needed).

- [ ] **Step 5: Commit**

```bash
git init
git add lib/common.sh lib/deps.sh lib/proton.sh
git commit -m "feat: add lib/common.sh with shared constants and utilities"
```

---

## Task 2: lib/deps.sh

**Files:**
- Modify: `lib/deps.sh`

- [ ] **Step 1: Write lib/deps.sh**

```bash
#!/usr/bin/env bash
# Installs system dependencies: flatpak and jq.
# Sourced by install.sh — do not call directly.
# Expects: info(), warn(), die(), step() from common.sh are already loaded.

# ── Detect package manager ─────────────────────────────────────────────────────
_detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null;     then echo "dnf"
    elif command -v pacman &>/dev/null;  then echo "pacman"
    elif command -v zypper &>/dev/null;  then echo "zypper"
    else echo "unknown"
    fi
}

# _install_pkg PKG — installs a single package via the detected manager
_install_pkg() {
    local pkg="$1"
    local mgr
    mgr=$(_detect_pkg_manager)
    case "$mgr" in
        apt)    sudo apt-get install -y "$pkg" ;;
        dnf)    sudo dnf install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        zypper) sudo zypper install -y "$pkg" ;;
        *)      die "Unsupported package manager. Please install '$pkg' manually and re-run." ;;
    esac
}

# install_deps — ensures flatpak and jq are present
install_deps() {
    step "Checking system dependencies"

    # ── flatpak ────────────────────────────────────────────────────────────────
    if ! command -v flatpak &>/dev/null; then
        warn "flatpak not found — installing..."
        _install_pkg flatpak
        success "flatpak installed"
    else
        success "flatpak already present ($(flatpak --version))"
    fi

    # ── jq ────────────────────────────────────────────────────────────────────
    if ! command -v jq &>/dev/null; then
        warn "jq not found — installing..."
        _install_pkg jq
        success "jq installed"
    else
        success "jq already present ($(jq --version))"
    fi

    # ── curl ──────────────────────────────────────────────────────────────────
    if ! command -v curl &>/dev/null; then
        warn "curl not found — installing..."
        _install_pkg curl
        success "curl installed"
    else
        success "curl already present"
    fi

    # ── tar ───────────────────────────────────────────────────────────────────
    require_cmd tar "Please install tar manually."
    success "tar present"

    # ── Flathub remote ────────────────────────────────────────────────────────
    step "Ensuring Flathub remote is configured"
    flatpak remote-add --if-not-exists --user flathub \
        https://flathub.org/repo/flathub.flatpakrepo
    success "Flathub remote ready"
}
```

- [ ] **Step 2: Verify shellcheck**

```bash
shellcheck --shell=bash lib/deps.sh
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/deps.sh
git commit -m "feat: add lib/deps.sh for OS-agnostic dependency installation"
```

---

## Task 3: lib/proton.sh

**Files:**
- Modify: `lib/proton.sh`

- [ ] **Step 1: Write lib/proton.sh**

```bash
#!/usr/bin/env bash
# Downloads Proton-GE-Latest from GitHub and extracts it into Heroic's tools dir.
# After calling install_proton_ge(), PROTON_VERSION is set and exported.
# Sourced by install.sh — do not call directly.

# install_proton_ge — downloads GE-Proton latest if not already present
install_proton_ge() {
    step "Fetching Proton-GE-Latest from GitHub"

    require_cmd curl
    require_cmd tar
    require_cmd jq

    local api_url="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
    local release_json
    release_json=$(curl -fsSL "$api_url") \
        || die "Failed to fetch Proton-GE release info. Check internet connection."

    PROTON_VERSION=$(echo "$release_json" | jq -r '.tag_name') \
        || die "Failed to parse Proton-GE version from GitHub API response."
    export PROTON_VERSION

    local tar_url
    tar_url=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url') \
        || die "Failed to find .tar.gz asset in Proton-GE release."

    local proton_dir="${HEROIC_TOOLS}/${PROTON_VERSION}"

    if [[ -d "$proton_dir" ]]; then
        success "Proton-GE ${PROTON_VERSION} already installed at ${proton_dir}"
        return 0
    fi

    info "Downloading ${PROTON_VERSION}..."
    mkdir -p "$HEROIC_TOOLS"

    local tmp_tar
    tmp_tar=$(mktemp --suffix=".tar.gz")
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_tar'" EXIT

    curl -fSL --progress-bar "$tar_url" -o "$tmp_tar" \
        || die "Download failed for $tar_url"

    info "Extracting to ${HEROIC_TOOLS}/ ..."
    tar -xf "$tmp_tar" -C "$HEROIC_TOOLS/" \
        || die "Extraction failed."

    [[ -f "${proton_dir}/proton" ]] \
        || die "Extraction succeeded but ${proton_dir}/proton not found. Check archive structure."

    chmod +x "${proton_dir}/proton"
    success "Proton-GE ${PROTON_VERSION} installed"
}
```

- [ ] **Step 2: Verify shellcheck**

```bash
shellcheck --shell=bash lib/proton.sh
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/proton.sh
git commit -m "feat: add lib/proton.sh to download Proton-GE-Latest from GitHub"
```

---

## Task 4: install.sh (main orchestrator)

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
# Main installer for Pokémon TCG Live on Linux.
# Usage: ./install.sh [/path/to/PokemonTCGLiveInstaller.msi]

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
install_proton_ge  # sets PROTON_VERSION
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

# Copy MSI into the prefix so msiexec can find it at a Windows path (C:\)
MSI_STAGING="${WINE_PREFIX}/drive_c/ptcgl_install"
# The pfx/ dir may not exist yet before first proton run — use a staging approach:
# Proton initializes pfx/ on first invocation.

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$FAKE_STEAM_COMPAT"
export STEAM_COMPAT_DATA_PATH="$PREFIX_PARENT"

# First proton invocation initializes the prefix (creates pfx/, sets up DXVK/VKD3D).
# We pass a harmless command (wineboot --init) to trigger initialization.
info "Initializing Wine prefix with Proton-GE ${PROTON_VERSION} ..."
"$PROTON_BIN" run wineboot --init \
    || warn "wineboot --init returned non-zero (often harmless; continuing)"

# Now pfx/drive_c exists — copy MSI in
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

# library.json must be valid JSON array at .games
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x install.sh
```

- [ ] **Step 3: Verify shellcheck**

```bash
shellcheck --shell=bash install.sh
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh main orchestrator"
```

---

## Task 5: register-handler.sh

**Files:**
- Create: `register-handler.sh`

This script registers `tpcitcgapp://` as a URI scheme on the user's system. When the game's OAuth flow redirects to `tpcitcgapp://callback?code=...`, the browser invokes our handler script, which launches the game exe with the URL as argument — completing the auth handshake.

- [ ] **Step 1: Write register-handler.sh**

```bash
#!/usr/bin/env bash
# Registers the tpcitcgapp:// URI handler so browser OAuth callbacks work.
# Can be re-run independently if the handler breaks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

load_state  # sets PROTON_VERSION, PROTON_ROOT, PROTON_BIN, WINE_PREFIX, GAME_EXE

# ── Write the handler script ───────────────────────────────────────────────────
step "Writing URI handler script to ${HANDLER_BIN}"
mkdir -p "$(dirname "$HANDLER_BIN")"

cat > "$HANDLER_BIN" <<HANDLER_SCRIPT
#!/usr/bin/env bash
# Auto-generated by register-handler.sh — do not edit manually.
# Invoked by the browser when it sees a tpcitcgapp:// URL.
# \$1 = the full tpcitcgapp://callback?code=... URL

set -euo pipefail

CALLBACK_URL="\${1:-}"
[[ -n "\$CALLBACK_URL" ]] || { echo "[ptcgl-handler] No URL provided" >&2; exit 1; }

export STEAM_COMPAT_CLIENT_INSTALL_PATH="${FAKE_STEAM_COMPAT}"
export STEAM_COMPAT_DATA_PATH="${PREFIX_PARENT}"
export WINE_CPU_TOPOLOGY="2:0,1"

exec "${PROTON_BIN}" run "${GAME_EXE}" "\$CALLBACK_URL"
HANDLER_SCRIPT

chmod +x "$HANDLER_BIN"
success "Handler script written"

# ── Write the .desktop file ────────────────────────────────────────────────────
step "Writing ${HANDLER_DESKTOP}"
mkdir -p "$(dirname "$HANDLER_DESKTOP")"

cat > "$HANDLER_DESKTOP" <<DESKTOP_FILE
[Desktop Entry]
Name=PTCGL URI Handler
Comment=Handles tpcitcgapp:// auth callbacks for Pokemon TCG Live
Exec=${HANDLER_BIN} %u
Type=Application
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/tpcitcgapp;
DESKTOP_FILE

# ── Register with xdg ─────────────────────────────────────────────────────────
step "Registering tpcitcgapp:// with xdg-mime"

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "${HOME}/.local/share/applications"
fi

xdg-mime default ptcgl-handler.desktop x-scheme-handler/tpcitcgapp \
    || die "xdg-mime registration failed. Is xdg-utils installed?"

success "URI handler registered"

# Verify (no 'local' here — we are outside a function)
registered=$(xdg-mime query default x-scheme-handler/tpcitcgapp 2>/dev/null || true)
if [[ "$registered" == "ptcgl-handler.desktop" ]]; then
    success "Verified: tpcitcgapp:// → ptcgl-handler.desktop"
else
    warn "xdg-mime verification returned '${registered}' (expected 'ptcgl-handler.desktop')"
    warn "Login may require manual URL copy-paste (see README)."
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x register-handler.sh
```

- [ ] **Step 3: Verify shellcheck**

```bash
shellcheck --shell=bash register-handler.sh
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add register-handler.sh
git commit -m "feat: add register-handler.sh for tpcitcgapp:// OAuth callbacks"
```

---

## Task 6: launch.sh

**Files:**
- Create: `launch.sh`

- [ ] **Step 1: Write launch.sh**

```bash
#!/usr/bin/env bash
# Launches Pokemon TCG Live directly without the Heroic GUI.
# Loads PROTON_VERSION from the state file written by install.sh.
# Usage: ./launch.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

load_state  # sets PROTON_VERSION (and re-derives PROTON_ROOT, PROTON_BIN)

[[ -f "$GAME_EXE" ]] || die "Game executable not found: ${GAME_EXE}\nRun ./install.sh first."
[[ -f "$PROTON_BIN" ]] || die "Proton binary not found: ${PROTON_BIN}\nRun ./install.sh first."

info "Launching ${GAME_TITLE} with Proton-GE ${PROTON_VERSION}..."

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$FAKE_STEAM_COMPAT"
export STEAM_COMPAT_DATA_PATH="$PREFIX_PARENT"
export WINE_CPU_TOPOLOGY="2:0,1"

exec "$PROTON_BIN" run "$GAME_EXE"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x launch.sh
```

- [ ] **Step 3: Verify shellcheck**

```bash
shellcheck --shell=bash launch.sh
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add launch.sh
git commit -m "feat: add launch.sh for direct game launch without Heroic GUI"
```

---

## Task 7: reset.sh

**Files:**
- Create: `reset.sh`

- [ ] **Step 1: Write reset.sh**

```bash
#!/usr/bin/env bash
# Troubleshooting: deletes the pokemon/ and Unity/ cache directories inside
# the Wine prefix. Fixes: daily quests stuck, game unresponsive/frozen on home page.
# Usage: ./reset.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

load_state

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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x reset.sh
```

- [ ] **Step 3: Verify shellcheck**

```bash
shellcheck --shell=bash reset.sh
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add reset.sh
git commit -m "feat: add reset.sh for cache troubleshooting"
```

---

## Task 8: uninstall.sh

**Files:**
- Create: `uninstall.sh`

- [ ] **Step 1: Write uninstall.sh**

```bash
#!/usr/bin/env bash
# Removes all PTCGL Linux installer artifacts.
# Usage: ./uninstall.sh

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
[[ -f "$GAME_CONFIG_FILE" ]] && rm -f "$GAME_CONFIG_FILE" && success "Removed ${GAME_CONFIG_FILE}"

# ── Remove URI handler ─────────────────────────────────────────────────────────
step "Removing tpcitcgapp:// URI handler"
[[ -f "$HANDLER_BIN" ]]     && rm -f "$HANDLER_BIN"     && success "Removed ${HANDLER_BIN}"
[[ -f "$HANDLER_DESKTOP" ]] && rm -f "$HANDLER_DESKTOP" && success "Removed ${HANDLER_DESKTOP}"

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
fi
# Deregister MIME type (set to empty)
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
[[ -d "$STATE_DIR" ]] && rm -rf "$STATE_DIR" && success "State dir removed: ${STATE_DIR}"

# ── Optionally remove Heroic Flatpak ──────────────────────────────────────────
echo ""
read -rp "Remove Heroic Games Launcher Flatpak? [y/N] " ans
if [[ "${ans,,}" =~ ^(y|yes)$ ]]; then
    flatpak uninstall --user -y "$HEROIC_FLATPAK" 2>/dev/null \
        && success "Heroic removed" \
        || warn "Could not remove Heroic (may not be installed)"
fi

echo ""
success "Uninstall complete."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x uninstall.sh
```

- [ ] **Step 3: Verify shellcheck**

```bash
shellcheck --shell=bash uninstall.sh
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add uninstall.sh
git commit -m "feat: add uninstall.sh for full cleanup"
```

---

## Task 9: Final verification + README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
# PTCGL Linux Installer

Automated installer for Pokémon TCG Live on Linux via Heroic + Proton-GE.

## Requirements

- A Linux distro with `flatpak` available (or the script will install it)
- `PokemonTCGLiveInstaller.msi` downloaded from the official Pokémon website
- Internet connection for Flatpak + Proton-GE download (~1-2 GB total)

## Quick Start

```bash
./install.sh ~/Downloads/PokemonTCGLiveInstaller.msi
```

Then launch the game:
```bash
./launch.sh        # Direct launch
# OR open Heroic and click Play
```

## First-Time Login

1. Launch the game and click **"Login to access more features!"**
2. A browser window opens — log in to your Pokémon account
3. The browser will ask to open the `tpcitcgapp://` link — **allow it**
4. The game receives the auth token automatically
5. You stay logged in for future sessions

If your browser blocks the `tpcitcgapp://` redirect, press F12 on the login page,
copy the `tpcitcgapp://callback?code=...` URL from the console, then run:
```bash
./launch.sh --callback "tpcitcgapp://callback?code=..."
```

## Troubleshooting

**Daily quests don't load / game is unresponsive:**
```bash
./reset.sh
```
Deletes cached game data (safe — your account data is on Pokemon's servers).

**Game doesn't appear in Heroic:**
Use `./launch.sh` directly. Re-run `./install.sh` to rebuild the Heroic entry.

**URI handler not working after browser update:**
```bash
./register-handler.sh
```

## Uninstall

```bash
./uninstall.sh
```

## How It Works

| Component | What it does |
|-----------|-------------|
| Heroic Flatpak | Provides a visual launcher; distributes cross-distro |
| Proton-GE-Latest | Wine layer with DXVK/VKD3D for DirectX support |
| `tpcitcgapp://` handler | Intercepts OAuth callbacks from browser → passes to game exe |
| `WINE_CPU_TOPOLOGY=2:0,1` | Limits to 2 CPU cores; fixes daily quest loading bug |
```

- [ ] **Step 2: Run full shellcheck pass on all scripts**

```bash
shellcheck --shell=bash install.sh register-handler.sh launch.sh reset.sh uninstall.sh lib/*.sh
```
Expected: no errors across all files.

- [ ] **Step 3: Verify script structure is correct**

```bash
# Confirm all executables exist
ls -la install.sh register-handler.sh launch.sh reset.sh uninstall.sh lib/common.sh lib/deps.sh lib/proton.sh
```
Expected: all 8 files with execute permission on the 5 main scripts.

- [ ] **Step 4: Dry-run install.sh --help (verify it loads without errors)**

```bash
bash -n install.sh && bash -n lib/common.sh && bash -n lib/deps.sh && bash -n lib/proton.sh
echo "Syntax OK"
```
Expected: `Syntax OK`

- [ ] **Step 5: Final commit**

```bash
git add README.md
git commit -m "docs: add README with usage, login flow, and troubleshooting"
```

---

## Post-Implementation Integration Testing

Run these after all scripts are implemented to verify end-to-end:

```bash
# 1. Dry syntax check
bash -n install.sh register-handler.sh launch.sh reset.sh uninstall.sh

# 2. Full install (requires MSI)
./install.sh ~/Downloads/PokemonTCGLiveInstaller.msi

# 3. Verify game exe exists
ls "${HOME}/Games/Heroic/Prefixes/default/Pokemon TCG Live/pfx/drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe"

# 4. Verify URI handler registration
xdg-mime query default x-scheme-handler/tpcitcgapp
# Expected: ptcgl-handler.desktop

# 5. Verify Heroic sideload entry
jq '.games[] | select(.app_name == "ptcgl")' \
    ~/.var/app/com.heroicgameslauncher.hgl/config/heroic/sideload_apps/library.json

# 6. Verify Heroic game config
cat ~/.var/app/com.heroicgameslauncher.hgl/config/heroic/GamesConfig/ptcgl.json

# 7. Test launch
./launch.sh  # Game should open

# 8. Test reset (creates no harm)
./reset.sh

# 9. Open Heroic and confirm game appears with Play button
flatpak run com.heroicgameslauncher.hgl
```

---

## Known Risks + Mitigations

| Risk | Mitigation |
|------|------------|
| `proton run msiexec /passive` silently fails | Verify GAME_EXE exists post-install; error message points to prefix for debugging |
| Heroic `library.json` schema changes between versions | Game still launchable via `./launch.sh`; document in README |
| Browser blocks `tpcitcgapp://` redirect | README documents F12 fallback; `launch.sh` can accept `--callback` arg (future) |
| `proton run wineboot --init` fails on some Proton-GE versions | Warn + continue; msiexec invocation will initialize prefix anyway |
| Paths with non-ASCII chars (é in Pokémon) | Bash handles UTF-8 paths with proper quoting; tested on Linux ext4 |
