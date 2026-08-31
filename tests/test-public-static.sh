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

# shellcheck source=/dev/null
source "$ROOT_DIR/share/lfs-linux/release.env"
[[ "$LFS_LINUX_VERSION" == "$(<"$ROOT_DIR/VERSION")" ]]
[[ "$LFS_VERSION" == '0.8C20' ]]
[[ "$LFS_CHANNEL" == 'public-test' ]]
[[ "$LFS_CHANNEL_LABEL" == *'PUBLIC TEST'* && "$LFS_CHANNEL_LABEL" == *'not stable'* ]]
[[ "$LFS_PUBLIC_TEST_FAMILY" == '0.8C' ]]
[[ "$LFS_FALLBACK_WRAPPER" == 'v0.1.6' ]]
[[ "$LFS_FALLBACK_VERSION" == '0.7G' ]]
[[ "$LFS_INSTALLER_URL" == https://www.lfs.net/* ]]
[[ "$LFS_INSTALLER_SIZE" == '1744256786' ]]
[[ "$LFS_INSTALLER_SHA256" == 'c06d3d9055f40e8e70994280a52b23f8c3c59b24ad726380547f0ed8899b9b76' ]]
[[ "$LFS_EXE_SIZE" == '2743808' ]]
[[ "$LFS_EXE_SHA256" == 'a8a41b1cb8763f6bfe51bead18c735ea9f7d4fbb21566f1d635283676ecc04dd' ]]
[[ "$LFS_STOCK_MANIFEST_NAME" == 'lfs-0.8C20-stock.manifest' ]]
[[ "$LFS_STOCK_MANIFEST_SIZE" == '197387' ]]
[[ "$LFS_STOCK_MANIFEST_SHA256" == 'be0868a84e9447a60e3b75f831563d551fc132c345cc3e8caa00dbcaf7d8a581' ]]
[[ "$LFS_STOCK_MANIFEST_ENTRIES" == '1963' ]]
lfs_stock_manifest="$ROOT_DIR/share/lfs-linux/$LFS_STOCK_MANIFEST_NAME"
[[ "$(stat -c %s "$lfs_stock_manifest")" == "$LFS_STOCK_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$lfs_stock_manifest" | awk '{print $1}')" == "$LFS_STOCK_MANIFEST_SHA256" ]]
[[ "$(awk -F '\t' '$1 == "f" || $1 == "l" { count++ } END { print count + 0 }' "$lfs_stock_manifest")" == "$LFS_STOCK_MANIFEST_ENTRIES" ]]
[[ "$LFS_STOCK_SEED_MANIFEST_NAME" == 'lfs-0.8C20-seed.manifest' ]]
[[ "$LFS_STOCK_SEED_MANIFEST_SIZE" == '494758' ]]
[[ "$LFS_STOCK_SEED_MANIFEST_SHA256" == 'f4cf02b8c7b2488dfe45644e3669af84200488f6bcfcd2a78b7240b450b1bffb' ]]
[[ "$LFS_STOCK_SEED_MANIFEST_ENTRIES" == '4847' ]]
lfs_seed_manifest="$ROOT_DIR/share/lfs-linux/$LFS_STOCK_SEED_MANIFEST_NAME"
[[ "$(stat -c %s "$lfs_seed_manifest")" == "$LFS_STOCK_SEED_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$lfs_seed_manifest" | awk '{print $1}')" == "$LFS_STOCK_SEED_MANIFEST_SHA256" ]]
[[ "$(grep -Ec $'^[fl]\t' "$lfs_seed_manifest")" == "$LFS_STOCK_SEED_MANIFEST_ENTRIES" ]]
grep -Fq $'\tdata/knw/AS1_BF1.knw' "$lfs_seed_manifest"
grep -Fq $'\tdata/training/Acceleration - GTI.lsn' "$lfs_seed_manifest"
grep -Fq $'\tdata/veh/FO8.vob' "$lfs_stock_manifest"
grep -Fq $'\tbin/shaders11/ps_1.cso' "$lfs_stock_manifest"
grep -Fq $'\tdata/versions/8C20.txt' "$lfs_stock_manifest"
if grep -Eq $'\tdata/(knw|training)/' "$lfs_stock_manifest"; then
  printf 'mutable AI knowledge or training content entered the immutable stock manifest\n' >&2
  exit 1
fi
grep -Fq '"data/knw/"' "$ROOT_DIR/scripts/generate-payload-manifest.py"
grep -Fq '"data/training/"' "$ROOT_DIR/scripts/generate-payload-manifest.py"
[[ "$LFS_TREE_MIN_FILE_COUNT" == "$LFS_STOCK_MANIFEST_ENTRIES" ]]
[[ "$LFS_TREE_MIN_BYTES" =~ ^[0-9]+$ && "$LFS_TREE_MIN_BYTES" -ge 3900000000 ]]
immutable_bytes="$(awk -F '\t' '$1 == "f" { total += $3 } END { printf "%.0f", total }' "$lfs_stock_manifest")"
(( immutable_bytes >= LFS_TREE_MIN_BYTES ))
[[ "$LFS_NESTED_ARCHIVE_COUNT" == '52' ]]
[[ "$LFS_NESTED_DDS_ARCHIVE_COUNT" == '41' ]]
[[ "$LFS_NESTED_WLD_ARCHIVE_COUNT" == '9' ]]
[[ "$LFS_NESTED_MANIFEST_NAME" == 'lfs-0.8C20-nested.manifest' ]]
[[ "$LFS_NESTED_MANIFEST_SIZE" == '5030' ]]
[[ "$LFS_NESTED_MANIFEST_SHA256" == '70ebd0402f33b82e83cc50c4f5f458b8fecfe32facbd6486105f227a3399237f' ]]
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
[[ "$LFS_UPGRADE_FROM_VERSION" == '0.8C19' ]]
read -r -a previous_lfs_hashes <<<"$LFS_UPGRADE_FROM_SHA256S"
for previous_hash in "${previous_lfs_hashes[@]}"; do
  [[ "$previous_hash" =~ ^[0-9a-f]{64}$ ]]
done
[[ "$LFS_UPGRADE_MANIFEST_NAME" == 'lfs-0.8C19-stock.manifest' ]]
[[ "$LFS_UPGRADE_MANIFEST_SIZE" == '196775' ]]
[[ "$LFS_UPGRADE_MANIFEST_SHA256" == '4b3516ccbb7c3afe0d00c7c26c044035ec236a389d054ee2f05935bacec2c3a8' ]]
[[ "$LFS_UPGRADE_MANIFEST_ENTRIES" == '1957' ]]
[[ "$(stat -c %s "$ROOT_DIR/share/lfs-linux/$LFS_UPGRADE_MANIFEST_NAME")" == "$LFS_UPGRADE_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$ROOT_DIR/share/lfs-linux/$LFS_UPGRADE_MANIFEST_NAME" | awk '{print $1}')" == "$LFS_UPGRADE_MANIFEST_SHA256" ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_NAME" == 'lfs-0.8C19-seed.manifest' ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_SIZE" == '494146' ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_SHA256" == 'f80039d4dcb415d69caa0802fea9aa4b8ab51c9596cc1ee94a6ec92192c4c9b8' ]]
[[ "$LFS_UPGRADE_SEED_MANIFEST_ENTRIES" == '4841' ]]
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
wine_runtime_manifest="$ROOT_DIR/share/lfs-linux/$WINE_RUNTIME_MANIFEST_NAME"
[[ "$(stat -c %s "$wine_runtime_manifest")" == "$WINE_RUNTIME_MANIFEST_SIZE" ]]
[[ "$(sha256sum "$wine_runtime_manifest" | awk '{print $1}')" == "$WINE_RUNTIME_MANIFEST_SHA256" ]]
[[ "$(awk -F '\t' '$1 == "f" || $1 == "l" { count++ } END { print count + 0 }' "$wine_runtime_manifest")" == "$WINE_RUNTIME_MANIFEST_ENTRIES" ]]

"$ROOT_DIR/bin/lfs-linux" help | grep -Fq 'setup'
"$ROOT_DIR/bin/lfs-linux" help | grep -Fq 'update-check'
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
grep -Fq '7z x -y' "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq "verify_extracted_game_tree \"\$unpack\" 'extracted LFS'" "$ROOT_DIR/libexec/lfs-linux-core"
grep -Fq "verify_payload_manifest \"\$label immutable stock payload\"" "$ROOT_DIR/libexec/lfs-linux-core"
if grep -Eq 'LFS_INSTALLER_ACCEPTED_EXIT_CODES|ALLOW_UNTESTED_WINE|WINE_TESTED_MAJOR|wine>=10' "$ROOT_DIR/libexec/lfs-linux-core" "$ROOT_DIR/share/lfs-linux/release.env"; then
  printf 'unbounded installer or Wine-version acceptance remains in the public core\n' >&2
  exit 1
fi

# Public package tree must not contain proprietary Windows payloads.
if find "$ROOT_DIR" -path "$ROOT_DIR/legacy" -prune -o -type f \
  \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.msi' -o -iname '*.zip' \) -print -quit | grep -q .; then
  printf 'proprietary or binary runtime payload found in public tree\n' >&2
  exit 1
fi

if [[ "${LFS_LINUX_SOURCE_ARCHIVE:-0}" != '1' ]]; then
  # Flathub stays policy-gated until upstream authorization.
  [[ ! -e "$ROOT_DIR/packaging/flathub/io.github.mitzracing.live_for_speed_linux.yml" ]]
  grep -Fq 'No Flatpak manifest exists here by design.' "$ROOT_DIR/packaging/flathub/README.md"

  # AUR recipe must use the exact audited Wine and a pinned project release asset.
  grep -Fq "'wine=11.15-1'" "$ROOT_DIR/packaging/aur/PKGBUILD"
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
