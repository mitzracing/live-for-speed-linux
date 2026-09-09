#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly OUTPUT_DIR="${1:?Usage: build-website.sh NEW_OUTPUT_DIRECTORY}"

# Refuse existing output rather than retaining stale files or overwriting other work.
mkdir -- "$OUTPUT_DIR"
for path in \
  index.html styles.css feedback.js installer-demo.js hero-slideshow.js \
  assets/lfs-gt3.webp assets/README.md \
  assets/lfs-open-wheel.webp assets/lfs-drift.webp \
  assets/lfs-blackwood.webp assets/lfs-cockpit.webp assets/lfs-roadsters.webp \
  assets/spacegrotesk.woff2 assets/spacegrotesk-OFL.txt \
  assets/installer-demo.webm assets/installer-demo.mp4 assets/installer-poster.webp; do
  install -Dm644 -- "$ROOT_DIR/website/$path" "$OUTPUT_DIR/$path"
done
install -Dm644 -- "$ROOT_DIR/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg" "$OUTPUT_DIR/icon.svg"
