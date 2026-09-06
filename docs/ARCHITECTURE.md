# Architecture

## Goal

Install and play the official Live for Speed build on Linux. Updates inside LFS must survive updater restart, full exit, and later application-menu launch. Downloaded packages and supported software-store packages use the same desktop entry and controller.

## Runtime path

```text
application menu
  -> /usr/bin/lfs-linux-desktop
  -> /usr/bin/lfs-linux
  -> /usr/lib/lfs-linux/lfs-linux-core (foreground launch lock)
  -> audited Wine 11.15-1 (exact system package or private verified extraction)
  -> LFS.exe
  -> private DXVK d3d11.dll + dxgi.dll
  -> host Vulkan driver
```

The shell controller handles installation, compatibility repair, and Help. Core events use a separate file descriptor. Detailed output stays in private logs. Each setup worker has its own process group; cancellation cannot signal an unrelated Wine session.

The wrapper verifies the official NSIS archive and every pinned nested archive before extraction. It rejects unsafe paths, links, unsupported types, and duplicate archive members. It does not execute the installer stub. Nested archives run in audited sorted order in disposable staging; later archives intentionally replace earlier seed entries. The complete seed manifest validates the final bytes before first installation.

On later launches, the controller checks components and closes progress as gameplay starts. A foreground shell holds the launch lock and waits for private Wine processes. It keeps waiting when the updater restarts LFS. If non-game Wine services do not settle after the grace period, it leaves them running and reports the failure. The GUI can offer to close the previous session; the CLI equivalent is `lfs-linux stop`. Launch never performs automatic prefix-wide termination.

During gameplay, the controller waits for the core. Neither performs rendering, translation, game-file inventory scans, or wrapper network requests. No daemon, container, Steam client, Bottles process, or web UI enters the game data path.

## Graphical views

`libexec/lfs-linux-ui` owns both views and all worker decisions. GTK is the default when available. `LFS_LINUX_UI=zenity` selects Zenity. `LFS_LINUX_UI=gtk` requires GTK.

The GTK view keeps the community logo, current action, checklist, and Details in one window. Download progress uses the partial file's actual size. Verification and extraction use an indeterminate indicator.

The controller owns one GTK process and a private Unix socket. The socket uses mode 0600; its directory uses mode 0700. Newline-delimited JSON frames have a 64 KiB limit. The view renders fixed dialog requests and returns button responses. It does not run installer commands or modify player files.

Core events on FD 3 include `stage`, `phase`, `download-start`, `download-end`, `error`, and `launched`. Download events contain a cache filename, byte total, and component name. The controller samples only active partial downloads.

Initial GTK failure selects Zenity before an operation starts. Later view failure never replays an operation through another view. Cancellation stops only the owned setup process group. Closing progress never kills a launch. GTK stops at gameplay handoff; the controller can open a new view if an operation fails.

## State ownership

| Data | Default path | Owner |
|---|---|---|
| Wine prefix and installed game | `~/.local/share/lfs-linux/prefix` | LFS and Wine |
| Runtime configuration marker | `~/.local/share/lfs-linux/install.env` | wrapper, written during setup |
| Legacy update manifests and session records | `~/.local/share/lfs-linux/game-update*.manifest`, `launch-session.env` | retained, ignored by launch and setup |
| Audited Wine runtime and private DXVK | `~/.local/share/lfs-linux/runtime` | wrapper |
| Download and shader cache | `~/.cache/lfs-linux` | wrapper and DXVK |
| Runtime logs | `~/.local/state/lfs-linux` | wrapper and DXVK |
| Launch lock | `$XDG_RUNTIME_DIR/lfs-linux-$UID` | wrapper |

The package manager owns files under `/usr`, not user state. Package removal does not delete player data. Explicit `lfs-linux remove` needs confirmation before deleting the prefix, runtime, and known legacy records.

## Compatibility and trust

The prefix is 64-bit. Audited Arch Wine 11.15-1 uses pure WoW64 and supports the 32-bit game. Setup uses that exact system package or downloads the immutable Arch package and detached signature. It checks the pinned packager key, exact signer fingerprint, archive, and every runtime file or link before executing Wine. Other Wine versions fail closed.

LFS 0.8C20 imports D3D11 and DXGI. The wrapper installs audited DXVK `x32/d3d11.dll` and `x32/dxgi.dll` in `syswow64`, with native-first overrides only for its launches. Component repair removes the obsolete private `d3d9.dll` and override from v0.1.6. The prefix disables `mscoree` and `mshtml` to prevent optional Mono or Gecko downloader dialogs. Launch passes `/windowed=yes`; `Shift+F4` changes mode inside LFS.

`share/lfs-linux/release.env` pins bootstrap URLs, sizes, archives, executable, representative assets, tree metrics, and manifest digests. The nested manifest covers all 52 inner archives; the complete seed covers all 4,847 extracted official 0.8C20 files. These are **first-install input checks**, not rules for an installed game. The Wine inventory and DXVK digests still gate execution of wrapper-owned compatibility components.

Installed game files belong to LFS and the user. Launch checks that `LFS.exe` is regular, readable, nonempty, and not a symlink, but does not hash the executable or scan the game tree. Changes, added files, removed assets, skins, and absent version markers do not require wrapper approval. This does not authenticate an installed game or prove its completeness. The game supplies its actual version and gameplay result.

The owner-only launch-lock directory and regular file are validated before opening without truncation. Unsafe ownership, permissions, or symlinks fail closed. Prefix process checks require both the private `WINEPREFIX` and a Wine/Windows process identity; unrelated native helpers are ignored. Wine is not a sandbox: it has the user's filesystem authority.

## Installation and updates

- No game directory: verify and extract the bootstrap privately, then activate it without replacing an existing destination.
- Existing usable executable: keep the entire game directory, including changed stock, player files and links. Repair only compatibility components.
- Existing incomplete or linked game executable: stop before game-file mutation and offer Help. Do not install an older bootstrap over a partially updated game.
- Legacy swap backup with no current tree: restore the backup. If both trees exist, keep both; do not select one by fingerprint or delete either automatically.

The wrapper creates no post-exit game manifest or pending launch record. Old records neither block play nor get migrated. `recover-update` remains a non-mutating compatibility notice; the desktop action uses normal launch. A Wine wait failure cannot leave a new fingerprint requirement behind.

`update-check` is an optional read-only maintainer command. It compares stable and public-test channels, returns 0 for matching pins and 2 for reviewed-page drift, and never enters normal launch. Scheduled automation creates a bounded maintenance issue; it cannot change pins or publish. Maintainers test clean extraction, existing-game preservation, update/relaunch, and actual gameplay before accepting new pins.

## Verification boundary

All project GUI checks use owned Xephyr display `:111` with its Xauthority file. Software rendering and fixture workers prove controller/widget behavior, not native GPU, audio, storefront installation, or LFS gameplay. Exact-package desktop tests and an owner-accepted real update/relaunch remain publication gates. Native Wayland and report Save require separate desktop checks.
