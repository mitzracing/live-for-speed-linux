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
    [[ "${LFS_TEST_BOOT_FAILURE:-0}" != 1 ]] || exit 1
    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
    printf '#arch=win64\n' >"$WINEPREFIX/system.reg"
    ;;
  reg)
    ;;
  *)
    [[ -z "${LFS_TEST_PLAY_LOG:-}" ]] || printf "played\n" >>"$LFS_TEST_PLAY_LOG"
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
      if [[ "${LFS_TEST_SKIP_VERSION_MARKER:-0}" != 1 ]]; then
        : >"$game_root/data/versions/$LFS_TEST_SELF_UPDATE_VERSION.txt"
      fi
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
# Unit fixtures test doctor decisions; native Vulkan is covered by release GUI checks.
cat >"$fake_bin/vulkaninfo" <<'EOF'
#!/usr/bin/env bash
printf 'deviceName = unit fixture\n'
EOF
chmod +x "$fake_bin/vulkaninfo"
chmod +x "$fake_wine" "$fake_wine_root/usr/bin/wineserver" "$fake_bin/restart-delay" "$fake_bin/timeout"
"$ROOT_DIR/scripts/generate-payload-manifest.py" wine "$fake_wine_root" "$data/fake-wine.manifest" >/dev/null
wine_manifest_size="$(stat -c %s "$data/fake-wine.manifest")"
wine_manifest_hash="$(sha256sum "$data/fake-wine.manifest" | awk '{print $1}')"
printf 'fake-signing-key' >"$data/fake-signing-key.gpg"
fake_signing_key_size="$(stat -c %s "$data/fake-signing-key.gpg")"
fake_signing_key_hash="$(sha256sum "$data/fake-signing-key.gpg" | awk '{print $1}')"

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
EOF

mkdir -p "$TMP_ROOT/xdg-runtime"
export XDG_RUNTIME_DIR="$TMP_ROOT/xdg-runtime"
printf '#arch=win64\n' >"$state/prefix/system.reg"
printf player-account-fixture >"$state/prefix/user.reg"
cp "$state/prefix/user.reg" "$TMP_ROOT/user-reg-before"
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

set +e
run_lfs install >"$TMP_ROOT/rejected-unsafe-archive.out" 2>&1
unsafe_archive_status=$?
set -e
[[ "$unsafe_archive_status" -ne 0 ]]
grep -Fq 'official LFS installer has unsafe' "$TMP_ROOT/rejected-unsafe-archive.out"
[[ ! -e "$state/archive-escape" && ! -e "$TMP_ROOT/archive-escape" ]]
[[ ! -e "$game" ]]
cmp "$state/prefix/user.reg" "$TMP_ROOT/user-reg-before"
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

set +e
run_lfs install >"$TMP_ROOT/rejected-nested.out" 2>&1
nested_status=$?
set -e
[[ "$nested_status" -ne 0 ]]
grep -Fq 'Recovered completed verified official LFS test-new installer download' "$TMP_ROOT/rejected-nested.out"
grep -Fq 'official LFS nested archive payload drift' "$TMP_ROOT/rejected-nested.out"
[[ ! -e "$game" ]]
cmp "$state/prefix/user.reg" "$TMP_ROOT/user-reg-before"
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

# A valid outer archive with a missing final seed file still fails before activation.
cp -a "$outer_stock" "$TMP_ROOT/missing-seed-outer"
rm "$TMP_ROOT/missing-seed-outer/data/veh/XFG.vob"
(cd "$TMP_ROOT/missing-seed-outer" && 7z a -t7z "$TMP_ROOT/missing-seed.exe" . >/dev/null)
seed_size="$(stat -c %s "$TMP_ROOT/missing-seed.exe")"
seed_hash="$(sha256sum "$TMP_ROOT/missing-seed.exe" | awk '{print $1}')"
cp "$TMP_ROOT/missing-seed.exe" "$upstream_installer"
rm -f "$cached_installer" "$cached_installer.part"
sed -i -e "s|LFS_INSTALLER_SIZE='$installer_size'|LFS_INSTALLER_SIZE='$seed_size'|" \
  -e "s|LFS_INSTALLER_SHA256='$installer_hash'|LFS_INSTALLER_SHA256='$seed_hash'|" "$data/release.env"
if run_lfs install >"$TMP_ROOT/missing-seed.out" 2>&1; then exit 1; fi
grep -Fq 'required stock file missing: data/veh/XFG.vob' "$TMP_ROOT/missing-seed.out"
[[ ! -e "$game" ]]
cmp "$state/prefix/user.reg" "$TMP_ROOT/user-reg-before"
cp "$TMP_ROOT/correct-fake-lfs.exe" "$upstream_installer"
rm -f "$cached_installer"
head -c 137 "$upstream_installer" >"$cached_installer.part"
sed -i -e "s|LFS_INSTALLER_SIZE='$seed_size'|LFS_INSTALLER_SIZE='$installer_size'|" \
  -e "s|LFS_INSTALLER_SHA256='$seed_hash'|LFS_INSTALLER_SHA256='$installer_hash'|" "$data/release.env"

# Game content remains LFS-owned across wrapper setup, updates and relaunch.
run_lfs install >"$TMP_ROOT/first-install.out"
grep -Fq 'Downloading official LFS test-new installer (safe to resume after interruption)' "$TMP_ROOT/first-install.out"
cmp "$upstream_installer" "$cached_installer"
[[ ! -e "$cached_installer.part" ]]
diff -qr "$new_stock" "$game" >/dev/null
run_lfs doctor >"$TMP_ROOT/doctor.out"
grep -Fq 'Doctor summary: 0 failure(s)' "$TMP_ROOT/doctor.out"

# Player paths include links, mutable defaults and names that once looked like stock.
printf 'player-settings' >"$game/cfg.txt"
printf 'changed-stock' >"$game/shared.stock"
printf 'player-owned-new-stock-name' >"$game/new.stock"
mkdir -p "$game/data/mpr" "$game/data/setups" "$TMP_ROOT/player-setups"
printf replay >"$game/data/mpr/player.mpr"
printf setup >"$TMP_ROOT/player-setups/player.set"
ln -s "$TMP_ROOT/player-setups" "$game/data/setups/linked"
printf downloaded-skin >"$game/data/skins_dds/PLAYER.dds"
cp -a "$game" "$TMP_ROOT/before-component-repair"
rm "$cached_installer"
run_lfs install >"$TMP_ROOT/component-repair.out"
grep -Fq 'Keeping existing Live for Speed and all player files' "$TMP_ROOT/component-repair.out"
[[ ! -e "$cached_installer" ]]
diff -qr "$TMP_ROOT/before-component-repair" "$game" >/dev/null
[[ -L "$game/data/setups/linked" ]]

# Even a previous bootstrap is preserved, not silently upgraded by a wrapper package.
cp -a "$state" "$TMP_ROOT/older-state"
older_game="$TMP_ROOT/older-state/prefix/drive_c/LFS"
rm -rf "$older_game"
cp -a "$old_stock" "$older_game"
printf older-player-data >"$older_game/cfg.txt"
cp -a "$older_game" "$TMP_ROOT/before-older-setup"
saved_state="$state"
state="$TMP_ROOT/older-state"
run_lfs install >"$TMP_ROOT/older-setup.out"
state="$saved_state"
diff -qr "$TMP_ROOT/before-older-setup" "$older_game" >/dev/null
[[ ! -e "$cached_installer" ]]

# Existing incomplete games are never replaced by an older installer.
mv "$game/LFS.exe" "$TMP_ROOT/saved-game.exe"
cp -a "$game" "$TMP_ROOT/incomplete-before"
if run_lfs install >"$TMP_ROOT/incomplete.out" 2>&1; then exit 1; fi
grep -Fq 'no files changed' "$TMP_ROOT/incomplete.out"
diff -qr "$TMP_ROOT/incomplete-before" "$game" >/dev/null
mv "$TMP_ROOT/saved-game.exe" "$game/LFS.exe"

# Preserve both trees from old swap transactions; restore only an absent destination.
cp -a "$game" "$state/.lfs-game-backup"
printf newer-game >"$game/LFS.exe"
run_lfs install >"$TMP_ROOT/two-trees.out"
[[ -f "$state/.lfs-game-backup/LFS.exe" ]]
grep -Fqx newer-game "$game/LFS.exe"
rm -rf "$state/.lfs-game-backup"
mv "$game" "$state/.lfs-game-backup"
run_lfs install >"$TMP_ROOT/recover-backup.out"
grep -Fq 'Recovered player data' "$TMP_ROOT/recover-backup.out"
[[ -f "$game/LFS.exe" && ! -e "$state/.lfs-game-backup" ]]

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


export DISPLAY="${DISPLAY:-:fixture}" LFS_TEST_SKIP_VERSION_MARKER=1
cp "$state/install.env" "$TMP_ROOT/marker-before-play"
export LFS_TEST_SELF_UPDATE_VERSION=9Z1 LFS_TEST_EXIT_STATUS=7
set +e
run_lfs launch >"$TMP_ROOT/update.out" 2>&1
update_status=$?
set -e
unset LFS_TEST_SELF_UPDATE_VERSION LFS_TEST_EXIT_STATUS
[[ "$update_status" == 7 ]]
[[ ! -e "$game/data/versions/9Z1.txt" && ! -e "$state/launch-session.env" ]]
grep -Fqx self-updated-9Z1 "$game/LFS.exe"
run_lfs ready
[[ "$(run_lfs desktop-state)" == ready ]]
run_lfs launch >"$TMP_ROOT/relaunch.out"
cmp "$state/install.env" "$TMP_ROOT/marker-before-play"
[[ -z "$(find "$state" -maxdepth 1 -name 'game-update*.manifest' -print -quit)" ]]

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
[[ ! -e "$state/launch-session.env" ]]

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
grep -Fq 'they were left running.' "$TMP_ROOT/orphan-wineserver.out"
[[ ! -e "$state/launch-session.env" ]]
orphan_launch_log="$logs/$(readlink "$logs/latest.log")"
grep -Fq 'game_active=no action=leave-running' "$orphan_launch_log"
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
[[ ! -e "$state/launch-session.env" ]]
latest_launch_log="$logs/$(readlink "$logs/latest.log")"
grep -Fq 'lfs-linux event=start wine=' "$latest_launch_log"
grep -Fq 'lfs-linux event=wine-parent-exit status=7' "$latest_launch_log"
grep -Eq 'game_active=yes action=continue(-after-grace)?' "$latest_launch_log"
grep -Fq 'lfs-linux event=finish status=7' "$latest_launch_log"


# Legacy evidence is ignored, not interpreted, upgraded or deleted.
printf obsolete-inventory >"$state/game-update.manifest"
printf interrupted-session >"$state/launch-session.env"
printf "LFS_BASELINE_KIND='game-update'\nLFS_STOCK_MANIFEST_NAME='missing-old-manifest'\n" >>"$state/install.env"
run_lfs ready
run_lfs launch >"$TMP_ROOT/legacy-relaunch.out"
run_lfs recover-update </dev/null >"$TMP_ROOT/legacy-command.out"
grep -Fq 'No wrapper recovery or rebaseline is needed' "$TMP_ROOT/legacy-command.out"
grep -Fqx obsolete-inventory "$state/game-update.manifest"
grep -Fqx interrupted-session "$state/launch-session.env"
rm "$state/game-update.manifest" "$state/launch-session.env"

# Concurrent launch retains the foreground lock while the updater runs.
concurrent_hold_file="$TMP_ROOT/concurrent-update-active"
export LFS_TEST_SELF_UPDATE_VERSION=9Z4 LFS_TEST_LAUNCH_HOLD_FILE="$concurrent_hold_file" LFS_TEST_LAUNCH_HOLD_SECONDS=2
run_lfs launch >"$TMP_ROOT/concurrent-first.out" 2>&1 &
first_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
  [[ -e "$concurrent_hold_file" ]] && break
  sleep .05
done
[[ -e "$concurrent_hold_file" ]]
run_lfs launch >"$TMP_ROOT/concurrent-second.out" 2>&1
wait "$first_pid"
unset LFS_TEST_SELF_UPDATE_VERSION LFS_TEST_LAUNCH_HOLD_FILE LFS_TEST_LAUNCH_HOLD_SECONDS
grep -Fq 'LFS is already launching or running' "$TMP_ROOT/concurrent-second.out"
run_lfs ready
run_lfs launch >"$TMP_ROOT/concurrent-relaunch.out"

# Installed desktop entry uses the same path for downloaded and store-managed packages.
# Only Wine and Zenity are adapters. Installer, desktop helper, controller and core are real.
staged="$TMP_ROOT/staged"
make -s -C "$ROOT_DIR" DESTDIR="$staged" PREFIX=/usr install
cat >"$fake_bin/zenity" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LFS_TEST_DIALOGS"
case "$*" in
  *--progress*) while read -r line; do [[ "$line" != 100 ]] || exit 0; done ;;
  *--ok-label=Retry*) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/zenity"
read -r -a desktop_command <<<"$(awk -F= '/^Exec=/{print $2; exit}' "$staged/usr/share/applications/io.github.mitzracing.live_for_speed_linux.desktop")"
run_desktop() {
  LFS_LINUX_DATA_DIR="$data" LFS_LINUX_LIBEXEC_DIR="$staged/usr/lib/lfs-linux" \
  LFS_LINUX_STATE_DIR="$TMP_ROOT/desktop-state" LFS_LINUX_CACHE_DIR="$cache" \
  LFS_LINUX_LOG_DIR="$TMP_ROOT/desktop-logs" LFS_LINUX_WINE="$fake_wine" \
  LFS_LINUX_UI=zenity LFS_TEST_DIALOGS="$TMP_ROOT/desktop-dialogs" \
  LFS_TEST_PLAY_LOG="$TMP_ROOT/desktop-plays" PATH="$staged/usr/bin:$fake_bin:$PATH" \
    "${desktop_command[@]}"
}
run_desktop >"$TMP_ROOT/desktop-first.out" 2>&1
LFS_TEST_SELF_UPDATE_VERSION=8C26 LFS_TEST_RESTART_SECONDS=1 run_desktop >"$TMP_ROOT/desktop-update.out" 2>&1
run_desktop >"$TMP_ROOT/desktop-reopen.out" 2>&1
[[ "$(wc -l <"$TMP_ROOT/desktop-plays")" == 3 ]]
[[ "$(grep -c -- --question "$TMP_ROOT/desktop-dialogs")" == 1 ]]
[[ ! -e "$TMP_ROOT/desktop-state/launch-session.env" ]]
grep -Fqx self-updated-8C26 "$TMP_ROOT/desktop-state/prefix/drive_c/LFS/LFS.exe"
if grep -Eq 'Finish update|Protected-file snapshot|rebaseline' "$TMP_ROOT/desktop-dialogs"; then
  printf 'desktop relaunch asked for obsolete update approval\n' >&2
  exit 1
fi
printf '[PASS] authenticated bootstrap, preserved games, update/restart/reopen, installed desktop flow, process and lock boundaries\n'
