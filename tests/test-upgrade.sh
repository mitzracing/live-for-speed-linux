#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
TMP_ROOT="$(mktemp -d /tmp/lfs-linux-upgrade.XXXXXX)"
readonly TMP_ROOT
cleanup() {
  local status=$?
  if (( status != 0 )); then
    printf 'upgrade fixture failed; temporary output follows\n' >&2
    find "$TMP_ROOT" -maxdepth 2 -type f \( -name '*.out' -o -name '*.log' \) -print -exec tail -n 80 {} \; >&2 || true
  fi
  if [[ "${LFS_KEEP_UPGRADE_FIXTURE:-0}" == '1' ]]; then
    printf 'kept upgrade fixture: %s\n' "$TMP_ROOT" >&2
  else
    rm -rf "$TMP_ROOT"
  fi
  return "$status"
}
trap cleanup EXIT

state="$TMP_ROOT/state"
cache="$TMP_ROOT/cache"
logs="$TMP_ROOT/log"
data="$TMP_ROOT/data"
old_stock="$TMP_ROOT/old-stock"
new_stock="$TMP_ROOT/new-stock"
outer_stock="$TMP_ROOT/outer-stock"
nested_root="$TMP_ROOT/nested-root"
game="$state/prefix/drive_c/LFS"
fake_wine_root="$TMP_ROOT/fake-wine"
fake_wine="$fake_wine_root/usr/bin/wine"
mkdir -p "$data" "$cache" "$logs" "$old_stock" "$new_stock" "$outer_stock" \
  "$nested_root/inst_tmp" "$TMP_ROOT/upstream" "$fake_wine_root/usr/bin" "$fake_wine_root/usr/lib/wine" \
  "$state/prefix/drive_c/windows/syswow64"

cat >"$fake_wine" <<'EOF'
#!/usr/bin/env bash
exit_status=0
case "${1:-}" in
  --version)
    printf '%s\n' 'wine-11.15'
    ;;
  wineboot)
    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
    printf '#arch=win64\n' >"$WINEPREFIX/system.reg"
    ;;
  reg)
    ;;
  *)
    if [[ -n "${LFS_TEST_SELF_UPDATE_VERSION:-}" && -f "${1:-}" ]]; then
      game_root="$(dirname -- "$1")"
      printf 'self-updated-%s' "$LFS_TEST_SELF_UPDATE_VERSION" >"$game_root/LFS.exe"
      printf 'game-owned-update' >"$game_root/game-update.stock"
      mkdir -p "$game_root/data/versions"
      : >"$game_root/data/versions/$LFS_TEST_SELF_UPDATE_VERSION.txt"
      exit_status="${LFS_TEST_EXIT_STATUS:-0}"
    fi
    ;;
esac
exit "$exit_status"
EOF
cat >"$fake_wine_root/usr/bin/wineserver" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fake_wine" "$fake_wine_root/usr/bin/wineserver"
"$ROOT_DIR/scripts/generate-payload-manifest.py" wine "$fake_wine_root" "$data/fake-wine.manifest" >/dev/null
wine_manifest_size="$(stat -c %s "$data/fake-wine.manifest")"
wine_manifest_hash="$(sha256sum "$data/fake-wine.manifest" | awk '{print $1}')"

mkdir -p "$old_stock/data/training" "$old_stock/data/knw"
printf 'old-executable' >"$old_stock/LFS.exe"
printf 'old-shared-stock' >"$old_stock/shared.stock"
printf 'obsolete-stock' >"$old_stock/obsolete.stock"
printf 'old-official-training' >"$old_stock/data/training/old-official.lsn"
printf 'old-training-seed' >"$old_stock/data/training/shared.lsn"
printf 'old-ai-knowledge' >"$old_stock/data/knw/shared.knw"
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs "$old_stock" "$data/old-stock.manifest" >/dev/null
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs-seed "$old_stock" "$data/old-seed.manifest" >/dev/null
old_manifest_size="$(stat -c %s "$data/old-stock.manifest")"
old_manifest_hash="$(sha256sum "$data/old-stock.manifest" | awk '{print $1}')"
old_manifest_entries="$(awk -F '\t' '$1 == "f" || $1 == "l" { n++ } END { print n + 0 }' "$data/old-stock.manifest")"
old_seed_size="$(stat -c %s "$data/old-seed.manifest")"
old_seed_hash="$(sha256sum "$data/old-seed.manifest" | awk '{print $1}')"
old_seed_entries="$(awk -F '\t' '$1 == "f" || $1 == "l" { n++ } END { print n + 0 }' "$data/old-seed.manifest")"
old_exe_hash="$(sha256sum "$old_stock/LFS.exe" | awk '{print $1}')"

mkdir -p "$new_stock/data/skins_dds" "$new_stock/data/wld" "$new_stock/data/veh" \
  "$new_stock/data/training" "$new_stock/data/knw" "$new_stock/data/misc" \
  "$new_stock/data/versions" "$TMP_ROOT/nested-training" "$TMP_ROOT/nested-knowledge"
printf 'new-executable' >"$new_stock/LFS.exe"
printf 'new-shared-stock' >"$new_stock/shared.stock"
printf 'new-stock-file' >"$new_stock/new.stock"
printf 'helmet' >"$new_stock/data/skins_dds/HEL_DEFAULT.dds"
printf 'track' >"$new_stock/data/wld/BLACKWOOD.wld"
printf 'vehicle' >"$new_stock/data/veh/XFG.vob"
printf 'new-official-training' >"$new_stock/data/training/new-official.lsn"
printf 'new-training-seed' >"$new_stock/data/training/shared.lsn"
printf 'new-official-knowledge' >"$new_stock/data/knw/new-official.knw"
printf 'new-ai-knowledge' >"$new_stock/data/knw/shared.knw"
printf 'new-default-profile' >"$new_stock/data/misc/default.ply"
: >"$new_stock/data/versions/8C20.txt"
cp "$new_stock/data/training/"* "$TMP_ROOT/nested-training/"
cp "$new_stock/data/knw/"* "$TMP_ROOT/nested-knowledge/"
(
  cd "$TMP_ROOT/nested-training"
  7z a -t7z "$nested_root/inst_tmp/training_1.7z" . >/dev/null
)
(
  cd "$TMP_ROOT/nested-knowledge"
  7z a -t7z "$nested_root/inst_tmp/knw_1.7z" . >/dev/null
)
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs "$new_stock" "$data/new-stock.manifest" >/dev/null
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs-seed "$new_stock" "$data/new-seed.manifest" >/dev/null
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs "$nested_root" "$data/nested.manifest" >/dev/null
new_manifest_size="$(stat -c %s "$data/new-stock.manifest")"
new_manifest_hash="$(sha256sum "$data/new-stock.manifest" | awk '{print $1}')"
new_manifest_entries="$(awk -F '\t' '$1 == "f" || $1 == "l" { n++ } END { print n + 0 }' "$data/new-stock.manifest")"
new_seed_size="$(stat -c %s "$data/new-seed.manifest")"
new_seed_hash="$(sha256sum "$data/new-seed.manifest" | awk '{print $1}')"
new_seed_entries="$(awk -F '\t' '$1 == "f" || $1 == "l" { n++ } END { print n + 0 }' "$data/new-seed.manifest")"
nested_manifest_size="$(stat -c %s "$data/nested.manifest")"
nested_manifest_hash="$(sha256sum "$data/nested.manifest" | awk '{print $1}')"
new_exe_hash="$(sha256sum "$new_stock/LFS.exe" | awk '{print $1}')"
helmet_hash="$(sha256sum "$new_stock/data/skins_dds/HEL_DEFAULT.dds" | awk '{print $1}')"
track_hash="$(sha256sum "$new_stock/data/wld/BLACKWOOD.wld" | awk '{print $1}')"
vehicle_hash="$(sha256sum "$new_stock/data/veh/XFG.vob" | awk '{print $1}')"

cp -a "$new_stock/." "$outer_stock/"
rm -f "$outer_stock/data/training/"* "$outer_stock/data/knw/"*
cp -a "$nested_root/inst_tmp" "$outer_stock/inst_tmp"
upstream_installer="$TMP_ROOT/upstream/fake-lfs.exe"
cached_installer="$cache/fake-lfs.exe"
(
  cd "$outer_stock"
  7z a -t7z "$upstream_installer" . >/dev/null
)
installer_size="$(stat -c %s "$upstream_installer")"
installer_hash="$(sha256sum "$upstream_installer" | awk '{print $1}')"
cp "$upstream_installer" "$TMP_ROOT/correct-fake-lfs.exe"

mkdir -p "$TMP_ROOT/dxvk/dxvk-3.0.2/x32"
printf 'd11' >"$TMP_ROOT/dxvk/dxvk-3.0.2/x32/d3d11.dll"
printf 'dxg' >"$TMP_ROOT/dxvk/dxvk-3.0.2/x32/dxgi.dll"
d3d11_hash="$(sha256sum "$TMP_ROOT/dxvk/dxvk-3.0.2/x32/d3d11.dll" | awk '{print $1}')"
dxgi_hash="$(sha256sum "$TMP_ROOT/dxvk/dxvk-3.0.2/x32/dxgi.dll" | awk '{print $1}')"
tar -czf "$cache/fake-dxvk.tar.gz" -C "$TMP_ROOT/dxvk" dxvk-3.0.2
dxvk_size="$(stat -c %s "$cache/fake-dxvk.tar.gz")"
dxvk_hash="$(sha256sum "$cache/fake-dxvk.tar.gz" | awk '{print $1}')"

cp "$ROOT_DIR/share/lfs-linux/release.env" "$data/release.env"
cat >>"$data/release.env" <<EOF
LFS_VERSION='test-new'
LFS_CHANNEL='public-test'
LFS_PUBLIC_TEST_FAMILY='test-new'
LFS_INSTALLER_NAME='fake-lfs.exe'
LFS_INSTALLER_URL='file://$upstream_installer'
LFS_INSTALLER_SIZE='$installer_size'
LFS_INSTALLER_SHA256='$installer_hash'
LFS_EXE_SIZE='14'
LFS_EXE_SHA256='$new_exe_hash'
LFS_STOCK_MANIFEST_NAME='new-stock.manifest'
LFS_STOCK_MANIFEST_SIZE='$new_manifest_size'
LFS_STOCK_MANIFEST_SHA256='$new_manifest_hash'
LFS_STOCK_MANIFEST_ENTRIES='$new_manifest_entries'
LFS_STOCK_SEED_MANIFEST_NAME='new-seed.manifest'
LFS_STOCK_SEED_MANIFEST_SIZE='$new_seed_size'
LFS_STOCK_SEED_MANIFEST_SHA256='$new_seed_hash'
LFS_STOCK_SEED_MANIFEST_ENTRIES='$new_seed_entries'
LFS_TREE_MIN_FILE_COUNT='7'
LFS_TREE_MIN_BYTES='1'
LFS_REQUIRED_HELMET_PATH='data/skins_dds/HEL_DEFAULT.dds'
LFS_REQUIRED_HELMET_SIZE='6'
LFS_REQUIRED_HELMET_SHA256='$helmet_hash'
LFS_REQUIRED_TRACK_PATH='data/wld/BLACKWOOD.wld'
LFS_REQUIRED_TRACK_SIZE='5'
LFS_REQUIRED_TRACK_SHA256='$track_hash'
LFS_REQUIRED_VEHICLE_PATH='data/veh/XFG.vob'
LFS_REQUIRED_VEHICLE_SIZE='7'
LFS_REQUIRED_VEHICLE_SHA256='$vehicle_hash'
LFS_NESTED_ARCHIVE_COUNT='2'
LFS_NESTED_DDS_ARCHIVE_COUNT='0'
LFS_NESTED_WLD_ARCHIVE_COUNT='0'
LFS_NESTED_MANIFEST_NAME='nested.manifest'
LFS_NESTED_MANIFEST_SIZE='$nested_manifest_size'
LFS_NESTED_MANIFEST_SHA256='$nested_manifest_hash'
LFS_NESTED_MANIFEST_ENTRIES='2'
LFS_UPGRADE_FROM_VERSION='test-old'
LFS_UPGRADE_FROM_SHA256S='$old_exe_hash'
LFS_UPGRADE_MANIFEST_NAME='old-stock.manifest'
LFS_UPGRADE_MANIFEST_SIZE='$old_manifest_size'
LFS_UPGRADE_MANIFEST_SHA256='$old_manifest_hash'
LFS_UPGRADE_MANIFEST_ENTRIES='$old_manifest_entries'
LFS_UPGRADE_SEED_MANIFEST_NAME='old-seed.manifest'
LFS_UPGRADE_SEED_MANIFEST_SIZE='$old_seed_size'
LFS_UPGRADE_SEED_MANIFEST_SHA256='$old_seed_hash'
LFS_UPGRADE_SEED_MANIFEST_ENTRIES='$old_seed_entries'
DXVK_ARCHIVE_NAME='fake-dxvk.tar.gz'
DXVK_ARCHIVE_URL='file://$cache/fake-dxvk.tar.gz'
DXVK_ARCHIVE_SIZE='$dxvk_size'
DXVK_ARCHIVE_SHA256='$dxvk_hash'
DXVK_D3D11_X32_SIZE='3'
DXVK_D3D11_X32_SHA256='$d3d11_hash'
DXVK_DXGI_X32_SIZE='3'
DXVK_DXGI_X32_SHA256='$dxgi_hash'
WINE_RUNTIME_MANIFEST_NAME='fake-wine.manifest'
WINE_RUNTIME_MANIFEST_SIZE='$wine_manifest_size'
WINE_RUNTIME_MANIFEST_SHA256='$wine_manifest_hash'
WINE_RUNTIME_MANIFEST_ENTRIES='2'
EOF

cp -a "$old_stock" "$game"
mkdir -p "$game/data/misc" "$game/data/setups" "$game/data/mpr" "$game/data/shots" \
  "$game/data/training" "$game/data/skins_dds" "$cache/dxvk-shaders"
printf 'player-config' >"$game/cfg.txt"
printf 'player-target-collision' >"$game/new.stock"
collision_hash="$(sha256sum "$game/new.stock" | awk '{print $1}')"
printf 'player-interface' >"$game/interface_cfg.txt"
printf 'player-profile' >"$game/data/misc/default.ply"
printf 'player-setup' >"$game/data/setups/player.set"
printf 'player-replay' >"$game/data/mpr/player.mpr"
printf 'player-shot' >"$game/data/shots/player.png"
printf 'player-training' >"$game/data/training/custom.lsn"
printf 'player-modified-training' >"$game/data/training/shared.lsn"
printf 'player-ai-cache' >"$game/data/knw/shared.knw"
printf 'downloaded-skin' >"$game/data/skins_dds/PLAYER.dds"
printf 'shader-cache' >"$cache/dxvk-shaders/cache.bin"
printf 'old-d3d9' >"$state/prefix/drive_c/windows/syswow64/d3d9.dll"
printf '#arch=win64\n' >"$state/prefix/system.reg"
printf '%s\n' 'lfs-linux managed state; unknown files are preserved on removal' >"$state/.managed-by-lfs-linux"

player_paths=(
  cfg.txt
  interface_cfg.txt
  data/misc/default.ply
  data/setups/player.set
  data/mpr/player.mpr
  data/shots/player.png
  data/training/custom.lsn
  data/training/shared.lsn
  data/knw/shared.knw
  data/skins_dds/PLAYER.dds
)
player_hashes="$TMP_ROOT/player-before.sha256"
(
  cd "$game"
  sha256sum "${player_paths[@]}"
) >"$player_hashes"
cache_hash="$(sha256sum "$cache/dxvk-shaders/cache.bin" | awk '{print $1}')"

run_lfs() {
  LFS_LINUX_DATA_DIR="$data" \
  LFS_LINUX_LIBEXEC_DIR="$ROOT_DIR/libexec" \
  LFS_LINUX_STATE_DIR="$state" \
  LFS_LINUX_CACHE_DIR="$cache" \
  LFS_LINUX_LOG_DIR="$logs" \
  LFS_LINUX_WINE="$fake_wine" \
    "$ROOT_DIR/bin/lfs-linux" "$@"
}

cp -a "$outer_stock" "$TMP_ROOT/tampered-outer"
printf 'tamper' >>"$TMP_ROOT/tampered-outer/inst_tmp/training_1.7z"
(
  cd "$TMP_ROOT/tampered-outer"
  7z a -t7z "$TMP_ROOT/tampered-lfs.exe" . >/dev/null
)
tampered_size="$(stat -c %s "$TMP_ROOT/tampered-lfs.exe")"
tampered_hash="$(sha256sum "$TMP_ROOT/tampered-lfs.exe" | awk '{print $1}')"
cp "$TMP_ROOT/tampered-lfs.exe" "$upstream_installer"
rm -f "$cached_installer" "$cached_installer.part"
cp "$TMP_ROOT/tampered-lfs.exe" "$cached_installer.part"
sed -i \
  -e "s|LFS_INSTALLER_SIZE='$installer_size'|LFS_INSTALLER_SIZE='$tampered_size'|" \
  -e "s|LFS_INSTALLER_SHA256='$installer_hash'|LFS_INSTALLER_SHA256='$tampered_hash'|" \
  "$data/release.env"
cp -a "$game" "$TMP_ROOT/before-rejected-nested"
set +e
run_lfs install >"$TMP_ROOT/rejected-nested.out" 2>&1
nested_status=$?
set -e
[[ "$nested_status" -ne 0 ]]
grep -Fq 'Recovered completed verified official LFS test-new installer download' "$TMP_ROOT/rejected-nested.out"
grep -Fq 'official LFS nested archive payload drift' "$TMP_ROOT/rejected-nested.out"
diff -qr "$TMP_ROOT/before-rejected-nested" "$game" >/dev/null
if compgen -G "$state/.lfs-unpack.*" >/dev/null; then
  printf 'failed nested extraction left a staging tree\n' >&2
  exit 1
fi
cp "$TMP_ROOT/correct-fake-lfs.exe" "$upstream_installer"
rm -f "$cached_installer"
head -c 137 "$upstream_installer" >"$cached_installer.part"
sed -i \
  -e "s|LFS_INSTALLER_SIZE='$tampered_size'|LFS_INSTALLER_SIZE='$installer_size'|" \
  -e "s|LFS_INSTALLER_SHA256='$tampered_hash'|LFS_INSTALLER_SHA256='$installer_hash'|" \
  "$data/release.env"

printf 'drifted-predecessor-stock' >"$game/shared.stock"
cp -a "$game" "$TMP_ROOT/before-rejected-predecessor"
set +e
run_lfs install >"$TMP_ROOT/rejected-predecessor.out" 2>&1
predecessor_status=$?
set -e
[[ "$predecessor_status" -ne 0 ]]
grep -Fq 'predecessor executable found but its stock payload drifted' "$TMP_ROOT/rejected-predecessor.out"
diff -qr "$TMP_ROOT/before-rejected-predecessor" "$game" >/dev/null
cp "$old_stock/shared.stock" "$game/shared.stock"

run_lfs install >"$TMP_ROOT/upgrade.out"
grep -Fq 'Downloading official LFS test-new installer (safe to resume after interruption)' "$TMP_ROOT/upgrade.out"
cmp "$upstream_installer" "$cached_installer"
[[ ! -e "$cached_installer.part" ]]
grep -Fq 'complete immutable payload of the approved older LFS build' "$TMP_ROOT/upgrade.out"
grep -Fq 'player file(s) that collide with new stock paths' "$TMP_ROOT/upgrade.out"
collision_backup="$state/migration-conflicts/from-test-old-to-test-new/new.stock.$collision_hash.pre-upgrade"
[[ "$(sha256sum "$collision_backup" | awk '{print $1}')" == "$collision_hash" ]]
[[ "$(sha256sum "$game/LFS.exe" | awk '{print $1}')" == "$new_exe_hash" ]]
[[ ! -e "$game/obsolete.stock" ]]
[[ ! -e "$game/data/training/old-official.lsn" ]]
grep -Fqx 'new-official-training' "$game/data/training/new-official.lsn"
grep -Fqx 'new-official-knowledge' "$game/data/knw/new-official.knw"
grep -Fqx 'new-shared-stock' "$game/shared.stock"
grep -Fqx 'new-stock-file' "$game/new.stock"
(
  cd "$game"
  sha256sum --check --quiet "$player_hashes"
)
[[ "$(sha256sum "$cache/dxvk-shaders/cache.bin" | awk '{print $1}')" == "$cache_hash" ]]
[[ ! -e "$state/prefix/drive_c/windows/syswow64/d3d9.dll" ]]
[[ "$(sha256sum "$state/prefix/drive_c/windows/syswow64/d3d11.dll" | awk '{print $1}')" == "$d3d11_hash" ]]
[[ "$(sha256sum "$state/prefix/drive_c/windows/syswow64/dxgi.dll" | awk '{print $1}')" == "$dxgi_hash" ]]
run_lfs doctor >"$TMP_ROOT/doctor.out"
grep -Fq 'Doctor summary: 0 failure(s)' "$TMP_ROOT/doctor.out"

rm -f "$cached_installer"
sed -i "s/LFS_VERSION='test-new'/LFS_VERSION='test-old'/" "$state/install.env"
run_lfs install >"$TMP_ROOT/self-updated-target.out"
grep -Fq 'Verified complete stock LFS installation; preserving game-owned data' "$TMP_ROOT/self-updated-target.out"
grep -Fqx "LFS_VERSION='test-new'" "$state/install.env"
[[ ! -e "$cached_installer" ]]
(
  cd "$game"
  sha256sum --check --quiet "$player_hashes"
)

rm "$game/new.stock"
run_lfs install >"$TMP_ROOT/repair.out"
grep -Fq 'repairing it from the verified official archive' "$TMP_ROOT/repair.out"
grep -Fqx 'new-stock-file' "$game/new.stock"
(
  cd "$game"
  sha256sum --check --quiet "$player_hashes"
)

rm "$game/LFS.exe"
run_lfs install >"$TMP_ROOT/executable-repair.out"
[[ "$(sha256sum "$game/LFS.exe" | awk '{print $1}')" == "$new_exe_hash" ]]
(
  cd "$game"
  sha256sum --check --quiet "$player_hashes"
)

cp -a "$game" "$state/.lfs-game-backup"
rm "$game/new.stock"
run_lfs install >"$TMP_ROOT/recovery-both.out"
grep -Fq 'Restored previous game tree after an interrupted upgrade' "$TMP_ROOT/recovery-both.out"
grep -Fqx 'new-stock-file' "$game/new.stock"
[[ ! -e "$state/.lfs-game-backup" ]]

cp -a "$game" "$state/.lfs-game-backup"
run_lfs install >"$TMP_ROOT/recovery-complete.out"
grep -Fq 'Removed completed game-tree swap backup' "$TMP_ROOT/recovery-complete.out"
[[ ! -e "$state/.lfs-game-backup" ]]

mv "$game" "$state/.lfs-game-backup"
run_lfs install >"$TMP_ROOT/recovery.out"
grep -Fq 'Recovered player data after an interrupted game-tree swap' "$TMP_ROOT/recovery.out"
[[ -f "$game/LFS.exe" && ! -e "$state/.lfs-game-backup" ]]

cp -a "$game" "$TMP_ROOT/before-trusted-game-update"
cp "$state/install.env" "$TMP_ROOT/before-trusted-game-update.env"
original_display="${DISPLAY:-}"
export DISPLAY="${DISPLAY:-:test}" LFS_TEST_SELF_UPDATE_VERSION='9Z1' LFS_TEST_EXIT_STATUS='7'
set +e
run_lfs launch >"$TMP_ROOT/trusted-game-update.out" 2>&1
trusted_update_status=$?
set -e
unset LFS_TEST_SELF_UPDATE_VERSION LFS_TEST_EXIT_STATUS
[[ "$trusted_update_status" -eq 7 ]]
grep -Fq 'Recorded LFS 0.9Z1 in-game update as the verified local launch baseline' "$TMP_ROOT/trusted-game-update.out"
[[ -f "$state/game-update.manifest" ]]
grep -Fqx "LFS_BASELINE_KIND='game-update'" "$state/install.env"
grep -Fqx "LFS_VERSION='0.9Z1'" "$state/install.env"
printf 'post-update-replay' >"$game/data/mpr/post-update.mpr"
run_lfs ready
run_lfs launch >"$TMP_ROOT/next-day-launch.out"
grep -Fq 'Starting verified LFS 0.9Z1' "$TMP_ROOT/next-day-launch.out"
export LFS_TEST_SELF_UPDATE_VERSION='9Z2'
run_lfs launch >"$TMP_ROOT/second-trusted-game-update.out"
unset LFS_TEST_SELF_UPDATE_VERSION
grep -Fq 'Recorded LFS 0.9Z2 in-game update as the verified local launch baseline' "$TMP_ROOT/second-trusted-game-update.out"
grep -Fqx "LFS_VERSION='0.9Z2'" "$state/install.env"
run_lfs ready
run_lfs launch >"$TMP_ROOT/second-next-day-launch.out"
grep -Fq 'Starting verified LFS 0.9Z2' "$TMP_ROOT/second-next-day-launch.out"
if [[ -n "$original_display" ]]; then export DISPLAY="$original_display"; else unset DISPLAY; fi
run_lfs doctor >"$TMP_ROOT/game-update-doctor.out"
grep -Fq 'Doctor summary: 0 failure(s)' "$TMP_ROOT/game-update-doctor.out"
rm -f "$cached_installer"
run_lfs install >"$TMP_ROOT/game-update-install.out"
grep -Fq 'Verified locally recorded LFS 0.9Z2 in-game update' "$TMP_ROOT/game-update-install.out"
[[ ! -e "$cached_installer" ]]
grep -Fqx 'game-owned-update' "$game/game-update.stock"
printf 'out-of-session-tamper' >"$game/game-update.stock"
set +e
run_lfs launch >"$TMP_ROOT/rejected-out-of-session-drift.out" 2>&1
out_of_session_status=$?
set -e
[[ "$out_of_session_status" -ne 0 ]]
grep -Fq 'recorded in-game update payload drift' "$TMP_ROOT/rejected-out-of-session-drift.out"
printf 'game-owned-update' >"$game/game-update.stock"
printf 'out-of-session-addition' >"$game/unrecorded.stock"
set +e
run_lfs launch >"$TMP_ROOT/rejected-out-of-session-addition.out" 2>&1
out_of_session_addition_status=$?
set -e
[[ "$out_of_session_addition_status" -ne 0 ]]
grep -Fq 'recorded in-game update inventory drift' "$TMP_ROOT/rejected-out-of-session-addition.out"
rm -rf "$game"
mkdir -p "$game"
cp -a "$TMP_ROOT/before-trusted-game-update/." "$game/"
cp "$TMP_ROOT/before-trusted-game-update.env" "$state/install.env"
rm -f "$state/game-update.manifest"

printf 'unknown-self-update' >"$game/LFS.exe"
cp -a "$game" "$TMP_ROOT/before-rejected-update"
set +e
run_lfs install >"$TMP_ROOT/rejected-update.out" 2>&1
rejected_status=$?
set -e
[[ "$rejected_status" -ne 0 ]]
grep -Fq 'unrecognized LFS update detected' "$TMP_ROOT/rejected-update.out"
grep -Fq 'no files changed' "$TMP_ROOT/rejected-update.out"
diff -qr "$TMP_ROOT/before-rejected-update" "$game" >/dev/null

printf '[PASS] resumable input, atomic upgrade, trusted in-game update relaunch, preservation, repair, recovery, and drift guards pass\n'
