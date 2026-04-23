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
