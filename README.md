# Live for Speed Linux

Unofficial community Linux launcher for the untouched official [Live for Speed](https://www.lfs.net/) Windows build.

**Status:** v0.3.0 public-test source release. The validated AUR recipe awaits maintainer SSH access. The core works without Steam, Bottles, Lutris, or a background launcher.

This release bootstraps exact official **LFS 0.8C20 new graphics**, which lfs.net still labels **PUBLIC TEST**. It is not represented as a stable LFS release. Use immutable [v0.1.6](https://github.com/mitzracing/live-for-speed-linux/releases/tag/v0.1.6) for the audited old-graphics 0.7G fallback.

This project is not affiliated with or endorsed by the Live for Speed developers.

Project website: <https://mitzracing.github.io/live-for-speed-linux/>

The public package is `live-for-speed-linux`. The stable command and player-state paths keep the `lfs-linux` name for compatibility.

## What it does

- Downloads LFS directly from `lfs.net` after an explicit user command.
- Verifies the official archive and all 52 nested archives, extracts without executing the installer, checks every official seed file, then tracks protected stock separately from mutable player data.
- Creates one private Wine prefix and uses only audited Wine 11.15-1 under the XDG data directory.
- Deploys only DXVK's audited 32-bit D3D11 and DXGI DLLs required by LFS 0.8C20.
- Starts Wine directly with no wrapper daemon or container.
- Records a versioned in-game update after the trusted LFS session exits, then verifies that local baseline on later launches.
- Preserves game-owned settings, profiles, replays, unlock state, and cache.
- Detects official download-page changes without editing game files.

## What it does not do

- Redistribute LFS binaries or proprietary assets
- Patch `LFS.exe`, cars, tracks, shaders, textures, or configuration
- Store account credentials
- Unlock licensed content
- Download or apply game updates itself; LFS owns its in-game updater
- Trust protected-file changes made outside a validated LFS session
- Claim official LFS support for Linux

## One-click setup

After installing the wrapper package, open **Live for Speed Linux** from the application menu. First launch explains that LFS 0.8C20 is a public test, shows the approximately 1.7 GB official download, verifies the LFS, Wine, and DXVK inputs, configures the private prefix, and starts LFS. Later launches go directly to the game.

If LFS updates itself during a validated session, the foreground wrapper waits for all private-prefix processes to exit. A newer game version marker allows it to record the resulting protected-file inventory as a local baseline. Next-day desktop launch verifies and starts that updated game without an old-version setup prompt, downgrade, full redownload, or matching wrapper release. Protected-file changes made outside that trusted session still fail closed.

No game payload is bundled with the wrapper package. Immutable [v0.1.6](https://github.com/mitzracing/live-for-speed-linux/releases/tag/v0.1.6) remains available as the audited old-graphics LFS 0.7G fallback.

## Commands

```text
lfs-linux setup         Interactive first-run setup used by the desktop launcher
lfs-linux install       Install or repair verified upstream runtime files
lfs-linux launch        Validate pins and start LFS
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
- Bash, 7-Zip, curl, GNU core utilities, findutils, libarchive (`bsdtar`), tar, and util-linux
- A supported terminal for graphical first-run setup (`xterm` is the AUR default)

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

## Other distributions

The core uses standard shell tools and a native Wine runtime. Distribution packages install files from `Makefile`; they must provide exact Wine 11.15-1 or allow the wrapper to provision the pinned archived package privately.

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

Run:

```bash
lfs-linux update-check
```

The command reports the official stable and public-test/new-graphics channels separately. A newer public test or changed installer returns status 2 for maintainer review. It never modifies LFS and does not block a versioned update that LFS completed during a trusted session.

There is no background checker in the launch path. The weekly repository workflow treats status 2 as an expected maintenance event: it checks whether the pinned bootstrap URL remains available, creates or refreshes one deduplicated GitHub issue, and leaves the run green with a warning. Downloads-page, script, or GitHub API failures remain red; an inconclusive supplemental installer-header probe is reported as unknown. Maintainers update release pins only after a clean extraction, audit, migration drill, and live run. See [`docs/RELEASING.md`](docs/RELEASING.md).

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
