#!/usr/bin/env bash
# Prepare unsigned AppStream catalog files for review, without publishing a repository.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/artifacts/catalog-candidate}"
STAGING="$(mktemp -d /tmp/lfs-catalog.XXXXXX)"
trap 'rm -rf -- "$STAGING"' EXIT
make -C "$ROOT_DIR" DESTDIR="$STAGING" PREFIX=/usr install >/dev/null
python3 - "$STAGING/usr/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
tree = ET.parse(path)
ET.SubElement(tree.getroot(), "pkgname").text = "live-for-speed-linux"
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
mkdir -p "$OUTPUT_DIR"
appstreamcli compose --no-net --origin=lfs-linux-candidate --result-root="$OUTPUT_DIR" "$STAGING"
printf 'Prepared catalog for review: %s\nNo package repository was configured, signed, or published.\n' "$OUTPUT_DIR"
