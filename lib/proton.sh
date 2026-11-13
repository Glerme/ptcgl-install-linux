#!/usr/bin/env bash
# Reuses Heroic's managed Proton-GE or downloads it into the selected tools dir.
# Exports PROTON_VERSION and PROTON_ROOT after selection.
# Sourced by install.sh — do not call directly.

# install_proton_ge [tools_dir] — defaults to Heroic for existing callers
install_proton_ge() {
    local tools_dir="${1:-$HEROIC_TOOLS}"
    if [[ -f "$tools_dir/GE-Proton-latest/proton" ]]; then
        PROTON_VERSION=GE-Proton-latest
        success "Using Heroic-managed Proton-GE at $tools_dir/$PROTON_VERSION"
    else
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
        # from the tarball name and use that as PROTON_VERSION (it's also the dir Heroic expects).
        local tar_name="${tar_url##*/}"
        PROTON_VERSION="${tar_name%.tar.gz}"

        local proton_dir="${tools_dir}/${PROTON_VERSION}"

        if [[ -f "${proton_dir}/proton" ]]; then
            success "Proton-GE ${PROTON_VERSION} already installed at ${proton_dir}"
        else
            info "Downloading ${PROTON_VERSION}..."
            mkdir -p "$tools_dir"

            local tmp_tar
            tmp_tar=$(mktemp --suffix=".tar.gz")
            # shellcheck disable=SC2064
            trap "rm -f '$tmp_tar'" EXIT

            curl -fSL --progress-bar "$tar_url" -o "$tmp_tar" \
                || die "Download failed for $tar_url"

            info "Extracting to ${tools_dir}/ ..."
            tar -xf "$tmp_tar" -C "$tools_dir/" \
                || die "Extraction failed."

            [[ -f "${proton_dir}/proton" ]] \
                || die "Extraction succeeded but ${proton_dir}/proton not found. Check archive structure."

            chmod +x "${proton_dir}/proton"
            success "Proton-GE ${PROTON_VERSION} installed"
        fi
    fi
    export PROTON_VERSION
    export PROTON_ROOT="$tools_dir/$PROTON_VERSION"
}

# cleanup_old_proton tools_dir — offers to delete unreferenced GE-Proton<N> dirs.
# Call only after the new state and launcher config are written, so they no longer
# reference the runner being replaced.
cleanup_old_proton() {
    local tools_dir="$1"
    local old_dir config ans referenced grep_status
    local -a references=()
    for config in "$HEROIC_GAMES_CONFIG"/*.json "$LUTRIS_GAMES_DIR"/*.yml "$STATE_FILE"; do
        [[ ! -e "$config" ]] || references+=("$config")
    done
    for old_dir in "$tools_dir"/GE-Proton[0-9]*; do
        [[ -d "$old_dir" && "$old_dir" != "$PROTON_ROOT" && ! -L "$old_dir" ]] || continue
        referenced=false
        if (( ${#references[@]} )); then
            grep_status=0
            grep -Fq -- "$old_dir" "${references[@]}" || grep_status=$?
            # A read error must not make an in-use runner eligible for deletion.
            [[ "$grep_status" == 1 ]] || referenced=true
        fi
        if [[ "$referenced" == true ]]; then
            info "Keeping referenced Proton directory: $old_dir"
            continue
        fi
        [[ -t 0 ]] || continue
        printf 'Remove old Proton directory %s? [y/N] ' "$old_dir"
        if read -r ans && [[ "${ans,,}" =~ ^(y|yes)$ ]]; then
            rm -rf -- "$old_dir" || warn "Could not remove $old_dir"
        fi
    done
}
