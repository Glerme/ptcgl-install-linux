# PTCGL Linux Installer

Automated installer for Pokémon TCG Live on Linux via Heroic + Proton-GE.

Works on any Linux distro with Flatpak support (Pop!_OS, Arch, Fedora, openSUSE, Ubuntu, Debian…).

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
# OR open Heroic Games Launcher and click Play
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
~/.local/bin/ptcgl-uri-handler "tpcitcgapp://callback?code=..."
```

## Scripts

| Script | Purpose |
|--------|---------|
| `install.sh` | Full installation: Heroic, Proton-GE, game, Heroic entry, URI handler |
| `launch.sh` | Launch the game directly (no Heroic GUI needed) |
| `register-handler.sh` | Re-register the `tpcitcgapp://` URI handler (run if login breaks) |
| `reset.sh` | Fix common issues: daily quests stuck, game frozen on home page |
| `uninstall.sh` | Remove everything (prefix, Heroic entry, URI handler, state) |

## Troubleshooting

**Daily quests don't load / game is unresponsive:**

```bash
./reset.sh
```

Deletes cached game data. Safe — your account and deck data are on Pokémon's servers.

**Game doesn't appear in Heroic:**

Use `./launch.sh` directly. Re-run `./install.sh` to rebuild the Heroic entry.

**URI handler not working after a browser update:**

```bash
./register-handler.sh
```

## How It Works

| Component | Role |
|-----------|------|
| Heroic Flatpak | Visual launcher; works across all distros via Flathub |
| Proton-GE-Latest | Wine layer with DXVK/VKD3D for DirectX support |
| `tpcitcgapp://` handler | Intercepts OAuth callbacks from browser, passes to game exe |
| `WINE_CPU_TOPOLOGY=2:0,1` | Limits to 2 CPU cores — fixes daily quest loading bug |

## Uninstall

```bash
./uninstall.sh
```

Proton-GE and Heroic are kept by default (useful for other games).
