"""Exercise shell install/launch/login flows without changing the real desktop."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
GAME_PATH = Path('drive_c/users/steamuser/The Pokémon Company International/Pokémon Trading Card Game Live/Pokemon TCG Live.exe')

# Record argv exactly, including callback punctuation and spaces in filenames.
MOCK_COMMAND = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["TEST_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == "flatpak":
    if args[0] == "--version":
        print("Flatpak test")
    elif args[0] == "ps":
        if os.environ.get("TEST_RUNNING_GAME", "1") == "1":
            print("100\\tnet.lutris.Lutris\\n101\\tnet.lutris.Lutris\\n102\\tother.application")
    elif args[0] == "enter" and "--probe" in args:
        sys.exit(0 if args[1] == "101" else 1)
    elif args[0] == "info":
        if os.environ.get("TEST_MISSING_LUTRIS") == "1":
            sys.exit(1)
        if "--system" in args:
            sys.exit(0 if os.environ.get("TEST_SYSTEM") == "1" else 1)
        if "--user" in args:
            sys.exit(1 if os.environ.get("TEST_SYSTEM") == "1" else 0)
    elif "--command=python3" in args:
        cmd = args[4]
        rest = args[5:]
        if cmd == "wine-dir":
            print(os.environ["TEST_RUNNERS"])
        elif cmd == "ensure-umu":
            print("/app/share/umu/umu-run")
        elif cmd == "run" and "msiexec" in rest:
            prefix = pathlib.Path(rest[rest.index("--prefix") + 1])
            exe = prefix / os.environ["TEST_GAME_PATH"]
            if os.environ.get("TEST_FAIL_MSI") != "1":
                exe.parent.mkdir(parents=True, exist_ok=True)
                exe.touch()
            else:
                sys.exit(1)
elif name == "curl":
    print(json.dumps({"tag_name": "GE-Proton-test", "assets": [{"name": "GE-Proton-test.tar.gz", "browser_download_url": "https://example.test/GE-Proton-test.tar.gz"}]}))
elif name == "jq":
    if args == ["--version"]:
        print("jq-test")
    else:
        release = json.load(sys.stdin)
        print(release["tag_name"] if args[-1] == ".tag_name" else release["assets"][0]["browser_download_url"])
elif name == "xdg-mime" and args[0] == "query":
    print("ptcgl-handler.desktop")
'''


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ptcgl-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # Spaces, quotes, dollars, and backticks must survive state serialization.
        self.home = self.root / "home espaço 'quoted' $literal `literal`"
        self.home.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("flatpak", "curl", "jq", "xdg-mime", "update-desktop-database"):
            command = self.bin / name
            command.write_text(MOCK_COMMAND)
            command.chmod(0o755)
        self.runners = self.home / ".var/app/net.lutris.Lutris/data/lutris/runners/wine"
        proton = self.runners / "GE-Proton-test/proton"
        proton.parent.mkdir(parents=True)
        proton.touch()
        self.log = self.root / "commands.jsonl"
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}",
                        TEST_LOG=str(self.log), TEST_RUNNERS=str(self.runners), TEST_GAME_PATH=str(GAME_PATH))
        self.state_dir = self.home / ".config/ptcgl-linux"
        self.msi = self.root / "installer with spaces.msi"
        self.msi.touch()

    def run_script(self, script, *args, input=None, expected=0):
        result = subprocess.run([str(REPO / script), *map(str, args)], env=self.env,
                                input=input, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_install_launch_and_callback(self):
        self.run_script("install.sh", self.msi)
        calls = self.calls()
        registration = next(call for call in calls if "register" in call)
        prefix = registration[registration.index("--prefix") + 1]
        self.assertTrue((Path(prefix) / GAME_PATH).exists())
        self.assertNotIn("heroic", json.dumps(calls).lower())
        self.run_script("launch.sh")
        self.assertEqual(self.calls()[-1], ["flatpak", "run", "net.lutris.Lutris", "lutris:rungame/ptcgl"])
        self.run_script("launch.sh", "--direct")
        self.assertNotIn("--callback", self.calls()[-1])
        url = 'tpcitcgapp://callback?code=a%20b&state=quoted%22;$(touch BAD)'
        handler = self.home / ".local/bin/ptcgl-uri-handler"
        subprocess.run([str(handler), url], env=self.env, check=True, capture_output=True)
        callback = self.calls()[-1]
        self.assertEqual(callback[-1], url)
        self.assertEqual(callback[:4], ["flatpak", "enter", "101", "/usr/bin/python3"])
        self.assertNotIn("--command=python3", callback)
        self.assertEqual(callback[callback.index("--prefix") + 1], prefix)
        self.assertTrue((self.state_dir / "lib/lutris_bridge.py").exists())
        self.assertTrue((self.state_dir / "lib/callback.py").exists())
        callback_log = (self.state_dir / "callback.log").read_text()
        self.assertIn("Entering game session 101", callback_log)
        self.assertIn("Callback process completed", callback_log)
        self.assertNotIn(url, callback_log)
        self.run_script("install.sh")  # Existing game needs no MSI.
        self.assertEqual(sum("msiexec" in call for call in self.calls()), 1)

    def test_migrate_old_prefix_and_reject_old_launch(self):
        old = self.home / "Games/Heroic/Prefixes/default/Pokemon TCG Live"
        exe = old / "pfx" / GAME_PATH
        exe.parent.mkdir(parents=True)
        exe.touch()
        self.state_dir.mkdir(parents=True)
        (self.state_dir / "state").write_text(f"PROTON_VERSION=old\nPREFIX_PARENT={shlex.quote(str(old))}\n")
        self.run_script("launch.sh", expected=1)
        self.run_script("install.sh")
        registration = next(call for call in self.calls() if "register" in call)
        self.assertEqual(registration[registration.index("--prefix") + 1], str(old / "pfx"))
        self.assertFalse(any("msiexec" in call for call in self.calls()))

    def test_missing_lutris_is_installed_from_flathub(self):
        self.env["TEST_MISSING_LUTRIS"] = "1"
        self.run_script("install.sh", self.msi)
        self.assertIn(["flatpak", "install", "--user", "-y", "flathub", "net.lutris.Lutris"], self.calls())

    def test_system_flatpak_is_reused(self):
        self.env["TEST_SYSTEM"] = "1"
        self.run_script("install.sh", self.msi)
        self.assertFalse(any(call[:2] == ["flatpak", "install"] for call in self.calls()))

    def test_failed_msi_does_not_save_success_state(self):
        self.env["TEST_FAIL_MSI"] = "1"
        self.run_script("install.sh", self.msi, expected=1)
        self.assertFalse((self.state_dir / "state").exists())
        self.assertFalse(any("register" in call for call in self.calls()))

    def test_invalid_urls_do_not_launch(self):
        self.run_script("install.sh", self.msi)
        count = len(self.calls())
        self.run_script("launch.sh", "https://example.test", expected=1)
        handler = self.home / ".local/bin/ptcgl-uri-handler"
        result = subprocess.run([str(handler), "https://example.test"], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.calls()), count)

    def test_callback_requires_the_existing_game_session(self):
        self.run_script("install.sh", self.msi)
        self.env["TEST_RUNNING_GAME"] = "0"
        count = len(self.calls())
        result = self.run_script("launch.sh", "tpcitcgapp://callback?code=test", expected=1)
        self.assertIn("Running PTCGL session not found", result.stderr)
        self.assertFalse(any(call[:2] == ["flatpak", "run"] for call in self.calls()[count:]))

    def test_uninstall_removes_managed_entry_and_keeps_proton(self):
        self.run_script("install.sh", self.msi)
        self.run_script("uninstall.sh", input="y\ny\nn\n")
        removal = next(call for call in self.calls() if "remove" in call)
        self.assertEqual(removal[-4:], ["--slug", "ptcgl", "--config-id", "ptcgl-linux"])
        self.assertFalse(self.state_dir.exists())
        self.assertTrue((self.runners / "GE-Proton-test/proton").exists())


if __name__ == "__main__":
    unittest.main()
