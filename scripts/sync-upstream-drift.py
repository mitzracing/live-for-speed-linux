#!/usr/bin/env python3
"""Synchronize one bounded GitHub maintenance issue for upstream LFS drift."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ISSUE_MARKER = "<!-- lfs-linux-upstream-drift -->"
FINGERPRINT_PREFIX = "<!-- lfs-linux-upstream-report:"
FINGERPRINT_PATTERN = re.compile(r"<!-- lfs-linux-upstream-report:([0-9a-f]{64}) -->")
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


def body_fingerprint(body: str) -> str:
    match = FINGERPRINT_PATTERN.search(body)
    return match.group(1) if match else ""


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
    if state == "drift":
        body = build_body(report, pin_status)
        if not matches:
            return {
                "action": "create",
                "title": ISSUE_TITLE,
                "body": body,
                "labels": sorted(ISSUE_LABELS),
            }
        issue = matches[0]
        same_report = body_fingerprint(str(issue.get("body") or "")) == body_fingerprint(body)
        if same_report and issue.get("state") == "open":
            return {"action": "noop"}
        return {
            "action": "update",
            "issue_number": int(issue["number"]),
            "body": body,
            "comment": "Automated upstream state changed; the maintenance summary was refreshed.",
        }
    if matches and matches[0].get("state") == "open":
        return {
            "action": "close",
            "issue_number": int(matches[0]["number"]),
            "comment": "The audited package pin now matches the official LFS downloads page; closing this maintenance alert.",
        }
    return {"action": "noop"}


def load_json_list(path: str) -> list[dict[str, Any]]:
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ValueError("issues file must contain a JSON array of objects")
    return value


def request_json(
    url: str,
    token: str,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
) -> Any:
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "live-for-speed-linux-upstream-drift",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            content = response.read()
            return json.loads(content) if content else None
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"GitHub API returned HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"GitHub API request failed: {error.reason}") from error


def repository_name(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("GITHUB_REPOSITORY is invalid")
    return value


def fetch_issues(repository: str, token: str, api_url: str) -> list[dict[str, Any]]:
    query = urllib.parse.urlencode(
        {
            "state": "all",
            "labels": "upstream-drift",
            "per_page": "100",
            "sort": "created",
            "direction": "desc",
        }
    )
    base = f"{api_url.rstrip('/')}/repos/{urllib.parse.quote(repository, safe='/')}"
    value = request_json(f"{base}/issues?{query}", token)
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise RuntimeError("GitHub issues response had an unexpected shape")
    return value


def apply_plan(plan: dict[str, Any], repository: str, token: str, api_url: str) -> None:
    base = f"{api_url.rstrip('/')}/repos/{urllib.parse.quote(repository, safe='/')}"
    action = plan["action"]
    if action == "noop":
        return
    if action == "create":
        request_json(
            f"{base}/issues",
            token,
            "POST",
            {key: plan[key] for key in ("title", "body", "labels")},
        )
        return
    issue_number = int(plan["issue_number"])
    issue_url = f"{base}/issues/{issue_number}"
    if action == "update":
        request_json(
            issue_url,
            token,
            "PATCH",
            {
                "title": ISSUE_TITLE,
                "body": plan["body"],
                "labels": sorted(ISSUE_LABELS),
                "state": "open",
            },
        )
        request_json(f"{issue_url}/comments", token, "POST", {"body": plan["comment"]})
        return
    if action == "close":
        request_json(f"{issue_url}/comments", token, "POST", {"body": plan["comment"]})
        request_json(issue_url, token, "PATCH", {"state": "closed"})
        return
    raise ValueError(f"unsupported plan action: {action}")


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
            issues = load_json_list(args.issues_file)
        else:
            token = os.environ.get("GITHUB_TOKEN", "")
            if not token:
                raise ValueError("GITHUB_TOKEN is required in apply mode")
            repository = repository_name(os.environ.get("GITHUB_REPOSITORY", ""))
            api_url = os.environ.get("GITHUB_API_URL", "https://api.github.com")
            issues = fetch_issues(repository, token, api_url)
        plan = build_plan(args.state, report, args.pin_status, issues)
        if args.apply:
            apply_plan(plan, repository, token, api_url)
            print(f"upstream drift issue action: {plan['action']}")
        else:
            json.dump(plan, sys.stdout, sort_keys=True)
            sys.stdout.write("\n")
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"upstream drift synchronization failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
