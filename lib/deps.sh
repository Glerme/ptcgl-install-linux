#!/usr/bin/env bash
# Installs system dependencies: flatpak and jq.
# Sourced by install.sh — do not call directly.
# Expects: success(), warn(), die(), step(), require_cmd() from common.sh are already loaded.

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
        apt)    sudo apt-get update -qq && sudo apt-get install -y "$pkg" ;;
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
        https://flathub.org/repo/flathub.flatpakrepo \
        || die "Failed to add Flathub remote. Check network and flatpak installation."
    success "Flathub remote ready"
}
