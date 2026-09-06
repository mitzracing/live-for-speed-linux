#!/usr/bin/env python3
"""GTK adapter's transport contract. No display or PyGObject required."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("dialog", ROOT / "libexec/lfs_linux_dialog.py")
dialog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dialog)


class Dialog(unittest.TestCase):
    def test_only_supported_dialogs_are_accepted(self):
        args = dialog.parse_dialog(["--question", "--text=<literal>", "--extra-button=Details"])
        self.assertEqual(args.kind, "question")
        self.assertEqual(args.text, "<literal>")
        self.assertEqual(args.extra_button, ["Details"])
        for flags in (["--run=sh"], ["--question", "--progress"], []):
            with self.subTest(flags=flags), self.assertRaises(ValueError):
                dialog.parse_dialog(flags)

    def test_invalid_and_oversized_frames_fail_closed(self):
        for data in (b"no json", b"[]", b"{}", b'{"args":[2]}', b"x" * 65537):
            with self.subTest(data=data[:30]), self.assertRaises(ValueError):
                dialog.decode_request(data)
        self.assertEqual(dialog.decode_request(b'{"line":"100"}'), {"line": "100"})

    def test_clients_preserve_button_exit_codes_and_stream_progress(self):
        for code, text, progress in ((0, "", False), (1, "Details", False), (0, "", True)):
            with self.subTest(code=code, text=text, progress=progress), tempfile.TemporaryDirectory() as temp:
                path = str(Path(temp) / "view.sock")
                server = socket.socket(socket.AF_UNIX)
                self.addCleanup(server.close)
                server.bind(path)
                server.listen(1)
                received = []

                def respond():
                    connection, _ = server.accept()
                    with connection, connection.makefile("rb") as stream:
                        received.append(json.loads(stream.readline()))
                        if progress:
                            received.append(json.loads(stream.readline()))
                        connection.sendall(dialog.encode({"code": code, "text": text}))

                thread = threading.Thread(target=respond)
                thread.start()
                result = subprocess.run(
                    [str(ROOT / "libexec/lfs-linux-gtk"), "--client", path,
                     "--progress" if progress else "--question"],
                    input="# Checking files\n", text=True, capture_output=True, timeout=5)
                thread.join(timeout=5)
                self.assertFalse(thread.is_alive())
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(result.stdout, text + "\n" if text else "")
                self.assertEqual(received[0]["args"], ["--progress" if progress else "--question"])
                if progress:
                    self.assertEqual(received[1], {"line": "# Checking files"})

    def test_disconnected_view_never_reports_acceptance(self):
        with tempfile.TemporaryDirectory() as temp:
            result = subprocess.run(
                [str(ROOT / "libexec/lfs-linux-gtk"), "--client", str(Path(temp) / "absent"), "--question"],
                capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
