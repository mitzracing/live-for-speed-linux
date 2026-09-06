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
from hashlib import sha256
from pathlib import Path
import re
import sys

class Audit(HTMLParser):
    def __init__(self):
        super().__init__()
        self.h1 = 0
        self.title = 0
        self.viewport = 0
        self.scripts = []
        self.images = []
        self.stylesheets = []
        self.release_versions = []
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
        if "id" in values:
            assert values["id"] not in self.ids, f"duplicate id: {values['id']}"
            self.ids.add(values["id"])
        if tag == "link" and values.get("rel") == "stylesheet": self.stylesheets.append(values.get("href", ""))
        if "data-release-version" in values: self.release_versions.append(values["data-release-version"])
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
assert set(audit.images) == {"icon.svg", "assets/blackwood-rallycross.webp"}, audit.images
assert "Martin Kapal" in text and "Archival imagery" in text
assert "https://commons.wikimedia.org/wiki/File:Rallycross_blackwood_lfs.jpg" in audit.links
assert "https://creativecommons.org/licenses/by-sa/3.0/" in audit.links
assets = Path(sys.argv[1]).parent / "assets"
assert {path.name for path in assets.iterdir()} == {"blackwood-rallycross.webp", "README.md"}, "unreviewed website asset"
image = assets / "blackwood-rallycross.webp"
assert image.is_file() and not image.is_symlink()
assert image.stat().st_size < 153600, "hero image exceeds 150 KiB budget"
assert sha256(image.read_bytes()).hexdigest() == "992b8b0e43fb8f8226a7be962ae995837639ffcc7b58a38a8542fc208cbaea9f", "unreviewed hero image bytes"
credits = (assets / "README.md").read_text()
assert "Martin Kapal" in credits and "CC BY-SA 3.0" in credits
assert "https://creativecommons.org/licenses/by-sa/3.0/" in credits
assert len(audit.stylesheets) == 1 and audit.stylesheets[0].startswith("styles.css?"), audit.stylesheets
assert audit.release_versions == [version], audit.release_versions
assert {"top", "install", "support", "trust", "feedback-disclosure", "feedback-form", "feedback-result", "github-handoff", "collapse-feedback"} <= audit.ids, audit.ids
assert {"kind", "summary", "distribution", "distributionVersion", "packageMethod", "wrapperVersion", "desktop", "graphics", "details", "expected", "steps", "value", "diagnostics", "safety"} <= audit.form_fields, audit.form_fields
assert '<details id="feedback-disclosure" class="feedback-disclosure">' in text
assert 'action="#support"' in text
assert 'name="' not in text[text.index('<form id="feedback-form"'):text.index('</form>', text.index('<form id="feedback-form"'))]
assert all(link.startswith(("#", "https://")) for link in audit.links), audit.links
assert "not affiliated with or endorsed" in text
assert all(link[1:] in audit.ids for link in audit.links if link.startswith("#")), "broken section link"
release = f"https://github.com/mitzracing/live-for-speed-linux/releases/download/v{version}"
assert f"{release}/live-for-speed-linux_{version}-0github1_amd64.deb" in audit.links
assert f"{release}/live-for-speed-linux-{version}-1-x86_64.pkg.tar.zst" in audit.links
assert "No software-store listing is available" in text
assert "locally recorded protected game file" not in text
assert "first installation" in text
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

root = Path(sys.argv[2]).parent
repository = "https://github.com/mitzracing/live-for-speed-linux"
headings = re.findall(r"^#{1,6} (.+)$", (root / "README.md").read_text(), re.MULTILINE)
readme_anchors = {re.sub(r"[^\w\s-]", "", heading.lower()).replace(" ", "-") for heading in headings}
for link in audit.links:
    if link.startswith(repository + "#"):
        assert link.split("#", 1)[1] in readme_anchors, f"broken README link: {link}"
    if link.startswith(repository + "/blob/main/"):
        path = link.removeprefix(repository + "/blob/main/").split("#", 1)[0]
        # AUR recipes and their README are intentionally omitted from source archives.
        # Check this link in Git checkouts; every bundled document is checked everywhere.
        if path == "packaging/aur/README.md" and not (root / ".git").exists() and not (root / "packaging/aur").exists():
            continue
        assert (root / path).is_file(), f"missing linked document: {link}"
PY

[[ "$(grep -o '{' "$CSS" | wc -l)" -eq "$(grep -o '}' "$CSS" | wc -l)" ]]
grep -Fq '@media (max-width: 760px)' "$CSS"
grep -Fq 'prefers-reduced-motion' "$CSS"

site_tmp="$(mktemp -d)"
readonly site_tmp
trap 'rm -rf -- "$site_tmp"' EXIT
(
  cd "$site_tmp"
  bash "$ROOT_DIR/scripts/build-website.sh" 'site with spaces'
)
for path in index.html styles.css feedback.js assets/blackwood-rallycross.webp assets/README.md; do
  cmp "$ROOT_DIR/website/$path" "$site_tmp/site with spaces/$path"
done
cmp "$ROOT_DIR/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg" "$site_tmp/site with spaces/icon.svg"
[[ "$(find "$site_tmp/site with spaces" -type f | wc -l)" -eq 6 ]]
printf 'keep existing output\n' > "$site_tmp/site with spaces/index.html"
if bash "$ROOT_DIR/scripts/build-website.sh" "$site_tmp/site with spaces" > "$site_tmp/refusal.log" 2>&1; then
  printf 'site builder overwrote an existing destination\n' >&2
  exit 1
fi
grep -Fxq 'keep existing output' "$site_tmp/site with spaces/index.html"

node "$ROOT_DIR/tests/test-feedback-generator.mjs"
timeout --foreground --kill-after=10s 120 node "$ROOT_DIR/tests/test-feedback-browser.mjs"

printf '[PASS] website is small, responsive, sanitizer-tested, with attributed and checksum-checked imagery\n'
