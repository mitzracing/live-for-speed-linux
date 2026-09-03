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
fake_bin="$TMP_ROOT/fake-bin"
mkdir -p "$data" "$cache" "$logs" "$old_stock" "$new_stock" "$outer_stock" \
  "$nested_root/inst_tmp" "$TMP_ROOT/upstream" "$fake_wine_root/usr/bin" "$fake_wine_root/usr/lib/wine" \
  "$state/prefix/drive_c/windows/syswow64" "$fake_bin"

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
    if [[ "${LFS_TEST_WINESERVER_HANG:-0}" == '1' && -f "${1:-}" ]]; then
      (
        exec -a wine-helper sleep 30
      ) &
      printf '%s\n' "$!" >"$WINEPREFIX/lingering-helper.pid"
    fi
    if [[ -n "${LFS_TEST_SELF_UPDATE_VERSION:-}" && -f "${1:-}" ]]; then
      game_root="$(dirname -- "$1")"
      printf 'self-updated-%s' "$LFS_TEST_SELF_UPDATE_VERSION" >"$game_root/LFS.exe"
      printf 'game-owned-update' >"$game_root/game-update.stock"
      mkdir -p "$game_root/data/versions"
      : >"$game_root/data/versions/$LFS_TEST_SELF_UPDATE_VERSION.txt"
      if [[ -n "${LFS_TEST_RESTART_SECONDS:-}" ]]; then
        restart-delay "${LFS_TEST_RESTART_DELAY_SECONDS:-0}" "$LFS_TEST_RESTART_SECONDS" &
        printf '%s\n' "$!" >"$WINEPREFIX/restarted-game.pid"
      fi
      exit_status="${LFS_TEST_EXIT_STATUS:-0}"
    fi
    if [[ -n "${LFS_TEST_LAUNCH_HOLD_FILE:-}" && -f "${1:-}" ]]; then
      : >"$LFS_TEST_LAUNCH_HOLD_FILE"
      sleep "${LFS_TEST_LAUNCH_HOLD_SECONDS:-2}"
    fi
    ;;
esac
exit "$exit_status"
EOF
cat >"$fake_wine_root/usr/bin/wineserver" <<'EOF'
#!/usr/bin/env bash
pid_file="$WINEPREFIX/restarted-game.pid"
helper_pid_file="$WINEPREFIX/lingering-helper.pid"
case "${1:-}" in
  --wait)
    [[ -z "${LFS_TEST_WINESERVER_ERROR_STATUS:-}" ]] || exit "$LFS_TEST_WINESERVER_ERROR_STATUS"
    while [[ "${LFS_TEST_WINESERVER_HANG:-0}" == '1' ]]; do sleep 1; done
    if [[ -f "$pid_file" ]]; then
      read -r pid <"$pid_file"
      while kill -0 "$pid" 2>/dev/null; do sleep 0.05; done
      rm -f "$pid_file"
    fi
    ;;
  -k)
    [[ -z "${LFS_TEST_CAPTURE_KILL:-}" ]] || : >"$LFS_TEST_CAPTURE_KILL"
    if [[ -f "$pid_file" ]]; then
      read -r pid <"$pid_file"
      kill "$pid" 2>/dev/null || true
      rm -f "$pid_file"
    fi
    if [[ -f "$helper_pid_file" ]]; then
      read -r helper_pid <"$helper_pid_file"
      kill "$helper_pid" 2>/dev/null || true
      rm -f "$helper_pid_file"
    fi
    ;;
esac
EOF
cat >"$fake_bin/restart-delay" <<'EOF'
#!/usr/bin/env bash
sleep "$1"
exec -a LFS.exe sleep "$2"
EOF
cat >"$fake_bin/timeout" <<'EOF'
#!/usr/bin/env bash
args=("$@")
if [[ "${*: -1}" == '--wait' ]]; then
  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
      60) args[$i]='1' ;;
      5) args[$i]='2' ;;
    esac
  done
fi
exec /usr/bin/timeout "${args[@]}"
EOF
cat >"$fake_bin/gpgv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '[GNUPG:] VALIDSIG AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 2026-01-01 0 0 0 0 0 0 0 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
EOF
chmod +x "$fake_wine" "$fake_wine_root/usr/bin/wineserver" "$fake_bin/restart-delay" \
  "$fake_bin/timeout" "$fake_bin/gpgv"
"$ROOT_DIR/scripts/generate-payload-manifest.py" wine "$fake_wine_root" "$data/fake-wine.manifest" >/dev/null
wine_manifest_size="$(stat -c %s "$data/fake-wine.manifest")"
wine_manifest_hash="$(sha256sum "$data/fake-wine.manifest" | awk '{print $1}')"
printf 'fake-signing-key' >"$data/fake-signing-key.gpg"
fake_signing_key_size="$(stat -c %s "$data/fake-signing-key.gpg")"
fake_signing_key_hash="$(sha256sum "$data/fake-signing-key.gpg" | awk '{print $1}')"
fake_wine_package="$TMP_ROOT/upstream/fake-wine.pkg.tar.gz"
tar -czf "$fake_wine_package" -C "$fake_wine_root" usr
fake_wine_package_size="$(stat -c %s "$fake_wine_package")"
fake_wine_package_hash="$(sha256sum "$fake_wine_package" | awk '{print $1}')"
printf 'fake-detached-signature' >"$TMP_ROOT/upstream/fake-wine.pkg.tar.gz.sig"
fake_wine_signature_size="$(stat -c %s "$TMP_ROOT/upstream/fake-wine.pkg.tar.gz.sig")"
fake_wine_signature_hash="$(sha256sum "$TMP_ROOT/upstream/fake-wine.pkg.tar.gz.sig" | awk '{print $1}')"

mkdir -p "$old_stock/data/training" "$old_stock/data/knw" "$old_stock/data/versions"
printf 'old-executable' >"$old_stock/LFS.exe"
printf 'old-shared-stock' >"$old_stock/shared.stock"
printf 'obsolete-stock' >"$old_stock/obsolete.stock"
printf 'second-obsolete-stock' >"$old_stock/zz-obsolete.stock"
printf 'old-official-training' >"$old_stock/data/training/old-official.lsn"
printf 'old-training-seed' >"$old_stock/data/training/shared.lsn"
printf 'old-ai-knowledge' >"$old_stock/data/knw/shared.knw"
: >"$old_stock/data/versions/8C23.txt"
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs "$old_stock" "$data/old-stock.manifest" >/dev/null
"$ROOT_DIR/scripts/generate-payload-manifest.py" lfs-seed "$old_stock" "$data/old-seed.manifest" >/dev/null
old_manifest_size="$(stat -c %s "$data/old-stock.manifest")"
old_manifest_hash="$(sha256sum "$data/old-stock.manifest" | awk '{print $1}')"
old_manifest_entries="$(awk -F '\t' '$1 == "f" || $1 == "l" { n++ } END { print n + 0 }' "$data/old-stock.manifest")"
old_seed_size="$(stat -c %s "$data/old-seed.manifest")"
old_seed_hash="$(sha256sum "$data/old-seed.manifest" | awk '{print $1}')"
old_seed_entries="$(awk -F '\t' '$1 == "f" || $1 == "l" { n++ } END { print n + 0 }' "$data/old-seed.manifest")"
old_exe_hash="$(sha256sum "$old_stock/LFS.exe" | awk '{print $1}')"
obsolete_hash="$(sha256sum "$old_stock/obsolete.stock" | awk '{print $1}')"
second_obsolete_hash="$(sha256sum "$old_stock/zz-obsolete.stock" | awk '{print $1}')"

mkdir -p "$new_stock/data/dds" "$new_stock/data/skins_dds" "$new_stock/data/wld" \
  "$new_stock/data/veh" "$new_stock/data/training" "$new_stock/data/knw" \
  "$new_stock/data/misc" "$new_stock/data/versions" "$TMP_ROOT/nested-dds-01" \
  "$TMP_ROOT/nested-dds-02" "$TMP_ROOT/nested-training" "$TMP_ROOT/nested-knowledge"
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
printf 'second-archive-wins' >"$new_stock/data/dds/ORDERED.dds"
: >"$new_stock/data/versions/8C20.txt"
: >"$new_stock/data/versions/8C23.txt"
printf 'first-archive-bytes' >"$TMP_ROOT/nested-dds-01/ORDERED.dds"
printf 'second-archive-wins' >"$TMP_ROOT/nested-dds-02/ORDERED.dds"
cp "$new_stock/data/training/"* "$TMP_ROOT/nested-training/"
cp "$new_stock/data/knw/"* "$TMP_ROOT/nested-knowledge/"
(
  cd "$TMP_ROOT/nested-dds-01"
  7z a -t7z "$nested_root/inst_tmp/dds_01.7z" . >/dev/null
)
(
  cd "$TMP_ROOT/nested-dds-02"
  7z a -t7z "$nested_root/inst_tmp/dds_02.7z" . >/dev/null
)
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
rm -f "$outer_stock/data/dds/ORDERED.dds" "$outer_stock/data/training/"* \
  "$outer_stock/data/knw/"*
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
LFS_NESTED_ARCHIVE_COUNT='4'
LFS_NESTED_DDS_ARCHIVE_COUNT='2'
LFS_NESTED_WLD_ARCHIVE_COUNT='0'
LFS_NESTED_MANIFEST_NAME='nested.manifest'
LFS_NESTED_MANIFEST_SIZE='$nested_manifest_size'
LFS_NESTED_MANIFEST_SHA256='$nested_manifest_hash'
LFS_NESTED_MANIFEST_ENTRIES='4'
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
LFS_LOCAL_UPDATE_UPGRADE_FROM_VERSION='test-local-old'
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
WINE_SIGNING_KEY_NAME='fake-signing-key.gpg'
WINE_SIGNING_KEY_SIZE='$fake_signing_key_size'
WINE_SIGNING_KEY_SHA256='$fake_signing_key_hash'
WINE_SIGNING_KEY_FINGERPRINT='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
WINE_PACKAGE_NAME='fake-wine.pkg.tar.gz'
WINE_PACKAGE_URL='file://$fake_wine_package'
WINE_PACKAGE_SIZE='$fake_wine_package_size'
WINE_PACKAGE_SHA256='$fake_wine_package_hash'
WINE_PACKAGE_SIGNATURE_NAME='fake-wine.pkg.tar.gz.sig'
WINE_PACKAGE_SIGNATURE_URL='file://$TMP_ROOT/upstream/fake-wine.pkg.tar.gz.sig'
WINE_PACKAGE_SIGNATURE_SIZE='$fake_wine_signature_size'
WINE_PACKAGE_SIGNATURE_SHA256='$fake_wine_signature_hash'
EOF

cp -a "$old_stock" "$game"
mkdir -p "$game/data/misc" "$game/data/setups" "$game/data/mpr" "$game/data/shots" \
  "$game/data/training" "$game/data/skins" "$game/data/skins_dds" "$game/data/skins_x" \
  "$game/data/skins_y" "$game/data/grids" "$game/cache/events" "$game/mods/vehicles" \
  "$cache/dxvk-shaders"
printf 'player-config' >"$game/cfg.txt"
printf 'player-target-collision' >"$game/new.stock"
collision_hash="$(sha256sum "$game/new.stock" | awk '{print $1}')"
printf 'player-interface' >"$game/interface_cfg.txt"
printf 'player-card-config' >"$game/card_cfg.txt"
printf 'runtime-debug-log' >"$game/deb.log"
printf 'older-runtime-debug-log' >"$game/deb_old.log"
printf 'player-account-state' >"$game/guest.txt"
printf 'event-cache' >"$game/cache/events/player.png"
printf 'downloaded-mod' >"$game/mods/vehicles/player.mod"
printf 'player-grid' >"$game/data/grids/player.rac"
printf 'player-skin' >"$game/data/skins/player.jpg"
printf 'downloaded-skin-x' >"$game/data/skins_x/player.dds"
printf 'downloaded-skin-y' >"$game/data/skins_y/player.dds"
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
  card_cfg.txt
  deb.log
  deb_old.log
  guest.txt
  cache/events/player.png
  mods/vehicles/player.mod
  data/grids/player.rac
  data/skins/player.jpg
  data/skins_x/player.dds
  data/skins_y/player.dds
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
  PATH="$fake_bin:$PATH" \
    "$ROOT_DIR/bin/lfs-linux" "$@"
}

inventory_tree_metadata() {
  python3 - "$1" "$2" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1])
rows = []
for path in [root, *sorted(root.rglob("*"), key=lambda item: os.fsencode(item.relative_to(root)))]:
    info = path.lstat()
    relative = "." if path == root else os.fsdecode(os.fsencode(path.relative_to(root)))
    if stat.S_ISREG(info.st_mode):
        kind = "file"
        value = hashlib.sha256(path.read_bytes()).hexdigest()
    elif stat.S_ISDIR(info.st_mode):
        kind = "directory"
        value = None
    elif stat.S_ISLNK(info.st_mode):
        kind = "symlink"
        value = os.readlink(path)
    else:
        raise SystemExit(f"unsupported player entry: {path}")
    xattrs = {
        os.fsdecode(name): os.getxattr(path, name, follow_symlinks=False).hex()
        for name in sorted(os.listxattr(path, follow_symlinks=False), key=os.fsencode)
    }
    rows.append({
        "path": relative,
        "type": kind,
        "value": value,
        "uid": info.st_uid,
        "gid": info.st_gid,
        "mode": stat.S_IMODE(info.st_mode),
        "mtime_ns": info.st_mtime_ns,
        "size": info.st_size,
        "xattrs": xattrs,
    })
Path(sys.argv[2]).write_text("\n".join(json.dumps(row, sort_keys=True) for row in rows) + "\n")
PY
}

write_runtime_game_manifest() {
  local root="$1" output="$2" generated path relative line
  generated="$(mktemp "$TMP_ROOT/runtime-manifest.XXXXXX")"
  "$ROOT_DIR/scripts/generate-payload-manifest.py" lfs "$root" "$generated" >/dev/null
  {
    head -n 2 "$generated"
    while IFS= read -r -d '' path; do
      relative="${path#"$root/"}"
      line="$(awk -F '\t' -v wanted="$relative" \
        '($1 == "f" || $1 == "l") && $4 == wanted { print; exit }' "$generated")"
      [[ -z "$line" ]] || printf '%s\n' "$line"
    done < <(find "$root" \( -type f -o -type l \) -print0 | sort -z)
  } >"$output"
  rm -f "$generated"
}

write_local_predecessor_marker() {
  local local_manifest_name="game-update-$old_local_manifest_hash.manifest"
  cp "$data/old-local.manifest" "$state/$local_manifest_name"
  chmod 0600 "$state/$local_manifest_name"
  cat >"$state/install.env" <<EOF
LFS_BASELINE_KIND='game-update'
LFS_VERSION='test-local-old'
LFS_CHANNEL='public-test'
LFS_EXE_SIZE='14'
LFS_EXE_SHA256='$old_exe_hash'
LFS_STOCK_MANIFEST_NAME='$local_manifest_name'
LFS_STOCK_MANIFEST_SIZE='$old_local_manifest_size'
LFS_STOCK_MANIFEST_SHA256='$old_local_manifest_hash'
LFS_STOCK_MANIFEST_ENTRIES='$old_local_manifest_entries'
LFS_PACKAGE_VERSION='test-new'
DXVK_VERSION='3.0.2'
DXVK_D3D11_X32_SHA256='$d3d11_hash'
DXVK_DXGI_X32_SHA256='$dxgi_hash'
WINE_RUNTIME_VERSION='11.15-1'
WINE_RUNTIME_MANIFEST_SHA256='$wine_manifest_hash'
WINE_VERSION='wine-11.15'
PREFIX_ARCH='win64'
EOF
  chmod 0600 "$state/install.env"
}

rm -f "$cached_installer" "$cached_installer.part" "$cache/fake-wine.pkg.tar.gz" \
  "$cache/fake-wine.pkg.tar.gz.part" "$cache/fake-wine.pkg.tar.gz.sig" \
  "$cache/fake-wine.pkg.tar.gz.sig.part"
run_lfs verify-sources >"$TMP_ROOT/verify-sources.out"
grep -Fq 'All pinned upstream archive bytes, signatures, complete official seed files, and extracted runtime manifests are verified' \
  "$TMP_ROOT/verify-sources.out"
if compgen -G "$cache/.verify-payloads.*" >/dev/null; then
  printf 'verify-sources left an extraction staging tree\n' >&2
  exit 1
fi

printf 'must-not-escape-staging' >"$TMP_ROOT/unsafe-member"
(
  cd "$TMP_ROOT"
  7z a -t7z unsafe-lfs.exe unsafe-member >/dev/null
  7z rn unsafe-lfs.exe unsafe-member ../archive-escape >/dev/null
)
unsafe_installer="$TMP_ROOT/unsafe-lfs.exe"
unsafe_size="$(stat -c %s "$unsafe_installer")"
unsafe_hash="$(sha256sum "$unsafe_installer" | awk '{print $1}')"
cp "$unsafe_installer" "$upstream_installer"
rm -f "$cached_installer" "$cached_installer.part"
sed -i \
  -e "s|LFS_INSTALLER_SIZE='$installer_size'|LFS_INSTALLER_SIZE='$unsafe_size'|" \
  -e "s|LFS_INSTALLER_SHA256='$installer_hash'|LFS_INSTALLER_SHA256='$unsafe_hash'|" \
  "$data/release.env"
cp -a "$game" "$TMP_ROOT/before-unsafe-archive"
set +e
run_lfs install >"$TMP_ROOT/rejected-unsafe-archive.out" 2>&1
unsafe_archive_status=$?
set -e
[[ "$unsafe_archive_status" -ne 0 ]]
grep -Fq 'official LFS installer has unsafe' "$TMP_ROOT/rejected-unsafe-archive.out"
[[ ! -e "$state/archive-escape" && ! -e "$TMP_ROOT/archive-escape" ]]
diff -qr "$TMP_ROOT/before-unsafe-archive" "$game" >/dev/null
if compgen -G "$state/.lfs-unpack.*" >/dev/null; then
  printf 'unsafe archive left a staging tree\n' >&2
  exit 1
fi
cp "$TMP_ROOT/correct-fake-lfs.exe" "$upstream_installer"
sed -i \
  -e "s|LFS_INSTALLER_SIZE='$unsafe_size'|LFS_INSTALLER_SIZE='$installer_size'|" \
  -e "s|LFS_INSTALLER_SHA256='$unsafe_hash'|LFS_INSTALLER_SHA256='$installer_hash'|" \
  "$data/release.env"

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
[[ ! -e "$game/obsolete.stock" && ! -e "$game/zz-obsolete.stock" ]]
[[ ! -e "$game/data/training/old-official.lsn" ]]
grep -Fqx 'new-official-training' "$game/data/training/new-official.lsn"
grep -Fqx 'new-official-knowledge' "$game/data/knw/new-official.knw"
grep -Fqx 'second-archive-wins' "$game/data/dds/ORDERED.dds"
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

unsafe_runtime="$TMP_ROOT/unsafe-runtime"
mkdir -p "$unsafe_runtime/lfs-linux-$UID"
chmod 0777 "$unsafe_runtime/lfs-linux-$UID"
set +e
XDG_RUNTIME_DIR="$unsafe_runtime" run_lfs launch >"$TMP_ROOT/unsafe-lock-directory.out" 2>&1
unsafe_lock_directory_status=$?
set -e
[[ "$unsafe_lock_directory_status" -ne 0 ]]
grep -Fq 'launch lock directory is accessible by other users' "$TMP_ROOT/unsafe-lock-directory.out"
rm -rf "$unsafe_runtime/lfs-linux-$UID"
mkdir -m 0700 "$unsafe_runtime/lfs-linux-$UID"
lock_symlink_target="$TMP_ROOT/lock-symlink-target"
printf 'must-not-be-truncated' >"$lock_symlink_target"
ln -s "$lock_symlink_target" "$unsafe_runtime/lfs-linux-$UID/launch.lock"
set +e
XDG_RUNTIME_DIR="$unsafe_runtime" run_lfs launch >"$TMP_ROOT/unsafe-lock-symlink.out" 2>&1
unsafe_lock_symlink_status=$?
set -e
[[ "$unsafe_lock_symlink_status" -ne 0 ]]
grep -Fq 'unsafe launch lock file' "$TMP_ROOT/unsafe-lock-symlink.out"
grep -Fqx 'must-not-be-truncated' "$lock_symlink_target"

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

cp -a "$game" "$TMP_ROOT/before-invalid-recovery-tests"
cp -a "$game" "$state/.lfs-game-backup"
printf 'invalid-backup-protected-bytes' >"$state/.lfs-game-backup/shared.stock"
rm "$game/new.stock"
printf 'current-tree-player-data' >"$game/data/mpr/current-during-invalid-backup.mpr"
cp -a "$game" "$TMP_ROOT/before-invalid-backup-current"
cp -a "$state/.lfs-game-backup" "$TMP_ROOT/before-invalid-backup-tree"
set +e
printf 'n\n' | run_lfs setup >"$TMP_ROOT/rejected-invalid-game-backup-setup.out" 2>&1
invalid_game_backup_setup_status=$?
set -e
[[ "$invalid_game_backup_setup_status" -ne 0 ]]
grep -Fq 'interrupted game backup is not an exact trusted baseline; no files changed' \
  "$TMP_ROOT/rejected-invalid-game-backup-setup.out"
if grep -Fq 'Continue with verified setup?' "$TMP_ROOT/rejected-invalid-game-backup-setup.out"; then
  printf 'invalid game backup reached setup consent\n' >&2
  exit 1
fi
diff -qr "$TMP_ROOT/before-invalid-backup-current" "$game" >/dev/null
diff -qr "$TMP_ROOT/before-invalid-backup-tree" "$state/.lfs-game-backup" >/dev/null
set +e
run_lfs install >"$TMP_ROOT/rejected-invalid-game-backup.out" 2>&1
invalid_game_backup_status=$?
set -e
[[ "$invalid_game_backup_status" -ne 0 ]]
grep -Fq 'interrupted game backup is not an exact trusted baseline; no files changed' \
  "$TMP_ROOT/rejected-invalid-game-backup.out"
diff -qr "$TMP_ROOT/before-invalid-backup-current" "$game" >/dev/null
diff -qr "$TMP_ROOT/before-invalid-backup-tree" "$state/.lfs-game-backup" >/dev/null
rm -rf "$state/.lfs-game-backup" "$game"
cp -a "$TMP_ROOT/before-invalid-recovery-tests" "$game"

backup_symlink_target="$TMP_ROOT/game-backup-symlink-target"
mkdir "$backup_symlink_target"
printf 'backup-symlink-sentinel' >"$backup_symlink_target/sentinel"
ln -s "$backup_symlink_target" "$state/.lfs-game-backup"
set +e
run_lfs install >"$TMP_ROOT/rejected-game-backup-symlink.out" 2>&1
backup_symlink_status=$?
set -e
[[ "$backup_symlink_status" -ne 0 ]]
grep -Fq 'interrupted game backup is not a private directory; no files changed' \
  "$TMP_ROOT/rejected-game-backup-symlink.out"
[[ -L "$state/.lfs-game-backup" ]]
grep -Fqx 'backup-symlink-sentinel' "$backup_symlink_target/sentinel"
rm "$state/.lfs-game-backup"

cp -a "$game" "$state/.lfs-game-backup"
rm "$game/new.stock"
run_lfs install >"$TMP_ROOT/recovery-both.out"
grep -Fq 'Restored previous game tree after an interrupted upgrade' "$TMP_ROOT/recovery-both.out"
grep -Fqx 'new-stock-file' "$game/new.stock"
[[ ! -e "$state/.lfs-game-backup" ]]
recovery_conflict="$state/migration-conflicts/interrupted-current-game-tree"
[[ -f "$recovery_conflict/LFS.exe" && ! -e "$recovery_conflict/new.stock" ]]
rm -rf "$recovery_conflict"

cp -a "$game" "$state/.lfs-game-backup"
run_lfs install >"$TMP_ROOT/recovery-complete.out"
grep -Fq 'Removed completed game-tree swap backup' "$TMP_ROOT/recovery-complete.out"
[[ ! -e "$state/.lfs-game-backup" ]]

mv "$game" "$state/.lfs-game-backup"
run_lfs install >"$TMP_ROOT/recovery.out"
grep -Fq 'Recovered player data after an interrupted game-tree swap' "$TMP_ROOT/recovery.out"
[[ -f "$game/LFS.exe" && ! -e "$state/.lfs-game-backup" ]]

cp -a "$game" "$TMP_ROOT/before-local-catchup"
cp "$state/install.env" "$TMP_ROOT/before-local-catchup.env"
rm -rf "$game"
cp -a "$old_stock" "$game"
mkdir -p "$game/data/mpr" "$game/data/skins_dds"
printf 'local-predecessor-replay' >"$game/data/mpr/local-predecessor.mpr"
printf 'downloaded-player-dds' >"$game/data/skins_dds/PLAYER.dds"
printf 'player-modified-stock-dds' >"$game/data/skins_dds/HEL_DEFAULT.dds"
local_helmet_collision_hash="$(sha256sum "$game/data/skins_dds/HEL_DEFAULT.dds" | awk '{print $1}')"
write_runtime_game_manifest "$game" "$data/old-local.manifest"
old_local_manifest_size="$(stat -c %s "$data/old-local.manifest")"
old_local_manifest_hash="$(sha256sum "$data/old-local.manifest" | awk '{print $1}')"
old_local_manifest_entries="$(awk -F '\t' '$1 == "f" || $1 == "l" { n++ } END { print n + 0 }' "$data/old-local.manifest")"
local_manifest_name="game-update-$old_local_manifest_hash.manifest"
write_local_predecessor_marker
set +e
printf 'n\n' | run_lfs setup >"$TMP_ROOT/local-catchup-setup.out" 2>&1
local_catchup_setup_status=$?
set -e
[[ "$local_catchup_setup_status" -eq 3 ]]
grep -Fq 'Upgrade the verified local LFS test-local-old baseline to audited test-new' \
  "$TMP_ROOT/local-catchup-setup.out"
grep -Fq 'preserve complete player-owned paths and metadata' "$TMP_ROOT/local-catchup-setup.out"
if run_lfs ready >"$TMP_ROOT/local-catchup-ready.out" 2>&1; then
  printf 'known local predecessor incorrectly reported ready\n' >&2
  exit 1
fi
set +e
run_lfs launch >"$TMP_ROOT/local-catchup-launch.out" 2>&1
local_catchup_launch_status=$?
set -e
[[ "$local_catchup_launch_status" -ne 0 ]]
grep -Fq 'verified local LFS test-local-old requires audited test-new catch-up; run lfs-linux install' \
  "$TMP_ROOT/local-catchup-launch.out"
mkdir -p "$game/data/mpr/empty-player-directory"
ln -s local-predecessor.mpr "$game/data/mpr/replay-link"
chmod 0710 "$game/data/mpr" "$game/data/mpr/empty-player-directory"
chmod 0640 "$game/data/mpr/local-predecessor.mpr"
touch -d '2026-08-31 21:12:13.123456789 UTC' "$game/data/mpr" \
  "$game/data/mpr/empty-player-directory" "$game/data/mpr/local-predecessor.mpr"
python3 - "$game/data/mpr" <<'PY'
import os
import sys
try:
    os.setxattr(sys.argv[1], b"user.lfs-linux-test", b"preserve-player-xattr")
except OSError:
    pass
PY
inventory_tree_metadata "$game/data/mpr" "$TMP_ROOT/local-player.before.jsonl"
inventory_tree_metadata "$game/data/skins_dds/PLAYER.dds" "$TMP_ROOT/local-player-dds.before.jsonl"
rm -f "$cached_installer"
set +e
LFS_LINUX_TEST_FAIL_AFTER_GAME_BACKUP=1 run_lfs install >"$TMP_ROOT/local-catchup-interrupted-swap.out" 2>&1
local_catchup_interrupted_status=$?
set -e
[[ "$local_catchup_interrupted_status" -ne 0 ]]
grep -Fq 'test fault after previous game tree moved to recovery backup' \
  "$TMP_ROOT/local-catchup-interrupted-swap.out"
[[ ! -e "$game" && -d "$state/.lfs-game-backup" && -f "$state/$local_manifest_name" ]]
inventory_tree_metadata "$state/.lfs-game-backup/data/mpr" "$TMP_ROOT/local-player.in-backup.jsonl"
inventory_tree_metadata "$state/.lfs-game-backup/data/skins_dds/PLAYER.dds" \
  "$TMP_ROOT/local-player-dds.in-backup.jsonl"
cmp "$TMP_ROOT/local-player.before.jsonl" "$TMP_ROOT/local-player.in-backup.jsonl"
cmp "$TMP_ROOT/local-player-dds.before.jsonl" "$TMP_ROOT/local-player-dds.in-backup.jsonl"
run_lfs install >"$TMP_ROOT/local-catchup-install.out" 2>&1
if grep -Fq 'behavior of -n is non-portable' "$TMP_ROOT/local-catchup-install.out"; then
  printf 'local catch-up used deprecated ambiguous no-clobber semantics\n' >&2
  exit 1
fi
grep -Fq 'Recovered player data after an interrupted game-tree swap' "$TMP_ROOT/local-catchup-install.out"
grep -Fq 'Verified locally recorded LFS test-local-old as the approved catch-up predecessor' \
  "$TMP_ROOT/local-catchup-install.out"
grep -Fq 'Preserved complete player-owned paths from the verified local update' \
  "$TMP_ROOT/local-catchup-install.out"
grep -Fq 'Preserved 1 player file(s) that collide with C24 stock' \
  "$TMP_ROOT/local-catchup-install.out"
[[ "$(sha256sum "$game/LFS.exe" | awk '{print $1}')" == "$new_exe_hash" ]]
[[ "$(sha256sum "$game/data/skins_dds/HEL_DEFAULT.dds" | awk '{print $1}')" == "$helmet_hash" ]]
local_helmet_conflict="$state/migration-conflicts/from-test-local-old-to-test-new/data/skins_dds/HEL_DEFAULT.dds.$local_helmet_collision_hash.pre-upgrade"
[[ "$(sha256sum "$local_helmet_conflict" | awk '{print $1}')" == "$local_helmet_collision_hash" ]]
[[ ! -e "$game/obsolete.stock" && ! -e "$game/zz-obsolete.stock" ]]
[[ -f "$cached_installer" && ! -e "$state/$local_manifest_name" ]]
grep -Fqx "LFS_BASELINE_KIND='package'" "$state/install.env"
grep -Fqx "LFS_VERSION='test-new'" "$state/install.env"
inventory_tree_metadata "$game/data/mpr" "$TMP_ROOT/local-player.after.jsonl"
inventory_tree_metadata "$game/data/skins_dds/PLAYER.dds" "$TMP_ROOT/local-player-dds.after.jsonl"
cmp "$TMP_ROOT/local-player.before.jsonl" "$TMP_ROOT/local-player.after.jsonl"
cmp "$TMP_ROOT/local-player-dds.before.jsonl" "$TMP_ROOT/local-player-dds.after.jsonl"
[[ ! -e "$state/.lfs-game-backup" ]]

cp "$old_stock/obsolete.stock" "$game/obsolete.stock"
cp "$old_stock/zz-obsolete.stock" "$game/zz-obsolete.stock"
[[ -f "$game/data/versions/8C23.txt" ]]
cp -a "$game" "$TMP_ROOT/same-marker-candidate"
write_local_predecessor_marker
set +e
printf 'n\n' | run_lfs setup >"$TMP_ROOT/same-marker-setup.out" 2>&1
same_marker_setup_status=$?
set -e
[[ "$same_marker_setup_status" -eq 3 ]]
grep -Fq 'Adopt the exact audited test-new files already produced over the verified test-local-old baseline' \
  "$TMP_ROOT/same-marker-setup.out"
grep -Fq 'no game installer download is needed' "$TMP_ROOT/same-marker-setup.out"
inventory_tree_metadata "$game/data/mpr" "$TMP_ROOT/same-marker-player.before.jsonl"
rm -f "$cached_installer"
run_lfs install >"$TMP_ROOT/same-marker-adoption.out"
grep -Fq 'Recognized exact audited test-new overlay on the verified test-local-old baseline' \
  "$TMP_ROOT/same-marker-adoption.out"
[[ ! -e "$cached_installer" && ! -e "$game/obsolete.stock" && ! -e "$game/zz-obsolete.stock" ]]
quarantined_obsolete="$state/migration-conflicts/from-test-local-old-to-test-new/obsolete.stock.$obsolete_hash.pre-upgrade"
quarantined_second_obsolete="$state/migration-conflicts/from-test-local-old-to-test-new/zz-obsolete.stock.$second_obsolete_hash.pre-upgrade"
[[ "$(sha256sum "$quarantined_obsolete" | awk '{print $1}')" == "$obsolete_hash" ]]
[[ "$(sha256sum "$quarantined_second_obsolete" | awk '{print $1}')" == "$second_obsolete_hash" ]]
[[ "$(sha256sum "$game/LFS.exe" | awk '{print $1}')" == "$new_exe_hash" ]]
grep -Fqx "LFS_BASELINE_KIND='package'" "$state/install.env"
grep -Fqx "LFS_VERSION='test-new'" "$state/install.env"
inventory_tree_metadata "$game/data/mpr" "$TMP_ROOT/same-marker-player.after.jsonl"
inventory_tree_metadata "$game/data/skins_dds/PLAYER.dds" "$TMP_ROOT/same-marker-player-dds.after.jsonl"
cmp "$TMP_ROOT/same-marker-player.before.jsonl" "$TMP_ROOT/same-marker-player.after.jsonl"
cmp "$TMP_ROOT/local-player-dds.before.jsonl" "$TMP_ROOT/same-marker-player-dds.after.jsonl"

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
overlay_race_ready="$TMP_ROOT/overlay-quarantine-after-first-ready"
LFS_LINUX_TEST_OVERLAY_QUARANTINE_AFTER_FIRST_READY_FILE="$overlay_race_ready" \
LFS_LINUX_TEST_OVERLAY_QUARANTINE_AFTER_FIRST_DELAY_SECONDS=2 \
  run_lfs install >"$TMP_ROOT/rejected-overlay-quarantine-race.out" 2>&1 &
overlay_race_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -e "$overlay_race_ready" ]] && break
  kill -0 "$overlay_race_pid" 2>/dev/null || break
  sleep 0.05
done
[[ -e "$overlay_race_ready" ]]
printf 'replacement-created-after-first-quarantine-move' >"$game/zz-obsolete.stock"
overlay_race_hash="$(sha256sum "$game/zz-obsolete.stock" | awk '{print $1}')"
set +e
wait "$overlay_race_pid"
overlay_race_status=$?
set -e
[[ "$overlay_race_status" -ne 0 && ! -e "$cached_installer" ]]
grep -Fq 'predecessor-only protected path changed before quarantine' \
  "$TMP_ROOT/rejected-overlay-quarantine-race.out"
[[ "$(sha256sum "$game/obsolete.stock" | awk '{print $1}')" == "$obsolete_hash" ]]
[[ "$(sha256sum "$game/zz-obsolete.stock" | awk '{print $1}')" == "$overlay_race_hash" ]]
[[ ! -e "$state/.lfs-predecessor-quarantine" ]]
grep -Fqx "LFS_BASELINE_KIND='game-update'" "$state/install.env"

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
set +e
LFS_LINUX_TEST_FAIL_AFTER_OVERLAY_MARKER_BEFORE_PHASE=1 \
  run_lfs install >"$TMP_ROOT/interrupted-committed-quarantine.out" 2>&1
committed_quarantine_status=$?
set -e
[[ "$committed_quarantine_status" -ne 0 ]]
grep -Fq 'test fault after package marker commit before quarantine phase persisted' \
  "$TMP_ROOT/interrupted-committed-quarantine.out"
grep -Fqx "LFS_BASELINE_KIND='package'" "$state/install.env"
[[ ! -e "$game/obsolete.stock" && ! -e "$game/zz-obsolete.stock" ]]
[[ -f "$state/.lfs-predecessor-quarantine/obsolete.stock" ]]
[[ -f "$state/.lfs-predecessor-quarantine/zz-obsolete.stock" ]]
run_lfs install >"$TMP_ROOT/recovered-committed-quarantine.out"
grep -Fq 'Retained committed predecessor quarantine after interrupted cleanup' \
  "$TMP_ROOT/recovered-committed-quarantine.out"
recovered_quarantine="$state/migration-conflicts/recovered-predecessor-quarantine"
[[ "$(sha256sum "$recovered_quarantine/obsolete.stock" | awk '{print $1}')" == "$obsolete_hash" ]]
[[ "$(sha256sum "$recovered_quarantine/zz-obsolete.stock" | awk '{print $1}')" == "$second_obsolete_hash" ]]
[[ ! -e "$state/.lfs-predecessor-quarantine" && ! -e "$cached_installer" ]]

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
printf 'unknown-protected-entry' >"$game/unexpected.stock"
cp -a "$game" "$TMP_ROOT/before-rejected-overlay-addition"
set +e
run_lfs install >"$TMP_ROOT/rejected-overlay-addition.out" 2>&1
overlay_addition_status=$?
set -e
[[ "$overlay_addition_status" -ne 0 && ! -e "$cached_installer" ]]
grep -Fq 'recorded in-game update baseline drifted outside a trusted LFS session' \
  "$TMP_ROOT/rejected-overlay-addition.out"
diff -qr "$TMP_ROOT/before-rejected-overlay-addition" "$game" >/dev/null

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
mkdir "$game/unexpected-empty-directory"
cp -a "$game" "$TMP_ROOT/before-rejected-overlay-directory"
set +e
run_lfs install >"$TMP_ROOT/rejected-overlay-directory.out" 2>&1
overlay_directory_status=$?
set -e
[[ "$overlay_directory_status" -ne 0 && ! -e "$cached_installer" ]]
grep -Fq 'recorded in-game update baseline drifted outside a trusted LFS session' \
  "$TMP_ROOT/rejected-overlay-directory.out"
diff -qr "$TMP_ROOT/before-rejected-overlay-directory" "$game" >/dev/null

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
mkfifo "$game/data/mpr/unsupported-player-fifo"
cp -a "$game" "$TMP_ROOT/before-rejected-overlay-special"
set +e
run_lfs install >"$TMP_ROOT/rejected-overlay-special.out" 2>&1
overlay_special_status=$?
set -e
[[ "$overlay_special_status" -ne 0 && ! -e "$cached_installer" ]]
grep -Fq 'recorded in-game update baseline drifted outside a trusted LFS session' \
  "$TMP_ROOT/rejected-overlay-special.out"
[[ -p "$game/data/mpr/unsupported-player-fifo" ]]
grep -Fqx 'obsolete-stock' "$game/obsolete.stock"

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
printf 'changed-predecessor-only-entry' >"$game/obsolete.stock"
cp -a "$game" "$TMP_ROOT/before-rejected-overlay-stale-drift"
set +e
run_lfs install >"$TMP_ROOT/rejected-overlay-stale-drift.out" 2>&1
overlay_stale_status=$?
set -e
[[ "$overlay_stale_status" -ne 0 && ! -e "$cached_installer" ]]
grep -Fq 'recorded in-game update baseline drifted outside a trusted LFS session' \
  "$TMP_ROOT/rejected-overlay-stale-drift.out"
diff -qr "$TMP_ROOT/before-rejected-overlay-stale-drift" "$game" >/dev/null

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
printf 'changed-target-entry' >"$game/shared.stock"
cp -a "$game" "$TMP_ROOT/before-rejected-overlay-target-drift"
set +e
run_lfs install >"$TMP_ROOT/rejected-overlay-target-drift.out" 2>&1
overlay_target_status=$?
set -e
[[ "$overlay_target_status" -ne 0 && ! -e "$cached_installer" ]]
grep -Fq 'recorded in-game update baseline drifted outside a trusted LFS session' \
  "$TMP_ROOT/rejected-overlay-target-drift.out"
diff -qr "$TMP_ROOT/before-rejected-overlay-target-drift" "$game" >/dev/null

rm -rf "$game"
cp -a "$TMP_ROOT/same-marker-candidate" "$game"
write_local_predecessor_marker
rm "$game/new.stock"
cp -a "$game" "$TMP_ROOT/before-rejected-overlay-missing-target"
set +e
run_lfs install >"$TMP_ROOT/rejected-overlay-missing-target.out" 2>&1
overlay_missing_status=$?
set -e
[[ "$overlay_missing_status" -ne 0 && ! -e "$cached_installer" ]]
grep -Fq 'recorded in-game update baseline drifted outside a trusted LFS session' \
  "$TMP_ROOT/rejected-overlay-missing-target.out"
diff -qr "$TMP_ROOT/before-rejected-overlay-missing-target" "$game" >/dev/null

rm -rf "$game"
cp -a "$TMP_ROOT/before-local-catchup" "$game"
cp "$TMP_ROOT/before-local-catchup.env" "$state/install.env"
rm -f "$state"/game-update-*.manifest "$state/game-update.manifest"

cp -a "$game" "$TMP_ROOT/before-trusted-game-update"
cp "$state/install.env" "$TMP_ROOT/before-trusted-game-update.env"
original_display="${DISPLAY:-}"
marker_field() {
  awk -F "'" -v key="$1=" '$1 == key { print $2 }' "$state/install.env"
}
session_field() {
  awk -F "'" -v key="$1=" '$1 == key { print $2 }' "$state/launch-session.env"
}
export DISPLAY="${DISPLAY:-:test}" LFS_TEST_SELF_UPDATE_VERSION='9Z1' LFS_TEST_EXIT_STATUS='7'
set +e
run_lfs launch >"$TMP_ROOT/trusted-game-update.out" 2>&1
trusted_update_status=$?
set -e
unset LFS_TEST_SELF_UPDATE_VERSION LFS_TEST_EXIT_STATUS
[[ "$trusted_update_status" -eq 7 ]]
grep -Fq 'Recorded LFS 0.9Z1 in-game update as the verified local launch baseline' "$TMP_ROOT/trusted-game-update.out"
first_manifest_name="$(marker_field LFS_STOCK_MANIFEST_NAME)"
[[ "$first_manifest_name" =~ ^game-update-[0-9a-f]{64}\.manifest$ ]]
[[ -f "$state/$first_manifest_name" ]]
grep -Fqx "LFS_BASELINE_KIND='game-update'" "$state/install.env"
grep -Fqx "LFS_VERSION='0.9Z1'" "$state/install.env"
cp "$state/$first_manifest_name" "$state/game-update.manifest"
rm -f "$state/$first_manifest_name"
sed -i '/^LFS_STOCK_MANIFEST_NAME=/d' "$state/install.env"
run_lfs ready
printf 'changed-player-card-config' >"$game/card_cfg.txt"
printf 'changed-runtime-debug-log' >"$game/deb.log"
printf 'changed-older-runtime-debug-log' >"$game/deb_old.log"
printf 'changed-player-account-state' >"$game/guest.txt"
printf 'changed-event-cache' >"$game/cache/events/player.png"
printf 'changed-downloaded-mod' >"$game/mods/vehicles/player.mod"
printf 'changed-player-grid' >"$game/data/grids/player.rac"
printf 'changed-player-skin' >"$game/data/skins/player.jpg"
printf 'changed-downloaded-skin-x' >"$game/data/skins_x/player.dds"
printf 'changed-downloaded-skin-y' >"$game/data/skins_y/player.dds"
printf 'new-event-cache' >"$game/cache/events/new.png"
player_paths+=(cache/events/new.png)
(
  cd "$game"
  sha256sum "${player_paths[@]}"
) >"$player_hashes"
printf 'post-update-replay' >"$game/data/mpr/post-update.mpr"
run_lfs ready
run_lfs launch >"$TMP_ROOT/next-day-launch.out"
grep -Fq 'Starting verified LFS 0.9Z1' "$TMP_ROOT/next-day-launch.out"
export LFS_TEST_SELF_UPDATE_VERSION='9Z2'
run_lfs launch >"$TMP_ROOT/second-trusted-game-update.out"
unset LFS_TEST_SELF_UPDATE_VERSION
grep -Fq 'Recorded LFS 0.9Z2 in-game update as the verified local launch baseline' "$TMP_ROOT/second-trusted-game-update.out"
grep -Fqx "LFS_VERSION='0.9Z2'" "$state/install.env"
second_manifest_name="$(marker_field LFS_STOCK_MANIFEST_NAME)"
[[ "$second_manifest_name" =~ ^game-update-[0-9a-f]{64}\.manifest$ ]]
[[ -f "$state/$second_manifest_name" && ! -e "$state/game-update.manifest" ]]
run_lfs ready
run_lfs launch >"$TMP_ROOT/second-next-day-launch.out"
grep -Fq 'Starting verified LFS 0.9Z2' "$TMP_ROOT/second-next-day-launch.out"

wait_error_kill="$TMP_ROOT/wine-wait-error-killed"
export LFS_TEST_WINESERVER_ERROR_STATUS='42' LFS_TEST_CAPTURE_KILL="$wait_error_kill"
set +e
run_lfs launch >"$TMP_ROOT/wine-wait-error.out" 2>&1
wait_error_status=$?
set -e
unset LFS_TEST_WINESERVER_ERROR_STATUS LFS_TEST_CAPTURE_KILL
[[ "$wait_error_status" -eq 42 && ! -e "$wait_error_kill" ]]
wait_error_log="$logs/$(readlink "$logs/latest.log")"
grep -Fq 'lfs-linux event=wine-wait-error phase=primary status=42' "$wait_error_log"
grep -Fq 'lfs-linux event=finish status=42 reason=wine-wait-failed' "$wait_error_log"
[[ -f "$state/launch-session.env" ]]

orphan_kill="$TMP_ROOT/orphan-wineserver-killed"
export LFS_TEST_WINESERVER_HANG='1' LFS_TEST_CAPTURE_KILL="$orphan_kill"
set +e
run_lfs launch >"$TMP_ROOT/orphan-wineserver.out" 2>&1
orphan_status=$?
set -e
unset LFS_TEST_WINESERVER_HANG
[[ "$orphan_status" -ne 0 && ! -e "$orphan_kill" ]]
[[ -f "$state/prefix/lingering-helper.pid" ]]
read -r orphan_helper_pid <"$state/prefix/lingering-helper.pid"
if find "/proc/$orphan_helper_pid/fd" -lname "${XDG_RUNTIME_DIR:-/tmp}/lfs-linux-$UID/launch.lock" -print -quit 2>/dev/null | grep -q .; then
  printf 'Wine descendant inherited the foreground launch lock\n' >&2
  exit 1
fi
grep -Fq 'they were left running and protected changes were not recorded' "$TMP_ROOT/orphan-wineserver.out"
grep -Fqx "LFS_VERSION='0.9Z2'" "$state/install.env"
[[ -f "$state/launch-session.env" ]]
orphan_launch_log="$logs/$(readlink "$logs/latest.log")"
grep -Fq 'game_active=no action=retain-evidence' "$orphan_launch_log"
grep -Fq 'lfs-linux event=finish status=1 reason=wine-wait-failed' "$orphan_launch_log"
run_lfs status | grep -Fq 'Wine services remain (run lfs-linux stop)'
set +e
run_lfs install >"$TMP_ROOT/orphan-install-rejected.out" 2>&1
orphan_install_status=$?
set -e
[[ "$orphan_install_status" -ne 0 ]]
grep -Fq 'private Wine processes are running; run lfs-linux stop before install' "$TMP_ROOT/orphan-install-rejected.out"
run_lfs stop >"$TMP_ROOT/orphan-stop.out"
[[ -e "$orphan_kill" && ! -e "$state/prefix/lingering-helper.pid" ]]
run_lfs status | grep -Fq 'Process:    stopped'
WINEPREFIX="$state/prefix" bash -c 'exec -a browser-helper sleep 10' &
unrelated_prefix_pid=$!
sleep 0.1
run_lfs status | grep -Fq 'Process:    stopped'
kill "$unrelated_prefix_pid"
wait "$unrelated_prefix_pid" 2>/dev/null || true
unset LFS_TEST_CAPTURE_KILL

restart_kill="$TMP_ROOT/restarted-game-killed"
export LFS_TEST_SELF_UPDATE_VERSION='9Z3' LFS_TEST_RESTART_DELAY_SECONDS='1.5' \
  LFS_TEST_RESTART_SECONDS='3' LFS_TEST_EXIT_STATUS='7' LFS_TEST_CAPTURE_KILL="$restart_kill"
set +e
run_lfs launch >"$TMP_ROOT/restarted-trusted-game-update.out" 2>&1
restart_status=$?
set -e
unset LFS_TEST_SELF_UPDATE_VERSION LFS_TEST_RESTART_DELAY_SECONDS LFS_TEST_RESTART_SECONDS \
  LFS_TEST_EXIT_STATUS LFS_TEST_CAPTURE_KILL
[[ "$restart_status" -eq 7 && ! -e "$restart_kill" ]]
grep -Fq 'Updater restarted LFS; waiting for the active game to exit' "$TMP_ROOT/restarted-trusted-game-update.out"
grep -Fq 'Recorded LFS 0.9Z3 in-game update as the verified local launch baseline' "$TMP_ROOT/restarted-trusted-game-update.out"
grep -Fqx "LFS_VERSION='0.9Z3'" "$state/install.env"
[[ ! -e "$state/launch-session.env" ]]
latest_launch_log="$logs/$(readlink "$logs/latest.log")"
grep -Fq 'lfs-linux event=start session=' "$latest_launch_log"
grep -Fq 'lfs-linux event=wine-parent-exit status=7' "$latest_launch_log"
grep -Eq 'game_active=yes action=continue(-after-grace)?' "$latest_launch_log"
grep -Fq 'lfs-linux event=update-recorded version=0.9Z3' "$latest_launch_log"
grep -Fq 'lfs-linux event=finish status=7' "$latest_launch_log"

pre_fault_manifest_name="$(marker_field LFS_STOCK_MANIFEST_NAME)"
pre_fault_manifest_hash="$(sha256sum "$state/$pre_fault_manifest_name" | awk '{print $1}')"
concurrent_hold_file="$TMP_ROOT/concurrent-update-active"
export LFS_TEST_SELF_UPDATE_VERSION='9Z4' LFS_TEST_LAUNCH_HOLD_FILE="$concurrent_hold_file" \
  LFS_TEST_LAUNCH_HOLD_SECONDS='2'
LFS_LINUX_TEST_FAIL_BEFORE_MARKER=1 run_lfs launch >"$TMP_ROOT/interrupted-marker-commit.out" 2>&1 &
interrupted_commit_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ -e "$concurrent_hold_file" ]] && break
  kill -0 "$interrupted_commit_pid" 2>/dev/null || break
  sleep 0.05
done
[[ -e "$concurrent_hold_file" ]]
set +e
run_lfs launch >"$TMP_ROOT/concurrent-launch-rejected-before-validation.out" 2>&1
concurrent_launch_status=$?
wait "$interrupted_commit_pid"
interrupted_commit_status=$?
set -e
unset LFS_TEST_SELF_UPDATE_VERSION LFS_TEST_LAUNCH_HOLD_FILE LFS_TEST_LAUNCH_HOLD_SECONDS
[[ "$concurrent_launch_status" -eq 0 ]]
grep -Fq 'LFS is already launching or running' "$TMP_ROOT/concurrent-launch-rejected-before-validation.out"
[[ "$interrupted_commit_status" -ne 0 ]]
grep -Fq 'test fault before in-game update marker commit; previous baseline retained' "$TMP_ROOT/interrupted-marker-commit.out"
grep -Fqx "LFS_VERSION='0.9Z3'" "$state/install.env"
[[ "$(marker_field LFS_STOCK_MANIFEST_NAME)" == "$pre_fault_manifest_name" ]]
[[ "$(sha256sum "$state/$pre_fault_manifest_name" | awk '{print $1}')" == "$pre_fault_manifest_hash" ]]
[[ -f "$state/launch-session.env" ]]
[[ "$(find "$state" -maxdepth 1 -type f -name 'game-update-*.manifest' -printf . | wc -c)" -ge 2 ]]
recovery_log="$logs/$(session_field LOG_BASENAME)"
cp "$state/launch-session.env" "$TMP_ROOT/valid-launch-session.env"
chmod 0644 "$state/launch-session.env"
set +e
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 run_lfs recover-update >"$TMP_ROOT/recovery-rejects-open-permissions.out" 2>&1
recovery_permissions_status=$?
set -e
[[ "$recovery_permissions_status" -ne 0 ]]
grep -Fq 'launch-session evidence is missing or changed; no files changed' "$TMP_ROOT/recovery-rejects-open-permissions.out"
install -m 0600 "$TMP_ROOT/valid-launch-session.env" "$state/launch-session.env"
printf "UNEXPECTED='malformed'\n" >>"$state/launch-session.env"
set +e
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 run_lfs recover-update >"$TMP_ROOT/recovery-rejects-unknown-key.out" 2>&1
recovery_unknown_key_status=$?
set -e
[[ "$recovery_unknown_key_status" -ne 0 ]]
grep -Fq 'launch-session evidence is missing or changed; no files changed' "$TMP_ROOT/recovery-rejects-unknown-key.out"
install -m 0600 "$TMP_ROOT/valid-launch-session.env" "$state/launch-session.env"
printf "BASELINE_VERSION='tampered'\n" >>"$state/launch-session.env"
set +e
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 run_lfs recover-update >"$TMP_ROOT/recovery-rejects-tampered-evidence.out" 2>&1
recovery_tamper_status=$?
set -e
[[ "$recovery_tamper_status" -ne 0 ]]
grep -Fq 'launch-session evidence is missing or changed; no files changed' "$TMP_ROOT/recovery-rejects-tampered-evidence.out"
install -m 0600 "$TMP_ROOT/valid-launch-session.env" "$state/launch-session.env"
sed -i "s/^STARTED_AT='[^']*'/STARTED_AT='1'/" "$state/launch-session.env"
set +e
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 run_lfs recover-update >"$TMP_ROOT/recovery-rejects-event-time-mismatch.out" 2>&1
recovery_time_status=$?
set -e
[[ "$recovery_time_status" -ne 0 ]]
grep -Fq 'launch-session evidence is missing or changed; no files changed' "$TMP_ROOT/recovery-rejects-event-time-mismatch.out"
install -m 0600 "$TMP_ROOT/valid-launch-session.env" "$state/launch-session.env"
prompt_snapshot_events_before="$(grep -Fc 'lfs-linux event=recovery-snapshot-ready' "$recovery_log" || true)"
set +e
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 LFS_LINUX_TEST_CONFIRMATION_DELAY_SECONDS=4 \
  run_lfs recover-update >"$TMP_ROOT/recovery-rejects-prompt-race.out" 2>&1 &
recovery_pid=$!
set -e
prompt_snapshot_ready=0
for ((attempt = 0; attempt < 200; attempt++)); do
  prompt_snapshot_events_now="$(grep -Fc 'lfs-linux event=recovery-snapshot-ready' "$recovery_log" || true)"
  if (( prompt_snapshot_events_now > prompt_snapshot_events_before )); then
    prompt_snapshot_ready=1
    break
  fi
  kill -0 "$recovery_pid" 2>/dev/null || break
  sleep 0.05
done
[[ "$prompt_snapshot_ready" -eq 1 ]]
printf "UNEXPECTED='prompt-race'\n" >>"$state/launch-session.env"
set +e
wait "$recovery_pid"
recovery_race_status=$?
set -e
[[ "$recovery_race_status" -ne 0 ]]
grep -Fq 'launch-session evidence changed during confirmation; no files changed' "$TMP_ROOT/recovery-rejects-prompt-race.out"
grep -Fqx "LFS_VERSION='0.9Z3'" "$state/install.env"
install -m 0600 "$TMP_ROOT/valid-launch-session.env" "$state/launch-session.env"
cp "$game/game-update.stock" "$TMP_ROOT/game-update.stock.before-confirmation-race"
snapshot_events_before="$(grep -Fc 'lfs-linux event=recovery-snapshot-ready' "$recovery_log" || true)"
set +e
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 LFS_LINUX_TEST_CONFIRMATION_DELAY_SECONDS=4 \
  run_lfs recover-update >"$TMP_ROOT/recovery-rejects-content-race.out" 2>&1 &
content_recovery_pid=$!
set -e
snapshot_ready=0
for ((attempt = 0; attempt < 200; attempt++)); do
  snapshot_events_now="$(grep -Fc 'lfs-linux event=recovery-snapshot-ready' "$recovery_log" || true)"
  if (( snapshot_events_now > snapshot_events_before )); then
    snapshot_ready=1
    break
  fi
  kill -0 "$content_recovery_pid" 2>/dev/null || break
  sleep 0.05
done
[[ "$snapshot_ready" -eq 1 ]]
printf 'changed-after-confirmation-snapshot' >"$game/game-update.stock"
set +e
WINEPREFIX="$state/prefix" bash -c 'exec -a LFS.exe sleep 0.2' &
transient_game_pid=$!
wait "$transient_game_pid"
wait "$content_recovery_pid"
content_recovery_status=$?
set -e
[[ "$content_recovery_status" -ne 0 ]]
grep -Fq 'protected LFS files changed after recovery confirmation; previous baseline retained' "$TMP_ROOT/recovery-rejects-content-race.out"
grep -Fqx "LFS_VERSION='0.9Z3'" "$state/install.env"
cp "$TMP_ROOT/game-update.stock.before-confirmation-race" "$game/game-update.stock"
if compgen -G "$state/.recovery-candidate.manifest.*" >/dev/null; then
  printf 'failed recovery left a pre-confirmation snapshot\n' >&2
  exit 1
fi
set +e
run_lfs recover-update </dev/null >"$TMP_ROOT/recovery-needs-confirmation.out" 2>&1
recovery_confirmation_status=$?
set -e
[[ "$recovery_confirmation_status" -ne 0 ]]
grep -Fq 'update recovery needs a terminal or LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1' "$TMP_ROOT/recovery-needs-confirmation.out"
grep -Fqx "LFS_VERSION='0.9Z3'" "$state/install.env"
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 run_lfs recover-update >"$TMP_ROOT/recovered-trusted-game-update.out"
grep -Fq 'Recovered LFS 0.9Z4 as the verified local launch baseline' "$TMP_ROOT/recovered-trusted-game-update.out"
grep -Fqx "LFS_VERSION='0.9Z4'" "$state/install.env"
recovered_manifest_name="$(marker_field LFS_STOCK_MANIFEST_NAME)"
[[ "$recovered_manifest_name" =~ ^game-update-[0-9a-f]{64}\.manifest$ ]]
[[ -f "$state/$recovered_manifest_name" && ! -e "$state/$pre_fault_manifest_name" ]]
[[ "$(find "$state" -maxdepth 1 -type f -name 'game-update-*.manifest' -printf . | wc -c)" -eq 1 ]]
[[ ! -e "$state/launch-session.env" ]]
(
  cd "$game"
  sha256sum --check --quiet "$player_hashes"
)
grep -Eq 'lfs-linux event=recovery-recorded session=[0-9]+-[0-9]+ version=0\.9Z4' "$recovery_log"
run_lfs ready
run_lfs launch >"$TMP_ROOT/recovered-next-day-launch.out"
grep -Fq 'Starting verified LFS 0.9Z4' "$TMP_ROOT/recovered-next-day-launch.out"

if [[ -n "$original_display" ]]; then export DISPLAY="$original_display"; else unset DISPLAY; fi
run_lfs doctor >"$TMP_ROOT/game-update-doctor.out"
grep -Fq 'Doctor summary: 0 failure(s)' "$TMP_ROOT/game-update-doctor.out"
rm -f "$cached_installer"
run_lfs install >"$TMP_ROOT/game-update-install.out"
grep -Fq 'Verified locally recorded LFS 0.9Z4 in-game update' "$TMP_ROOT/game-update-install.out"
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
rm -f "$state"/game-update-*.manifest "$state/game-update.manifest"

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
set +e
LFS_LINUX_CONFIRM_UPDATE_RECOVERY=1 run_lfs recover-update >"$TMP_ROOT/recovery-rejects-missing-evidence.out" 2>&1
missing_recovery_status=$?
set -e
[[ "$missing_recovery_status" -ne 0 ]]
grep -Fq 'no interrupted trusted launch session is available for recovery' "$TMP_ROOT/recovery-rejects-missing-evidence.out"
diff -qr "$TMP_ROOT/before-rejected-update" "$game" >/dev/null

printf '[PASS] resumable input, atomic upgrade, trusted in-game update relaunch, preservation, repair, recovery, and drift guards pass\n'
