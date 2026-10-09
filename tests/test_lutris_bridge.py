"""Check the Lutris bridge against mocked Lutris APIs, without a Flatpak install."""

import builtins
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch

BRIDGE = Path(__file__).resolve().parents[1] / "lib/lutris_bridge.py"


class MissingExecutableError(Exception):
    pass


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ptcgl-bridge-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.settings = SimpleNamespace(GAME_CONFIG_DIR=str(root / "config/games"),
                                        DB_PATH=str(root / "data/pga.db"),
                                        RUNTIME_DIR=str(root / "runtime"),
                                        RUNTIME_URL="https://lutris.test/api/runtimes")
        self.games = SimpleNamespace(add_or_update=Mock(), get_games_by_slug=Mock(), delete_game=Mock())
        modules = {name: ModuleType(name) for name in (
            "lutris", "lutris.database", "lutris.database.schema", "lutris.exceptions",
            "lutris.util", "lutris.util.wine", "lutris.util.wine.proton", "lutris.util.http", "lutris.util.extract")}
        modules["lutris"].settings = self.settings
        modules["lutris.database"].games = self.games
        modules["lutris.database.schema"].syncdb = Mock()
        modules["lutris.exceptions"].MissingExecutableError = MissingExecutableError
        modules["lutris.util.wine"].proton = modules["lutris.util.wine.proton"]
        modules["lutris.util.wine.proton"].get_umu_path = Mock(return_value="/app/umu/umu-run")
        self.request = modules["lutris.util.http"].Request = Mock()
        self.extract = modules["lutris.util.extract"].extract_archive = Mock()
        with patch.dict(sys.modules, modules):
            spec = importlib.util.spec_from_file_location("ptcgl_bridge", BRIDGE)
            self.bridge = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.bridge)
        self.modules = modules
        self.args = SimpleNamespace(config_id="ptcgl-linux", title="Pokemon TCG Live", slug="ptcgl",
                                    prefix=str(root / "prefix espaço/pfx"),
                                    exe=str(root / 'prefix espaço/pfx/Game "quoted".exe'),
                                    version="GE-Proton-test", proton_root=str(root / "runner"),
                                    callback=True, arguments=["tpcitcgapp://callback?code=a%22&state=b"])

    def test_register_uses_wine_runner_and_matching_prefix(self):
        self.bridge.register_game(self.args)
        config = json.loads((Path(self.settings.GAME_CONFIG_DIR) / "ptcgl-linux.yml").read_text())
        self.assertEqual(config["game"]["prefix"], self.args.prefix)
        self.assertEqual(config["game"]["exe"], self.args.exe)
        self.assertEqual(config["wine"]["version"], self.args.version)
        self.assertEqual(config["system"]["env"]["PROTONPATH"], self.args.proton_root)
        self.assertEqual(self.games.add_or_update.call_args.kwargs["runner"], "wine")
        self.assertEqual(self.games.add_or_update.call_args.kwargs["configpath"], "ptcgl-linux")
        self.bridge.register_game(self.args)
        self.assertEqual(len(list(Path(self.settings.GAME_CONFIG_DIR).glob("*.yml"))), 1)
        self.assertEqual(self.games.add_or_update.call_args_list[0], self.games.add_or_update.call_args_list[1])

    def test_imports_use_lutris_entry_point_and_restore_helper_arguments(self):
        imported_entry_points = []
        original_import = builtins.__import__

        def import_with_wrapper_lookup(name, *args, **kwargs):
            if name == "lutris.util.wine":
                imported_entry_points.append(sys.argv[0])
            return original_import(name, *args, **kwargs)

        argv = [str(BRIDGE), "wine-dir"]
        spec = importlib.util.spec_from_file_location("ptcgl_bridge_regression", BRIDGE)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, self.modules), patch.object(sys, "argv", argv):
            with patch.object(builtins, "__import__", side_effect=import_with_wrapper_lookup):
                spec.loader.exec_module(module)
            self.assertEqual(sys.argv, [str(BRIDGE), "wine-dir"])
        self.assertEqual(imported_entry_points, ["/app/bin/lutris"])

    def test_failed_lutris_import_restores_helper_entry_point(self):
        original_import = builtins.__import__

        def failing_import(name, *args, **kwargs):
            if name == "lutris.util.wine":
                raise ImportError("runtime import failed")
            return original_import(name, *args, **kwargs)

        spec = importlib.util.spec_from_file_location("ptcgl_bridge_failed_import", BRIDGE)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, self.modules), patch.object(sys, "argv", [str(BRIDGE), "wine-dir"]):
            with patch.object(builtins, "__import__", side_effect=failing_import):
                with self.assertRaisesRegex(ImportError, "runtime import failed"):
                    spec.loader.exec_module(module)
            self.assertEqual(sys.argv, [str(BRIDGE), "wine-dir"])

    def test_direct_launch_uses_the_configured_proton_and_prefix(self):
        with patch.object(self.bridge.os, "execvpe") as execute:
            self.bridge.run_proton(self.args)
        executable, argv, env = execute.call_args.args
        self.assertEqual(executable, "/app/umu/umu-run")
        self.assertEqual(argv, [executable, self.args.exe, *self.args.arguments])
        self.assertEqual(env["WINEPREFIX"], self.args.prefix)
        self.assertEqual(env["PROTONPATH"], self.args.proton_root)
        self.assertEqual(env["WINE_CPU_TOPOLOGY"], "2:0,1")
        self.assertEqual(env["PROTON_VERB"], "waitforexitandrun")

    def test_remove_preserves_other_lutris_entries(self):
        self.bridge.register_game(self.args)
        Path(self.settings.DB_PATH).touch()
        self.games.get_games_by_slug.return_value = [
            {"id": "1", "configpath": "ptcgl-linux"}, {"id": "2", "configpath": "user-other-install"}]
        self.bridge.remove_game(self.args)
        self.games.delete_game.assert_called_once_with("1")
        self.assertFalse((Path(self.settings.GAME_CONFIG_DIR) / "ptcgl-linux.yml").exists())

    def test_missing_umu_downloads_runtime_before_retrying(self):
        self.bridge.get_umu_path.side_effect = [MissingExecutableError(), "/runtime/umu/umu-run"]
        self.request.return_value.get.side_effect = [
            SimpleNamespace(json={"runtimes": {"umu": {"url": "https://lutris.test/umu.tar.gz"}}}),
            SimpleNamespace(content=b"archive fixture")]
        with patch.dict(sys.modules, self.modules):
            self.assertEqual(self.bridge.ensure_umu(), "/runtime/umu/umu-run")
        self.assertEqual(self.request.call_args_list[0].args[0], self.settings.RUNTIME_URL + "/versions")
        self.extract.assert_called_once()
        self.assertEqual(self.extract.call_args.args[1], str(Path(self.settings.RUNTIME_DIR) / "umu"))
        self.assertEqual(self.extract.call_args.kwargs, {"merge_single": True})


if __name__ == "__main__":
    unittest.main()
