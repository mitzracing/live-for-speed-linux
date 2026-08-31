#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sync-upstream-drift.py"
SPEC = importlib.util.spec_from_file_location("sync_upstream_drift", SCRIPT)
assert SPEC and SPEC.loader
DRIFT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIFT)


def managed_issue(body: str, *, state: str = "open", number: int = 17) -> dict:
    return {"number": number, "state": state, "body": body, "title": DRIFT.ISSUE_TITLE}


class UpstreamDriftTest(unittest.TestCase):
    def test_drift_without_managed_issue_plans_one_issue(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "report.txt"
            issues = root / "issues.json"
            report.write_text(
                "Audited target: 0.8C20\nWebsite test:   0.8C24\n",
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
        self.assertIn("0.8C20", plan["body"])
        self.assertIn("0.8C24", plan["body"])
        self.assertIn("Pinned C20 bootstrap remains available", plan["body"])

    def test_repeated_identical_drift_is_noop(self) -> None:
        report = "Audited target: 0.8C20\nWebsite test:   0.8C24"
        body = DRIFT.build_body(report, "available")
        plan = DRIFT.build_plan("drift", report, "available", [managed_issue(body)])
        self.assertEqual(plan, {"action": "noop"})

    def test_changed_drift_updates_existing_issue_once(self) -> None:
        old_report = "Audited target: 0.8C20\nWebsite test:   0.8C24"
        new_report = "Audited target: 0.8C20\nWebsite test:   0.8C25"
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
            "Audited target: 0.8C20\nWebsite test:   0.8C24",
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
        report = "\x1b[31m@maintainers <script>alert(1)</script>\x00" + "x" * 9000
        body = DRIFT.build_body(report, "unknown")
        self.assertNotIn("\x1b", body)
        self.assertNotIn("<script>", body)
        self.assertNotIn("@maintainers", body)
        self.assertIn("@\u200bmaintainers", body)
        self.assertIn("&lt;script&gt;", body)
        self.assertIn("[report truncated]", body)


if __name__ == "__main__":
    unittest.main()
