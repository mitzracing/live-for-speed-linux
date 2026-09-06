#!/usr/bin/env python3
"""Exercise the real graphical controller with deterministic dialog/worker adapters."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Desktop(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lfs-desktop-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "bin").mkdir()
        (self.root / "lock").mkdir(mode=0o700)
        self.script("zenity", r'''
printf '%s\n' "$*" >>"$FIXTURE/dialogs"
case "$*" in
  *--progress*)
    if [[ "$*" == *'Preparing Live'* && "$SCENARIO" == cancel ]]; then sleep .4; exit 1; fi
    while read -r line; do [[ "$line" != 100 ]] || exit 0; done ;;
  *--question*)
    if [[ "$*" == *--ok-label=Retry* ]]; then
      [[ "$SCENARIO" != failure ]] || exit 1
    fi ;;
esac
''')
        self.script("worker", r'''
printf '%s\n' "$1" >>"$FIXTURE/actions"
case "$1" in
  desktop-state)
    if [[ -f "$FIXTURE/ready" ]]; then printf 'ready\n'
    else printf '%s\n' "${INITIAL_STATE:-fresh}"; fi ;;
  install)
    case "$SCENARIO" in
      cancel|view-failure)
        sleep 120 & child=$!; printf '%s\n' "$child" >"$FIXTURE/child"
        trap 'wait "$child" 2>/dev/null || true; touch "$FIXTURE/cancelled"; exit 130' TERM
        wait "$child" ;;
      failure) printf 'error\tdownload\n' >&3; exit 1 ;;
      *) printf 'stage\tChecking downloaded files\n' >&3; touch "$FIXTURE/ready" ;;
    esac ;;
  launch)
    printf 'launched\t\n' >&3
    if [[ -f "$FIXTURE/view-pid" ]]; then
      view="$(<"$FIXTURE/view-pid")"
      for ((attempt=0; attempt<40; attempt++)); do
        kill -0 "$view" 2>/dev/null || break
        sleep .05
      done
      if kill -0 "$view" 2>/dev/null; then touch "$FIXTURE/view-survived"; fi
    fi
    sleep .2
    touch "$FIXTURE/played" ;;
  stop) touch "$FIXTURE/ready" ;;
  support-report) printf 'Safe diagnostic summary\n' ;;
esac
''')

    def script(self, name, body):
        path = self.root / "bin" / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body)
        path.chmod(0o755)

    def run_ui(self, scenario="success", state="fresh", script="ui_main launch", backend="zenity"):
        env = dict(os.environ, PATH=str(self.root / "bin") + ":" + os.environ["PATH"],
                   FIXTURE=str(self.root), SCENARIO=scenario, INITIAL_STATE=state,
                   TEST_REPO=str(ROOT), LFS_LINUX_UI=backend)
        # Use real core lock and prerequisite functions; only external worker/dialogs are adapters.
        program = r'''
set -Eeuo pipefail
umask 077
CORE_EXECUTABLE="$FIXTURE/bin/worker"
UI_GTK_EXECUTABLE="$TEST_REPO/libexec/lfs-linux-gtk"
LOCK_DIR="$FIXTURE/lock"
LOG_DIR="$FIXTURE/log"
DATA_DIR="$TEST_REPO/share/lfs-linux"
CACHE_DIR="$FIXTURE/cache"
LFS_VERSION=0.8C20
LFS_INSTALLER_SIZE=1000000
WINE_PACKAGE_SIZE=1000000
DXVK_ARCHIVE_SIZE=1000000
eval "$(sed -n '/^owner_private_regular_file() {/,/^require_host_arch() {/p' "$TEST_REPO/libexec/lfs-linux-core" | sed '$d')"
die() { printf '%s\n' "$*" >&2; exit 1; }
source "$TEST_REPO/libexec/lfs-linux-ui"
''' + script
        return subprocess.run(["bash", "-c", program], env=env, text=True,
                              capture_output=True, timeout=15)

    def actions(self):
        return (self.root / "actions").read_text().splitlines()

    def test_first_launch_installs_and_plays(self):
        result = self.run_ui()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), ["desktop-state", "install", "desktop-state", "launch"])
        self.assertTrue((self.root / "played").exists())
        self.assertIn("Install and play", (self.root / "dialogs").read_text())
        self.assertEqual(list((self.root / "lock").glob("desktop.*")), [self.root / "lock/desktop.lock"])

    def test_first_prompt_uses_packaged_community_logo(self):
        result = self.run_ui()
        self.assertEqual(result.returncode, 0, result.stderr)
        dialogs = (self.root / "dialogs").read_text()
        self.assertIn("io.github.mitzracing.live_for_speed_linux.svg", dialogs)
        self.assertIn("--no-markup", dialogs)
        self.assertIn("Download: up to", dialogs)

    def test_progress_displays_phase_and_measured_download_bytes(self):
        (self.root / "cache").mkdir()
        (self.root / "cache/game.bin.part").write_bytes(b"x" * 1048576)
        result = self.run_ui(script=r'''
mkdir "$FIXTURE/pump"
{ printf 'phase\tgame\tCheck game files\n';
  printf 'download-start\tgame.bin.part\t2097152\tLive for Speed\n';
  sleep .7;
  printf 'download-end\t\n'; } | ui_pump "$FIXTURE/pump" 'Starting'
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Check game files", result.stdout)
        self.assertIn("Downloading Live for Speed", result.stdout)
        self.assertIn("1.0 / 2.0 MiB", result.stdout)
        self.assertTrue((self.root / "pump/complete").exists())

    def test_dialog_text_uses_real_line_breaks_without_markup(self):
        result = self.run_ui(script=r"ui_question --text='First\nSecond'")
        self.assertEqual(result.returncode, 0, result.stderr)
        dialogs = (self.root / "dialogs").read_text()
        self.assertIn("First\nSecond", dialogs)
        self.assertNotIn(r"First\nSecond", dialogs)

    def test_ready_launch_needs_no_question(self):
        result = self.run_ui(state="ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), ["desktop-state", "launch"])
        self.assertNotIn("--question", (self.root / "dialogs").read_text())
        self.assertIn("--no-cancel", (self.root / "dialogs").read_text())

    def test_repair_and_services_dispatch(self):
        for state, operation in (("repair", "install"), ("services", "stop")):
            with self.subTest(state=state):
                (self.root / "ready").unlink(missing_ok=True)
                (self.root / "actions").unlink(missing_ok=True)
                result = self.run_ui(state=state)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.actions(), ["desktop-state", operation, "desktop-state", "launch"])

    def test_incomplete_game_never_gets_overwritten(self):
        result = self.run_ui(state="blocked")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.actions(), ["desktop-state", "support-report"])
        self.assertFalse((self.root / "played").exists())

    def test_download_failure_explains_retry(self):
        result = self.run_ui(scenario="failure")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.actions(), ["desktop-state", "install"])
        self.assertIn("download was interrupted", (self.root / "dialogs").read_text())

    def test_cancel_stops_only_owned_process_group(self):
        unrelated = subprocess.Popen(["sleep", "120"])
        self.addCleanup(lambda: (unrelated.terminate(), unrelated.wait()))
        result = self.run_ui(scenario="cancel")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "cancelled").exists())
        child = int((self.root / "child").read_text())
        self.assertFalse(Path(f"/proc/{child}").exists())
        self.assertIsNone(unrelated.poll())
        self.assertFalse((self.root / "played").exists())

    def test_missing_gtk_falls_back_before_any_worker_starts(self):
        result = self.run_ui(script=r'''
LFS_LINUX_UI=auto
UI_GTK_EXECUTABLE="$FIXTURE/missing-view"
ui_main launch
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), ["desktop-state", "install", "desktop-state", "launch"])
        self.assertIn("--question", (self.root / "dialogs").read_text())

    def test_forced_missing_gtk_does_not_start_worker(self):
        result = self.run_ui(script=r'''
LFS_LINUX_UI=gtk
UI_GTK_EXECUTABLE="$FIXTURE/missing-view"
ui_main launch
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "actions").exists())

    def test_gtk_waits_for_ready_marker_not_only_socket_path(self):
        self.script("slow-view", r'''
case "$1" in
  --probe) exit 0 ;;
  --serve)
    exec python3 - "$2" <<'PY'
from pathlib import Path
import socket, sys, time
connection = socket.socket(socket.AF_UNIX)
connection.bind(sys.argv[1])
time.sleep(.5)
connection.listen(1)
Path(sys.argv[1] + '.ready').touch(mode=0o600)
time.sleep(60)
PY
    ;;
  --client)
    if [[ ! -f "$2.ready" ]]; then touch "$FIXTURE/early-client"; exit 2; fi
    shift 2
    exec zenity "$@"
    ;;
esac
''')
        result = self.run_ui(backend="gtk", script=r'''
UI_GTK_EXECUTABLE="$FIXTURE/bin/slow-view"
ui_main launch
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "early-client").exists())
        self.assertTrue((self.root / "played").exists())

    def test_repeated_icon_does_not_start_second_operation(self):
        result = self.run_ui(script=r'''
exec 7>"$LOCK_DIR/desktop.lock"
flock -n 7
ui_main launch
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "actions").exists())

    def test_help_remains_available_while_game_or_setup_owns_desktop_lock(self):
        result = self.run_ui(script=r'''
exec 7>"$LOCK_DIR/desktop.lock"
flock -n 7
ui_main help
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "actions").exists(), "Help was silently ignored")
        self.assertEqual(self.actions(), ["support-report"])
        self.assertIn("--text-info", (self.root / "dialogs").read_text())

    def test_support_browser_does_not_inherit_launcher_locks(self):
        self.script("xdg-open", r'''
for fd in 8 9; do
  [[ ! -e "/proc/$$/fd/$fd" ]] || touch "$FIXTURE/inherited-lock"
done
touch "$FIXTURE/support-opened"
''')
        result = self.run_ui(script=r'''
# Model Help -> Open support -> Close, without opening an actual browser.
zenity() {
  if [[ ! -f "$FIXTURE/support-opened" ]]; then printf 'Open support\n'; fi
}
ui_main help
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "support-opened").exists())
        self.assertFalse((self.root / "inherited-lock").exists())

    def test_old_recovery_desktop_action_uses_normal_launch(self):
        result = self.run_ui(state="ready", script="ui_main recover-update")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actions(), ["desktop-state", "launch"])
        self.assertNotIn("--question", (self.root / "dialogs").read_text())


if __name__ == "__main__":
    unittest.main()
