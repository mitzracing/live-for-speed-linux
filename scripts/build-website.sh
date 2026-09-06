#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly OUTPUT_DIR="${1:?Usage: build-website.sh NEW_OUTPUT_DIRECTORY}"

# Refuse existing output rather than retaining stale files or overwriting other work.
mkdir -- "$OUTPUT_DIR"
for path in index.html styles.css feedback.js assets/blackwood-rallycross.webp assets/README.md; do
  install -Dm644 -- "$ROOT_DIR/website/$path" "$OUTPUT_DIR/$path"
done
install -Dm644 -- "$ROOT_DIR/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg" "$OUTPUT_DIR/icon.svg"
