# PTCGL Linux Installer

Automated installer for Pokémon TCG Live on Linux via Heroic or Lutris + Proton-GE.

Works on any Linux distro with Flatpak support (Pop!_OS, Arch, Fedora, openSUSE, Ubuntu, Debian…).

Based on: https://www.reddit.com/r/PTCGL/comments/1q05iny/guide_how_to_install_and_login_to_pokemon_tcg/

## Requirements

- A Linux distro with `flatpak` available (or the script will install it)
- `PokemonTCGLiveInstaller.msi` downloaded from the official Pokémon website
- Internet connection for Flatpak + Proton-GE download (~1-2 GB total)

## Quick Start

```bash
./install.sh ~/Downloads/PokemonTCGLiveInstaller.msi                     # asks which launcher
./install.sh --launcher lutris ~/Downloads/PokemonTCGLiveInstaller.msi   # or heroic (default)
```

Already installed? Re-run `./install.sh` (no MSI needed): it skips the game install and only
refreshes Proton, the launcher entry, the state and the URI handler. If Heroic's
`GE-Proton-latest` exists it is reused, and you are offered to delete old unused `GE-Proton<N>` dirs.

Then launch the game:

```bash
./launch.sh        # Direct launch
# OR open Heroic / Lutris and click Play
```

## First-Time Login

1. Launch the game and click **"Login to access more features!"**
2. A browser window opens — log in to your Pokémon account
3. The browser will ask to open the `tpcitcgapp://` link — **allow it**
4. The game receives the auth token automatically
5. You stay logged in for future sessions

If the game is already open (e.g. it restarted after an update), the handler delivers the
callback to that running window instead of opening a second one. It enters the launcher's
Flatpak sandbox with `flatpak enter`. Each callback is logged to `~/.config/ptcgl-linux/handler.log`.

If your browser blocks the `tpcitcgapp://` redirect, press F12 on the login page,
copy the `tpcitcgapp://callback?code=...` URL from the console, then run:

```bash
~/.local/bin/ptcgl-uri-handler "tpcitcgapp://callback?code=..."
```

Using Steam, Heroic or Lutris without this installer and getting a second game window on login?
See the manual callback guide: [English](docs/manual-login-callback.md) | [Português (BR)](docs/manual-login-callback.pt-BR.md).

## Scripts

| Script | Purpose |
|--------|---------|
| `install.sh` | Full installation: Heroic or Lutris, Proton-GE, game, launcher entry, URI handler. Re-run to update |
| `launch.sh` | Launch the game directly (no Heroic GUI needed) |
| `register-handler.sh` | Re-register the `tpcitcgapp://` URI handler (run if login breaks) |
| `reset.sh` | Fix common issues: daily quests stuck, game frozen on home page |
| `uninstall.sh` | Remove everything (prefix, Heroic/Lutris entry, URI handler, state) |

## Troubleshooting

**Daily quests don't load / game is unresponsive:**

```bash
./reset.sh
```

Deletes cached game data. Safe — your account and deck data are on Pokémon's servers.

**Game doesn't appear in Heroic:**

Use `./launch.sh` directly. Re-run `./install.sh` to rebuild the Heroic entry.

**Login opens a second game window:**

Re-run `./install.sh` (or `./register-handler.sh`) to get the new handler, then check
`~/.config/ptcgl-linux/handler.log`: `flatpak-enter` means it went to the running game,
`host-proton` means it fell back to a new instance.

**URI handler not working after a browser update:**

```bash
./register-handler.sh
```

## How It Works

| Component | Role |
|-----------|------|
| Heroic or Lutris Flatpak | Visual launcher; works across all distros via Flathub |
| Proton-GE-Latest | Wine layer with DXVK/VKD3D for DirectX support |
| `tpcitcgapp://` handler | Intercepts OAuth callbacks from browser, passes to game exe |
| `WINE_CPU_TOPOLOGY=2:0,1` | Limits to 2 CPU cores — fixes daily quest loading bug |

## Uninstall

```bash
./uninstall.sh
```

Proton-GE, Heroic and Lutris are kept by default (useful for other games).
