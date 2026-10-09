#!/usr/bin/env bash
# Downloads Proton-GE-Latest from GitHub and extracts it into Lutris's Wine runners directory.
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
    [[ -z "$PROTON_VERSION" || "$PROTON_VERSION" == "null" ]] \
        && die "Unexpected .tag_name value from GitHub API: '${PROTON_VERSION}'"
    export PROTON_VERSION

    # Since GE-Proton11, releases ship one tarball per arch (e.g. -x86_64, -aarch64).
    # Prefer the one matching this machine; fall back to an arch-less tarball for older releases.
    local arch
    arch=$(uname -m)
    local tar_url
    tar_url=$(echo "$release_json" | jq -r --arg suffix "-${arch}.tar.gz" '
        [.assets[] | select(.name | endswith(".tar.gz"))]
        | map(select(.name | endswith($suffix))) + map(select(.name | test("-(x86_64|aarch64)[.]tar[.]gz$") | not))
        | .[0].browser_download_url // empty') \
        || die "Failed to find .tar.gz asset in Proton-GE release."
    [[ -z "$tar_url" ]] \
        && die "No .tar.gz download for architecture '${arch}' found in Proton-GE release assets."

    # The extracted directory may carry an arch suffix (GE-Proton11-7-x86_64), so derive it
    # from the tarball name and use that as PROTON_VERSION (it's also the runner directory Lutris discovers).
    local tar_name="${tar_url##*/}"
    PROTON_VERSION="${tar_name%.tar.gz}"
    export PROTON_VERSION

    local proton_dir="${LUTRIS_TOOLS}/${PROTON_VERSION}"

    if [[ -f "${proton_dir}/proton" ]]; then
        success "Proton-GE ${PROTON_VERSION} already installed at ${proton_dir}"
        return 0
    fi

    info "Downloading ${PROTON_VERSION}..."
    mkdir -p "$LUTRIS_TOOLS"

    local tmp_tar
    tmp_tar=$(mktemp --suffix=".tar.gz")
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_tar'" EXIT

    curl -fSL --progress-bar "$tar_url" -o "$tmp_tar" \
        || die "Download failed for $tar_url"

    info "Extracting to ${LUTRIS_TOOLS}/ ..."
    tar -xf "$tmp_tar" -C "$LUTRIS_TOOLS/" \
        || die "Extraction failed."

    [[ -f "${proton_dir}/proton" ]] \
        || die "Extraction succeeded but ${proton_dir}/proton not found. Check archive structure."

    chmod +x "${proton_dir}/proton"
    success "Proton-GE ${PROTON_VERSION} installed"
}
