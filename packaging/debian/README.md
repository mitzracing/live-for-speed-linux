# Debian and Ubuntu package

The deterministic `.deb` contains only the MIT-licensed launcher, manifests, desktop metadata, and documentation. It does not contain Live for Speed, Wine, DXVK, Windows executables, or player data. Runtime payloads are downloaded from their pinned upstream URLs only after an explicit user command.

## Supported distributions

The release gate covers x86-64 installations on:

- Ubuntu 24.04 LTS
- Debian 13

The pinned Wine 11.15 runtime requires glibc 2.38 or newer. Ubuntu 22.04 and Debian 12 are therefore not supported by this package.

## Install

Install the local release asset with APT so its amd64 Wine and Vulkan host dependencies are resolved. The audited private Wine 11.15 runtime uses pure WoW64, so this package does not require an i386 Unix library stack.

```bash
sudo apt update
sudo apt install ./live-for-speed-linux_0.3.1-1_amd64.deb
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

A GitHub release `.deb` is a direct-download package, not a Debian archive, PPA, or graphical software-catalog listing. Publishing through one of those channels requires separate repository ownership, review, signing, and explicit approval. The package must never embed or redistribute proprietary upstream payloads.
