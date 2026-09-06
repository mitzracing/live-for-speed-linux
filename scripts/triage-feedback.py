#!/usr/bin/env python3
"""Classify GitHub support tickets without evaluating untrusted issue text."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

TYPE_RULES = {
    "type:bug": {
        "labels": ("status:needs-reproduction", "help wanted"),
        "comment": (
            "Thanks for the report. This ticket is now in the contributor queue.\n\n"
            "Contributors: reproduce the problem, comment before starting work, and submit a "
            "focused pull request with `Closes #NUMBER`."
        ),
    },
    "type:compatibility": {
        "labels": ("status:needs-reproduction", "help wanted"),
        "comment": (
            "Thanks for the compatibility report. This ticket is now in the contributor queue.\n\n"
            "Contributors: confirm the result on the reported distribution, comment before "
            "starting work, and preserve the exact Wine and payload pins."
        ),
    },
    "type:feature": {
        "labels": ("status:needs-maintainer",),
        "comment": (
            "Thanks for the proposal. A maintainer must confirm scope before implementation. "
            "Contributors should wait for a maintainer decision before opening a pull request."
        ),
    },
    "type:feedback": {
        "labels": ("status:needs-maintainer",),
        "comment": (
            "Thanks for sharing your experience. A maintainer will decide whether this feedback "
            "becomes documentation, a feature ticket, or a closed record."
        ),
    },
}

SENSITIVE_PATTERNS = tuple(
    re.compile(pattern, re.IGNORECASE | re.MULTILINE)
    for pattern in (
        r"gh[pousr]_[A-Za-z0-9_]{20,}",
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
        r"\bBearer\s+[A-Za-z0-9._~+/=-]{16,}",
        r"^\s*(?:password|passwd|unlock(?:\s+code)?|authorization|cookie|token|access[_ -]?key|secret|account(?:\s+(?:name|id|key))?)\s*[:=]\s*\S+",
        r"^\s*(?:machine[- ]?id|hardware\s+serial|serial\s+number)\s*[:=]\s*\S+",
        r"/(?:home|Users)/[^/\s]+(?:/[^\s]*)?",
        r"\b[A-Z]:\\Users\\[^\\\s]+(?:\\[^\s]*)?",
        r"(?:WINE REGISTRY Version|Windows Registry Editor Version|\[?HKEY_(?:CURRENT_USER|LOCAL_MACHINE|CLASSES_ROOT|USERS|CURRENT_CONFIG))",
        r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b",
    )
)

QUEUE_LABELS = frozenset(("help wanted", "status:needs-reproduction"))
DISTRO_LABELS = frozenset(("distro:arch", "distro:manjaro", "distro:other"))
SENSITIVE_COMMENT = (
    "Possible sensitive data was detected. Edit the public report immediately and remove "
    "credentials, unlock data, tokens, cookies, private keys, registry content, email addresses, "
    "machine identifiers, and full home paths. This ticket is withheld from the contributor queue "
    "until a maintainer confirms that the public text is safe."
)


def issue_label_names(issue: dict[str, Any]) -> set[str]:
    names: set[str] = set()
    for label in issue.get("labels", []):
        if isinstance(label, str):
            names.add(label)
        elif isinstance(label, dict) and isinstance(label.get("name"), str):
            names.add(label["name"])
    return names


def markdown_sections(body: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    matches = list(re.finditer(r"^###\s+(.+?)\s*$", body, re.MULTILINE))
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        sections[match.group(1).strip().casefold()] = body[start:end].strip()
    return sections


def distribution_label(body: str) -> str | None:
    sections = markdown_sections(body)
    value = sections.get("linux distribution", "").casefold()
    if "manjaro" in value:
        return "distro:manjaro"
    if value == "arch linux" or value.startswith("arch linux\n"):
        return "distro:arch"
    if value:
        return "distro:other"
    return None


def contains_sensitive_data(body: str) -> bool:
    # The browser preserves field names when it removes values. Only an exact
    # placeholder at the end of that line is safe; appended text is still scanned.
    body = re.sub(
        r"(?im)^([ \t]*(?:password|passwd|unlock(?:\s+code)?|authorization|cookie|token|access[_ -]?key|secret|account(?:\s+(?:name|id|key))?|machine[- ]?id|hardware\s+serial|serial\s+number)[ \t]*[:=])[ \t]*\[redacted\][ \t]*$",
        "",
        body,
    )
    return any(pattern.search(body) for pattern in SENSITIVE_PATTERNS)


def build_plan(event: dict[str, Any]) -> dict[str, Any]:
    issue = event.get("issue")
    if not isinstance(issue, dict):
        raise ValueError("event does not contain an issue object")

    existing = issue_label_names(issue)
    selected_type = next((name for name in TYPE_RULES if name in existing), None)
    if selected_type is None:
        labels = {"status:needs-maintainer"}
        comment = (
            "This ticket did not use a recognized support form. A maintainer must classify it "
            "before contributor work starts."
        )
    else:
        rule = TYPE_RULES[selected_type]
        labels = set(rule["labels"])
        comment = str(rule["comment"])

    body = str(issue.get("body") or "")
    distro = distribution_label(body)
    if distro is not None:
        labels.add(distro)
    remove_labels = (existing & DISTRO_LABELS) - ({distro} if distro is not None else set())

    detected_sensitive = contains_sensitive_data(body) or contains_sensitive_data(str(issue.get("title") or ""))
    sensitive = detected_sensitive or "status:possible-sensitive" in existing
    if sensitive:
        labels.difference_update(QUEUE_LABELS)
        labels.update(("status:possible-sensitive", "status:needs-maintainer"))
        remove_labels.update(existing & QUEUE_LABELS)
        comments = (
            [SENSITIVE_COMMENT]
            if detected_sensitive and "status:possible-sensitive" not in existing
            else []
        )
    else:
        comments = [] if event.get("action") == "edited" else [comment]

    return {
        "issue_number": int(issue["number"]),
        "labels": sorted(labels - existing),
        "remove_labels": sorted(remove_labels),
        "comments": comments,
        "sensitive": sensitive,
    }


def request_json(
    url: str,
    token: str,
    method: str,
    payload: dict[str, Any] | None,
    *,
    ignore_not_found: bool = False,
) -> None:
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "live-for-speed-linux-feedback-triage",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f"GitHub API returned HTTP {response.status}")
    except urllib.error.HTTPError as error:
        if ignore_not_found and error.code == 404:
            return
        raise RuntimeError(f"GitHub API returned HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"GitHub API request failed: {error.reason}") from error


def apply_plan(event: dict[str, Any], plan: dict[str, Any], token: str, api_url: str) -> None:
    repository = event.get("repository", {}).get("full_name")
    if not isinstance(repository, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("event does not contain a valid repository name")
    issue_number = int(plan["issue_number"])
    base = f"{api_url.rstrip('/')}/repos/{urllib.parse.quote(repository, safe='/')}/issues/{issue_number}"

    for label in plan["remove_labels"]:
        encoded_label = urllib.parse.quote(str(label), safe="")
        request_json(
            f"{base}/labels/{encoded_label}",
            token,
            "DELETE",
            None,
            ignore_not_found=True,
        )
    labels = list(plan["labels"])
    if labels:
        request_json(f"{base}/labels", token, "POST", {"labels": labels})
    for comment in plan["comments"]:
        request_json(f"{base}/comments", token, "POST", {"body": str(comment)})


def load_event(path: str) -> dict[str, Any]:
    value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("event root must be an object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("event_path")
    args = parser.parse_args()

    try:
        event = load_event(args.event_path)
        plan = build_plan(event)
        if args.dry_run:
            json.dump(plan, sys.stdout, sort_keys=True)
            sys.stdout.write("\n")
            return 0

        token = os.environ.get("GITHUB_TOKEN", "")
        if not token:
            raise ValueError("GITHUB_TOKEN is required in apply mode")
        apply_plan(event, plan, token, os.environ.get("GITHUB_API_URL", "https://api.github.com"))
        print(f"triaged issue #{plan['issue_number']}")
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"feedback triage failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
