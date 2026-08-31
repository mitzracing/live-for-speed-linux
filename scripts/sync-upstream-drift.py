#!/usr/bin/env python3
"""Synchronize one bounded GitHub maintenance issue for upstream LFS drift."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import sys
from pathlib import Path
from typing import Any

ISSUE_MARKER = "<!-- lfs-linux-upstream-drift -->"
FINGERPRINT_PREFIX = "<!-- lfs-linux-upstream-report:"
ISSUE_TITLE = "[Maintenance] Upstream LFS download drift"
ISSUE_LABELS = ("status:needs-maintainer", "upstream-drift")
MAX_REPORT_CHARS = 8192
ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
PIN_MESSAGES = {
    "available": "Pinned C20 bootstrap remains available at its audited byte size.",
    "changed": "Pinned bootstrap URL responds, but its byte size changed. Treat clean installs as at risk.",
    "unavailable": "Pinned bootstrap URL is unavailable. Audit the new upstream build urgently.",
    "unknown": "Pinned bootstrap availability could not be confirmed. Review manually.",
}


def sanitize_report(value: str) -> str:
    value = ANSI_ESCAPE.sub("", value.replace("\r\n", "\n").replace("\r", "\n"))
    value = "".join(character for character in value if character in "\n\t" or ord(character) >= 32)
    value = value.replace("\t", "    ").strip()
    if not value:
        raise ValueError("upstream report is empty")
    if len(value) > MAX_REPORT_CHARS:
        value = value[:MAX_REPORT_CHARS] + "\n[report truncated]"
    return html.escape(value, quote=False).replace("@", "@\u200b")


def report_fingerprint(report: str, pin_status: str) -> str:
    return hashlib.sha256(f"{pin_status}\n{report}".encode("utf-8")).hexdigest()


def build_body(report: str, pin_status: str) -> str:
    if pin_status not in PIN_MESSAGES:
        raise ValueError(f"unsupported pin status: {pin_status}")
    safe_report = sanitize_report(report)
    fingerprint = report_fingerprint(safe_report, pin_status)
    quoted = "\n".join(f"> {line}" if line else ">" for line in safe_report.splitlines())
    return f"""{ISSUE_MARKER}

## Automated detection

{quoted}

## Bootstrap availability

{PIN_MESSAGES[pin_status]}

## Impact

Recorded in-game updates remain launchable. No package pin, game file, commit, tag, or release was changed.

## Required maintainer decision

Choose **monitor**, **audit**, or **release**. Binary trust and publication remain manual.

{FINGERPRINT_PREFIX}{fingerprint} -->
"""


def managed_issues(issues: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        issue
        for issue in issues
        if "pull_request" not in issue and ISSUE_MARKER in str(issue.get("body") or "")
    ]


def build_plan(
    state: str,
    report: str,
    pin_status: str,
    issues: list[dict[str, Any]],
) -> dict[str, Any]:
    if state not in ("current", "drift"):
        raise ValueError(f"unsupported upstream state: {state}")
    matches = managed_issues(issues)
    if len(matches) > 1:
        raise ValueError("multiple managed upstream drift issues found")
    if state == "drift" and not matches:
        return {
            "action": "create",
            "title": ISSUE_TITLE,
            "body": build_body(report, pin_status),
            "labels": sorted(ISSUE_LABELS),
        }
    return {"action": "noop"}


def load_json_list(path: str) -> list[dict[str, Any]]:
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ValueError("issues file must contain a JSON array of objects")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--state", choices=("current", "drift"), required=True)
    parser.add_argument("--report-file", required=True)
    parser.add_argument("--pin-status", choices=tuple(PIN_MESSAGES), default="unknown")
    parser.add_argument("--issues-file")
    args = parser.parse_args()

    try:
        report = Path(args.report_file).read_text(encoding="utf-8")
        if args.dry_run:
            if not args.issues_file:
                raise ValueError("--issues-file is required in dry-run mode")
            plan = build_plan(args.state, report, args.pin_status, load_json_list(args.issues_file))
            json.dump(plan, sys.stdout, sort_keys=True)
            sys.stdout.write("\n")
            return 0
        raise ValueError("apply mode is not implemented")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"upstream drift synchronization failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
