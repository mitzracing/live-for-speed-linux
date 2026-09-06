#!/usr/bin/env python3
"""Exercise preservation and source-verification orchestration on disposable data."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PlayerSafety(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lfs-player-safety-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("data", "state", "cache", "log", "runtime"):
            (self.root / name).mkdir()
        for path in (ROOT / "share/lfs-linux").glob("*"):
            if path.is_file():
                shutil.copyfile(path, self.root / "data" / path.name)
        self.game = self.root / "state/prefix/drive_c/LFS"
        self.game.mkdir(parents=True)
        (self.game / "LFS.exe").write_bytes(b"fixture-game")
        (self.game / "cfg.txt").write_text("player-settings")
        self.pin("LFS_EXE_SIZE", len(b"fixture-game"))
        self.pin("LFS_EXE_SHA256", hashlib.sha256(b"fixture-game").hexdigest())

    def pin(self, key, value):
        with (self.root / "data/release.env").open("a") as stream:
            stream.write(f"\n{key}='{value}'\n")

    def run_core(self, script, *, locale=None):
        env = dict(os.environ, LFS_LINUX_DATA_DIR=str(self.root / "data"),
                   LFS_LINUX_STATE_DIR=str(self.root / "state"),
                   LFS_LINUX_CACHE_DIR=str(self.root / "cache"),
                   LFS_LINUX_LOG_DIR=str(self.root / "log"),
                   XDG_RUNTIME_DIR=str(self.root / "runtime"),
                   TEST_ROOT=str(self.root), TEST_REPO=str(ROOT))
        if locale is not None:
            env["LC_ALL"] = locale
        return subprocess.run(["bash", "-c", 'set -- help\nsource "$TEST_REPO/libexec/lfs-linux-core" >/dev/null\n' + script],
                              env=env, text=True, capture_output=True)

    def prepare_public_launch(self):
        """Install a tiny, authenticated runtime fixture; never use host Wine or data."""
        wine = self.root / "wine/usr/bin/wine"
        wine.parent.mkdir(parents=True)
        (self.root / "wine/usr/lib/wine").mkdir(parents=True)
        wine.write_text('''#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'wine-11.15\\n' ;;
  wineboot|reg) ;;
  *)
    if [[ "${TEST_UPDATE:-0}" == 1 ]]; then
      printf updated-game-executable >"$1"
      printf updated-asset >"$(dirname "$1")/new-from-update.stock"
    fi
    printf 'played\\n' >>"$TEST_ROOT/played"
    ;;
esac
''')
        server = wine.with_name("wineserver")
        server.write_text('''#!/usr/bin/env bash
[[ "${1:-}" != --wait ]] || exit "${TEST_WAIT_STATUS:-0}"
exit 0
''')
        wine.chmod(0o755)
        server.chmod(0o755)
        for field, relative in (("HELMET", "data/skins_dds/HEL_DEFAULT.dds"),
                                ("TRACK", "data/wld/BLACKWOOD.wld"),
                                ("VEHICLE", "data/veh/XFG.vob")):
            path = self.game / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"asset")
            self.pin(f"LFS_REQUIRED_{field}_SIZE", 5)
            self.pin(f"LFS_REQUIRED_{field}_SHA256", hashlib.sha256(b"asset").hexdigest())
        self.pin("LFS_TREE_MIN_FILE_COUNT", 4)
        self.pin("LFS_TREE_MIN_BYTES", 1)
        for kind, root, field in (("wine", self.root / "wine", "WINE_RUNTIME_MANIFEST"),
                                  ("lfs", self.game, "LFS_STOCK_MANIFEST")):
            manifest = self.root / "data" / f"{kind}.manifest"
            subprocess.run([str(ROOT / "scripts/generate-payload-manifest.py"), kind,
                            str(root), str(manifest)], check=True, capture_output=True)
            self.pin(field + "_NAME", manifest.name)
            self.pin(field + "_SIZE", manifest.stat().st_size)
            self.pin(field + "_SHA256", hashlib.sha256(manifest.read_bytes()).hexdigest())
            self.pin(field + "_ENTRIES", sum(line.startswith(("f\t", "l\t")) for line in manifest.read_text().splitlines()))
        for dll in ("d3d11", "dxgi"):
            for root in (self.root / "state/runtime/dxvk-3.0.2/x32",
                         self.root / "state/prefix/drive_c/windows/syswow64"):
                root.mkdir(parents=True, exist_ok=True)
                (root / f"{dll}.dll").write_bytes(b"dll")
            self.pin(f"DXVK_{dll.upper()}_X32_SIZE", 3)
            self.pin(f"DXVK_{dll.upper()}_X32_SHA256", hashlib.sha256(b"dll").hexdigest())
        archive_path = self.root / "cache/fixture-dxvk.tar"
        with tarfile.open(archive_path, "w") as archive:
            archive.add(self.root / "state/runtime/dxvk-3.0.2", arcname="dxvk-3.0.2")
        self.pin("DXVK_ARCHIVE_NAME", archive_path.name)
        self.pin("DXVK_ARCHIVE_SIZE", archive_path.stat().st_size)
        self.pin("DXVK_ARCHIVE_SHA256", hashlib.sha256(archive_path.read_bytes()).hexdigest())
        self.pin("LFS_INSTALLER_URL", (self.root / "no-installer-download.exe").as_uri())
        (self.root / "state/prefix/system.reg").write_text("#arch=win64\n")
        (self.root / "state/.managed-by-lfs-linux").write_text("fixture\n")
        import re
        values = dict(re.findall(r"^([A-Z0-9_]+)='([^'\n]*)'$", (self.root / "data/release.env").read_text(), re.M))
        fields = ("LFS_VERSION", "LFS_CHANNEL", "LFS_EXE_SIZE", "LFS_EXE_SHA256",
                  "LFS_STOCK_MANIFEST_NAME", "LFS_STOCK_MANIFEST_SIZE", "LFS_STOCK_MANIFEST_SHA256",
                  "LFS_STOCK_MANIFEST_ENTRIES", "DXVK_VERSION", "DXVK_D3D11_X32_SHA256",
                  "DXVK_DXGI_X32_SHA256", "WINE_RUNTIME_VERSION", "WINE_RUNTIME_MANIFEST_SHA256")
        (self.root / "state/install.env").write_text("".join(f"{key}='{values[key]}'\n" for key in fields)
                                                  + "WINE_VERSION='wine-11.15'\nPREFIX_ARCH='win64'\n")

    def call_public(self, command, **extra):
        env = dict(os.environ, LFS_LINUX_DATA_DIR=str(self.root / "data"),
                   LFS_LINUX_LIBEXEC_DIR=str(ROOT / "libexec"),
                   LFS_LINUX_STATE_DIR=str(self.root / "state"),
                   LFS_LINUX_CACHE_DIR=str(self.root / "cache"),
                   LFS_LINUX_LOG_DIR=str(self.root / "log"),
                   LFS_LINUX_WINE=str(self.root / "wine/usr/bin/wine"),
                   XDG_RUNTIME_DIR=str(self.root / "runtime"),
                   TEST_ROOT=str(self.root), DISPLAY=":fixture", **extra)
        return subprocess.run([str(ROOT / "bin/lfs-linux"), command], env=env,
                              text=True, capture_output=True, timeout=30)

    def test_update_wait_failure_does_not_block_next_desktop_launch(self):
        self.prepare_public_launch()
        marker = (self.root / "state/install.env").read_bytes()
        first = self.call_public("launch", TEST_UPDATE="1", TEST_WAIT_STATUS="42")
        self.assertEqual(first.returncode, 42, first.stdout + first.stderr)
        self.assertEqual((self.game / "LFS.exe").read_bytes(), b"updated-game-executable")
        for command in ("ready", "desktop-state", "launch"):
            result = self.call_public(command)
            self.assertEqual(result.returncode, 0, command + result.stdout + result.stderr)
            if command == "desktop-state":
                self.assertEqual(result.stdout.strip(), "ready")
        self.assertEqual((self.root / "played").read_text().splitlines(), ["played", "played"])
        self.assertEqual((self.game / "cfg.txt").read_text(), "player-settings")
        self.assertEqual((self.root / "state/install.env").read_bytes(), marker)
        self.assertFalse((self.root / "state/launch-session.env").exists())
        self.assertEqual(list((self.root / "state").glob("game-update*.manifest")), [])

    def test_legacy_update_evidence_neither_blocks_play_nor_gets_rewritten(self):
        self.prepare_public_launch()
        evidence = self.root / "state/game-update.manifest"
        evidence.write_text("obsolete local inventory\n")
        session = self.root / "state/launch-session.env"
        session.write_text("incomplete old session\n")
        with (self.root / "state/install.env").open("a") as stream:
            stream.write("LFS_BASELINE_KIND='game-update'\nLFS_STOCK_MANIFEST_NAME='missing-old-record'\n")
        marker = (self.root / "state/install.env").read_bytes()
        (self.game / "LFS.exe").write_bytes(b"updated outside wrapper observation")
        result = self.call_public("launch")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "state/install.env").read_bytes(), marker)
        self.assertEqual(evidence.read_text(), "obsolete local inventory\n")
        self.assertEqual(session.read_text(), "incomplete old session\n")

    def test_component_repair_preserves_entire_updated_game_without_download(self):
        self.prepare_public_launch()
        (self.game / "LFS.exe").write_bytes(b"updated-game")
        (self.game / "data/wld/BLACKWOOD.wld").write_bytes(b"updated-track")
        (self.game / "new-game-file").write_bytes(b"new")
        (self.game / "data/skins_dds/HEL_DEFAULT.dds").unlink()
        (self.game / "linked-player-data").symlink_to(self.game / "cfg.txt")
        evidence = self.root / "state/launch-session.env"
        evidence.write_text("old evidence\n")
        before = {p.relative_to(self.game): p.read_bytes() for p in self.game.rglob("*") if p.is_file()}
        result = self.call_public("install")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, {p.relative_to(self.game): p.read_bytes() for p in self.game.rglob("*") if p.is_file()})
        self.assertTrue((self.game / "linked-player-data").is_symlink())
        self.assertEqual(evidence.read_text(), "old evidence\n")
        self.assertFalse((self.root / "cache/LFS_S3_8C20_setup.exe").exists())

    def test_bad_graphics_component_offers_repair_then_plays(self):
        self.prepare_public_launch()
        (self.root / "state/prefix/drive_c/windows/syswow64/dxgi.dll").write_bytes(b"broken")
        result = self.call_public("desktop-state")
        self.assertEqual(result.stdout.strip(), "repair", result.stderr)
        result = self.call_public("install")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.call_public("launch")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_game_appearing_during_bootstrap_is_not_overwritten(self):
        shutil.rmtree(self.game)
        result = self.run_core('''
download_verified() { :; }
extract_lfs_payload() { printf verified >"$2/LFS.exe"; }
verify_extracted_game_tree() {
  mkdir -p "$GAME_DIR"
  printf external-game >"$GAME_EXE"
  printf player-data >"$GAME_DIR/player"
}
install_game
''')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("game folder appeared", result.stderr)
        self.assertEqual((self.game / "LFS.exe").read_text(), "external-game")
        self.assertEqual((self.game / "player").read_text(), "player-data")
        self.assertEqual(list((self.root / "state").glob(".lfs-unpack.*")), [])

    def test_failed_initialization_preserves_existing_player_data(self):
        result = self.run_core('''
validate_existing_game_source
WINE_BIN=/bin/false
WINE_SERVER=/bin/true
WINE_VERSION=fixture
init_prefix
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn("existing player data was preserved", result.stderr)
        self.assertEqual((self.game / "cfg.txt").read_text(), "player-settings")
        self.assertEqual((self.game / "LFS.exe").read_bytes(), b"fixture-game")

    def test_failed_new_prefix_is_cleaned(self):
        shutil.rmtree(self.root / "state/prefix")
        result = self.run_core('''
wine_env() { mkdir -p "$PREFIX"; touch "$PREFIX/partial"; return 1; }
WINE_VERSION=fixture
init_prefix
''')
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / "state/prefix").exists())

    def test_linked_player_directory_is_not_replaced_during_setup(self):
        (self.game / "data").mkdir()
        (self.root / "setups").mkdir()
        (self.root / "setups/player.set").write_text("custom")
        (self.game / "data/setups").symlink_to(self.root / "setups", target_is_directory=True)
        result = self.run_core('install_game')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.game / "data/setups").is_symlink())
        self.assertEqual((self.game / "data/setups/player.set").read_text(), "custom")
        self.assertFalse((self.root / "setups/default.set").exists())

    def test_source_verification_uses_empty_dxvk_destination(self):
        payload = self.root / "payload"
        (payload / "dxvk-3.0.2/x32").mkdir(parents=True)
        for dll in ("d3d11", "dxgi"):
            (payload / f"dxvk-3.0.2/x32/{dll}.dll").write_text(dll)
            self.pin(f"DXVK_{dll.upper()}_X32_SIZE", len(dll))
            self.pin(f"DXVK_{dll.upper()}_X32_SHA256", hashlib.sha256(dll.encode()).hexdigest())
        for name in ("wine", "dxvk"):
            with tarfile.open(self.root / f"cache/{name}.tar", "w") as archive:
                archive.add(payload / "dxvk-3.0.2", arcname="dxvk-3.0.2")
        self.pin("WINE_PACKAGE_NAME", "wine.tar")
        self.pin("DXVK_ARCHIVE_NAME", "dxvk.tar")
        result = self.run_core('''
# Isolate orchestration from proprietary downloads; keep real extraction and DLL checks.
download_verified() { :; }
verify_wine_package_signature() { :; }
verify_payload_manifest() { :; }
verify_extracted_game_tree() { :; }
extract_lfs_payload() { printf 'log\\n' >"$3"; }
verify_sources
''')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("All pinned upstream", result.stdout)
        self.assertEqual(list((self.root / "cache").glob(".verify-payloads.*")), [])

    def test_graphics_staging_is_removed_after_failure_or_cancel(self):
        for interrupted in (False, True):
            with self.subTest(interrupted=interrupted):
                failure = 'kill -TERM "$$"' if interrupted else "die 'fixture extraction failure'"
                result = self.run_core('''
download_verified() { :; }
INSTALL_ACTIVE=1
trap cancel_install TERM
extract_bsdtar_archive() {
  printf partial >"$2/partial"
  ''' + failure + '''
}
install_dxvk
''')
                self.assertEqual(result.returncode, 130 if interrupted else 1)
                self.assertEqual(list((self.root / "cache").glob(".dxvk-unpack.*")), [])
                self.assertEqual((self.game / "cfg.txt").read_text(), "player-settings")

    def test_unrecognized_downloads_page_is_operational_error(self):
        result = self.run_core('''
printf '<html>Maintenance</html>' >"$TEST_ROOT/page"
export LFS_LINUX_DOWNLOADS_PAGE_FILE="$TEST_ROOT/page"
update_check
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not be recognized", result.stderr)

    def test_download_events_identify_component_without_changing_verification(self):
        (self.root / "download.bin").write_bytes(b"data")
        result = self.run_core('''
export LFS_LINUX_GUI_EVENTS=1
exec 3>"$TEST_ROOT/events"
download_verified 'fixture' "file://$TEST_ROOT/download.bin" "$INSTALLER" 4 "$(sha256_of "$TEST_ROOT/download.bin")"
''')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        events = (self.root / "events").read_text()
        self.assertIn("download-start\t", events)
        self.assertIn(".part\t4\tLive for Speed", events)
        self.assertIn("download-end\t", events)
        self.assertIn("Checking Live for Speed", events)

    def test_low_space_stops_before_installation(self):
        result = self.run_core('''
df() { printf 'Filesystem 1B-blocks Used Available Use%% Mounted\\nfixture 100 99 1 99%% /\\n'; }
check_install_space
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn("not enough free space", result.stderr)
        self.assertEqual((self.game / "cfg.txt").read_text(), "player-settings")

    def test_skin_changes_do_not_require_approval_or_repair(self):
        self.prepare_public_launch()
        skins = self.game / "data/skins_dds"
        (skins / "PLAYER.dds").write_text("downloaded")
        result = self.call_public("launch")
        self.assertEqual(result.returncode, 0, result.stderr)
        (skins / "PLAYER.dds").unlink()
        (skins / "NEW.dds").write_text("another download")
        (skins / "HEL_DEFAULT.dds").write_text("updated default")
        result = self.call_public("desktop-state")
        self.assertEqual(result.stdout.strip(), "ready", result.stderr)
        result = self.call_public("launch")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_empty_and_linked_executable_are_kept_and_reported(self):
        self.prepare_public_launch()
        exe = self.game / "LFS.exe"
        for kind in ("missing", "empty", "link"):
            with self.subTest(kind=kind):
                exe.unlink(missing_ok=True)
                if kind == "empty":
                    exe.touch()
                elif kind == "link":
                    exe.symlink_to(self.game / "cfg.txt")
                result = self.call_public("desktop-state")
                self.assertEqual(result.stdout.strip(), "blocked", result.stderr)
                result = self.call_public("install")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("no files changed", result.stderr)
                self.assertEqual((self.game / "cfg.txt").read_text(), "player-settings")
                if kind == "link":
                    self.assertTrue(exe.is_symlink())

    def test_existing_game_needs_no_space_for_a_second_game_download(self):
        self.prepare_public_launch()
        result = self.run_core('''
WINE_BIN=/bin/true
df() { printf 'Filesystem 1B-blocks Used Available Use%% Mounted\\nfixture 536870912 268435456 268435456 50%% /\\n'; }
check_install_space
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_legacy_swap_recovery_never_discards_either_existing_tree(self):
        backup = self.root / "state/.lfs-game-backup"
        shutil.copytree(self.game, backup)
        (self.game / "LFS.exe").write_bytes(b"updated game")
        result = self.run_core("recover_interrupted_game_swap")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.game / "LFS.exe").read_bytes(), b"updated game")
        self.assertEqual((backup / "LFS.exe").read_bytes(), b"fixture-game")


if __name__ == "__main__":
    unittest.main()
