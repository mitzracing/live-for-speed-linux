# Architecture

## Goal

Run the untouched official Live for Speed build with low wrapper overhead on Linux.

## Runtime path

```text
application menu
  -> /usr/bin/lfs-linux-desktop (first-run decision, then exec)
  -> /usr/bin/lfs-linux
  -> /usr/lib/lfs-linux/lfs-linux-core (foreground launch lock and post-exit recorder)
  -> audited Wine 11.15-1 (exact system package or private verified extraction)
  -> LFS.exe
  -> private DXVK d3d11.dll + dxgi.dll
  -> host Vulkan driver
```

First-run setup uses a terminal only while downloading and installing. It verifies the official NSIS archive, rejects unsafe, linked, or duplicate archive members before extraction, extracts its outer payload and every pinned nested 7z payload without executing the installer stub, removes installer-only helper files, and verifies the resulting asset tree before installation. Nested archives run in audited sorted order inside disposable staging; later archives intentionally replace earlier seed entries, and the complete seed manifest validates the final bytes. On later launches, the desktop helper replaces itself with the direct launcher. One foreground shell process holds the launch lock, waits for all private Wine processes, and records a versioned LFS update after exit. If LFS's updater replaces the original process, the wrapper keeps waiting while the restarted game remains active. If non-game Wine services do not settle after a bounded grace period, launch fails closed, leaves them running, and retains recovery evidence; only explicit `lfs-linux stop` performs prefix-wide termination. It performs no rendering, translation, network request, or background polling. No wrapper daemon, container, Steam client, Bottles process, or web UI enters the game data path.

## State ownership

| Data | Default path | Owner |
|---|---|---|
| Wine prefix and official game | `~/.local/share/lfs-linux/prefix` | LFS and Wine |
| Recorded in-game update manifest | `~/.local/share/lfs-linux/game-update-<sha256>.manifest` | foreground wrapper after trusted LFS exit |
| Pending trusted-launch evidence | `~/.local/share/lfs-linux/launch-session.env` | foreground wrapper; removed after normal completion |
| Audited Wine runtime and private DXVK archive | `~/.local/share/lfs-linux/runtime` | wrapper |
| Download and shader cache | `~/.cache/lfs-linux` | wrapper and DXVK |
| Runtime logs | `~/.local/state/lfs-linux` | wrapper and DXVK |
| Launch lock | `$XDG_RUNTIME_DIR/lfs-linux-$UID` | wrapper |

The package manager owns only files under `/usr`. Package removal does not delete user data.

## Compatibility choices

The prefix is 64-bit. Audited Arch Wine 11.15-1 uses pure WoW64 and supports the 32-bit LFS executable. The wrapper accepts that exact package payload only. If the exact system package is unavailable, setup downloads its immutable Arch Linux Archive package and detached signature, verifies the package with the pinned Arch packager key and exact signer fingerprint, rejects unsafe archive members, extracts it privately, and validates every runtime file and link before executing Wine. Other Wine versions fail closed.

LFS 0.8C24 imports D3D11 and DXGI. The wrapper deploys audited DXVK `x32/d3d11.dll` and `x32/dxgi.dll` to `syswow64`, then sets native-first `d3d11` and `dxgi` overrides only for wrapper launches. Upgrade removes the obsolete private `d3d9.dll` and override from v0.1.6.

LFS does not use .NET or Wine's HTML engine. The prefix disables `mscoree` and `mshtml` so Wine never opens optional Mono or Gecko downloader dialogs during one-click setup.

The launcher always passes `/windowed=yes`. Users can switch modes in LFS with `Shift+F4`.

## Performance choices

- Direct native execution of the exact audited Wine runtime
- Direct host Vulkan loader and driver
- One D3D translation layer: DXVK
- No Gamescope or compositor wrapper by default
- Persistent DXVK shader cache
- Prefix-local processes only
- One idle foreground shell waits for exit; no daemon or hot-path translation work
- Full active-baseline validation before Wine starts
- Post-exit re-inventory only when LFS advances its version marker
- Bounded setup commands with prefix-scoped cleanup
- No wrapper update network request during launch
- No wrapper-owned game-file mutation

## Update model

`share/lfs-linux/release.env` is the audited bootstrap manifest. It pins upstream URLs, sizes, archive digests, the exact Wine package and detached signature, the Arch signer fingerprint and key digest, and all payload-manifest digests. The nested manifest validates each of the 52 inner LFS archives before extraction. A seed manifest then validates all 4,848 extracted official 0.8C24 files before installation. The packaged stock manifest covers every protected non-player file from that clean payload while allowing unlisted additions. Local update manifests additionally omit runtime-owned account/configuration files (`guest.txt`, `cfg.txt`, `interface_cfg.txt`, `card_cfg.txt`), debug logs, cache and downloaded-mod trees, downloaded/generated skin trees, AI knowledge, training content, profiles, setups, layouts, replays, screenshots, and similar mutable paths. Legacy C23 local manifests still inventory the shared `data/skins_dds` directory, so the C24 migration handles its downloaded files explicitly while retaining exact target stock. The Wine manifest covers every runtime file or link.

Before every launch, the wrapper fully validates either the packaged stock manifest or a recorded local game-update manifest. After validation, it writes an owner-only, exact-schema pending-session record and an `event=start` line containing the same session ID and epoch. It then starts LFS and waits in the foreground until all processes in the private Wine prefix exit. If protected files changed and LFS added a newer `data/versions/*.txt` marker during that session, the wrapper generates a deterministic protected-file manifest. The manifest is stored under its content hash before an atomic `install.env` replacement references it, so interruption cannot invalidate the previous marker/manifest pair. Normal launch completion removes pending evidence; successful update commit also removes obsolete manifests. Version 0.3.1 still reads the legacy v0.3.0 `game-update.manifest` layout. Normal player-file changes do not alter the baseline. Protected-file drift outside a trusted LFS session is rejected.

C24 is one bounded exception to marker advancement: its executable identifies C24 while the newest protected marker remains `8C23.txt`. Wrapper 0.3.3 does not generalize trust from that anomaly. Setup accepts an already-updated C23 baseline only when a fresh protected snapshot is an exact overlay of the audited C24 target and its previously trusted C23 manifest. Every target path must have exact C24 type, size, and digest; predecessor-only paths must be absent or byte-identical to their prior entries; unknown protected directories and special filesystem entries also fail. Consented setup atomically quarantines every unchanged C23-only protected entry into content-addressed `migration-conflicts` storage, rechecks the exact overlay and complete target, atomically writes package metadata, then removes obsolete local manifests.

The owner-only launch-lock directory and regular lock file are validated before opening without truncation; unsafe permissions, ownership, directory symlinks, or file symlinks fail closed. Launch acquires this lock before baseline loading and protected-tree validation. Prefix process checks require both the private `WINEPREFIX` and a Wine/Windows process identity; unrelated native helpers or browsers that merely inherited `WINEPREFIX` do not block launch, recovery, or status. If the foreground wrapper is interrupted, `recover-update` acquires the same lock, validates exact-schema session metadata, baseline hashes, log ownership and matching session epoch, the newer marker, and a stopped prefix. It creates and validates a pre-confirmation protected-file snapshot, binds its digest into the prompt and durable log, then requires a byte-identical post-confirmation inventory. Evidence, marker, log, version, baseline, and process state are rechecked around both snapshots and immediately before marker commit. Missing, inconsistent, or raced evidence or content fails closed. This local baseline proves continuity from a previously validated launch session; it is not a maintainer audit or vendor signature. LFS and Wine already run with the user's filesystem authority. Package pins remain the stronger reproducible bootstrap for clean installs and repair.

`lfs-linux update-check` reads the official downloads page and models old-graphics stable and new-graphics public-test channels separately. It parses the exact public-test installer build. Matching pins return 0; a newer build, channel change, or installer-name drift returns 2 with an actionable bootstrap-review message. It never edits the game or manifest and never runs in the launch path. Repository automation maps status 2 to one bounded, deduplicated maintenance issue and checks only the pinned installer's HTTP headers; unexpected checker or GitHub API failures remain failed runs.

A release maintainer updates the bootstrap installer, executable, nested archives, required assets, tree size, and tree count only after clean extraction, complete manifest generation, migration drills, in-game update continuity checks, and a behavioral run.

## Player-safe migration

An existing tree is classified before mutation:

- complete target stock: repair in place from verified staging while preserving player-owned paths
- recorded in-game update newer than the package target: require its complete local manifest and marker metadata; preserve it without downloading an older game
- exact local C23 predecessor: require its content-addressed protected baseline, then stage C24, replace dedicated player-owned roots with `cp -a`, and merge downloaded DDS skins without overwriting audited target files before the atomic swap
- exact C24 overlay on a trusted C23 baseline: adopt without a second installer download only through the bounded target/predecessor comparison above
- approved packaged C20 predecessor: require both its complete protected migration manifest and approved `LFS.exe` digest; mutable AI knowledge and training data remain outside that manifest
- unknown tree or unrecorded protected-file drift: stop before mutation and require restoration or a reviewed migration

Upgrade builds and verifies a separate staging tree first. The predecessor seed manifest distinguishes unchanged official defaults from modified or added player files in otherwise mutable directories. Upgrade drops unchanged old defaults, merges changed and player-owned data—including AI knowledge and custom training files—without overwriting target immutable stock, then performs an atomic rename through `game.backup`. Interrupted swaps recover the last complete tree. The backup is removed only after the new tree passes complete verification. A player file whose path collides with a newly introduced immutable stock path is kept by content hash under `~/.local/share/lfs-linux/migration-conflicts/` instead of being silently discarded.

## Display policy for this workspace

All project GUI checks use Xephyr display `:111` with its Xauthority file. The nested display currently reports llvmpipe.

Xephyr proves isolated GUI behavior. It does not prove native GPU latency. Native performance claims must come from direct-host architecture or separate approved hardware measurements.
