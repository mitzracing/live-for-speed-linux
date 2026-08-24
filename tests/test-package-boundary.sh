#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="${1:-}"
[[ -n "$ROOT" && -d "$ROOT" ]] || { printf 'Usage: %s STAGED_PACKAGE_ROOT\n' "$0" >&2; exit 2; }

for path in \
  usr/bin/lfs-linux \
  usr/bin/lfs-linux-desktop \
  usr/lib/lfs-linux/lfs-linux-core \
  usr/share/lfs-linux/release.env \
  usr/share/lfs-linux/lfs-0.8C20-stock.manifest \
  usr/share/lfs-linux/lfs-0.8C20-seed.manifest \
  usr/share/lfs-linux/lfs-0.8C20-nested.manifest \
  usr/share/lfs-linux/lfs-0.8C19-stock.manifest \
  usr/share/lfs-linux/lfs-0.8C19-seed.manifest \
  usr/share/lfs-linux/wine-11.15-1-runtime.manifest \
  usr/share/applications/io.github.mitzracing.live_for_speed_linux.desktop \
  usr/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml \
  usr/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg \
  usr/share/licenses/live-for-speed-linux/LICENSE; do
  [[ -e "$ROOT/$path" ]] || { printf 'missing package file: %s\n' "$path" >&2; exit 1; }
done

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
