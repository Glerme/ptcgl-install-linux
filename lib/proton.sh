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

    local release_tag
    release_tag=$(echo "$release_json" | jq -r '.tag_name') \
        || die "Failed to parse Proton-GE version from GitHub API response."
    [[ -z "$release_tag" || "$release_tag" == "null" ]] \
        && die "Unexpected .tag_name value from GitHub API: '${release_tag}'"

    # GE-Proton releases publish one tarball per architecture
    # (e.g. GE-Proton11-5-x86_64.tar.gz, GE-Proton11-5-aarch64.tar.gz), and the
    # archive's top-level directory is named to match (GE-Proton11-5-x86_64/).
    # Fold the arch suffix into PROTON_VERSION so it stays in sync with the
    # actual on-disk folder name everywhere downstream (state file, launch.sh,
    # Heroic's GamesConfig).
    local host_arch proton_arch
    host_arch="$(uname -m)"
    case "$host_arch" in
        x86_64)  proton_arch="x86_64" ;;
        aarch64) proton_arch="aarch64" ;;
        *) die "Unsupported architecture for Proton-GE: ${host_arch}" ;;
    esac
    PROTON_VERSION="${release_tag}-${proton_arch}"
    export PROTON_VERSION

    local asset_name="${PROTON_VERSION}.tar.gz"
    local tar_url
    tar_url=$(echo "$release_json" | jq -r --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .browser_download_url') \
    || die "Failed to find ${asset_name} asset in Proton-GE release."
    [[ -z "$tar_url" || "$tar_url" == "null" ]] \
        && die "No exact-match ${asset_name} download URL found in Proton-GE release assets."

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
