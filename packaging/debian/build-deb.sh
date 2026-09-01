#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C
umask 022
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
VERSION="$(<"$ROOT_DIR/VERSION")"
readonly VERSION
readonly PACKAGE='live-for-speed-linux'
readonly REVISION='0github1'
readonly ARCHITECTURE='amd64'
readonly SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1786665600}"
readonly OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
readonly DEB_NAME="${PACKAGE}_${VERSION}-${REVISION}_${ARCHITECTURE}.deb"
TMP_ROOT=''

cleanup() {
  [[ -z "$TMP_ROOT" ]] || rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

for command_name in awk dpkg dpkg-deb du find gzip install make md5sum sha256sum sort touch xargs; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'error: required Debian package-build command is unavailable: %s\n' "$command_name" >&2
    exit 1
  fi
done

if ! dpkg --validate-version "$VERSION-$REVISION" >/dev/null 2>&1; then
  printf 'error: invalid Debian package version: %s-%s\n' "$VERSION" "$REVISION" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d /tmp/lfs-linux-deb.XXXXXX)"
readonly PACKAGE_ROOT="$TMP_ROOT/root"
mkdir -p "$OUTPUT_DIR" "$PACKAGE_ROOT/DEBIAN"
make -C "$ROOT_DIR" DESTDIR="$PACKAGE_ROOT" PREFIX=/usr install >/dev/null

install -Dm644 "$ROOT_DIR/packaging/debian/copyright" "$PACKAGE_ROOT/usr/share/doc/$PACKAGE/copyright"
rm -rf "$PACKAGE_ROOT/usr/share/licenses"
gzip -n -9 "$PACKAGE_ROOT/usr/share/man/man1/lfs-linux.1"
rm "$PACKAGE_ROOT/usr/share/man/man1/lfs-linux-desktop.1"
ln -s lfs-linux.1.gz "$PACKAGE_ROOT/usr/share/man/man1/lfs-linux-desktop.1.gz"
cat >"$TMP_ROOT/changelog" <<CHANGELOG
$PACKAGE ($VERSION-$REVISION) unstable; urgency=medium

  * Package wrapper release $VERSION for Debian 13 and Ubuntu 24.04.

 -- mitzracing <mitzracing@users.noreply.github.com>  Fri, 14 Aug 2026 00:00:00 +0000
CHANGELOG
gzip -n -9 <"$TMP_ROOT/changelog" >"$PACKAGE_ROOT/usr/share/doc/$PACKAGE/changelog.Debian.gz"
mkdir -p "$PACKAGE_ROOT/usr/share/lintian/overrides"
cat >"$PACKAGE_ROOT/usr/share/lintian/overrides/$PACKAGE" <<OVERRIDES
# This direct GitHub release is not an upload to the Debian archive.
live-for-speed-linux: initial-upload-closes-no-bugs
OVERRIDES

installed_size="$(du -sk "$PACKAGE_ROOT/usr" | awk '{print $1}')"
cat >"$PACKAGE_ROOT/DEBIAN/control" <<CONTROL
Package: $PACKAGE
Version: $VERSION-$REVISION
Section: contrib/games
Priority: optional
Architecture: $ARCHITECTURE
Maintainer: mitzracing <mitzracing@users.noreply.github.com>
Installed-Size: $installed_size
Homepage: https://github.com/mitzracing/live-for-speed-linux
Provides: lfs-linux, live-for-speed-launcher
Conflicts: lfs-linux, live-for-speed-launcher
Replaces: lfs-linux, live-for-speed-launcher
Depends: 7zip, ca-certificates, curl, fontconfig, gawk, gettext-base, gpgv, libarchive-tools, libasound2t64, libc6 (>= 2.38), libfreetype6, libgcc-s1, libglib2.0-0t64, libgphoto2-6t64, libgphoto2-port12t64, libgstreamer-plugins-base1.0-0, libgstreamer1.0-0, libpcsclite1, libpulse0, libsane1, libsystemd0, libudev1, libunwind8, libusb-1.0-0, libvulkan1, libwayland-client0, libwayland-egl1, libx11-6, libxcursor1, libxext6, libxi6, libxkbcommon0, libxkbregistry0, libxrandr2, mesa-vulkan-drivers | vulkan-icd, ocl-icd-libopencl1, xterm | x-terminal-emulator
Recommends: libnotify-bin, vulkan-tools, wmctrl, xdotool
Description: unofficial launcher for the Live for Speed racing simulator
 Verifies and installs untouched official Live for Speed racing simulator
 downloads into a private Wine prefix. The game, Wine, and DXVK payloads are
 not included.
 Live for Speed 0.8C20 is a public test and is not represented as stable.
CONTROL

(
  cd "$PACKAGE_ROOT"
  find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums
)
chmod 0644 "$PACKAGE_ROOT/DEBIAN/control" "$PACKAGE_ROOT/DEBIAN/md5sums"
find "$PACKAGE_ROOT" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
rm -f "$OUTPUT_DIR/$DEB_NAME"
export SOURCE_DATE_EPOCH
dpkg-deb --root-owner-group -Zxz -z9 --build "$PACKAGE_ROOT" "$OUTPUT_DIR/$DEB_NAME" >/dev/null

printf '%s  %s\n' "$(sha256sum "$OUTPUT_DIR/$DEB_NAME" | awk '{print $1}')" "$OUTPUT_DIR/$DEB_NAME"
