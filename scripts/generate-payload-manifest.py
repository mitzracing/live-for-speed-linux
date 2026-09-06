#!/usr/bin/env python3
"""Generate deterministic file/link manifests for Live for Speed Linux payloads."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath

PLAYER_OWNED_PREFIXES = (
    "cache/",
    "mods/",
    "data/colours/",
    "data/grids/",
    "data/layout/",
    "data/knw/",
    "data/misc/",
    "data/move/",
    "data/mpr/",
    "data/raf/",
    "data/script/",
    "data/setups/",
    "data/settings/",
    "data/shots/",
    "data/skins/",
    "data/skins_x/",
    "data/skins_y/",
    "data/spr/",
    "data/training/",
    "data/views/",
)
PLAYER_OWNED_FILES = {
    "card_cfg.txt",
    "cfg.txt",
    "deb.log",
    "deb_old.log",
    "guest.txt",
    "interface_cfg.txt",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def include_path(profile: str, relative: str, stock_skins: set[str] | None = None) -> bool:
    if profile == "wine":
        return relative.startswith("usr/")
    if profile == "lfs-seed":
        return True
    if stock_skins is not None and relative.startswith("data/skins_dds/") and relative.endswith(".dds"):
        return relative in stock_skins
    return relative not in PLAYER_OWNED_FILES and not (relative + "/").startswith(PLAYER_OWNED_PREFIXES)


def manifest_lines(root: Path, profile: str, stock_skins: set[str] | None = None) -> list[str]:
    entries: list[str] = []
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        if not include_path(profile, relative, stock_skins):
            continue
        PurePosixPath(relative)
        if path.is_symlink():
            entries.append(f"l\t{os.readlink(path)}\t-\t{relative}")
        elif path.is_file():
            entries.append(f"f\t{sha256(path)}\t{path.stat().st_size}\t{relative}")
    return entries


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("profile", choices=("lfs", "lfs-seed", "wine"))
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--stock-manifest", type=Path, help="Known stock inventory when inspecting a player tree; omit for a clean official seed")
    args = parser.parse_args()
    if args.stock_manifest and args.profile != "lfs":
        parser.error("--stock-manifest is only valid with the lfs profile")

    root = args.root.resolve()
    if not root.is_dir():
        raise SystemExit(f"payload root is not a directory: {root}")
    stock_skins = None
    if args.stock_manifest:
        stock_skins = {fields[3] for line in args.stock_manifest.read_text().splitlines()
                       if len(fields := line.split("\t")) == 4 and fields[0] == "f"
                       and fields[3].startswith("data/skins_dds/")}
    lines = manifest_lines(root, args.profile, stock_skins)
    if not lines:
        raise SystemExit("payload manifest would be empty")

    content = (
        "# lfs-linux payload manifest v1\n"
        "# type<TAB>sha256-or-link-target<TAB>size-or-dash<TAB>relative-path\n"
        + ("# lfs-linux ownership v2\n" if args.stock_manifest else "")
        + "\n".join(lines)
        + "\n"
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(args.output)
    print(f"{len(lines)} entries -> {args.output}")


if __name__ == "__main__":
    main()
