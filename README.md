# PTCGL Linux Installer

Automated installer for Pokémon TCG Live on Linux via Lutris Flatpak + Proton-GE.
Works on Linux distributions with Flatpak support.

## Requirements

- `PokemonTCGLiveInstaller.msi` downloaded from the official Pokémon website
- Internet access for Lutris, Proton-GE, and the UMU runtime downloads
- Graphics drivers with Vulkan support

The script installs missing `flatpak`, `jq`, `curl`, and `xdg-utils` through the
system package manager (using `sudo`). `tar` must also be available.
It uses the **Flatpak edition of Lutris** (`net.lutris.Lutris`), including when a
native Lutris installation is already present. Existing user or system Flatpak
installations are reused.

## Quick Start

```bash
./install.sh ~/Downloads/PokemonTCGLiveInstaller.msi
./launch.sh
```

The installer registers **Pokemon TCG Live** in Lutris with the Wine runner and
Proton-GE. You can also open Lutris and click **Play**. Reopen Lutris if it was
running during installation.

To launch directly with Lutris's UMU runtime:

```bash
./launch.sh --direct
```

New installations use `~/Games/Lutris/pokemon-tcg-live/pfx` as the Wine prefix.
Proton-GE is installed in the runners directory reported by Lutris. UMU is
prepared automatically if it has not been downloaded yet.

## Migrating an Existing Installation

```bash
./install.sh
```

If `~/.config/ptcgl-linux/state` points to an existing game installed by this
repository, the script reuses that prefix and game without requiring the MSI.
It registers the game in Lutris and replaces the URI handler. The old prefix
keeps its original location, which may include `Games/Heroic` in its name.
Heroic and its old library entry are left in place; the updated scripts use Lutris.

## First-Time Login

1. Launch the game and click **Login**.
2. Complete login in the browser.
3. Allow the browser to open the `tpcitcgapp://` link.

The handler forwards the full URL as one argument to the game executable,
as in the original script. It locates the Flatpak container containing the
running game and its wineserver, then uses `flatpak enter` and that session's
Proton with `runinprefix`. This keeps the callback in the same runtime and
prefix without initializing another UMU container. The game must already be
open. Lutris's `lutris:rungame/ptcgl` command handles normal launches.

If the browser blocks the redirect, copy the callback URL and run:

```bash
~/.local/bin/ptcgl-uri-handler 'tpcitcgapp://callback?code=...'
# Or:
./launch.sh 'tpcitcgapp://callback?code=...'
```

Keep the URL quoted. The installed handler uses a copy of the launcher under
`~/.config/ptcgl-linux`, so moving this repository does not break login.
Callback delivery milestones are recorded in `~/.config/ptcgl-linux/callback.log`
without the URL or authentication code.

## Scripts

| Script | Purpose |
|--------|---------|
| `install.sh` | Install Lutris, UMU, Proton-GE, game, Lutris entry, and URI handler |
| `launch.sh` | Launch through Lutris; `--direct` uses UMU; accepts a callback URL |
| `register-handler.sh` | Refresh the installed launcher and register the URI handler |
| `reset.sh` | Clear game caches to troubleshoot frozen screens or daily quests |
| `uninstall.sh` | Remove the managed Lutris entry, prefix, URI handler, and state |

## Troubleshooting

**Game doesn't appear in Lutris:**

Confirm you are opening the Flatpak edition:

```bash
flatpak run net.lutris.Lutris
```

Reopen Lutris after installation. Re-run `./install.sh` to rebuild the entry.

**Daily quests don't load or the game is unresponsive:**

Close the game, then run `./reset.sh` and launch again.

**URI handler stops working:**

```bash
./register-handler.sh
xdg-mime query default x-scheme-handler/tpcitcgapp
# Expected: ptcgl-handler.desktop
```

If the browser login succeeds but the game remains logged out, close the game
and any leftover instances, then reopen it through Lutris and try again. Check
`~/.config/ptcgl-linux/callback.log` for `Entering game session` and
`Callback process completed`. These indicate process delivery, not confirmation
that the game accepted the authentication code.

**UMU is unavailable:**

Update Lutris and re-run the installer:

```bash
flatpak update net.lutris.Lutris
./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

Proton-GE is kept. Lutris is kept unless you choose to uninstall its Flatpak.
Only the library entry managed by this installer is removed.

## Development Checks

```bash
python3 -m unittest discover -s tests -v
for script in *.sh lib/*.sh; do bash -n "$script" || exit; done
```

Tests use temporary directories and mocked external commands; they do not
install applications or run the actual game. A real game launch and browser
login still require testing on a desktop with the MSI and graphics drivers.

The integration follows the upstream [Lutris CLI](https://github.com/lutris/lutris/blob/master/lutris/gui/application.py)
and [Lutris Proton/UMU support](https://github.com/lutris/lutris/blob/master/lutris/util/wine/proton.py).
Callbacks reuse the running container with [flatpak enter](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-enter).
