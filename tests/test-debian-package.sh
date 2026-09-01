#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
VERSION="$(<"$ROOT_DIR/VERSION")"
readonly VERSION
readonly DIRECT_REVISION='0github1'
TMP_ROOT="$(mktemp -d /tmp/lfs-linux-deb-test.XXXXXX)"
readonly TMP_ROOT
trap 'rm -rf "$TMP_ROOT"' EXIT

if ! command -v dpkg-deb >/dev/null 2>&1 || ! command -v dpkg >/dev/null 2>&1; then
  printf '[SKIP] dpkg and dpkg-deb are required for the Debian package check\n'
  exit 0
fi

mkdir -p "$TMP_ROOT/one" "$TMP_ROOT/two" "$TMP_ROOT/extracted"
(umask 077; "$ROOT_DIR/packaging/debian/build-deb.sh" "$TMP_ROOT/one") >"$TMP_ROOT/one.sha"
(umask 022; "$ROOT_DIR/packaging/debian/build-deb.sh" "$TMP_ROOT/two") >"$TMP_ROOT/two.sha"
deb_one="$TMP_ROOT/one/live-for-speed-linux_${VERSION}-${DIRECT_REVISION}_amd64.deb"
deb_two="$TMP_ROOT/two/live-for-speed-linux_${VERSION}-${DIRECT_REVISION}_amd64.deb"
[[ -f "$deb_one" && -f "$deb_two" ]]
[[ "$(sha256sum "$deb_one" | awk '{print $1}')" == "$(sha256sum "$deb_two" | awk '{print $1}')" ]]

[[ "$(dpkg-deb --field "$deb_one" Package)" == 'live-for-speed-linux' ]]
[[ "$(dpkg-deb --field "$deb_one" Version)" == "$VERSION-$DIRECT_REVISION" ]]
[[ "$(dpkg-deb --field "$deb_one" Architecture)" == 'amd64' ]]
[[ "$(dpkg-deb --field "$deb_one" Section)" == 'contrib/games' ]]
grep -Fqi 'racing simulator' <<<"$(dpkg-deb --field "$deb_one" Description)"
depends="$(dpkg-deb --field "$deb_one" Depends)"
for dependency in \
  '7zip' 'gpgv' 'libarchive-tools' 'libasound2t64' 'libc6' 'libsane1' \
  'libvulkan1' 'vulkan-icd' 'x-terminal-emulator'; do
  grep -Eq "(^|[,|] )${dependency//./\\.}([ ,|]|$)" <<<"$depends"
done

control_contents="$(dpkg-deb --ctrl-tarfile "$deb_one" | tar -tf -)"
for maintainer_file in preinst postinst prerm postrm config conffiles triggers; do
  if grep -Eq "(^|/)${maintainer_file}$" <<<"$control_contents"; then
    printf 'unexpected Debian maintainer script or package-manager hook: %s\n' "$maintainer_file" >&2
    exit 1
  fi
done

contents="$(dpkg-deb --contents "$deb_one")"
grep -Fq './usr/bin/lfs-linux' <<<"$contents"
grep -Fq './usr/lib/lfs-linux/lfs-linux-core' <<<"$contents"
grep -Fq './usr/share/lfs-linux/release.env' <<<"$contents"
grep -Fq './usr/share/lfs-linux/arch-wine-peter-jung.pgp' <<<"$contents"
grep -Fq './usr/share/man/man1/lfs-linux.1.gz' <<<"$contents"
grep -Fq './usr/share/man/man1/lfs-linux-desktop.1.gz' <<<"$contents"
if grep -Ei '(^|/)(home|root|artifacts|cache)(/|$)|\.(exe|dll|msi|zip)$' <<<"$contents"; then
  printf 'private paths or proprietary/runtime payloads entered the Debian package\n' >&2
  exit 1
fi

dpkg-deb --extract "$deb_one" "$TMP_ROOT/extracted"
"$ROOT_DIR/tests/test-package-boundary.sh" "$TMP_ROOT/extracted" >/dev/null
cmp "$ROOT_DIR/bin/lfs-linux" "$TMP_ROOT/extracted/usr/bin/lfs-linux"
cmp "$ROOT_DIR/libexec/lfs-linux-core" "$TMP_ROOT/extracted/usr/lib/lfs-linux/lfs-linux-core"
cmp "$ROOT_DIR/share/lfs-linux/arch-wine-peter-jung.pgp" "$TMP_ROOT/extracted/usr/share/lfs-linux/arch-wine-peter-jung.pgp"
cmp "$ROOT_DIR/packaging/debian/copyright" "$TMP_ROOT/extracted/usr/share/doc/live-for-speed-linux/copyright"
grep -Fq 'Files: share/lfs-linux/arch-wine-peter-jung.pgp' "$TMP_ROOT/extracted/usr/share/doc/live-for-speed-linux/copyright"
grep -Fq 'License: GPL-3+' "$TMP_ROOT/extracted/usr/share/doc/live-for-speed-linux/copyright"
[[ "$(stat -c %a "$TMP_ROOT/extracted/usr/bin/lfs-linux")" == '755' ]]
[[ "$(stat -c %a "$TMP_ROOT/extracted/usr/share/lfs-linux/release.env")" == '644' ]]
[[ "$(readlink "$TMP_ROOT/extracted/usr/share/man/man1/lfs-linux-desktop.1.gz")" == 'lfs-linux.1.gz' ]]
(( $(stat -c %s "$deb_one") < 3000000 ))

grep -Fq 'libc6 (>= 2.38)' <<<"$depends"
if grep -Eq '(^|[,|] )(wine32|wine64|[^, ]+:i386|desktop-file-utils|vulkan-tools|xdotool|xz-utils)([ ,|]|$)' <<<"$depends"; then
  printf 'Debian package incorrectly requires a system Wine, i386 stack, or optional tool\n' >&2
  exit 1
fi

printf '[PASS] Debian package is deterministic, pure-WoW64, wrapper-only, and relocatable\n'
