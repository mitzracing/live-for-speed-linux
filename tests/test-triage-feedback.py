#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "triage-feedback.py"
SPEC = importlib.util.spec_from_file_location("triage_feedback", SCRIPT)
assert SPEC and SPEC.loader
TRIAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TRIAGE)


def event(labels: list[str], body: str = "", number: int = 42, action: str = "opened") -> dict:
    return {
        "action": action,
        "repository": {"full_name": "mitzracing/live-for-speed-linux"},
        "issue": {
            "number": number,
            "body": body,
            "labels": [{"name": name} for name in labels],
        },
    }


class CaptureHandler(BaseHTTPRequestHandler):
    requests: list[dict] = []

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length))
        self.__class__.requests.append(
            {
                "method": "POST",
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
                "payload": payload,
            }
        )
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{}")

    def do_DELETE(self) -> None:
        self.__class__.requests.append(
            {
                "method": "DELETE",
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
                "payload": None,
            }
        )
        self.send_response(204)
        self.end_headers()

    def log_message(self, _format: str, *_args: object) -> None:
        return


class FeedbackTriageTest(unittest.TestCase):
    def test_sensitive_title_is_withheld_even_on_edit(self) -> None:
        report = event(["type:bug", "help wanted"], "Ordinary details", action="edited")
        report["issue"]["title"] = "token=abcdefghijklmnopqrstuvwxyz0123456789"
        plan = TRIAGE.build_plan(report)
        self.assertTrue(plan["sensitive"])
        self.assertIn("help wanted", plan["remove_labels"])

    def test_browser_redactions_do_not_quarantine_safe_reports(self) -> None:
        sanitized = subprocess.check_output([
            "node", "-e",
            "const f=require('./website/feedback.js'); process.stdout.write(f.sanitizeText('token=abcdefghijklmnopqrstuvwxyz0123456789\\nmachine-id=abcdef').value)",
        ], cwd=ROOT, text=True)
        plan = TRIAGE.build_plan(event(["type:bug"], sanitized))
        self.assertFalse(plan["sensitive"])
        self.assertIn("help wanted", plan["labels"])
        for value in ("token=[redacted] secret", "token=[redacted]ghp_" + "a" * 30):
            self.assertTrue(TRIAGE.contains_sensitive_data(value))

    def test_bug_enters_manjaro_contributor_queue(self) -> None:
        plan = TRIAGE.build_plan(
            event(
                ["type:bug"],
                "### Linux distribution\n\nManjaro Linux\n\n### What happened?\n\nWindow closed.",
            )
        )
        self.assertEqual(
            plan["labels"],
            ["distro:manjaro", "help wanted", "status:needs-reproduction"],
        )
        self.assertIn("contributor queue", plan["comments"][0])
        self.assertFalse(plan["sensitive"])

    def test_arch_compatibility_preserves_exact_runtime_guidance(self) -> None:
        plan = TRIAGE.build_plan(
            event(["type:compatibility"], "### Linux distribution\n\nArch Linux")
        )
        self.assertEqual(
            plan["labels"],
            ["distro:arch", "help wanted", "status:needs-reproduction"],
        )
        self.assertIn("exact Wine and payload pins", plan["comments"][0])

    def test_feature_waits_for_maintainer(self) -> None:
        plan = TRIAGE.build_plan(event(["type:feature"]))
        self.assertEqual(plan["labels"], ["status:needs-maintainer"])
        self.assertIn("before implementation", plan["comments"][0])

    def test_unknown_ticket_waits_for_classification(self) -> None:
        plan = TRIAGE.build_plan(event([]))
        self.assertEqual(plan["labels"], ["status:needs-maintainer"])
        self.assertIn("did not use a recognized support form", plan["comments"][0])

    def test_sensitive_pattern_is_flagged_without_echo(self) -> None:
        secret = "ghp_" + "abcdefghijklmnopqrstuvwxyz" + "0123456789"
        plan = TRIAGE.build_plan(event(["type:feedback"], f"### Notes\n\n{secret}"))
        self.assertTrue(plan["sensitive"])
        self.assertEqual(
            plan["labels"],
            ["status:needs-maintainer", "status:possible-sensitive"],
        )
        self.assertNotIn("help wanted", plan["labels"])
        self.assertNotIn(secret, json.dumps(plan))
        self.assertIn("withheld from the contributor queue", plan["comments"][0])

    def test_all_documented_sensitive_categories_are_detected(self) -> None:
        examples = {
            "linux home": "/home/alice/.local/share/lfs-linux/install.env",
            "mac home": "/Users/alice/Library/Application Support/LFS",
            "windows home": r"C:\Users\Alice\AppData\Local\LFS",
            "registry": "WINE REGISTRY Version 2\n[HKEY_CURRENT_USER\\Software\\LFS]",
            "email": "driver report: alice@example.invalid",
            "cookie": "cookie=session-value-that-must-not-be-public",
            "unlock": "unlock code: 123456789",
            "machine": "machine-id=0123456789abcdef",
            "private key": "-----BEGIN " + "PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----",
        }
        for category, body in examples.items():
            with self.subTest(category=category):
                plan = TRIAGE.build_plan(event(["type:bug"], f"### Diagnostics\n\n{body}"))
                self.assertTrue(plan["sensitive"])
                self.assertNotIn("help wanted", plan["labels"])
                self.assertNotIn("status:needs-reproduction", plan["labels"])
                self.assertIn("status:possible-sensitive", plan["labels"])
                self.assertIn("status:needs-maintainer", plan["labels"])

    def test_sensitive_rerun_removes_contributor_labels(self) -> None:
        plan = TRIAGE.build_plan(
            event(
                ["type:bug", "help wanted", "status:needs-reproduction"],
                "### Diagnostics\n\n/home/example/private.log",
            )
        )
        self.assertEqual(plan["remove_labels"], ["help wanted", "status:needs-reproduction"])
        self.assertNotIn("help wanted", plan["labels"])

    def test_edited_quarantine_cannot_reenter_contributor_queue(self) -> None:
        plan = TRIAGE.build_plan(
            event(
                ["type:bug", "status:possible-sensitive", "help wanted"],
                "### Diagnostics\n\nThe author removed the exposed path.",
                action="edited",
            )
        )
        self.assertTrue(plan["sensitive"])
        self.assertEqual(plan["remove_labels"], ["help wanted"])
        self.assertNotIn("status:needs-reproduction", plan["labels"])
        self.assertEqual(plan["comments"], [])

    def test_distribution_edit_removes_stale_distribution_label(self) -> None:
        plan = TRIAGE.build_plan(
            event(
                ["type:compatibility", "distro:manjaro", "help wanted", "status:needs-reproduction"],
                "### Linux distribution\n\nArch Linux",
                action="edited",
            )
        )
        self.assertEqual(plan["labels"], ["distro:arch"])
        self.assertEqual(plan["remove_labels"], ["distro:manjaro"])
        self.assertEqual(plan["comments"], [])

    def test_clean_edit_does_not_repeat_static_guidance(self) -> None:
        plan = TRIAGE.build_plan(
            event(
                ["type:bug", "help wanted", "status:needs-reproduction"],
                "### What happened?\n\nClarified public details.",
                action="edited",
            )
        )
        self.assertFalse(plan["sensitive"])
        self.assertEqual(plan["comments"], [])

    def test_apply_posts_labels_and_static_comment_to_mock_github(self) -> None:
        CaptureHandler.requests = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), CaptureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            source_event = event(["type:bug"])
            plan = TRIAGE.build_plan(source_event)
            TRIAGE.apply_plan(
                source_event,
                plan,
                "test-token",
                f"http://127.0.0.1:{server.server_address[1]}",
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(len(CaptureHandler.requests), 2)
        labels_request, comment_request = CaptureHandler.requests
        self.assertEqual(labels_request["path"], "/repos/mitzracing/live-for-speed-linux/issues/42/labels")
        self.assertEqual(
            labels_request["payload"],
            {"labels": ["help wanted", "status:needs-reproduction"]},
        )
        self.assertEqual(comment_request["path"], "/repos/mitzracing/live-for-speed-linux/issues/42/comments")
        self.assertIn("contributor queue", comment_request["payload"]["body"])
        self.assertEqual(labels_request["authorization"], "Bearer test-token")

    def test_apply_removes_queue_label_before_sensitive_comment(self) -> None:
        CaptureHandler.requests = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), CaptureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            source_event = event(
                ["type:bug", "help wanted"],
                "### Diagnostics\n\nWINE REGISTRY Version 2",
            )
            plan = TRIAGE.build_plan(source_event)
            TRIAGE.apply_plan(
                source_event,
                plan,
                "test-token",
                f"http://127.0.0.1:{server.server_address[1]}",
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(
            [request["method"] for request in CaptureHandler.requests],
            ["DELETE", "POST", "POST"],
        )
        self.assertEqual(
            CaptureHandler.requests[0]["path"],
            "/repos/mitzracing/live-for-speed-linux/issues/42/labels/help%20wanted",
        )
        self.assertEqual(
            CaptureHandler.requests[1]["payload"],
            {"labels": ["status:needs-maintainer", "status:possible-sensitive"]},
        )
        self.assertIn("withheld", CaptureHandler.requests[2]["payload"]["body"])

    def test_cli_dry_run_matches_library_plan(self) -> None:
        source_event = event(["type:feedback"], number=7)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8") as handle:
            json.dump(source_event, handle)
            handle.flush()
            result = subprocess.run(
                [str(SCRIPT), "--dry-run", handle.name],
                check=True,
                capture_output=True,
                text=True,
                timeout=20,
            )
        plan = json.loads(result.stdout)
        self.assertEqual(plan["issue_number"], 7)
        self.assertEqual(plan["labels"], ["status:needs-maintainer"])


if __name__ == "__main__":
    unittest.main()
