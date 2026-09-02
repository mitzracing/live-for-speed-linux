#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sync-upstream-drift.py"
SPEC = importlib.util.spec_from_file_location("sync_upstream_drift", SCRIPT)
assert SPEC and SPEC.loader
DRIFT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIFT)


def managed_issue(body: str, *, state: str = "open", number: int = 17) -> dict:
    return {"number": number, "state": state, "body": body, "title": DRIFT.ISSUE_TITLE}


class CaptureHandler(BaseHTTPRequestHandler):
    requests: list[dict] = []
    issues: list[dict] = []

    def do_GET(self) -> None:
        self.__class__.requests.append(
            {
                "method": "GET",
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
                "payload": None,
            }
        )
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(self.__class__.issues).encode("utf-8"))

    def capture_mutation(self, method: str) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length))
        self.__class__.requests.append(
            {
                "method": method,
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
                "payload": payload,
            }
        )
        self.send_response(201 if method == "POST" else 200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{}")

    def do_POST(self) -> None:
        self.capture_mutation("POST")

    def do_PATCH(self) -> None:
        self.capture_mutation("PATCH")

    def log_message(self, _format: str, *_args: object) -> None:
        return


class UpstreamDriftTest(unittest.TestCase):
    def test_drift_without_managed_issue_plans_one_issue(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "report.txt"
            issues = root / "issues.json"
            report.write_text(
                "Audited target: 0.8C24\nWebsite test:   0.8C25\n",
                encoding="utf-8",
            )
            issues.write_text("[]\n", encoding="utf-8")
            result = subprocess.run(
                [
                    str(SCRIPT),
                    "--dry-run",
                    "--state",
                    "drift",
                    "--report-file",
                    str(report),
                    "--pin-status",
                    "available",
                    "--issues-file",
                    str(issues),
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=20,
            )

        plan = json.loads(result.stdout)
        self.assertEqual(plan["action"], "create")
        self.assertEqual(plan["labels"], ["status:needs-maintainer", "upstream-drift"])
        self.assertIn("0.8C24", plan["body"])
        self.assertIn("0.8C25", plan["body"])
        self.assertIn("Pinned bootstrap remains available", plan["body"])

    def test_repeated_identical_drift_is_noop(self) -> None:
        report = "Audited target: 0.8C24\nWebsite test:   0.8C25"
        body = DRIFT.build_body(report, "available")
        plan = DRIFT.build_plan("drift", report, "available", [managed_issue(body)])
        self.assertEqual(plan, {"action": "noop"})

    def test_changed_drift_updates_existing_issue_once(self) -> None:
        old_report = "Audited target: 0.8C24\nWebsite test:   0.8C25"
        new_report = "Audited target: 0.8C24\nWebsite test:   0.8C26"
        old_body = DRIFT.build_body(old_report, "available")
        plan = DRIFT.build_plan(
            "drift",
            new_report,
            "available",
            [managed_issue(old_body, number=29)],
        )
        self.assertEqual(plan["action"], "update")
        self.assertEqual(plan["issue_number"], 29)
        self.assertIn("0.8C25", plan["body"])
        self.assertNotIn("0.8C24", plan["body"])
        self.assertIn("changed", plan["comment"].casefold())

    def test_current_pin_closes_open_managed_issue(self) -> None:
        report = "Audited target: 0.8C24\nWebsite test:   0.8C24"
        body = DRIFT.build_body(
            "Audited target: 0.8C24\nWebsite test:   0.8C25",
            "available",
        )
        plan = DRIFT.build_plan(
            "current",
            report,
            "available",
            [managed_issue(body, number=31)],
        )
        self.assertEqual(plan["action"], "close")
        self.assertEqual(plan["issue_number"], 31)
        self.assertIn("matches", plan["comment"].casefold())

    def test_duplicate_managed_issues_fail_closed(self) -> None:
        body = DRIFT.build_body("Website test:   0.8C24", "available")
        with self.assertRaisesRegex(ValueError, "multiple managed"):
            DRIFT.build_plan(
                "drift",
                "Website test:   0.8C24",
                "available",
                [managed_issue(body, number=1), managed_issue(body, number=2)],
            )

    def test_report_is_bounded_and_cannot_mention_or_inject_html(self) -> None:
        report = "\x1b[31m@maintainers <script>alert(1)</script>\x00\u202e" + "x" * 9000
        body = DRIFT.build_body(report, "unknown")
        self.assertNotIn("\x1b", body)
        self.assertNotIn("\u202e", body)
        self.assertNotIn("<script>", body)
        self.assertNotIn("@maintainers", body)
        self.assertIn("@\u200bmaintainers", body)
        self.assertIn("&lt;script&gt;", body)
        self.assertIn("[report truncated]", body)

    def test_apply_creates_issue_through_bounded_github_api(self) -> None:
        CaptureHandler.requests = []
        CaptureHandler.issues = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), CaptureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8") as report:
                report.write("Audited target: 0.8C24\nWebsite test:   0.8C25\n")
                report.flush()
                environment = os.environ.copy()
                environment.update(
                    {
                        "GITHUB_TOKEN": "test-token",
                        "GITHUB_REPOSITORY": "mitzracing/live-for-speed-linux",
                        "GITHUB_API_URL": f"http://127.0.0.1:{server.server_address[1]}",
                    }
                )
                subprocess.run(
                    [
                        str(SCRIPT),
                        "--apply",
                        "--state",
                        "drift",
                        "--report-file",
                        report.name,
                        "--pin-status",
                        "available",
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=20,
                    env=environment,
                )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual([request["method"] for request in CaptureHandler.requests], ["GET", "POST"])
        self.assertIn("labels=upstream-drift", CaptureHandler.requests[0]["path"])
        self.assertEqual(CaptureHandler.requests[0]["authorization"], "Bearer test-token")
        create = CaptureHandler.requests[1]
        self.assertEqual(create["path"], "/repos/mitzracing/live-for-speed-linux/issues")
        self.assertEqual(create["payload"]["title"], DRIFT.ISSUE_TITLE)
        self.assertEqual(create["payload"]["labels"], ["status:needs-maintainer", "upstream-drift"])
        self.assertNotIn("test-token", json.dumps(create["payload"]))

    def test_apply_update_reopens_before_posting_change_comment(self) -> None:
        CaptureHandler.requests = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), CaptureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            plan = {
                "action": "update",
                "issue_number": 41,
                "body": DRIFT.build_body("Website test:   0.8C25", "available"),
                "comment": "Automated upstream state changed.",
            }
            DRIFT.apply_plan(
                plan,
                "mitzracing/live-for-speed-linux",
                "test-token",
                f"http://127.0.0.1:{server.server_address[1]}",
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual([request["method"] for request in CaptureHandler.requests], ["PATCH", "POST"])
        self.assertEqual(CaptureHandler.requests[0]["payload"]["state"], "open")
        self.assertEqual(
            CaptureHandler.requests[1]["path"],
            "/repos/mitzracing/live-for-speed-linux/issues/41/comments",
        )

    def test_apply_resolution_comments_then_closes(self) -> None:
        CaptureHandler.requests = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), CaptureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            DRIFT.apply_plan(
                {
                    "action": "close",
                    "issue_number": 43,
                    "comment": "Package pin now matches.",
                },
                "mitzracing/live-for-speed-linux",
                "test-token",
                f"http://127.0.0.1:{server.server_address[1]}",
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual([request["method"] for request in CaptureHandler.requests], ["POST", "PATCH"])
        self.assertEqual(CaptureHandler.requests[1]["payload"], {"state": "closed"})


if __name__ == "__main__":
    unittest.main()
