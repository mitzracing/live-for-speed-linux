#!/usr/bin/env python3
"""Fail closed if the final Debian package tree crosses the wrapper boundary."""

import hashlib
import os
import stat
import subprocess
import sys
from pathlib import Path

EXPECTED_FILES = {
    "usr/bin/lfs-linux",
    "usr/bin/lfs-linux-desktop",
    "usr/lib/lfs-linux/lfs-linux-core",
    "usr/share/applications/io.github.mitzracing.live_for_speed_linux.desktop",
    "usr/share/doc/live-for-speed-linux/ARCHITECTURE.md.gz",
    "usr/share/doc/live-for-speed-linux/LEGAL.md",
    "usr/share/doc/live-for-speed-linux/MAINTENANCE.md",
    "usr/share/doc/live-for-speed-linux/README.Debian",
    "usr/share/doc/live-for-speed-linux/TROUBLESHOOTING.md.gz",
    "usr/share/doc/live-for-speed-linux/changelog.Debian.gz",
    "usr/share/doc/live-for-speed-linux/copyright",
    "usr/share/doc/live-for-speed-linux/wine-runtime-audit.md.gz",
    "usr/share/icons/hicolor/scalable/apps/io.github.mitzracing.live_for_speed_linux.svg",
    "usr/share/lfs-linux/arch-wine-peter-jung.pgp",
    "usr/share/lfs-linux/lfs-0.8C19-seed.manifest",
    "usr/share/lfs-linux/lfs-0.8C19-stock.manifest",
    "usr/share/lfs-linux/lfs-0.8C20-nested.manifest",
    "usr/share/lfs-linux/lfs-0.8C20-seed.manifest",
    "usr/share/lfs-linux/lfs-0.8C20-stock.manifest",
    "usr/share/lfs-linux/release.env",
    "usr/share/lfs-linux/wine-11.15-1-runtime.manifest",
    "usr/share/lintian/overrides/live-for-speed-linux",
    "usr/share/man/man1/lfs-linux-desktop.1.gz",
    "usr/share/man/man1/lfs-linux.1.gz",
    "usr/share/metainfo/io.github.mitzracing.live_for_speed_linux.metainfo.xml",
}
EXPECTED_KEY_SHA256 = "c3186f2f7bdbe1cd02002dc84bce781580e4edc49fdc3ad848096af6768f3a89"
FORBIDDEN_FILE_DESCRIPTIONS = (
    "ELF ",
    "PE32",
    "MS-DOS executable",
    "Zip archive data",
    "7-zip archive data",
    "RAR archive data",
    "Microsoft Cabinet archive",
)


def fail(message: str) -> None:
    raise SystemExit(f"package boundary error: {message}")


def main() -> None:
    if len(sys.argv) != 2:
        fail(f"usage: {sys.argv[0]} STAGED_PACKAGE_ROOT")
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        fail(f"not a directory: {root}")

    actual = {
        path.relative_to(root).as_posix()
        for path in (root / "usr").rglob("*")
        if path.is_file() or path.is_symlink()
    }
    missing = sorted(EXPECTED_FILES - actual)
    extras = sorted(actual - EXPECTED_FILES)
    if missing or extras:
        fail(f"installed-file allowlist drift; missing={missing!r}; extras={extras!r}")

    metadata = root / "DEBIAN"
    if metadata.exists():
        unexpected_control = sorted(
            path.name
            for path in metadata.iterdir()
            if path.is_file() and path.name not in {"control", "md5sums"}
        )
        if unexpected_control:
            fail(f"maintainer scripts or triggers present: {unexpected_control!r}")

    for relative in sorted(actual):
        path = root / relative
        if path.is_symlink():
            continue
        result = subprocess.run(
            ["file", "--brief", "--", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )
        description = result.stdout.strip()
        if any(marker in description for marker in FORBIDDEN_FILE_DESCRIPTIONS):
            fail(f"binary or archive payload at {relative}: {description}")
        mode = stat.S_IMODE(path.stat().st_mode)
        if mode & 0o022:
            fail(f"group/world-writable installed file: {relative} ({mode:o})")

    signing_key = root / "usr/share/lfs-linux/arch-wine-peter-jung.pgp"
    if signing_key.stat().st_size != 1527:
        fail("Arch Wine signing key size drift")
    if hashlib.sha256(signing_key.read_bytes()).hexdigest() != EXPECTED_KEY_SHA256:
        fail("Arch Wine signing key digest drift")

    for relative in actual:
        if "/home/" in (root / relative).read_text(errors="ignore"):
            fail(f"build-host home path in installed payload: {relative}")

    apparent_size = sum(
        path.lstat().st_size
        for path in (root / "usr").rglob("*")
        if path.is_file() or path.is_symlink()
    )
    if apparent_size >= 2 * 1024 * 1024:
        fail(f"wrapper payload exceeds 2 MiB: {apparent_size} bytes")
    print(
        f"[PASS] final Debian package matches {len(EXPECTED_FILES)} reviewed files "
        f"and contains no executable/archive payload ({apparent_size} bytes)"
    )


if __name__ == "__main__":
    main()
