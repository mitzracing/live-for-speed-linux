#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sync-upstream-drift.py"


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


if __name__ == "__main__":
    unittest.main()
