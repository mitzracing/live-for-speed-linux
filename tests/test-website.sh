#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly HTML="$ROOT_DIR/website/index.html"
readonly CSS="$ROOT_DIR/website/styles.css"
readonly JS="$ROOT_DIR/website/feedback.js"
readonly MEDIA_JS="$ROOT_DIR/website/installer-demo.js"
readonly HERO_JS="$ROOT_DIR/website/hero-slideshow.js"

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
        self.videos = []
        self.sources = []
        self.font_preloads = []
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
        if tag == "video": self.videos.append(values)
        if tag == "source": self.sources.append(values)
        if tag == "link" and values.get("rel") == "preload" and values.get("as") == "font": self.font_preloads.append(values)
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
assert audit.scripts == ["feedback.js", "installer-demo.js?v=1", "hero-slideshow.js?v=2"], audit.scripts
photos = {"pit-lane.webp", "gt3-track.webp", "drift-smoke.webp", "garage.webp", "drift-action.webp", "gt3-detail.webp"}
assert set(audit.images) == {"icon.svg", "assets/installer-poster.webp", *(f"assets/{name}" for name in photos)}, audit.images
assert {"hero-image", "hero-previous", "hero-next", "hero-rotate", "hero-caption", "hero-status", "game-gallery"} <= audit.ids
assert not {"hero-credit", "image-credit", "gt3-credit", "drift-credit"} & audit.ids
assert 'class="gallery-credits"' not in text
assert 'aria-roledescription="carousel"' in text and 'id="hero-photos"' in text
assert "Motorsport photography—not game screenshots." in text
assert len(audit.videos) == 1, audit.videos
video = audit.videos[0]
assert video.get("id") == "installer-demo" and video.get("preload") == "none"
assert {"muted", "loop", "playsinline", "hidden"} <= video.keys()
assert "autoplay" not in video and "src" not in video, "do not fetch/animate before motion and visibility checks"
assert [(source.get("data-src"), source.get("type")) for source in audit.sources] == [
    ("assets/installer-demo.webm", "video/webm"), ("assets/installer-demo.mp4", "video/mp4")]
assert all("src" not in source for source in audit.sources), "media must load on demand"
assert "Simulated local data" in text and "Read demo steps" in text
assert len(audit.font_preloads) == 1
assert audit.font_preloads[0].get("href") == "assets/spacegrotesk.woff2" and "crossorigin" in audit.font_preloads[0]
assets = Path(sys.argv[1]).parent / "assets"
reviewed_assets = {
    "pit-lane.webp": (153600, "56db2dcac374fd328264abd0727e566b7e323ba3d34e2f03775cd589b9d5c065"),
    "gt3-track.webp": (153600, "a4f8a7ba126391b32ca44975385655ba2042cedce6a57c24fb7eb24d68903d32"),
    "drift-smoke.webp": (153600, "8047f0d0c67cd727fd2942c3e07144ec6d71f0827d84c8f3818281303e6b7aa9"),
    "garage.webp": (153600, "4c1326ff8fadebd06c286a304bc2c8f5bd41c0c63835b8bdf103f1cc4e861c80"),
    "drift-action.webp": (153600, "ca82884582c8cadce7418ccd75c6922da5c6df0da0f42a8af511ae64ee328c2d"),
    "gt3-detail.webp": (153600, "9aad4b2161aa8f0ed6e60f6ae990b2e4b1682dba46e7322119e238f930cf7659"),
    "installer-demo.webm": (204800, "07d55f1b1d310e8d8bcb5365b52d5cac9916bfc6f0f9adfe96b076ee4ec4ef08"),
    "installer-demo.mp4": (204800, "53e7c66bf81792b0fb2e901014962c21e15dc82101112f57be1f2464db31df5b"),
    "installer-poster.webp": (61440, "6ba27303d47bf45902a437a768bbaf6b888dfa501856da4bd1b48b2bfd0bde30"),
    "spacegrotesk.woff2": (20480, "685bbbf69fa616df1ef81847c85fc76be097ddfb3468ff2257be54511ab3130f"),
    "spacegrotesk-OFL.txt": (10240, "18a4de52385f6b988782639d5d0cc1326e5a8c2de9a7f01d7b20d9aedcc60943"),
}
assert {path.name for path in assets.iterdir()} == {"README.md", *reviewed_assets}, "unreviewed website asset"
for name, (budget, digest) in reviewed_assets.items():
    path = assets / name
    assert path.is_file() and not path.is_symlink(), name
    assert path.stat().st_size < budget, f"asset exceeds reviewed budget: {name}"
    assert sha256(path.read_bytes()).hexdigest() == digest, f"unreviewed asset bytes: {name}"
assert sum((assets / name).stat().st_size for name in photos) < 563200, "photos exceed combined 550 KiB budget"
credits = (assets / "README.md").read_text()
assert "https://unsplash.com/license" in credits and "Attribution is not required" in credits
assert all(name in credits for name in photos), "photo source record missing"
assert "Space Grotesk" in credits and "SIL Open Font License" in credits
assert "scripted" in credits and "GTK" in credits and "MIT" in credits
assert all(digest in credits for _budget, digest in reviewed_assets.values()), "credits omit asset provenance"
assert len(audit.stylesheets) == 1 and audit.stylesheets[0].startswith("styles.css?"), audit.stylesheets
assert audit.release_versions == [version], audit.release_versions
assert {"top", "install", "support", "trust", "feedback-disclosure", "feedback-form", "feedback-result", "github-handoff", "collapse-feedback"} <= audit.ids, audit.ids
assert {"kind", "summary", "distribution", "distributionVersion", "packageMethod", "wrapperVersion", "desktop", "graphics", "details", "expected", "steps", "value", "diagnostics", "safety"} <= audit.form_fields, audit.form_fields
assert '<details id="feedback-disclosure" class="feedback-disclosure">' in text
assert 'action="#support"' in text
assert 'name="' not in text[text.index('<form id="feedback-form"'):text.index('</form>', text.index('<form id="feedback-form"'))]
assert all(link.startswith(("#", "https://")) or link == "assets/installer-demo.mp4" for link in audit.links), audit.links
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
assert repository + "/blob/main/website/assets/README.md" in (root / "docs/LEGAL.md").read_text(), "installed legal notes need publicly reachable image credits"
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
for path in index.html styles.css feedback.js installer-demo.js hero-slideshow.js assets/pit-lane.webp assets/gt3-track.webp assets/drift-smoke.webp assets/garage.webp assets/drift-action.webp assets/gt3-detail.webp assets/README.md assets/spacegrotesk.woff2 assets/spacegrotesk-OFL.txt assets/installer-demo.webm assets/installer-demo.mp4 assets/installer-poster.webp; do
  cmp "$ROOT_DIR/website/$path" "$site_tmp/site with spaces/$path"
done
cmp "$ROOT_DIR/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg" "$site_tmp/site with spaces/icon.svg"
[[ "$(find "$site_tmp/site with spaces" -type f | wc -l)" -eq 18 ]]
printf 'keep existing output\n' > "$site_tmp/site with spaces/index.html"
if bash "$ROOT_DIR/scripts/build-website.sh" "$site_tmp/site with spaces" > "$site_tmp/refusal.log" 2>&1; then
  printf 'site builder overwrote an existing destination\n' >&2
  exit 1
fi
grep -Fxq 'keep existing output' "$site_tmp/site with spaces/index.html"

(( $(stat -c %s "$MEDIA_JS") < 10240 ))
node --check "$MEDIA_JS"
(( $(stat -c %s "$HERO_JS") < 10240 ))
node --check "$HERO_JS"
node "$ROOT_DIR/tests/test-feedback-generator.mjs"
timeout --foreground --kill-after=10s 120 node "$ROOT_DIR/tests/test-feedback-browser.mjs"

printf '[PASS] website is responsive, sanitizer-tested, with local media integrity, no photo-credit UI, and playback/photo fallbacks\n'
