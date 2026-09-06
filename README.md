# Live for Speed Linux

Unofficial community Linux launcher for the untouched official [Live for Speed](https://www.lfs.net/) Windows build.

**Mission:** get LFS running in a few clicks, then get out of its way. The wrapper owns setup and compatibility; LFS owns game files and updates. Updates must survive restart, full exit, and later launch without wrapper approval.

**Status:** [v0.4.0 public-test release](https://github.com/mitzracing/live-for-speed-linux/releases/tag/v0.4.0). Manual acceptance checks remain open; see [release status](docs/RELEASE-CANDIDATE.md). No software-store listing is available. The core works without Steam, Bottles, Lutris, or a background launcher.

This release bootstraps exact official **LFS 0.8C20 new graphics**, which lfs.net still labels **PUBLIC TEST**. It is not represented as a stable LFS release. Use immutable [v0.1.6](https://github.com/mitzracing/live-for-speed-linux/releases/tag/v0.1.6) for the audited old-graphics 0.7G fallback.

This project is not affiliated with or endorsed by the Live for Speed developers.

Project website: <https://mitzracing.github.io/live-for-speed-linux/>

The public package is `live-for-speed-linux`. The stable command and player-state paths keep the `lfs-linux` name for compatibility.

## What it does

- Downloads LFS directly from `lfs.net` after the player confirms graphical setup.
- Verifies the official archive and all 52 nested archives, extracts without executing the installer, and checks every official seed file before first installation.
- Authenticates the pinned Wine package with its detached Arch packager signature, then creates one private Wine prefix under the XDG data directory.
- Deploys only DXVK's audited 32-bit D3D11 and DXGI DLLs required by LFS 0.8C20.
- Starts Wine directly with no wrapper daemon or container.
- Lets LFS manage its installed files and updates; no game fingerprint, version-marker gate, or update approval on later launches.
- Keeps an updater-restarted LFS process alive and records diagnostic launch events.
- Preserves game-owned settings, profiles, replays, unlock state, and cache.
- Detects official download-page changes without editing game files.

## What it does not do

- Redistribute LFS binaries or proprietary assets
- Patch `LFS.exe`, cars, tracks, shaders, textures, or configuration
- Store account credentials
- Unlock licensed content
- Download or apply game updates itself; LFS owns its in-game updater
- Authenticate or certify the contents of an already installed game
- Claim official LFS support for Linux

## One-click setup

Install the wrapper package, then open **Live for Speed Linux** from the application menu. The graphical first launch shows the download size and public-test notice. Choose **Install and play**; progress names the active stage, interrupted downloads resume, and LFS opens when preparation finishes. Later clicks open the installed game.

Accept updates inside LFS, follow its restart prompt, then reopen normally after closing. No wrapper update approval or rebaseline is needed. Downloaded packages and supported software-store packages use this same launcher flow.

The same icon offers repair of compatibility components when needed. Repair keeps your entire existing game and all player files; it does not replace them with the older bootstrap. Right-click the icon for **Help and Diagnostic Report** to preview a small report and optionally save it or open support.

No game payload is bundled with the wrapper package. Immutable [v0.1.6](https://github.com/mitzracing/live-for-speed-linux/releases/tag/v0.1.6) remains available as the audited old-graphics LFS 0.7G fallback.

## Commands

```text
lfs-linux setup         Optional interactive terminal setup
lfs-linux install       Install or repair verified upstream runtime files
lfs-linux launch        Check compatibility components and start LFS
lfs-linux recover-update  Legacy command; updates need no wrapper recovery
lfs-linux stop          Stop only this private Wine prefix
lfs-linux doctor        Check host and installation state
lfs-linux status        Show versions and paths
lfs-linux update-check  Compare pins with the official downloads page
lfs-linux verify-sources  Fully download and verify pinned release inputs
lfs-linux purge-cache   Remove wrapper download and shader caches
lfs-linux remove        Remove per-user prefix after explicit confirmation
```

## Requirements

- Linux x86_64
- Audited Wine 11.15-1 (the wrapper provisions the pinned Arch runtime when that exact system package is unavailable)
- Vulkan-capable GPU and driver
- Bash, 7-Zip, curl, `gpgv`, GNU core utilities, findutils, libarchive (`bsdtar`), tar, and util-linux
- GTK 4.10 or later and Python/PyGObject for branded setup and help (installed by the package)
- Zenity for the selectable fallback (installed by the package)

The audited Arch Wine runtime uses pure WoW64. This lets its x86_64 package run the 32-bit LFS executable without the traditional 32-bit Unix Wine stack. Other Wine versions fail closed instead of being accepted by a broad compatibility range.

## Install from source

```bash
make test
sudo make install
lfs-linux install
lfs-linux launch
```

System installation needs root because it writes under `/usr`. Game installation is user-local and must not use root.

## Arch and Manjaro

A publish-ready package recipe is in [`packaging/aur/`](packaging/aur/README.md). After publication, Pamac users can find `live-for-speed-linux` when AUR support is enabled.

The AUR package contains only this open-source wrapper. It does not contain the game installer or game files.

## Debian and Ubuntu

[Download the 0.4.0 public-test `.deb`](https://github.com/mitzracing/live-for-speed-linux/releases/download/v0.4.0/live-for-speed-linux_0.4.0-0github1_amd64.deb) for Debian 13 or Ubuntu 24.04. Open it with a graphical package installer, then open **Live for Speed Linux** from the application menu.

Package and container checks passed. Exact graphical installer and real updated-game acceptance remain open; this is a testing release, not a verified software-store route. See [release status](docs/RELEASE-CANDIDATE.md).

Advanced APT instructions and deterministic builds are documented in [Debian packaging](packaging/debian/README.md).

The package does not contain the game, Wine, DXVK, or player data. It installs no proprietary payload and downloads nothing during package installation. See [`packaging/debian/`](packaging/debian/README.md) for the support boundary, deterministic build, removal behavior, and repository-publication distinction.

The `.deb` is a direct GitHub download, not a Debian archive or PPA. It cannot appear in GNOME Software or KDE Discover by itself. AppStream and desktop metadata include the `Game`, `Simulation`, and `SportsGame` categories and `games`, `racing`, and `simulator` search terms; graphical catalog discovery begins only after the package is accepted into a configured Debian archive. The pinned private Wine runtime requires glibc 2.38 or newer, so Ubuntu 22.04 and Debian 12 are not supported.

The package name uses the full game name to avoid confusion with Linux From Scratch. Existing scripts can continue to use the `lfs-linux` command.

## Separate launcher, small patches

This project is not a fork. Most upstream updates change one audited manifest and then run the existing clean-install checks.

Contributors do not need game source, a private build server, or a full-time service. See [`docs/MAINTENANCE.md`](docs/MAINTENANCE.md).

## Low-overhead architecture

```text
lfs-linux -> audited Wine 11.15-1 -> stock LFS.exe -> private DXVK d3d11/dxgi -> host Vulkan driver
```

No Bottles process, Steam client, Gamescope session, web UI, or update request exists in the hot path. Shader cache persists between launches.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for state paths and performance boundaries.

## Updates

Use LFS's in-game updater. After its restart, play and close normally. Open **Live for Speed Linux** again to continue. The version shown inside LFS is authoritative; bootstrap pins describe new installations only.

Optional maintainer check:

```bash
lfs-linux update-check
```

The command reports the official stable and public-test/new-graphics channels separately. A newer public test or changed installer returns status 2 for maintainer review. It never modifies LFS and does not control whether an installed game may launch.

There is no background checker in the launch path. The weekly repository workflow treats status 2 as an expected maintenance event: it checks whether the pinned bootstrap URL remains available, creates or refreshes one deduplicated GitHub issue, and leaves the run green with a warning. Downloads-page, script, or GitHub API failures remain red; an inconclusive supplemental installer-header probe is reported as unknown. Maintainers update release pins only after a clean extraction, audit, existing-game preservation check, and live run. See [`docs/RELEASING.md`](docs/RELEASING.md).

## Flathub

Current Flathub policy accepts Wine-based Windows applications only as official upstream submissions. This project will not submit an unauthorized manifest.

[`docs/FLATHUB.md`](docs/FLATHUB.md) defines the authorization gate and proposal path.

## Help and feedback

Players can use the plain-language browser form on the [project website](https://mitzracing.github.io/live-for-speed-linux/#support) or the direct forms in [`SUPPORT.md`](SUPPORT.md). The browser removes known private-data patterns before it opens a prefilled GitHub Issue Form. A GitHub account is required. No external form service stores reports.

Automation classifies each ticket. Reproducible, sanitized bugs and compatibility reports enter the [`help wanted` contributor queue](https://github.com/mitzracing/live-for-speed-linux/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22+-label%3A%22status%3Apossible-sensitive%22). Feature requests wait for a maintainer scope decision. Suspected-sensitive reports stay out of contributor work until reviewed.

Never attach passwords, unlock codes, Wine registry files, full home paths, or proprietary game assets to an issue.

## Contributing

Select a ticket from the contributor queue, comment before implementation, and open a pull request with `Closes #NUMBER`. Read [`CONTRIBUTING.md`](CONTRIBUTING.md), [`docs/TRIAGE.md`](docs/TRIAGE.md), [`docs/LEGAL.md`](docs/LEGAL.md), and [`SECURITY.md`](SECURITY.md).

## License

Wrapper code: MIT.

Live for Speed: proprietary, governed by its own [terms](https://www.lfs.net/agreement).

DXVK: Zlib license, downloaded from its official release page.
