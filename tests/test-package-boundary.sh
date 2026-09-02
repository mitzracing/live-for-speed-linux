#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="${1:-}"
[[ -n "$ROOT" && -d "$ROOT" ]] || { printf 'Usage: %s STAGED_PACKAGE_ROOT\n' "$0" >&2; exit 2; }
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lfs-linux-package-boundary.XXXXXX")"
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT

for path in \
  usr/bin/lfs-linux \
  usr/bin/lfs-linux-desktop \
  usr/lib/lfs-linux/lfs-linux-core \
  usr/share/lfs-linux/release.env \
  usr/share/lfs-linux/arch-wine-peter-jung.pgp \
  usr/share/lfs-linux/lfs-0.8C24-stock.manifest \
  usr/share/lfs-linux/lfs-0.8C24-seed.manifest \
  usr/share/lfs-linux/lfs-0.8C24-nested.manifest \
  usr/share/lfs-linux/lfs-0.8C20-stock.manifest \
  usr/share/lfs-linux/lfs-0.8C20-seed.manifest \
  usr/share/lfs-linux/wine-11.15-1-runtime.manifest \
  usr/share/applications/io.github.mitzracing.live_for_speed_linux.desktop \
  usr/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml \
  usr/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg; do
  [[ -e "$ROOT/$path" ]] || { printf 'missing package file: %s\n' "$path" >&2; exit 1; }
done

special_entry="$(find -P "$ROOT" -mindepth 1 ! -type d ! -type f ! -type l -print -quit)"
[[ -z "$special_entry" ]] || {
  printf 'special filesystem entry in package: %s\n' "${special_entry#"$ROOT/"}" >&2
  exit 1
}

expected_inventory="$TMP_ROOT/expected.txt"
actual_inventory="$TMP_ROOT/actual.txt"
expected_directories="$TMP_ROOT/expected-directories.txt"
actual_directories="$TMP_ROOT/actual-directories.txt"
if [[ -f "$ROOT/usr/share/doc/live-for-speed-linux/copyright" ]]; then
  cat >"$expected_inventory" <<'EOF'
usr/bin/lfs-linux
usr/bin/lfs-linux-desktop
usr/lib/lfs-linux/lfs-linux-core
usr/share/applications/io.github.mitzracing.live_for_speed_linux.desktop
usr/share/doc/live-for-speed-linux/ARCHITECTURE.md
usr/share/doc/live-for-speed-linux/LEGAL.md
usr/share/doc/live-for-speed-linux/MAINTENANCE.md
usr/share/doc/live-for-speed-linux/TROUBLESHOOTING.md
usr/share/doc/live-for-speed-linux/changelog.Debian.gz
usr/share/doc/live-for-speed-linux/copyright
usr/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg
usr/share/lfs-linux/arch-wine-peter-jung.pgp
usr/share/lfs-linux/lfs-0.8C20-seed.manifest
usr/share/lfs-linux/lfs-0.8C20-stock.manifest
usr/share/lfs-linux/lfs-0.8C24-nested.manifest
usr/share/lfs-linux/lfs-0.8C24-seed.manifest
usr/share/lfs-linux/lfs-0.8C24-stock.manifest
usr/share/lfs-linux/release.env
usr/share/lfs-linux/wine-11.15-1-runtime.manifest
usr/share/lintian/overrides/live-for-speed-linux
usr/share/man/man1/lfs-linux-desktop.1.gz
usr/share/man/man1/lfs-linux.1.gz
usr/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml
EOF
  cat >"$expected_directories" <<'EOF'
usr
usr/bin
usr/lib
usr/lib/lfs-linux
usr/share
usr/share/applications
usr/share/doc
usr/share/doc/live-for-speed-linux
usr/share/icons
usr/share/icons/hicolor
usr/share/icons/hicolor/scalable
usr/share/icons/hicolor/scalable/apps
usr/share/lfs-linux
usr/share/lintian
usr/share/lintian/overrides
usr/share/man
usr/share/man/man1
usr/share/metainfo
EOF
else
  cat >"$expected_inventory" <<'EOF'
usr/bin/lfs-linux
usr/bin/lfs-linux-desktop
usr/lib/lfs-linux/lfs-linux-core
usr/share/applications/io.github.mitzracing.live_for_speed_linux.desktop
usr/share/doc/live-for-speed-linux/ARCHITECTURE.md
usr/share/doc/live-for-speed-linux/LEGAL.md
usr/share/doc/live-for-speed-linux/MAINTENANCE.md
usr/share/doc/live-for-speed-linux/TROUBLESHOOTING.md
usr/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg
usr/share/lfs-linux/arch-wine-peter-jung.pgp
usr/share/lfs-linux/lfs-0.8C20-seed.manifest
usr/share/lfs-linux/lfs-0.8C20-stock.manifest
usr/share/lfs-linux/lfs-0.8C24-nested.manifest
usr/share/lfs-linux/lfs-0.8C24-seed.manifest
usr/share/lfs-linux/lfs-0.8C24-stock.manifest
usr/share/lfs-linux/release.env
usr/share/lfs-linux/wine-11.15-1-runtime.manifest
usr/share/licenses/live-for-speed-linux/LICENSE
usr/share/man/man1/lfs-linux-desktop.1
usr/share/man/man1/lfs-linux.1
usr/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml
EOF
  cat >"$expected_directories" <<'EOF'
usr
usr/bin
usr/lib
usr/lib/lfs-linux
usr/share
usr/share/applications
usr/share/doc
usr/share/doc/live-for-speed-linux
usr/share/icons
usr/share/icons/hicolor
usr/share/icons/hicolor/scalable
usr/share/icons/hicolor/scalable/apps
usr/share/lfs-linux
usr/share/licenses
usr/share/licenses/live-for-speed-linux
usr/share/man
usr/share/man/man1
usr/share/metainfo
EOF
fi
find "$ROOT" \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort >"$actual_inventory"
cmp "$expected_inventory" "$actual_inventory" || {
  printf 'package file/symlink inventory differs from the exact allowlist\n' >&2
  exit 1
}
find -P "$ROOT" -mindepth 1 -type d -printf '%P\n' | LC_ALL=C sort >"$actual_directories"
cmp "$expected_directories" "$actual_directories" || {
  printf 'package directory inventory differs from the exact allowlist\n' >&2
  exit 1
}

if [[ ! -f "$ROOT/usr/share/licenses/live-for-speed-linux/LICENSE" &&
      ! -f "$ROOT/usr/share/doc/live-for-speed-linux/copyright" ]]; then
  printf 'missing installed wrapper license\n' >&2
  exit 1
fi
if [[ ! -f "$ROOT/usr/share/man/man1/lfs-linux.1" &&
      ! -f "$ROOT/usr/share/man/man1/lfs-linux.1.gz" ]]; then
  printf 'missing lfs-linux manual page\n' >&2
  exit 1
fi

if find "$ROOT" -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.msi' \) -print -quit | grep -q .; then
  printf 'Windows payload found in wrapper package\n' >&2
  exit 1
fi

if grep -R -Il '/home/' "$ROOT/usr" | grep -q .; then
  printf 'build-host home path found in installed wrapper payload\n' >&2
  exit 1
fi

size="$(du -sb "$ROOT" | awk '{print $1}')"
(( size < 2097152 )) || { printf 'wrapper package unexpectedly exceeds 2 MiB: %s bytes\n' "$size" >&2; exit 1; }
printf '[PASS] staged package contains only small, relocatable wrapper artifacts (%s bytes)\n' "$size"
