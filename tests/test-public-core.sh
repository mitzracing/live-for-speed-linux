#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
TMP_ROOT="$(mktemp -d /tmp/lfs-linux-core.XXXXXX)"
readonly TMP_ROOT
trap 'rm -rf "$TMP_ROOT"' EXIT

export LFS_LINUX_DATA_DIR="$ROOT_DIR/share/lfs-linux"
export LFS_LINUX_LIBEXEC_DIR="$ROOT_DIR/libexec"
export LFS_LINUX_STATE_DIR="$TMP_ROOT/state"
export LFS_LINUX_CACHE_DIR="$TMP_ROOT/cache"
export LFS_LINUX_LOG_DIR="$TMP_ROOT/log"

# shellcheck source=/dev/null
source "$ROOT_DIR/share/lfs-linux/release.env"

status_output="$("$ROOT_DIR/bin/lfs-linux" status)"
grep -Fq "State:      $TMP_ROOT/state" <<<"$status_output"

LFS_LINUX_DOWNLOADS_PAGE_FILE="$ROOT_DIR/tests/fixtures/lfs-downloads-current.html" \
  "$ROOT_DIR/bin/lfs-linux" update-check >"$TMP_ROOT/update-current.out"
grep -Fq 'Website test:   0.8C20 (new graphics public test; LFS_S3_8C20_setup.exe)' "$TMP_ROOT/update-current.out"
grep -Fq 'Status:         current public-test pin' "$TMP_ROOT/update-current.out"

set +e
LFS_LINUX_DOWNLOADS_PAGE_FILE="$ROOT_DIR/tests/fixtures/lfs-downloads-drift.html" \
  "$ROOT_DIR/bin/lfs-linux" update-check >"$TMP_ROOT/update-drift.out"
drift_status=$?
set -e
[[ "$drift_status" -eq 2 ]]
grep -Fq 'public-test update or drift detected' "$TMP_ROOT/update-drift.out"

legacy_data="$TMP_ROOT/update-legacy-data"
mkdir -p "$legacy_data"
cp "$ROOT_DIR/share/lfs-linux/release.env" "$legacy_data/release.env"
python3 - "$legacy_data/release.env" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "LFS_VERSION='0.8C20'": "LFS_VERSION='0.7G'",
    "LFS_CHANNEL='public-test'": "LFS_CHANNEL='stable'",
    "LFS_PUBLIC_TEST_FAMILY='0.8C'": "LFS_PUBLIC_TEST_FAMILY=''",
    "LFS_INSTALLER_NAME='LFS_S3_8C20_setup.exe'": "LFS_INSTALLER_NAME='LFS_S3_7G_setup.exe'",
}
for old, new in replacements.items():
    assert old in text
    text = text.replace(old, new)
path.write_text(text)
PY
set +e
LFS_LINUX_DATA_DIR="$legacy_data" \
LFS_LINUX_DOWNLOADS_PAGE_FILE="$ROOT_DIR/tests/fixtures/lfs-downloads-current.html" \
  "$ROOT_DIR/bin/lfs-linux" update-check >"$TMP_ROOT/update-legacy.out"
legacy_status=$?
set -e
[[ "$legacy_status" -eq 2 ]]
grep -Fq 'new-graphics public test available (0.8C20)' "$TMP_ROOT/update-legacy.out"
grep -Fq 'wrapper made no game-file changes' "$TMP_ROOT/update-legacy.out"
[[ ! -d "$TMP_ROOT/state" ]]

set +e
printf 'n\n' | "$ROOT_DIR/bin/lfs-linux" setup >"$TMP_ROOT/setup-cancel.out" 2>&1
setup_status=$?
set -e
[[ "$setup_status" -eq 3 ]]
grep -Fq 'Setup cancelled' "$TMP_ROOT/setup-cancel.out"
[[ ! -d "$TMP_ROOT/state" ]]

setup_drift_state="$TMP_ROOT/setup-drift-state"
mkdir -p "$setup_drift_state/prefix/drive_c/LFS"
printf 'unexpected-executable' >"$setup_drift_state/prefix/drive_c/LFS/LFS.exe"
set +e
printf 'y\n' | LFS_LINUX_STATE_DIR="$setup_drift_state" \
  "$ROOT_DIR/bin/lfs-linux" setup >"$TMP_ROOT/setup-drift.out" 2>&1
setup_drift_status=$?
set -e
[[ "$setup_drift_status" -ne 0 ]]
grep -Fq 'unrecognized LFS update detected' "$TMP_ROOT/setup-drift.out"
if grep -Fq 'Continue with verified setup?' "$TMP_ROOT/setup-drift.out"; then
  printf 'unknown self-update reached obsolete setup confirmation\n' >&2
  exit 1
fi
[[ ! -e "$setup_drift_state/.managed-by-lfs-linux" ]]

set +e
"$ROOT_DIR/bin/lfs-linux" launch >"$TMP_ROOT/launch.out" 2>&1
launch_status=$?
set -e
[[ "$launch_status" -ne 0 ]]
grep -Eq 'private prefix is missing|exact audited Wine 11.15-1' "$TMP_ROOT/launch.out"

fake_root="$TMP_ROOT/fake-runtime"
fake_wine="$fake_root/usr/bin/wine"
test_data="$TMP_ROOT/test-data"
mkdir -p "$fake_root/usr/bin" "$fake_root/usr/lib/wine" "$test_data" "$TMP_ROOT/marker-state/prefix"
cat >"$fake_wine" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == '--version' ]] && { printf '%s\n' 'wine-11.15'; exit 0; }
exit 1
EOF
cat >"$fake_root/usr/bin/wineserver" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fake_wine" "$fake_root/usr/bin/wineserver"
"$ROOT_DIR/scripts/generate-payload-manifest.py" wine "$fake_root" "$test_data/fake-wine.manifest" >/dev/null
fake_wine_manifest_size="$(stat -c %s "$test_data/fake-wine.manifest")"
fake_wine_manifest_hash="$(sha256sum "$test_data/fake-wine.manifest" | awk '{print $1}')"
printf 'fake-signing-key' >"$test_data/fake-signing-key.gpg"
fake_signing_key_size="$(stat -c %s "$test_data/fake-signing-key.gpg")"
fake_signing_key_hash="$(sha256sum "$test_data/fake-signing-key.gpg" | awk '{print $1}')"
cp "$ROOT_DIR/share/lfs-linux/release.env" "$test_data/release.env"
cp "$ROOT_DIR/share/lfs-linux/$LFS_STOCK_MANIFEST_NAME" "$test_data/$LFS_STOCK_MANIFEST_NAME"
cat >>"$test_data/release.env" <<EOF
WINE_RUNTIME_MANIFEST_NAME='fake-wine.manifest'
WINE_RUNTIME_MANIFEST_SIZE='$fake_wine_manifest_size'
WINE_RUNTIME_MANIFEST_SHA256='$fake_wine_manifest_hash'
WINE_RUNTIME_MANIFEST_ENTRIES='2'
WINE_SIGNING_KEY_NAME='fake-signing-key.gpg'
WINE_SIGNING_KEY_SIZE='$fake_signing_key_size'
WINE_SIGNING_KEY_SHA256='$fake_signing_key_hash'
EOF

fake12_root="$TMP_ROOT/fake12-runtime"
mkdir -p "$fake12_root/usr/bin" "$fake12_root/usr/lib/wine"
cat >"$fake12_root/usr/bin/wine" <<'EOF'
#!/usr/bin/env bash
: >"${LFS_TEST_WINE_EXEC_MARKER:?}"
[[ "${1:-}" == '--version' ]] && { printf '%s\n' 'wine-12.0'; exit 0; }
exit 1
EOF
cat >"$fake12_root/usr/bin/wineserver" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fake12_root/usr/bin/wine" "$fake12_root/usr/bin/wineserver"
set +e
LFS_TEST_WINE_EXEC_MARKER="$TMP_ROOT/unverified-wine-executed" \
  LFS_LINUX_DATA_DIR="$test_data" LFS_LINUX_STATE_DIR="$TMP_ROOT/untested-state" \
  LFS_LINUX_WINE="$fake12_root/usr/bin/wine" "$ROOT_DIR/bin/lfs-linux" doctor >"$TMP_ROOT/untested-wine.out" 2>&1
untested_wine_status=$?
set -e
[[ "$untested_wine_status" -ne 0 ]]
grep -Fq 'exact audited Wine 11.15-1 is unavailable' "$TMP_ROOT/untested-wine.out"
[[ ! -e "$TMP_ROOT/unverified-wine-executed" ]]
[[ ! -e "$TMP_ROOT/untested-state/.managed-by-lfs-linux" ]]

mkdir -p "$TMP_ROOT/drift-state/prefix/drive_c/LFS"
printf 'unexpected-executable' >"$TMP_ROOT/drift-state/prefix/drive_c/LFS/LFS.exe"
set +e
LFS_LINUX_DATA_DIR="$test_data" LFS_LINUX_STATE_DIR="$TMP_ROOT/drift-state" LFS_LINUX_WINE="$fake_wine" \
  "$ROOT_DIR/bin/lfs-linux" install >"$TMP_ROOT/install-drift.out" 2>&1
install_drift_status=$?
set -e
[[ "$install_drift_status" -ne 0 ]]
grep -Fq 'unrecognized LFS update detected' "$TMP_ROOT/install-drift.out"
grep -Fq 'no files changed' "$TMP_ROOT/install-drift.out"
[[ ! -e "$TMP_ROOT/drift-state/.managed-by-lfs-linux" ]]
[[ ! -e "$TMP_ROOT/drift-state/runtime" ]]

mkdir -p "$TMP_ROOT/missing-exe-state/prefix/drive_c/LFS"
printf 'player-data' >"$TMP_ROOT/missing-exe-state/prefix/drive_c/LFS/profile.dat"
set +e
LFS_LINUX_DATA_DIR="$test_data" LFS_LINUX_STATE_DIR="$TMP_ROOT/missing-exe-state" LFS_LINUX_WINE="$fake_wine" \
  "$ROOT_DIR/bin/lfs-linux" install >"$TMP_ROOT/missing-exe.out" 2>&1
missing_exe_status=$?
set -e
[[ "$missing_exe_status" -ne 0 ]]
grep -Fq 'no recognized executable or current marker' "$TMP_ROOT/missing-exe.out"
grep -Fqx 'player-data' "$TMP_ROOT/missing-exe-state/prefix/drive_c/LFS/profile.dat"
[[ ! -e "$TMP_ROOT/missing-exe-state/.managed-by-lfs-linux" ]]
[[ ! -e "$TMP_ROOT/missing-exe-state/runtime" ]]

printf '#arch=win64\n' >"$TMP_ROOT/marker-state/prefix/system.reg"
cat >"$TMP_ROOT/marker-state/install.env" <<EOF
LFS_VERSION='$LFS_VERSION'
LFS_CHANNEL='$LFS_CHANNEL'
LFS_EXE_SHA256='$LFS_EXE_SHA256'
LFS_STOCK_MANIFEST_SHA256='$LFS_STOCK_MANIFEST_SHA256'
DXVK_VERSION='$DXVK_VERSION'
DXVK_D3D11_X32_SHA256='$DXVK_D3D11_X32_SHA256'
DXVK_DXGI_X32_SHA256='$DXVK_DXGI_X32_SHA256'
WINE_RUNTIME_VERSION='$WINE_RUNTIME_VERSION'
WINE_RUNTIME_MANIFEST_SHA256='$fake_wine_manifest_hash'
WINE_VERSION='wine-11.15'
PREFIX_ARCH='win64'
touch '$TMP_ROOT/marker-was-sourced'
EOF
set +e
LFS_LINUX_DATA_DIR="$test_data" LFS_LINUX_STATE_DIR="$TMP_ROOT/marker-state" LFS_LINUX_WINE="$fake_wine" \
  "$ROOT_DIR/bin/lfs-linux" launch >"$TMP_ROOT/marker.out" 2>&1
marker_status=$?
set -e
[[ "$marker_status" -ne 0 ]]
[[ ! -e "$TMP_ROOT/marker-was-sourced" ]]
grep -Fq 'immutable stock payload drift' "$TMP_ROOT/marker.out"

# Deleting an arbitrary immutable asset must fail even when loose tree totals still pass.
tiny_data="$TMP_ROOT/tiny-data"
tiny_state="$TMP_ROOT/tiny-state"
tiny_game="$tiny_state/prefix/drive_c/LFS"
mkdir -p "$tiny_data" "$tiny_game/data/skins_dds" "$tiny_game/data/wld" "$tiny_game/data/veh" \
  "$tiny_state/runtime/dxvk/x32" "$tiny_state/prefix/drive_c/windows/syswow64"
printf exe >"$tiny_game/LFS.exe"
printf helmet >"$tiny_game/data/skins_dds/HEL_DEFAULT.dds"
printf track >"$tiny_game/data/wld/BLACKWOOD.wld"
printf vehicle >"$tiny_game/data/veh/XFG.vob"
printf fone >"$tiny_game/data/veh/F1.vob"
printf d11 >"$tiny_state/runtime/dxvk/x32/d3d11.dll"
printf dxg >"$tiny_state/runtime/dxvk/x32/dxgi.dll"
printf d11 >"$tiny_state/prefix/drive_c/windows/syswow64/d3d11.dll"
printf dxg >"$tiny_state/prefix/drive_c/windows/syswow64/dxgi.dll"
printf '#arch=win64\n' >"$tiny_state/prefix/system.reg"
printf '%s\n' 'lfs-linux managed state; unknown files are preserved on removal' >"$tiny_state/.managed-by-lfs-linux"
exe_hash="$(sha256sum "$tiny_game/LFS.exe" | awk '{print $1}')"
helmet_hash="$(sha256sum "$tiny_game/data/skins_dds/HEL_DEFAULT.dds" | awk '{print $1}')"
track_hash="$(sha256sum "$tiny_game/data/wld/BLACKWOOD.wld" | awk '{print $1}')"
vehicle_hash="$(sha256sum "$tiny_game/data/veh/XFG.vob" | awk '{print $1}')"
d3d11_hash="$(sha256sum "$tiny_state/runtime/dxvk/x32/d3d11.dll" | awk '{print $1}')"
dxgi_hash="$(sha256sum "$tiny_state/runtime/dxvk/x32/dxgi.dll" | awk '{print $1}')"
cp "$test_data/release.env" "$tiny_data/release.env"
cp "$test_data/fake-wine.manifest" "$tiny_data/fake-wine.manifest"
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs "$tiny_game" "$tiny_data/tiny-stock.manifest" >/dev/null
tiny_manifest_size="$(stat -c %s "$tiny_data/tiny-stock.manifest")"
tiny_manifest_hash="$(sha256sum "$tiny_data/tiny-stock.manifest" | awk '{print $1}')"
cat >>"$tiny_data/release.env" <<EOF
LFS_EXE_SIZE='3'
LFS_EXE_SHA256='$exe_hash'
LFS_STOCK_MANIFEST_NAME='tiny-stock.manifest'
LFS_STOCK_MANIFEST_SIZE='$tiny_manifest_size'
LFS_STOCK_MANIFEST_SHA256='$tiny_manifest_hash'
LFS_STOCK_MANIFEST_ENTRIES='5'
LFS_TREE_MIN_FILE_COUNT='4'
LFS_TREE_MIN_BYTES='1'
LFS_REQUIRED_HELMET_SIZE='6'
LFS_REQUIRED_HELMET_SHA256='$helmet_hash'
LFS_REQUIRED_TRACK_SIZE='5'
LFS_REQUIRED_TRACK_SHA256='$track_hash'
LFS_REQUIRED_VEHICLE_SIZE='7'
LFS_REQUIRED_VEHICLE_SHA256='$vehicle_hash'
DXVK_D3D11_X32_SIZE='3'
DXVK_D3D11_X32_SHA256='$d3d11_hash'
DXVK_DXGI_X32_SIZE='3'
DXVK_DXGI_X32_SHA256='$dxgi_hash'
EOF
cat >"$tiny_state/install.env" <<EOF
LFS_VERSION='$LFS_VERSION'
LFS_CHANNEL='$LFS_CHANNEL'
LFS_EXE_SHA256='$exe_hash'
LFS_STOCK_MANIFEST_SHA256='$tiny_manifest_hash'
DXVK_VERSION='$DXVK_VERSION'
DXVK_D3D11_X32_SHA256='$d3d11_hash'
DXVK_DXGI_X32_SHA256='$dxgi_hash'
WINE_RUNTIME_VERSION='$WINE_RUNTIME_VERSION'
WINE_RUNTIME_MANIFEST_SHA256='$fake_wine_manifest_hash'
WINE_VERSION='wine-11.15'
PREFIX_ARCH='win64'
EOF
rm "$tiny_game/data/veh/F1.vob"
set +e
LFS_LINUX_DATA_DIR="$tiny_data" LFS_LINUX_STATE_DIR="$tiny_state" LFS_LINUX_WINE="$fake_wine" \
  "$ROOT_DIR/bin/lfs-linux" doctor >"$TMP_ROOT/partial-doctor.out" 2>&1
partial_doctor_status=$?
LFS_LINUX_DATA_DIR="$tiny_data" LFS_LINUX_STATE_DIR="$tiny_state" LFS_LINUX_WINE="$fake_wine" \
  "$ROOT_DIR/bin/lfs-linux" launch >"$TMP_ROOT/partial-launch.out" 2>&1
partial_launch_status=$?
LFS_LINUX_DATA_DIR="$tiny_data" LFS_LINUX_STATE_DIR="$tiny_state" LFS_LINUX_WINE="$fake_wine" \
  "$ROOT_DIR/bin/lfs-linux" ready >"$TMP_ROOT/partial-ready.out" 2>&1
partial_ready_status=$?
set -e
[[ "$partial_doctor_status" -ne 0 && "$partial_launch_status" -ne 0 && "$partial_ready_status" -ne 0 ]]
grep -Fq 'required stock file missing: data/veh/F1.vob' "$TMP_ROOT/partial-doctor.out"
grep -Fq 'required stock file missing: data/veh/F1.vob' "$TMP_ROOT/partial-launch.out"
grep -Fq 'stock LFS tree file count: 4' "$TMP_ROOT/partial-doctor.out"

mkdir -p "$TMP_ROOT/state/prefix/drive_c/LFS"
printf '%s\n' 'lfs-linux managed state; unknown files are preserved on removal' >"$TMP_ROOT/state/.managed-by-lfs-linux"
printf 'player-owned-data' >"$TMP_ROOT/state/prefix/drive_c/LFS/player.test"
set +e
"$ROOT_DIR/bin/lfs-linux" remove >"$TMP_ROOT/remove.out" 2>&1
remove_status=$?
set -e
[[ "$remove_status" -ne 0 ]]
grep -Fq 'removal needs a terminal' "$TMP_ROOT/remove.out"
[[ -f "$TMP_ROOT/state/prefix/drive_c/LFS/player.test" ]]

printf 'unrelated-user-file' >"$TMP_ROOT/state/keep.test"
LFS_LINUX_CONFIRM_REMOVE=1 "$ROOT_DIR/bin/lfs-linux" remove >"$TMP_ROOT/remove-confirmed.out" 2>&1
[[ ! -e "$TMP_ROOT/state/prefix" ]]
[[ -f "$TMP_ROOT/state/keep.test" ]]
grep -Fq 'kept unrecognized files' "$TMP_ROOT/remove-confirmed.out"

mkdir -p "$TMP_ROOT/fake-bin"
cat >"$TMP_ROOT/fake-bin/lfs-mock" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  ready) [[ -f "$MOCK_READY" ]] ;;
  setup) printf 'setup\n' >>"$MOCK_LOG"; touch "$MOCK_READY" ;;
  launch) printf 'launch\n' >>"$MOCK_LOG" ;;
  doctor) printf 'doctor\n' >>"$MOCK_LOG" ;;
  *) exit 2 ;;
esac
EOF
cat >"$TMP_ROOT/fake-bin/xterm" <<'EOF'
#!/usr/bin/env bash
while (( $# > 0 )); do
  if [[ "$1" == '-e' ]]; then
    shift
    exec "$@"
  fi
  shift
done
exit 2
EOF
chmod +x "$TMP_ROOT/fake-bin/lfs-mock" "$TMP_ROOT/fake-bin/xterm"
export MOCK_READY="$TMP_ROOT/desktop-ready" MOCK_LOG="$TMP_ROOT/desktop.log"
PATH="$TMP_ROOT/fake-bin:$PATH" LFS_LINUX_COMMAND="$TMP_ROOT/fake-bin/lfs-mock" \
  "$ROOT_DIR/bin/lfs-linux-desktop" launch
PATH="$TMP_ROOT/fake-bin:$PATH" LFS_LINUX_COMMAND="$TMP_ROOT/fake-bin/lfs-mock" \
  "$ROOT_DIR/bin/lfs-linux-desktop" launch
[[ "$(grep -c '^setup$' "$MOCK_LOG")" -eq 1 ]]
[[ "$(grep -c '^launch$' "$MOCK_LOG")" -eq 2 ]]

generic_bin="$TMP_ROOT/generic-terminal-bin"
mkdir -p "$generic_bin"
ln -s /usr/bin/bash "$generic_bin/bash"
ln -s /usr/bin/dirname "$generic_bin/dirname"
ln -s /usr/bin/touch "$generic_bin/touch"
ln -s "$TMP_ROOT/fake-bin/lfs-mock" "$generic_bin/lfs-mock"
cat >"$generic_bin/x-terminal-emulator" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$MOCK_TERMINAL_LOG"
[[ "${1:-}" == '-e' ]] || exit 2
shift
exec "$@"
EOF
chmod +x "$generic_bin/x-terminal-emulator"
rm -f "$MOCK_READY"
export MOCK_TERMINAL_LOG="$TMP_ROOT/generic-terminal.log"
PATH="$generic_bin" LFS_LINUX_COMMAND="$generic_bin/lfs-mock" \
  "$ROOT_DIR/bin/lfs-linux-desktop" setup
grep -Fq -- '-e ' "$MOCK_TERMINAL_LOG"
grep -Fxq 'setup' "$MOCK_LOG"

printf '[PASS] pre-execution Wine verification, stock drift, terminal dispatch, marker, and safe-removal paths pass\n'
