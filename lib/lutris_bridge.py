#!/usr/bin/env python3
"""Run inside the Lutris Flatpak to use its paths, database API, and UMU."""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

# Meson installs Lutris here; it is not necessarily a Python site-package.
sys.path.insert(0, "/app/lib/lutris")

# Lutris resolves lutris-wrapper relative to sys.argv[0] during import.
# Our helper lives outside /app/bin, so give these imports the same entry
# point as the Lutris CLI, then restore our arguments for argparse.
helper_entry_point = sys.argv[0]
try:
    sys.argv[0] = "/app/bin/lutris"
    from lutris import settings
    from lutris.database import games
    from lutris.database.schema import syncdb
    from lutris.exceptions import MissingExecutableError
    from lutris.util.wine import proton
    from lutris.util.wine.proton import get_umu_path
finally:
    sys.argv[0] = helper_entry_point


def ensure_umu():
    try:
        return get_umu_path()
    except MissingExecutableError:
        pass
    # UMU is a Lutris runtime component, downloaded on first use rather than
    # necessarily included in a fresh Flatpak installation.
    from lutris.util.http import Request
    from lutris.util.extract import extract_archive

    runtime_dir = Path(settings.RUNTIME_DIR)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    metadata = Request(settings.RUNTIME_URL + "/versions").get().json
    component = metadata["runtimes"]["umu"]
    content = Request(component["url"]).get().content
    suffix = "".join(Path(component["url"]).suffixes)
    with tempfile.NamedTemporaryFile(dir=runtime_dir, suffix=suffix) as archive:
        archive.write(content)
        archive.flush()
        extract_archive(archive.name, str(runtime_dir / "umu"), merge_single=True)
    # Lutris caches this function, but failed lookups are not cached.
    return get_umu_path()


def register_game(args):
    config_dir = Path(settings.GAME_CONFIG_DIR)
    config_dir.mkdir(parents=True, exist_ok=True)
    Path(settings.DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    syncdb()
    config = {
        "game": {
            "exe": args.exe,
            "prefix": args.prefix,
            "arch": "win64",
            "working_dir": str(Path(args.exe).parent),
        },
        "wine": {"version": args.version},
        "system": {
            "env": {"WINE_CPU_TOPOLOGY": "2:0,1", "PROTONPATH": args.proton_root},
        },
    }
    # JSON is valid YAML; serialize paths rather than interpolating shell text.
    config_path = config_dir / f"{args.config_id}.yml"
    temporary = config_path.with_suffix(".tmp")
    temporary.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(config_path)
    games.add_or_update(
        name=args.title,
        slug=args.slug,
        runner="wine",
        configpath=args.config_id,
        directory=args.prefix,
        executable=args.exe,
        installed=1,
        platform="Windows",
    )


def remove_game(args):
    if Path(settings.DB_PATH).exists():
        syncdb()
        for game in games.get_games_by_slug(args.slug):
            if game["configpath"] == args.config_id:
                games.delete_game(game["id"])
    (Path(settings.GAME_CONFIG_DIR) / f"{args.config_id}.yml").unlink(missing_ok=True)


def run_proton(args):
    env = os.environ.copy()
    env.update(
        WINEPREFIX=args.prefix,
        WINEARCH="win64",
        PROTONPATH=args.proton_root,
        GAMEID="umu-default",
        WINE_CPU_TOPOLOGY="2:0,1",
        PROTON_VERB="waitforexitandrun",
    )
    umu = get_umu_path()
    os.execvpe(umu, [umu, args.exe, *args.arguments], env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("wine-dir")
    commands.add_parser("ensure-umu")
    register = commands.add_parser("register")
    remove = commands.add_parser("remove")
    for command in (register, remove):
        command.add_argument("--slug", required=True)
        command.add_argument("--config-id", required=True)
    register.add_argument("--title", required=True)
    register.add_argument("--version", required=True)
    register.add_argument("--proton-root", required=True)
    register.add_argument("--prefix", required=True)
    register.add_argument("--exe", required=True)
    run = commands.add_parser("run")
    run.add_argument("--proton-root", required=True)
    run.add_argument("--prefix", required=True)
    run.add_argument("exe")
    run.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command == "wine-dir":
        print(getattr(proton, "PROTON_DIR", settings.WINE_DIR))
    elif args.command == "ensure-umu":
        print(ensure_umu())
    elif args.command == "register":
        register_game(args)
    elif args.command == "remove":
        remove_game(args)
    else:
        run_proton(args)


if __name__ == "__main__":
    main()
