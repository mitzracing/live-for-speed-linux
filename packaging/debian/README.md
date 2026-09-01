# Debian and Ubuntu package

The deterministic `.deb` contains only the MIT-licensed launcher, GPL-3.0-or-later public signing certificate, manifests, desktop metadata, and documentation. It does not contain Live for Speed, Wine, DXVK, Windows executables, or player data. Runtime payloads are downloaded from their pinned upstream URLs only after an explicit user command.

## Supported distributions

The release gate covers x86-64 installations on:

- Ubuntu 24.04 LTS
- Debian 13

The pinned Wine 11.15 runtime requires glibc 2.38 or newer. Ubuntu 22.04 and Debian 12 are therefore not supported by this package.

## Install

Install the local release asset with APT so its audited amd64 host-library and Vulkan dependencies are resolved. The package does not depend on system Wine; it provisions the exact private Wine 11.15 runtime only after verifying its pinned digest and detached Arch packager signature. Pure WoW64 requires no i386 Unix library stack.

```bash
sudo apt update
sudo apt install ./live-for-speed-linux_0.3.2-0github1_amd64.deb
```

Then open **Live for Speed Linux** from the application menu or run:

```bash
lfs-linux install
lfs-linux launch
```

Package installation does not download or install the game. Never run `lfs-linux install` or `lfs-linux launch` as root.

## Build and verify

On Debian or Ubuntu:

```bash
./packaging/debian/build-deb.sh dist
make deb-check
```

The build uses a fixed `SOURCE_DATE_EPOCH`, root-owned archive entries, and deterministic xz compression. `tests/test-debian-package.sh` builds twice, compares hashes, validates control metadata, extracts the data archive, and applies the proprietary-payload boundary check.

## Remove

```bash
sudo apt remove live-for-speed-linux
```

Normal package removal deletes only files managed under `/usr`. User profiles, settings, replays, mods, game files, caches, and local update baselines remain under the user's XDG directories. Use `lfs-linux remove` and `lfs-linux purge-cache` before removing the package only when those user-owned files should also be deleted.

## Publication boundary

A GitHub release `.deb` is a direct-download package, not a Debian archive, PPA, or graphical software-catalog listing. AppStream and desktop metadata provide `Game`, `Simulation`, and `SportsGame` categories plus `games`, `racing`, and `simulator` search terms, but GNOME Software and KDE Discover can index them only after this package enters a configured archive. Publishing through one of those channels requires separate repository ownership, review, signing, and explicit approval. The package must never embed or redistribute proprietary upstream payloads.
