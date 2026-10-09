#!/usr/bin/env python3
"""Deliver a callback inside the existing game's Flatpak/Proton container."""

import argparse
import os
from pathlib import Path
import sys


def running_environment(prefix, executable, proc_root=Path("/proc")):
    """Find the game and its wineserver in this PID namespace and prefix."""
    target_prefix = Path(prefix).resolve()
    game_name = Path(executable).name[:15]
    game_env = None
    server_env = None
    for process in proc_root.iterdir():
        if not process.name.isdigit():
            continue
        try:
            name = (process / "comm").read_text().strip()
            if name not in (game_name, "wineserver"):
                continue
            env = dict(
                entry.split("=", 1)
                for entry in (process / "environ").read_bytes().decode(errors="replace").split("\0")
                if "=" in entry
            )
            if not env.get("WINEPREFIX") or Path(env["WINEPREFIX"]).resolve() != target_prefix:
                continue
            if name == game_name:
                game_env = env
            elif name == "wineserver":
                server_env = env
        except (OSError, ValueError):
            continue
    # Callback containers can contain another game process while relying on a
    # wineserver in a different container. Only enter the original session.
    if game_env is None or server_env is None:
        return None
    return server_env


def callback_command(env, executable, url):
    proton_root = env.get("PROTONPATH")
    if not proton_root:
        raise RuntimeError("Running game has no PROTONPATH")
    proton = Path(proton_root) / "proton"
    if not proton.is_file():
        raise RuntimeError("Running game's Proton executable is unavailable")
    env = env.copy()
    # These client-specific values can refer to FDs or memory from the old
    # process, and must not be inherited by a new Wine client.
    for key in ("WINESERVERSOCKET", "WINELOADERNOEXEC", "WINEPRELOADRESERVE"):
        env.pop(key, None)
    env["PROTON_VERB"] = "runinprefix"
    return [str(proton), "runinprefix", executable, url], env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--exe", required=True)
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("url", nargs="?")
    args = parser.parse_args()
    env = running_environment(args.prefix, args.exe)
    if args.probe:
        return 0 if env else 1
    if not args.url or not args.url.startswith("tpcitcgapp://"):
        parser.error("A tpcitcgapp:// callback URL is required")
    if env is None:
        print("[ptcgl-handler] The running game session was not found", file=sys.stderr)
        return 1
    command, env = callback_command(env, args.exe, args.url)
    os.chdir(Path(args.exe).parent)
    os.execvpe(command[0], command, env)


if __name__ == "__main__":
    sys.exit(main())
