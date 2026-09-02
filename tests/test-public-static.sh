#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR

bash -n "$ROOT_DIR/bin/"* "$ROOT_DIR/libexec/lfs-linux-core" "$ROOT_DIR/scripts/"*.sh "$ROOT_DIR/tests/"*.sh
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' "$ROOT_DIR/scripts/generate-payload-manifest.py"
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' "$ROOT_DIR/scripts/sync-upstream-drift.py"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT_DIR/bin/"* "$ROOT_DIR/libexec/lfs-linux-core" "$ROOT_DIR/scripts/"*.sh "$ROOT_DIR/tests/"*.sh
fi

python3 - "$ROOT_DIR/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml" "$ROOT_DIR/share/applications/io.github.mitzracing.live_for_speed_linux.desktop" <<'PY'
import configparser
import sys
import xml.etree.ElementTree as ET

component = ET.parse(sys.argv[1]).getroot()
categories = {node.text for node in component.findall("./categories/category")}
keywords = {node.text.casefold() for node in component.findall("./keywords/keyword")}
assert {"Game", "Simulation", "SportsGame"} <= categories
assert {"game", "games", "racing", "simulator"} <= keywords
releases = component.findall("./releases/release")
assert releases[0].attrib == {"version": "0.3.3", "date": "2026-09-02"}
assert "0.8C24" in " ".join(releases[0].itertext())
assert "0.8C24" in " ".join(component.find("./description").itertext())

desktop = configparser.ConfigParser(interpolation=None, strict=True)
desktop.optionxform = str
desktop.read(sys.argv[2])
entry = desktop["Desktop Entry"]
assert {"Game", "Simulation", "SportsGame"} <= set(filter(None, entry["Categories"].split(";")))
assert {"game", "games", "racing", "simulator"} <= {word.casefold() for word in filter(None, entry["Keywords"].split(";"))}
PY

# shellcheck source=/dev/null
source "$ROOT_DIR/share/lfs-linux/release.env"
[[ "$LFS_LINUX_VERSION" == "$(<"$ROOT_DIR/VERSION")" ]]
[[ "$LFS_LINUX_VERSION" == '0.3.3' ]]
[[ "$LFS_VERSION" == '0.8C24' ]]
[[ "$LFS_CHANNEL" == 'public-test' ]]
[[ "$LFS_CHANNEL_LABEL" == *'PUBLIC TEST'* && "$LFS_CHANNEL_LABEL" == *'not stable'* ]]
[[ "$LFS_PUBLIC_TEST_FAMILY" == '0.8C' ]]
[[ "$LFS_FALLBACK_WRAPPER" == 'v0.1.6' ]]
[[ "$LFS_FALLBACK_VERSION" == '0.7G' ]]
[[ "$LFS_INSTALLER_URL" == https://www.lfs.net/* ]]
[[ "$LFS_INSTALLER_SIZE" == '1744514064' ]]
[[ "$LFS_INSTALLER_SHA256" == '9aa925840f9a8f9a4c3b60ad476ba5b6baa28fa78d584b057a1d2c0cf3d5ec47' ]]
[[ "$LFS_EXE_SIZE" == '2744320' ]]
[[ "$LFS_EXE_SHA256" == 'f76daf499d8a27a51889f1c169c2d986f865690ab378fdca8dbedbc0a3b9defb' ]]
[[ "$LFS_STOCK_MANIFEST_NAME" == 'lfs-0.8C24-stock.manifest' ]]
[[ "$LFS_STOCK_MANIFEST_SIZE" == '197380' ]]
[[ "$LFS_STOCK_MANIFEST_SHA256" == '212d77485e2e9a5d926b2aa925ae4e2df7fa413a0ec7b052b93892676ae8dad0' ]]
[[ "$LFS_STOCK_MANIFEST_ENTRIES" == '1963' ]]
lfs_stock_manifest="$ROOT_DIR/share/lfs-linux/$LFS_STOCK_MANIFEST_NAME"
[[ "$(stat -c %s "$lfs_stock_manifest")" == "$LFS_STOCK_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$lfs_stock_manifest" | awk '{print $1}')" == "$LFS_STOCK_MANIFEST_SHA256" ]]
[[ "$(awk -F '\t' '$1 == "f" || $1 == "l" { count++ } END { print count + 0 }' "$lfs_stock_manifest")" == "$LFS_STOCK_MANIFEST_ENTRIES" ]]
[[ "$LFS_STOCK_SEED_MANIFEST_NAME" == 'lfs-0.8C24-seed.manifest' ]]
[[ "$LFS_STOCK_SEED_MANIFEST_SIZE" == '494850' ]]
[[ "$LFS_STOCK_SEED_MANIFEST_SHA256" == '06ea20e01162c6f13fd291da6453a94790f9e93e986ac2e456e0b1f89aaf6d52' ]]
[[ "$LFS_STOCK_SEED_MANIFEST_ENTRIES" == '4848' ]]
lfs_seed_manifest="$ROOT_DIR/share/lfs-linux/$LFS_STOCK_SEED_MANIFEST_NAME"
[[ "$(stat -c %s "$lfs_seed_manifest")" == "$LFS_STOCK_SEED_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$lfs_seed_manifest" | awk '{print $1}')" == "$LFS_STOCK_SEED_MANIFEST_SHA256" ]]
[[ "$(grep -Ec $'^[fl]\t' "$lfs_seed_manifest")" == "$LFS_STOCK_SEED_MANIFEST_ENTRIES" ]]
grep -Fq $'\tdata/knw/AS1_BF1.knw' "$lfs_seed_manifest"
grep -Fq $'\tdata/training/Acceleration - GTI.lsn' "$lfs_seed_manifest"
grep -Fq $'\tdata/veh/FO8.vob' "$lfs_stock_manifest"
grep -Fq $'\tbin/shaders11/ps_1.cso' "$lfs_stock_manifest"
grep -Fq $'\tdata/versions/8C20.txt' "$lfs_stock_manifest"
grep -Fq $'\tdata/versions/8C23.txt' "$lfs_stock_manifest"
if grep -Fq $'\tdata/versions/8C24.txt' "$lfs_stock_manifest"; then
  printf 'C24 manifest unexpectedly gained an unaudited 8C24 marker\n' >&2
  exit 1
fi
if grep -Fq $'\tUninstallLFS.exe' "$lfs_stock_manifest"; then
  printf 'removed C23 uninstaller entered the C24 target manifest\n' >&2
  exit 1
fi
if grep -Eq $'\tdata/(knw|training)/' "$lfs_stock_manifest"; then
  printf 'mutable AI knowledge or training content entered the immutable stock manifest\n' >&2
  exit 1
fi
grep -Fq '"data/knw/"' "$ROOT_DIR/scripts/generate-payload-manifest.py"
grep -Fq '"data/training/"' "$ROOT_DIR/scripts/generate-payload-manifest.py"
python3 - "$ROOT_DIR/scripts/generate-payload-manifest.py" <<'PY'
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("payload_manifest", Path(sys.argv[1]))
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
mutable_paths = (
    "cfg.txt",
    "interface_cfg.txt",
    "card_cfg.txt",
    "deb.log",
    "deb_old.log",
    "guest.txt",
    "cache/events/banner.png",
    "mods/vehicles/example.mod",
    "data/grids/player.rac",
    "data/skins/player.jpg",
    "data/skins_x/downloaded.dds",
    "data/skins_y/generated.dds",
)
assert all(not module.include_path("lfs", path) for path in mutable_paths)
assert all(module.include_path("lfs-seed", path) for path in mutable_paths)
assert module.include_path("lfs", "UninstallLFS.exe")
assert module.include_path("lfs", "data/skins_dds/HEL_DEFAULT.dds")
PY
[[ "$LFS_TREE_MIN_FILE_COUNT" == "$LFS_STOCK_MANIFEST_ENTRIES" ]]
[[ "$LFS_TREE_MIN_BYTES" =~ ^[0-9]+$ && "$LFS_TREE_MIN_BYTES" -ge 3900000000 ]]
immutable_bytes="$(awk -F '\t' '$1 == "f" { total += $3 } END { printf "%.0f", total }' "$lfs_stock_manifest")"
(( immutable_bytes >= LFS_TREE_MIN_BYTES ))
[[ "$LFS_NESTED_ARCHIVE_COUNT" == '52' ]]
[[ "$LFS_NESTED_DDS_ARCHIVE_COUNT" == '41' ]]
[[ "$LFS_NESTED_WLD_ARCHIVE_COUNT" == '9' ]]
[[ "$LFS_NESTED_MANIFEST_NAME" == 'lfs-0.8C24-nested.manifest' ]]
[[ "$LFS_NESTED_MANIFEST_SIZE" == '5030' ]]
[[ "$LFS_NESTED_MANIFEST_SHA256" == '82d735bc73ab9ecb09ae4bfc4b951344d1c81dc56c0f4df63952edff59195eed' ]]
[[ "$LFS_NESTED_MANIFEST_ENTRIES" == '52' ]]
nested_manifest="$ROOT_DIR/share/lfs-linux/$LFS_NESTED_MANIFEST_NAME"
[[ "$(stat -c %s "$nested_manifest")" == "$LFS_NESTED_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$nested_manifest" | awk '{print $1}')" == "$LFS_NESTED_MANIFEST_SHA256" ]]
[[ "$(awk -F '\t' '$1 == "f" { count++ } END { print count + 0 }' "$nested_manifest")" == "$LFS_NESTED_MANIFEST_ENTRIES" ]]
[[ "$(awk -F '\t' '$4 ~ /^inst_tmp\/dds_[0-9][0-9]\.7z$/ { count++ } END { print count + 0 }' "$nested_manifest")" == "$LFS_NESTED_DDS_ARCHIVE_COUNT" ]]
[[ "$(awk -F '\t' '$4 ~ /^inst_tmp\/wld_[A-Z][A-Z]\.7z$/ { count++ } END { print count + 0 }' "$nested_manifest")" == "$LFS_NESTED_WLD_ARCHIVE_COUNT" ]]
grep -Fq $'\tinst_tmp/knw_1.7z' "$nested_manifest"
grep -Fq $'\tinst_tmp/training_1.7z' "$nested_manifest"
for required_path in "$LFS_REQUIRED_HELMET_PATH" "$LFS_REQUIRED_TRACK_PATH" "$LFS_REQUIRED_VEHICLE_PATH"; do
  [[ "$required_path" != /* && "$required_path" != *'..'* ]]
done
[[ "$LFS_REQUIRED_HELMET_SIZE" =~ ^[0-9]+$ ]]
[[ "$LFS_REQUIRED_HELMET_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$LFS_REQUIRED_TRACK_SIZE" =~ ^[0-9]+$ ]]
[[ "$LFS_REQUIRED_TRACK_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$LFS_REQUIRED_VEHICLE_SIZE" =~ ^[0-9]+$ ]]
[[ "$LFS_REQUIRED_VEHICLE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$LFS_UPGRADE_FROM_VERSION" == '0.8C20' ]]
[[ "$LFS_LOCAL_UPDATE_UPGRADE_FROM_VERSION" == '0.8C23' ]]
read -r -a previous_lfs_hashes <<<"$LFS_UPGRADE_FROM_SHA256S"
for previous_hash in "${previous_lfs_hashes[@]}"; do
  [[ "$previous_hash" =~ ^[0-9a-f]{64}$ ]]
done
[[ " $LFS_UPGRADE_FROM_SHA256S " == *' a8a41b1cb8763f6bfe51bead18c735ea9f7d4fbb21566f1d635283676ecc04dd '* ]]
[[ "$LFS_UPGRADE_MANIFEST_NAME" == 'lfs-0.8C20-stock.manifest' ]]
[[ "$LFS_UPGRADE_MANIFEST_SIZE" == '197387' ]]
[[ "$LFS_UPGRADE_MANIFEST_SHA256" == 'be0868a84e9447a60e3b75f831563d551fc132c345cc3e8caa00dbcaf7d8a581' ]]
[[ "$LFS_UPGRADE_MANIFEST_ENTRIES" == '1963' ]]
[[ "$(stat -c %s "$ROOT_DIR/share/lfs-linux/$LFS_UPGRADE_MANIFEST_NAME")" == "$LFS_UPGRADE_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$ROOT_DIR/share/lfs-linux/$LFS_UPGRADE_MANIFEST_NAME" | awk '{print $1}')" == "$LFS_UPGRADE_MANIFEST_SHA256" ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_NAME" == 'lfs-0.8C20-seed.manifest' ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_SIZE" == '494758' ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_SHA256" == 'f4cf02b8c7b2488dfe45644e3669af84200488f6bcfcd2a78b7240b450b1bffb' ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_ENTRIES" == '4847' ]]
upgrade_seed_manifest="$ROOT_DIR/share/lfs-linux/$LFS_UPGRADE_SEED_MANIFEST_NAME"
[[ "$(stat -c %s "$upgrade_seed_manifest")" == "$LFS_UPGRADE_SEED_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$upgrade_seed_manifest" | awk '{print $1}')" == "$LFS_UPGRADE_SEED_MANIFEST_SHA256" ]]
[[ "$(grep -Ec $'^[fl]\t' "$upgrade_seed_manifest")" == "$LFS_UPGRADE_SEED_MANIFEST_ENTRIES" ]]
python3 - "$lfs_stock_manifest" "$lfs_seed_manifest" \
  "$ROOT_DIR/share/lfs-linux/$LFS_UPGRADE_MANIFEST_NAME" "$upgrade_seed_manifest" <<'PY'
from pathlib import Path
import sys


def entries(path: str) -> dict[str, tuple[str, str, str]]:
    result = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith(("f\t", "l\t")):
            kind, value, size, relative = line.split("\t", 3)
            result[relative] = (kind, value, size)
    return result

for subset_path, seed_path in ((sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])):
    subset = entries(subset_path)
    seed = entries(seed_path)
    assert all(seed.get(path) == value for path, value in subset.items())

target = entries(sys.argv[1])
predecessor = entries(sys.argv[3])
target_dds = {path: value for path, value in target.items() if path.startswith("data/skins_dds/")}
predecessor_dds = {path: value for path, value in predecessor.items() if path.startswith("data/skins_dds/")}
assert target_dds and target_dds == predecessor_dds
PY
if grep -Eq $'\tdata/(knw|training)/' "$ROOT_DIR/share/lfs-linux/$LFS_UPGRADE_MANIFEST_NAME"; then
  printf 'mutable predecessor cache entered the migration manifest\n' >&2
  exit 1
fi
[[ "$DXVK_ARCHIVE_URL" == https://github.com/doitsujin/dxvk/* ]]
[[ "$DXVK_ARCHIVE_SIZE" =~ ^[0-9]+$ ]]
[[ "$DXVK_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$DXVK_D3D11_X32_SIZE" == '8155150' ]]
[[ "$DXVK_D3D11_X32_SHA256" == '313f3482b850c1a39987a42f6da9e398919a15aecd0c506ca889099e5baaefff' ]]
[[ "$DXVK_DXGI_X32_SIZE" == '5869582' ]]
[[ "$DXVK_DXGI_X32_SHA256" == 'a97c07a7bdd2c580461de99bac5c7b8297fe3ac348587d84315bb6f4090ee092' ]]
[[ "$WINE_RUNTIME_VERSION" == '11.15-1' ]]
[[ "$WINE_VERSION_OUTPUT" == 'wine-11.15' ]]
[[ "$WINE_PACKAGE_URL" == https://archive.archlinux.org/packages/w/wine/* ]]
[[ "$WINE_PACKAGE_SIZE" =~ ^[0-9]+$ ]]
[[ "$WINE_PACKAGE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$WINE_PACKAGE_SIGNATURE_URL" == "$WINE_PACKAGE_URL.sig" ]]
[[ "$WINE_PACKAGE_SIGNATURE_SIZE" == '119' ]]
[[ "$WINE_PACKAGE_SIGNATURE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$WINE_SIGNING_KEY_NAME" == 'arch-wine-peter-jung.pgp' ]]
[[ "$WINE_SIGNING_KEY_SIZE" == '1527' ]]
[[ "$WINE_SIGNING_KEY_SHA256" == 'c3186f2f7bdbe1cd02002dc84bce781580e4edc49fdc3ad848096af6768f3a89' ]]
[[ "$WINE_SIGNING_KEY_FINGERPRINT" == 'D2E95FEC015CF1F911AAAB0C3D4C5008BB5C8D29' ]]
wine_signing_key="$ROOT_DIR/share/lfs-linux/$WINE_SIGNING_KEY_NAME"
[[ -f "$wine_signing_key" ]]
[[ "$(stat -c %s "$wine_signing_key")" == "$WINE_SIGNING_KEY_SIZE" ]]
[[ "$(sha256sum "$wine_signing_key" | awk '{print $1}')" == "$WINE_SIGNING_KEY_SHA256" ]]
wine_runtime_manifest="$ROOT_DIR/share/lfs-linux/$WINE_RUNTIME_MANIFEST_NAME"
[[ "$(stat -c %s "$wine_runtime_manifest")" == "$WINE_RUNTIME_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$wine_runtime_manifest" | awk '{print $1}')" == "$WINE_RUNTIME_MANIFEST_SHA256" ]]
[[ "$(awk -F '\t' '$1 == "f" || $1 == "l" { count++ } END { print count + 0 }' "$wine_runtime_manifest")" == "$WINE_RUNTIME_MANIFEST_ENTRIES" ]]

"$ROOT_DIR/bin/lfs-linux" help | grep -Fq 'setup'
"$ROOT_DIR/bin/lfs-linux" help | grep -Fq 'update-check'
"$ROOT_DIR/bin/lfs-linux" help | grep -Fq 'recover-update'
"$ROOT_DIR/bin/lfs-linux" help | grep -Fq 'verify-sources'
"$ROOT_DIR/bin/lfs-linux" help | grep -Fq 'remove'
status_output="$("$ROOT_DIR/bin/lfs-linux" status)"
grep -Fq 'PUBLIC TEST — NEW GRAPHICS (not stable)' <<<"$status_output"
grep -Fq 'v0.1.6 (LFS 0.7G old graphics)' <<<"$status_output"

community_icon="$ROOT_DIR/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg"
(( $(stat -c %s "$community_icon") < 4096 ))
xmllint --noout "$community_icon"
if grep -Eq '<(text|image|script)([[:space:]]|>)|href=' "$community_icon"; then
  printf 'community icon contains text, scripts, or external assets\n' >&2
  exit 1
fi

desktop-file-validate "$ROOT_DIR/share/applications/io.github.mitzracing.live_for_speed_linux.desktop"
if command -v appstreamcli >/dev/null 2>&1; then
  appstreamcli validate --no-net "$ROOT_DIR/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml"
else
  xmllint --noout "$ROOT_DIR/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml"
fi

ci_workflow="$ROOT_DIR/.github/workflows/ci.yml"
grep -Fq 'fetch-depth: 0' "$ci_workflow"

upstream_workflow="$ROOT_DIR/.github/workflows/upstream-check.yml"
grep -Fq 'contents: read' "$upstream_workflow"
grep -Fq 'issues: write' "$upstream_workflow"
grep -Fq 'persist-credentials: false' "$upstream_workflow"
grep -Fq 'scripts/sync-upstream-drift.py' "$upstream_workflow"
grep -Fq 'status:needs-maintainer' "$ROOT_DIR/scripts/sync-upstream-drift.py"
grep -Fq 'upstream-drift' "$ROOT_DIR/scripts/sync-upstream-drift.py"
if grep -Eq 'contents: write|pull-requests: write|packages: write' "$upstream_workflow"; then
  printf 'upstream drift workflow has excessive write permission\n' >&2
  exit 1
fi

# No privileged game install and no hidden auto-update path.
if grep -R -nE '^[[:space:]]*sudo[[:space:]]' "$ROOT_DIR/bin" "$ROOT_DIR/libexec" "$ROOT_DIR/scripts"; then
  printf 'privileged runtime command found\n' >&2
  exit 1
fi
if grep -R -nE '(curl|wget).*(launch_game|case.*launch)' "$ROOT_DIR/libexec/lfs-linux-core"; then
  printf 'network command found in launch hot path\n' >&2
  exit 1
fi
grep -Fq 'extract_7z_archive()' "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq "keep-existing) overwrite_option='-aos'" "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq "replace-existing) overwrite_option='-aoa'" "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq 'preflight_7z_archive' "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq 'preflight_bsdtar_archive' "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq 'gpgv --status-fd 1' "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq "verify_extracted_game_tree \"\$unpack\" 'extracted LFS'" "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq "verify_payload_manifest \"\$label immutable stock payload\"" "$ROOT_DIR/libexec/lfs-linux-core"
if grep -Eq 'LFS_INSTALLER_ACCEPTED_EXIT_CODES|ALLOW_UNTESTED_WINE|WINE_TESTED_MAJOR|wine>=10' "$ROOT_DIR/libexec/lfs-linux-core" "$ROOT_DIR/share/lfs-linux/release.env"; then
  printf 'unbounded installer or Wine-version acceptance remains in the public core\n' >&2
  exit 1
fi

# Public package tree must not contain proprietary Windows payloads.
if find "$ROOT_DIR" \( -path "$ROOT_DIR/legacy" -o -path "$ROOT_DIR/artifacts" \) -prune -o -type f \
  \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.msi' -o -iname '*.zip' \) -print -quit | grep -q .; then
  printf 'proprietary or binary runtime payload found in public tree\n' >&2
  exit 1
fi

[[ -x "$ROOT_DIR/packaging/debian/build-deb.sh" ]]
grep -Fq 'Section: contrib/games' "$ROOT_DIR/packaging/debian/build-deb.sh"
grep -Fq 'libc6 (>= 2.38)' "$ROOT_DIR/packaging/debian/build-deb.sh"
grep -Fq 'gpgv' "$ROOT_DIR/packaging/debian/build-deb.sh"
grep -Fq 'libsane1' "$ROOT_DIR/packaging/debian/build-deb.sh"
grep -Fq 'libvulkan1' "$ROOT_DIR/packaging/debian/build-deb.sh"
grep -Fq 'vulkan-icd' "$ROOT_DIR/packaging/debian/build-deb.sh"
if grep -Eq 'wine32|wine64|:i386' "$ROOT_DIR/packaging/debian/build-deb.sh"; then
  printf 'Debian package incorrectly requires system Wine or i386 Unix libraries for pure WoW64\n' >&2
  exit 1
fi
grep -Fq 'does not contain Live for Speed, Wine, DXVK' "$ROOT_DIR/packaging/debian/README.md"
grep -Fq 'live-for-speed-linux_0.3.3-0github1_amd64.deb' "$ROOT_DIR/packaging/debian/README.md"
grep -Fq 'Live for Speed 0.8C24 is a public test' "$ROOT_DIR/packaging/debian/build-deb.sh"
grep -Fq '**Status:** v0.3.3 public-test wrapper candidate.' "$ROOT_DIR/README.md"
grep -Fq '**LFS 0.8C24 new graphics**' "$ROOT_DIR/README.md"
grep -Fq 'same 8C23 marker' "$ROOT_DIR/README.md"
grep -Fq '"lfs-linux 0.3.3"' "$ROOT_DIR/docs/lfs-linux.1"
grep -Fq 'Live for Speed 0.8C24 is a public test' "$ROOT_DIR/docs/lfs-linux.1"
grep -Fq 'all 4,848 extracted official 0.8C24 files' "$ROOT_DIR/docs/ARCHITECTURE.md"
grep -Fq 'unchanged `8C23.txt` marker' "$ROOT_DIR/docs/TROUBLESHOOTING.md"
grep -Fq $'deb-check:\n\t./tests/test-debian-package.sh' "$ROOT_DIR/Makefile"
grep -Fq 'LFS_LINUX_DISPOSABLE_CONTAINER=1' "$ROOT_DIR/.github/workflows/ci.yml"
grep -Eq 'image: ubuntu@sha256:[0-9a-f]{64}$' "$ROOT_DIR/.github/workflows/ci.yml"
grep -Eq 'image: debian@sha256:[0-9a-f]{64}$' "$ROOT_DIR/.github/workflows/ci.yml"
grep -Fq 'LFS_LINUX_DISPOSABLE_CONTAINER' "$ROOT_DIR/scripts/test-debian-compat.sh"
grep -Fq '/.dockerenv' "$ROOT_DIR/scripts/test-debian-compat.sh"
python3 - "$ROOT_DIR/libexec/lfs-linux-core" "$ROOT_DIR/docs/lfs-linux.1" "$ROOT_DIR/bin/lfs-linux" "$ROOT_DIR/bin/lfs-linux-desktop" <<'PY'
import re
import sys
from pathlib import Path

core = Path(sys.argv[1]).read_text()
manual = Path(sys.argv[2]).read_text()
wrapper = Path(sys.argv[3]).read_text()
desktop = Path(sys.argv[4]).read_text()
assert core.index("(( EUID != 0 ))") < core.index('source "$RELEASE_FILE"')
assert wrapper.index("(( EUID != 0 ))") < wrapper.index('LFS_LINUX_LIBEXEC_DIR')
assert desktop.index("(( EUID != 0 ))") < desktop.index('LFS_LINUX_COMMAND')
detect = core.split("detect_wine() {", 1)[1].split("\n}", 1)[0]
assert detect.index("wine_runtime_is_complete") < detect.index('--version')
usage = core.split("Commands:\n", 1)[1].split("\nEnvironment:", 1)[0]
usage_commands = set(re.findall(r"^  ([a-z][a-z-]*)\s", usage, re.MULTILINE))
dispatch_commands = set(re.findall(r"^  ([a-z][a-z-]*)(?:\||\))", core, re.MULTILINE))
manual_commands = set(re.findall(r"^\.TP\n\.B ([a-z][a-z-]*)$", manual, re.MULTILINE))
assert usage_commands == dispatch_commands == manual_commands, (
    usage_commands,
    dispatch_commands,
    manual_commands,
)
PY

if [[ "${LFS_LINUX_SOURCE_ARCHIVE:-0}" != '1' ]]; then
  # Flathub stays policy-gated until upstream authorization.
  [[ ! -e "$ROOT_DIR/packaging/flathub/io.github.mitzracing.live_for_speed_linux.yml" ]]
  grep -Fq 'No Flatpak manifest exists here by design.' "$ROOT_DIR/packaging/flathub/README.md"

  # AUR recipe must use the exact audited Wine and a pinned project release asset.
  grep -Fq "pkgver=$(<"$ROOT_DIR/VERSION")" "$ROOT_DIR/packaging/aur/PKGBUILD"
  grep -Fq "pkgver = $(<"$ROOT_DIR/VERSION")" "$ROOT_DIR/packaging/aur/.SRCINFO"
  grep -Fq "pkgdesc='Unofficial launcher for Live for Speed, a racing simulator game'" "$ROOT_DIR/packaging/aur/PKGBUILD"
  grep -Fq 'pkgdesc = Unofficial launcher for Live for Speed, a racing simulator game' "$ROOT_DIR/packaging/aur/.SRCINFO"
  grep -Fq "'wine=11.15-1'" "$ROOT_DIR/packaging/aur/PKGBUILD"
  grep -Fq "'gnupg'" "$ROOT_DIR/packaging/aur/PKGBUILD"
  grep -Fq 'depends = gnupg' "$ROOT_DIR/packaging/aur/.SRCINFO"
  if grep -Eq 'ALLOW_UNTESTED_WINE|WINE_TESTED_MAJOR|wine>=10' "$ROOT_DIR/packaging/aur/PKGBUILD"; then
    printf 'broad Wine dependency remains in the AUR recipe\n' >&2
    exit 1
  fi
  if grep -Fq 'SKIP' "$ROOT_DIR/packaging/aur/PKGBUILD"; then
    printf 'AUR source checksum is not pinned\n' >&2
    exit 1
  fi
  grep -Fq "releases/download/v\$pkgver/\$_source_name-\$pkgver.tar.gz" "$ROOT_DIR/packaging/aur/PKGBUILD"
  grep -Eq "^sha256sums=\('[0-9a-f]{64}'\)$" "$ROOT_DIR/packaging/aur/PKGBUILD"
fi

printf '[PASS] syntax, manifest pins, metadata, stock-game boundary, and publication gates\n'
