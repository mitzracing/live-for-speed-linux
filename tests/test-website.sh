#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly HTML="$ROOT_DIR/website/index.html"
readonly CSS="$ROOT_DIR/website/styles.css"
readonly JS="$ROOT_DIR/website/feedback.js"

[[ -f "$HTML" && -f "$CSS" && -f "$JS" ]]
(( $(stat -c %s "$HTML") < 102400 ))
(( $(stat -c %s "$CSS") < 102400 ))
(( $(stat -c %s "$JS") < 102400 ))

python3 - "$HTML" "$ROOT_DIR/VERSION" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Audit(HTMLParser):
    def __init__(self):
        super().__init__()
        self.h1 = 0
        self.title = 0
        self.viewport = 0
        self.scripts = []
        self.images = []
        self.ids = set()
        self.links = []
        self.form_fields = set()
    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "h1": self.h1 += 1
        if tag == "title": self.title += 1
        if tag == "meta" and values.get("name") == "viewport": self.viewport += 1
        if tag == "script": self.scripts.append(values.get("src", ""))
        if tag == "img": self.images.append(values.get("src", ""))
        if "id" in values: self.ids.add(values["id"])
        if tag == "a": self.links.append(values.get("href", ""))
        if tag in {"input", "select", "textarea"} and values.get("id"):
            self.form_fields.add(values["id"])

audit = Audit()
text = Path(sys.argv[1]).read_text()
version = Path(sys.argv[2]).read_text().strip()
audit.feed(text)
assert audit.h1 == 1, audit.h1
assert audit.title == 1, audit.title
assert audit.viewport == 1, audit.viewport
assert audit.scripts == ["feedback.js"], audit.scripts
assert set(audit.images) == {"icon.svg"}, audit.images
assert {"top", "install", "support", "trust", "feedback-disclosure", "feedback-form", "feedback-result", "github-handoff", "collapse-feedback"} <= audit.ids, audit.ids
assert {"kind", "summary", "distribution", "distributionVersion", "packageMethod", "wrapperVersion", "desktop", "graphics", "details", "expected", "steps", "value", "diagnostics", "safety"} <= audit.form_fields, audit.form_fields
assert '<details id="feedback-disclosure" class="feedback-disclosure">' in text
assert 'action="#support"' in text
assert 'name="' not in text[text.index('<form id="feedback-form"'):text.index('</form>', text.index('<form id="feedback-form"'))]
assert all(link.startswith(("#", "https://")) for link in audit.links), audit.links
assert "not affiliated with or endorsed" in text
assert text.count(f"<strong>{version}</strong>") == 2
assert f"v{version}/live-for-speed-linux_{version}-1_amd64.deb" in text
assert "0.3.0" not in text
assert "Debian 13" in text and "Ubuntu 24.04" in text
assert "0.8C20" in text
assert "updates itself" in text
assert "No game binaries" in text
assert "GitHub sign-in is required" in text
assert "issues/new?template=bug.yml" in text
assert 'label%3A%22help+wanted%22+-label%3A%22status%3Apossible-sensitive%22' in text
assert "Nothing is sent until you review and submit on GitHub" in text
assert "lfs.net" not in " ".join(audit.images)
PY

[[ "$(grep -o '{' "$CSS" | wc -l)" -eq "$(grep -o '}' "$CSS" | wc -l)" ]]
grep -Fq '@media (max-width: 760px)' "$CSS"
grep -Fq 'prefers-reduced-motion' "$CSS"

node "$ROOT_DIR/tests/test-feedback-generator.mjs"
timeout --foreground --kill-after=10s 120 node "$ROOT_DIR/tests/test-feedback-browser.mjs"

printf '[PASS] website is small, responsive, sanitizer-tested, and uses only community-owned imagery\n'
