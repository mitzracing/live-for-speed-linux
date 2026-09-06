# Debian and Ubuntu package

The deterministic `.deb` contains only the MIT-licensed launcher, GPL-3.0-or-later public signing certificate, manifests, desktop metadata, and documentation. It does not contain Live for Speed, Wine, DXVK, Windows executables, or player data. Runtime payloads are downloaded from their pinned upstream URLs only after an explicit user command.

## Supported distributions

The release gate covers x86-64 installations on:

- Ubuntu 24.04 LTS
- Debian 13

The pinned Wine 11.15 runtime requires glibc 2.38 or newer. Ubuntu 22.04 and Debian 12 are therefore not supported by this package.

## Install

The 0.4.0 public test uses native graphical setup. Open its `.deb` with a graphical package installer, then open **Live for Speed Linux** from the application menu. Choose **Install and play**. Game setup, retry, compatibility repair, and Help require no terminal.

The owner approved public-test downloads with manual acceptance checks open. This does not certify graphical dependency installation or gameplay. The default Ubuntu App Center, GNOME Software, KDE Discover, and GDebi are distinct routes; record exactly which one was tested before advertising it as verified. See `docs/RELEASE-CANDIDATE.md`.

The package provisions the exact private Wine runtime, independent of any system Wine package. Pure WoW64 requires no i386 Unix library stack. Package installation itself downloads no game files.

### Advanced command-line installation

```bash
sudo apt install ./live-for-speed-linux_0.4.0-0github1_amd64.deb
```

Then open the game icon. Per-user launcher commands must never run as root.

## Build and verify

On Debian or Ubuntu:

```bash
./packaging/debian/build-deb.sh dist
make deb-check
```

The build uses a fixed `SOURCE_DATE_EPOCH`, root-owned archive entries, and deterministic xz compression. `tests/test-debian-package.sh` builds twice, compares hashes, validates control metadata, extracts the data archive, and applies the proprietary-payload boundary check.

`./packaging/debian/build-catalog.sh` composes a local AppStream collection and
icons from the staged package tree. It requires AppStream's compose tool and
Python 3. Review this output alongside the package; the command configures no
repository, generates no signing keys, and publishes nothing.

## Remove

```bash
sudo apt remove live-for-speed-linux
```

Normal package removal deletes only files managed under `/usr`. User profiles, settings, replays, mods, game files, caches, and local update baselines remain under the user's XDG directories. Use `lfs-linux remove` and `lfs-linux purge-cache` before removing the package only when those user-owned files should also be deleted.

## Publication boundary

A GitHub release `.deb` is a direct-download package, not a Debian archive, PPA, or graphical software-catalog listing. AppStream and desktop metadata provide `Game`, `Simulation`, and `SportsGame` categories plus `games`, `racing`, and `simulator` search terms, but GNOME Software and KDE Discover can index them only after this package enters a configured archive. Publishing through one of those channels requires separate repository ownership, review, signing, and explicit approval. The package must never embed or redistribute proprietary upstream payloads.
