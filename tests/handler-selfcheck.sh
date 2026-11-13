#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
export PATH="$TEST_DIR/bin:$PATH"
export CALLS="$TEST_DIR/calls"
mkdir -p "$HOME/.config/ptcgl-linux" "$TEST_DIR/bin" "$TEST_DIR/proc/42/root"
printf 'PROTON_VERSION=test\n' > "$HOME/.config/ptcgl-linux/state"

cat > "$TEST_DIR/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
[[ -n "$TEST_PID" ]] || exit 1
printf '%s\n' "$TEST_PID"
STUB
cat > "$TEST_DIR/bin/flatpak" <<'STUB'
#!/usr/bin/env bash
printf 'flatpak' >> "$CALLS"
printf ' <%s>' "$@" >> "$CALLS"
printf '\n' >> "$CALLS"
exit "$FLATPAK_STATUS"
STUB
cat > "$TEST_DIR/bin/proton" <<'STUB'
#!/usr/bin/env bash
printf 'proton' >> "$CALLS"
printf ' <%s>' "$@" >> "$CALLS"
printf '\n' >> "$CALLS"
exit 0
STUB
cat > "$TEST_DIR/bin/xdg-mime" <<'STUB'
#!/usr/bin/env bash
printf 'ptcgl-handler.desktop\n'
STUB
cat > "$TEST_DIR/bin/update-desktop-database" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$TEST_DIR/bin/"*
PROTON_ROOT="$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/proton/test"
mkdir -p "$PROTON_ROOT"
ln -s "$TEST_DIR/bin/proton" "$PROTON_ROOT/proton"
bash "$REPO_DIR/register-handler.sh" > "$TEST_DIR/register.log"
HANDLER="$HOME/.local/bin/ptcgl-uri-handler"
bash -n "$HANDLER"
# Replace only /proc in the generated handler to simulate sandbox membership.
sed "s|/proc/|$TEST_DIR/proc/|g" "$HANDLER" > "$TEST_DIR/handler"
CALLBACK='tpcitcgapp://callback?code=a%20b&state=hello world'
GAME_EXE="$HOME/Games/Heroic/Prefixes/default/Pokemon TCG Live/pfx/drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe"
LOG_FILE="$HOME/.config/ptcgl-linux/handler.log"

assert() {
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        cat "$CALLS" >&2
        exit 1
    fi
}

run_case() {
    local label="$1" expected_status="$2" expected_flatpak="$3" expected_proton="$4" status=0
    : > "$CALLS"
    : > "$LOG_FILE"
    bash "$TEST_DIR/handler" "$CALLBACK" || status=$?
    assert test "$status" -eq "$expected_status"
    assert test "$(grep -c '^flatpak' "$CALLS" || true)" -eq "$expected_flatpak"
    assert test "$(grep -c '^proton' "$CALLS" || true)" -eq "$expected_proton"
    if [[ "$expected_flatpak" -eq 1 ]]; then
        assert grep -Fq "flatpak <enter> <42> <env> <WINEPREFIX=$HOME/Games/Heroic/Prefixes/default/Pokemon TCG Live/pfx> <$PROTON_ROOT/files/bin/wine> <$GAME_EXE> <$CALLBACK>" "$CALLS"
        assert grep -Fq "flatpak-enter pid=42 exit=$FLATPAK_STATUS" "$LOG_FILE"
    fi
    if [[ "$expected_proton" -eq 1 ]]; then
        assert grep -Fxq "proton <run> <$GAME_EXE> <$CALLBACK>" "$CALLS"
        assert grep -Fq 'host-proton exit=0' "$LOG_FILE"
    fi
    printf 'PASS: %s\n' "$label"
}

export TEST_PID=42 FLATPAK_STATUS=1
touch "$TEST_DIR/proc/42/root/.flatpak-info"
run_case 'sandbox exit 1: no host fallback' 1 1 0
export FLATPAK_STATUS=127
run_case 'sandbox exit 127: host fallback' 0 1 1
export FLATPAK_STATUS=126
run_case 'sandbox exit 126: host fallback' 0 1 1
export FLATPAK_STATUS=0
run_case 'sandbox exit 0: no host fallback' 0 1 0
rm "$TEST_DIR/proc/42/root/.flatpak-info"
run_case 'PID outside sandbox: proton directly' 0 0 1
export TEST_PID=''
run_case 'no running game: proton directly' 0 0 1
