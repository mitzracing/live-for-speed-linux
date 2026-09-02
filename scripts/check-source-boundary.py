#!/usr/bin/env python3
"""Fail closed when a wrapper source archive would include binary payloads."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import stat
import sys

MAX_SOURCE_BYTES = 4 * 1024 * 1024
ALLOWED_BINARY_HASHES = {
    "share/lfs-linux/arch-wine-peter-jung.pgp": "c3186f2f7bdbe1cd02002dc84bce781580e4edc49fdc3ad848096af6768f3a89",
    "tests/fixtures/runtime-trust/combined-keys.pgp": "b479b43482b9fd4c1cb87437ccc669b3940697cd7e76aebd5d175d2ac247789a",
    "tests/fixtures/runtime-trust/valid.sig": "b1bf25dc93f3a3428d7f98a8df161568af5685c6c9fe577af928a053c561c2bb",
    "tests/fixtures/runtime-trust/wrong.sig": "c947aab85a8c6e0f2caaafeefae35c7fb87043776fad4a5f04bf60cf1a5fa471",
}
PROHIBITED_SUFFIXES = (
    ".7z",
    ".a",
    ".apk",
    ".appimage",
    ".bz2",
    ".cab",
    ".class",
    ".deb",
    ".dll",
    ".dmg",
    ".exe",
    ".gz",
    ".img",
    ".iso",
    ".jar",
    ".lz",
    ".lzma",
    ".msi",
    ".o",
    ".rar",
    ".rpm",
    ".so",
    ".tar",
    ".tbz",
    ".tgz",
    ".txz",
    ".wasm",
    ".xz",
    ".zip",
    ".zst",
)
MAGIC_PREFIXES = {
    b"\x7fELF": "ELF",
    b"MZ": "PE/Windows",
    b"7z\xbc\xaf\x27\x1c": "7z",
    b"PK\x03\x04": "ZIP",
    b"PK\x05\x06": "ZIP",
    b"PK\x07\x08": "ZIP",
    b"\x1f\x8b": "gzip",
    b"BZh": "bzip2",
    b"\xfd7zXZ\x00": "xz",
    b"\x28\xb5\x2f\xfd": "zstd",
    b"!<arch>\n": "ar/deb",
    b"Rar!\x1a\x07": "RAR",
    b"MSCF": "CAB",
}


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def selected_paths(root: Path, entries: list[str]) -> list[Path]:
    paths: list[Path] = []
    for entry in entries:
        candidate = root / entry
        if not candidate.exists() and not candidate.is_symlink():
            fail(f"source archive entry is missing: {entry}")
        candidates = [candidate]
        if candidate.is_dir() and not candidate.is_symlink():
            candidates.extend(candidate.rglob("*"))
        for path in candidates:
            relative = path.relative_to(root)
            if "__pycache__" in relative.parts or path.name.endswith((".pyc", ".pyo")):
                continue
            paths.append(path)
    return paths


def main() -> None:
    if len(sys.argv) < 3:
        fail(f"usage: {Path(sys.argv[0]).name} ROOT ENTRY...")
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        fail(f"source root is not a directory: {root}")
    paths = selected_paths(root, sys.argv[2:])
    regular_files: list[tuple[Path, str, int]] = []
    total_bytes = 0
    for path in paths:
        relative = path.relative_to(root).as_posix()
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if stat.S_ISLNK(mode):
            target = os.readlink(path)
            if os.path.isabs(target):
                fail(f"prohibited source payload: {relative} (absolute symlink)")
            resolved = (path.parent / target).resolve(strict=False)
            try:
                resolved.relative_to(root)
            except ValueError:
                fail(f"prohibited source payload: {relative} (escaping symlink)")
            continue
        if not stat.S_ISREG(mode):
            fail(f"prohibited source payload: {relative} (special filesystem entry)")
        size = path.stat().st_size
        total_bytes += size
        regular_files.append((path, relative, size))
    if total_bytes >= MAX_SOURCE_BYTES:
        fail(f"source payload boundary exceeds {MAX_SOURCE_BYTES} bytes: {total_bytes}")

    for path, relative, _size in regular_files:
        data = path.read_bytes()
        if relative in ALLOWED_BINARY_HASHES:
            digest = hashlib.sha256(data).hexdigest()
            if digest != ALLOWED_BINARY_HASHES[relative]:
                fail(f"prohibited source payload: {relative} (binary fixture checksum drift)")
            continue
        lowered = relative.casefold()
        suffix = next((item for item in PROHIBITED_SUFFIXES if lowered.endswith(item)), None)
        if suffix is not None:
            fail(f"prohibited source payload: {relative} ({suffix} file)")
        magic = next((label for prefix, label in MAGIC_PREFIXES.items() if data.startswith(prefix)), None)
        if magic is not None:
            fail(f"prohibited source payload: {relative} ({magic} magic)")
        if b"\x00" in data:
            fail(f"prohibited source payload: {relative} (unapproved binary data)")


if __name__ == "__main__":
    main()
