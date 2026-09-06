#!/usr/bin/env python3
"""Real GTK widgets and controller on a disposable X11/Wayland display.

Run through `make gtk-check`, for example with xvfb-run or an owned Xephyr.
Workers are deterministic fixtures. No real game state or network is used.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("desktop", ROOT / "tests/test-desktop.py")
desktop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)

DRIVER = r'''
import json, os, sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(os.environ["TEST_REPO"]) / "libexec"))
from lfs_linux_gtk import View, GLib, Gtk
from lfs_linux_dialog import main
root = Path(os.environ["FIXTURE"])
scenario = os.environ["SCENARIO"]
if sys.argv[1] == "--client":
    with (root / "dialogs").open("a") as output:
        output.write(" ".join(sys.argv[3:]) + "\n")
if sys.argv[1] == "--serve":
    (root / "view-pid").write_text(str(os.getpid()))
original = View.show

def find_button(widget, text):
    if isinstance(widget, Gtk.Button) and widget.get_label() == text:
        return widget
    child = widget.get_first_child()
    while child:
        found = find_button(child, text)
        if found: return found
        child = child.get_next_sibling()
    return None

def respond(view, request, choice):
    if view.active is request:
        button = find_button(request["buttons"], choice)
        assert button is not None, choice
        button.emit("clicked")
    return GLib.SOURCE_REMOVE

def show(view, request):
    original(view, request)
    options = request["options"]
    with (root / "requests").open("a") as output:
        output.write(json.dumps({"kind": options.kind, "text": options.text}) + "\n")
    choice = options.ok_label
    if options.kind == "progress":
        if scenario == "view-failure" and options.text.startswith("Preparing Live"):
            GLib.timeout_add(300, os._exit, 4)
            return
        if scenario == "cancel" and options.text.startswith("Preparing Live"):
            choice = "Cancel"
        else: return
    elif scenario == "cancel-prompt" and options.kind == "question":
        choice = "Cancel"
    elif options.ok_label == "Retry" and scenario == "failure":
        choice = "Close"
    elif scenario == "gtk-help" and options.kind == "text-info" and not (root / "support-opened").exists():
        choice = "Open support"
    GLib.timeout_add(300, respond, view, request, choice)

View.show = show
raise SystemExit(main(sys.argv[1:]))
'''


class GtkView(unittest.TestCase):
    def setUp(self):
        self.fixture = desktop.Desktop()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        (self.root / "driver.py").write_text(DRIVER)
        self.fixture.script("gtk", 'exec /usr/bin/python3 "$FIXTURE/driver.py" "$@"')

    def run_ui(self, **kwargs):
        script = kwargs.pop("script", "ui_main launch")
        return self.fixture.run_ui(backend="gtk", script='UI_GTK_EXECUTABLE="$FIXTURE/bin/gtk"\n' + script,
                                   **kwargs)

    def assert_clean(self):
        pid = int((self.root / "view-pid").read_text())
        self.assertFalse(Path(f"/proc/{pid}").exists(), "GTK view survived controller exit")
        self.assertFalse((self.root / "view-survived").exists(), "GTK view survived gameplay handoff")
        self.assertEqual(list((self.root / "lock").glob("desktop.*")), [self.root / "lock/desktop.lock"])
        if (self.root / "log").exists():
            logs = "".join(path.read_text() for path in (self.root / "log").iterdir())
            self.assertNotIn("Traceback", logs)
            self.assertNotIn("View request failed", logs)

    def test_install_play_and_ready_relaunch(self):
        for state in ("fresh", "ready"):
            with self.subTest(state=state):
                (self.root / "actions").unlink(missing_ok=True)
                result = self.run_ui(state=state)
                self.assertEqual(result.returncode, 0, result.stderr)
                actions = self.fixture.actions()
                expected = ["desktop-state", "launch"] if state == "ready" else ["desktop-state", "install", "desktop-state", "launch"]
                self.assertEqual(actions, expected)
                self.assert_clean()

    def test_cancel_prompt_starts_no_download(self):
        result = self.run_ui(scenario="cancel-prompt")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fixture.actions(), ["desktop-state"])
        self.assert_clean()

    def test_cancel_owned_worker_preserves_unrelated_process(self):
        unrelated = subprocess.Popen(["sleep", "120"])
        self.addCleanup(lambda: (unrelated.terminate(), unrelated.wait()))
        result = self.run_ui(scenario="cancel")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "cancelled").exists())
        self.assertIsNone(unrelated.poll())
        child = int((self.root / "child").read_text())
        self.assertFalse(Path(f"/proc/{child}").exists())
        self.assert_clean()

    def test_view_crash_cancels_setup_without_switching_frontends(self):
        result = self.run_ui(scenario="view-failure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "cancelled").exists())
        self.assertEqual(self.fixture.actions(), ["desktop-state", "install"])
        self.assertFalse((self.root / "played").exists())
        self.assert_clean()

    def test_widget_progress_is_measured_and_verification_indeterminate(self):
        program = r'''
from pathlib import Path
import tempfile
from lfs_linux_gtk import View, Gtk
from lfs_linux_dialog import parse_dialog
with tempfile.TemporaryDirectory() as temp:
    app = View(str(Path(temp) / "view.sock"), "io.github.mitzracing.live_for_speed_linux")
    app.register(None)
    app.activate(app)
    request = {"options": parse_dialog(["--progress", "--text=<literal>"])}
    app.build(request)
    app.show(request)
    assert request["message"].get_text() == "<literal>"
    assert not request["bar"].get_visible()
    assert request["buttons"].get_parent() is app.actions
    app.progress_line(request, "@phase\truntime")
    app.progress_line(request, "@bytes\t1048576\t4194304")
    assert request["bar"].get_fraction() == 0.25
    assert request["meter"].get_text() == "25% of this download"
    assert request["meter"].get_visible()
    assert request["bar"].get_visible()
    assert not request["spinner"].get_spinning()
    app.progress_line(request, "@indeterminate")
    assert not request["bar"].get_visible()
    assert not request["meter"].get_visible()
    assert request["spinner"].get_spinning()
    app.progress_line(request, "@phase\tgame")
    assert app.completed == {"runtime"}
    assert request["steps"]["game"].get_text().startswith("●")
    Gtk.Settings.get_default().set_property("gtk-enable-animations", False)
    assert not Gtk.Settings.get_default().get_property("gtk-enable-animations")
    for _ in range(150):
        app.progress_line(request, "# Update " + str(_))
    assert len(request["history"]) == 128
    try:
        app.progress_line(request, "@bytes\t5\t4")
    except ValueError:
        pass
    else:
        raise AssertionError("invalid byte count accepted")
    app.window.destroy()
    app.listener.close()
'''
        result = subprocess.run(["/usr/bin/python3", "-c", program],
                                env=dict(os.environ, PYTHONPATH=str(ROOT / "libexec")),
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("CRITICAL", result.stderr)

    def test_failure_does_not_silently_retry(self):
        result = self.run_ui(scenario="failure")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.fixture.actions(), ["desktop-state", "install"])
        self.assertIn("download was interrupted", (self.root / "dialogs").read_text())
        self.assert_clean()

    def test_ready_game_launches_without_update_confirmation(self):
        result = self.run_ui(state="ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fixture.actions(), ["desktop-state", "launch"])
        self.assertNotIn("--question", (self.root / "dialogs").read_text())
        self.assert_clean()

    def test_component_repair_keeps_game_and_then_plays(self):
        result = self.run_ui(state="repair")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fixture.actions(), ["desktop-state", "install", "desktop-state", "launch"])
        self.assertIn("existing game and all player files will be kept", (self.root / "dialogs").read_text())
        self.assert_clean()

    def test_help_opens_browser_without_inheriting_locks(self):
        self.fixture.script("xdg-open", r'''
for fd in 8 9; do
  [[ ! -e "/proc/$$/fd/$fd" ]] || touch "$FIXTURE/inherited-lock"
done
touch "$FIXTURE/support-opened"
''')
        result = self.run_ui(scenario="gtk-help", script="ui_main help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "support-opened").exists())
        self.assertFalse((self.root / "inherited-lock").exists())
        self.assert_clean()


if __name__ == "__main__":
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        raise SystemExit("GTK view tests require a disposable display; see make gtk-check")
    unittest.main()
