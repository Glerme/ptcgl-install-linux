# PTCGL login on Linux: send the callback by hand (Linux Mint)

The game's login hands the result back through a `tpcitcgapp://callback?code=...` link.
On Windows, a second copy of the game starts, sees the first one and passes the code to it.
Under Wine this only works when the second copy uses **the same wineserver** as the running game,
meaning the same Wine/Proton build, the same prefix and, for Flatpak, the same sandbox.
Steam, Heroic and Lutris start a fresh Proton on the host, so you get a second window and no login.

The fix is to run the second copy inside the running game's environment yourself.

## 1. Get the callback URL

1. Start the game and click **Login**. Leave the game open on that screen the whole time.
2. In the browser, press **F12** and open the **Console** tab *before* you log in.
3. Log in. The redirect fails, and the console shows something like
   `Failed to launch 'tpcitcgapp://callback?code=...'`.
   You can also find it in the **Network** tab.
4. Copy the full `tpcitcgapp://callback?code=...` URL. The code expires quickly, so do the next step right away.

## 2a. Heroic (Flatpak or .deb) or Lutris

Open a terminal and paste this block. Put your URL between the single quotes on the first line:

```bash
URL='tpcitcgapp://callback?code=PASTE_HERE'

# The Wine process of the game: its command line holds a Windows path (C:\...)
pid=$(pgrep -of '[\\]Pokemon TCG Live[.]exe')
[ -n "$pid" ] || { echo "Game is not running"; }
wine="$(dirname "$(readlink /proc/$pid/exe)")/wine"
exe=$(tr '\0' '\n' < /proc/$pid/cmdline | grep -m1 -i 'Pokemon TCG Live.exe')
echo "pid=$pid  wine=$wine  exe=$exe"

if [ -e "/proc/$pid/root/.flatpak-info" ]; then
  # Flatpak Heroic/Lutris: enter the game's sandbox (it copies the game's env)
  flatpak enter "$pid" "$wine" "$exe" "$URL"
else
  # Native launcher: copy the game's environment, then run the same wine
  ( while IFS= read -rd '' v; do export "$v"; done < /proc/$pid/environ
    "$wine" "$exe" "$URL" )
fi
```

The running game should finish logging in, and no second window should open.

Notes:
- In Heroic, keep **UMU disabled** for the game. With UMU on, the game runs in Steam's container and this block can't reach it.
- If `echo` prints an empty `pid`, the game isn't running, or the `.exe` has a different name. Check with `pgrep -af 'TCG'`.
- If `flatpak enter` says `Operation not permitted`, update flatpak with `sudo apt update && sudo apt upgrade` and try again.

## 2b. Steam (native .deb, game added as a Non-Steam Game with Proton)

On Steam the game runs inside the Steam Linux Runtime container, so you have to ask that container to run the command.

1. In Steam, right-click the game, then **Properties → Launch Options**, and set:
   ```
   STEAM_COMPAT_LAUNCHER_SERVICE=proton %command%
   ```
2. Start the game and get the URL as in step 1.
3. In a terminal:
   ```bash
   URL='tpcitcgapp://callback?code=PASTE_HERE'
   LC=$(find ~/.steam/root/steamapps/common -name steam-runtime-launch-client -path '*sniper*' | head -1)
   pid=$(pgrep -of '[\\]Pokemon TCG Live[.]exe')
   exe=$(tr '\0' '\n' < /proc/$pid/cmdline | grep -m1 -i 'Pokemon TCG Live.exe')

   "$LC" --list          # prints something like --bus-name=com.steampowered.App1234567890
   "$LC" --bus-name=com.steampowered.AppXXXXXXXX --directory='' -- wine "$exe" "$URL"
   ```
   Replace `AppXXXXXXXX` with the name that `--list` printed.

If `find` prints nothing, look for `SteamLinuxRuntime_sniper` under `~/.steam/root/steamapps/common` and install it from your Steam Library (Tools).

## Why not just close the game and launch it with the URL?

The code belongs to the login that the running game started. A fresh copy of the game can't use it,
so you have to send it to the window that is already open.
