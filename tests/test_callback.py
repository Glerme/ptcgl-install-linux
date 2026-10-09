"""Verify callbacks join the exact game/prefix rather than spawning UMU again."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("ptcgl_callback", Path(__file__).resolve().parents[1] / "lib/callback.py")
callback = importlib.util.module_from_spec(spec)
spec.loader.exec_module(callback)


class CallbackTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ptcgl-callback-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.proc = self.root / "proc"
        self.proc.mkdir()
        self.prefix = self.root / "prefix/pfx"
        self.prefix.mkdir(parents=True)
        (self.prefix / "pfx").symlink_to(self.prefix, target_is_directory=True)
        self.proton_root = self.root / "GE-Proton-test"
        self.proton_root.mkdir()
        (self.proton_root / "proton").touch()
        self.exe = str(self.prefix / "drive_c/Pokemon TCG Live.exe")
        self.env = {"WINEPREFIX": str(self.prefix / "pfx"), "PROTONPATH": str(self.proton_root),
                    "STEAM_COMPAT_DATA_PATH": str(self.prefix), "WINE_CPU_TOPOLOGY": "2:0,1",
                    "DISPLAY": ":0", "PROTON_VERB": "waitforexitandrun"}

    def process(self, pid, name, env):
        path = self.proc / str(pid)
        path.mkdir()
        (path / "comm").write_text(name + "\n")
        (path / "environ").write_bytes("\0".join(f"{key}={value}" for key, value in env.items()).encode())

    def test_original_container_matches_symlinked_prefix_and_wineserver(self):
        self.process(20, "Pokemon TCG Liv", self.env)
        self.process(21, "wineserver", self.env)
        self.assertEqual(callback.running_environment(self.prefix, self.exe, self.proc), self.env)

    def test_callback_container_without_own_wineserver_is_rejected(self):
        self.process(20, "Pokemon TCG Liv", self.env)
        self.assertIsNone(callback.running_environment(self.prefix, self.exe, self.proc))

    def test_unrelated_wineserver_is_rejected(self):
        self.process(20, "Pokemon TCG Liv", self.env)
        self.process(21, "wineserver", dict(self.env, WINEPREFIX=str(self.root / "other-game")))
        self.assertIsNone(callback.running_environment(self.prefix, self.exe, self.proc))

    def test_callback_preserves_runtime_and_exact_url_without_prefix_initialization(self):
        url = 'tpcitcgapp://callback?code=a%20b&state="quoted";$(literal)'
        original = dict(self.env, WINESERVERSOCKET="123", WINELOADERNOEXEC="1", WINEPRELOADRESERVE="123")
        command, env = callback.callback_command(original, self.exe, url)
        self.assertEqual(command, [str(self.proton_root / "proton"), "runinprefix", self.exe, url])
        self.assertEqual(env["PROTON_VERB"], "runinprefix")
        for key in ("WINEPREFIX", "PROTONPATH", "STEAM_COMPAT_DATA_PATH", "WINE_CPU_TOPOLOGY", "DISPLAY"):
            self.assertEqual(env[key], self.env[key])
        for key in ("WINESERVERSOCKET", "WINELOADERNOEXEC", "WINEPRELOADRESERVE"):
            self.assertNotIn(key, env)
        self.assertEqual(original["PROTON_VERB"], "waitforexitandrun")


if __name__ == "__main__":
    unittest.main()
