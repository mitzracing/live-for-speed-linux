# Release Procedure

## Wrapper release

1. Run `make test`.
2. Run `make package-check`; its exact direct-package file, symlink, and directory allowlists must reject every unexpected path or special filesystem entry.
3. Build a staged filesystem with `make DESTDIR="$PWD/pkgroot" install`.
4. Run `make deb-check` in clean Ubuntu 24.04 and Debian 13 containers.
5. Validate the desktop file and AppStream metadata.
6. Build the AUR package from a real signed or immutable project tag.
7. Install each candidate package in a disposable environment.
8. Run a clean `lfs-linux install` without copying an existing prefix.
9. Run `lfs-linux doctor`.
10. Run a cold GUI launch on the project display.
11. Confirm DXVK, Vulkan device, audio stream, and clean exit.
12. Remove the package and confirm user-owned state remains unchanged.
13. Publish only audited wrapper artifacts.

## Upstream pin update

Update `share/lfs-linux/release.env` as one change:

- LFS version, channel, and public-test family (label public tests explicitly)
- installer filename and URL
- byte size
- installer SHA-256
- installed `LFS.exe` SHA-256 and byte size
- the complete runtime immutable manifest and complete extraction seed-manifest names, sizes, SHA-256 digests, and entry counts
- required helmet, track, and vehicle asset paths, sizes, and SHA-256 digests
- every nested archive's exact path, destination class, size, and SHA-256 digest
- minimum extracted file count and byte size as secondary sanity checks
- prior audited executable digest, immutable predecessor migration manifest, and complete predecessor seed manifest; use the seed to distinguish untouched defaults from player changes
- DXVK version, URL, size, archive SHA-256, and required 32-bit D3D11/DXGI DLL sizes and SHA-256 digests
- exact Wine package version, immutable archive and detached-signature URLs, sizes and SHA-256 digests, audited packager-key fingerprint and digest, and complete runtime-manifest pins

The wrapper preflights archive member paths and links, extracts the verified NSIS archive with 7-Zip, and does not execute the installer stub. For 0.8, verify and preflight every nested archive before extracting it into its audited destination. Preserve sorted installer order and explicit replacement semantics: later pinned nested archives intentionally replace earlier seed entries inside disposable staging. A skip-existing policy changes official bytes and must fail the complete seed manifest. Remove `$PLUGINSDIR`, `inst_tmp`, and `UninstallLFS.exe`, then regenerate the LFS manifest with `scripts/generate-payload-manifest.py lfs`. Extract the exact Wine package and regenerate its manifest with the `wine` profile. Review player-owned exclusions before accepting either manifest.

Delete a randomly selected immutable file that is not one of the separately pinned representative files. Confirm `doctor` and `launch` fail, `install` restores its exact hash, and player-owned paths remain byte-identical. Perform the same drift-and-reprovision check on one non-entry-point Wine DLL.

Then test an in-place upgrade from every digest listed in `LFS_UPGRADE_FROM_SHA256S`. Require its complete protected predecessor migration manifest, compare player-owned paths before and after the atomic swap, interrupt each swap state to prove recovery, and confirm that the complete new stock tree passes validation. Recovery must reject backup symlinks and invalid backup content before touching the current tree; when both trusted backup and incomplete current trees exist, verify the current tree is retained before restoration. Prove a changed predecessor stock file and unknown out-of-session executable drift are rejected before game-tree mutation. Remove a digest and predecessor manifest when that path is no longer supported.

Simulate an in-game update from a fully validated launch. Require a newer `data/versions/*.txt` marker, changed `LFS.exe`, and at least one added protected file. Make the original Wine parent exit nonzero while `LFS.exe` starts during the settle-grace boundary and remains active beyond another interval; confirm the wrapper waits without killing it, preserves the parent status, then records only after exit. Make `wineserver --wait` return an unexpected status and confirm exact propagation without cleanup. Keep a real non-game Wine-prefix process past the interval; confirm launch never calls prefix-wide kill, retains recovery evidence, reports the service, releases its foreground lock to descendants, and only explicit `stop` terminates it. Also give an unrelated native helper the same `WINEPREFIX`; confirm process status ignores it. Fault between content-addressed manifest placement and marker commit; confirm the old pair remains valid. While that failed commit still holds the launch lock, start another launcher and confirm it rejects before baseline validation. Precreate a public fallback lock directory and a lock-file symlink; confirm both fail without truncating the symlink target. Verify recovery rejects open-permission, unknown-key, duplicate-key, event-time, confirmation-evidence-race, protected-content race by a short-lived game process, and missing evidence. Require a validated pre-confirmation snapshot digest plus an identical post-confirmation inventory, preserve mutable account/log/cache/mod/skin paths, and succeed with valid interrupted-session evidence. Finally confirm `ready` succeeds, next launch uses the baseline without downloading the packaged installer, `doctor` passes, explicit `install` preserves it, and later out-of-session drift fails closed.

Then run the full wrapper release procedure.

Do not copy an existing user prefix into a release. A clean prefix is mandatory.

## Debian and Ubuntu `.deb` publication

The `.deb` is a GitHub release asset, not entry into the Debian archive or an Ubuntu PPA. Shipping AppStream metadata does not create a graphical software-catalog listing: GNOME Software and KDE Discover can index it only after a reviewed package enters a configured archive. Those channels require separate ownership, signing, review, and explicit approval.

1. Run `packaging/debian/build-deb.sh` twice and compare SHA-256 digests.
2. Run `tests/test-debian-package.sh` and inspect `dpkg-deb --info` plus `dpkg-deb --contents`.
3. Confirm the package contains only the same wrapper files accepted by `tests/test-package-boundary.sh`.
4. In fresh Ubuntu 24.04 and Debian 13 environments, install with `apt install ./live-for-speed-linux_<version>-0github1_amd64.deb`.
5. Confirm APT resolves only amd64 host libraries for the audited pure-WoW64 runtime.
6. On each distribution, use an empty state directory, run the official audited install, `doctor`, a real DXVK/Vulkan GUI launch, and a clean stop.
7. Create user-state sentinels, remove the package, and prove those sentinels and all XDG game data remain.
8. Upload that exact `.deb` beside the deterministic source archive on the matching GitHub release.

Normal package installation and removal must never download, embed, replace, or delete proprietary game payloads or player-owned state.

## AUR publication

The AUR recipe uses the deterministic archive created by `make release-archive`, not GitHub's generated source snapshot. Set `VERSION` to a new, unreleased value first: the builder refuses to reuse an archive name whose matching tag already points to another commit. `LFS_LINUX_ALLOW_POST_RELEASE_ARCHIVE=1` is reserved for deterministic test snapshots and must not be used for publication.

1. Run `make release-archive` twice under different timezone, umask, and checkout-mode conditions and compare SHA-256 digests. Directories must be `0755`; only paths in `scripts/release-executable-paths.txt` may be `0755`; all other regular files must be `0644`. The source-boundary scanner must reject unapproved binary/archive magic, payload extensions, special entries, escaping links, or a selected tree of 4 MiB or more; the compressed archive must remain below 2 MiB.
2. Confirm the digest equals `packaging/aur/PKGBUILD`.
3. Upload that exact archive as `live-for-speed-linux-<version>.tar.gz` on the matching GitHub release.
4. Run `makepkg --verifysource`.
5. Run `makepkg --cleanbuild --syncdeps` in a clean Arch environment.
6. Run `namcap` when available.
7. Generate `.SRCINFO` with `makepkg --printsrcinfo`.
8. Compare generated `.SRCINFO` with the committed file.
9. Inspect package contents for proprietary files and home paths.
10. Recheck that the AUR package name is available, then submit.
11. Set the AUR package-base keywords to `game`, `games`, `racing`, `simulator`, `wine`, and `lfs`; verify them on the package page and through the AUR RPC.

GitHub release publication and AUR submission require explicit owner approval.

## Rollback

Revert the wrapper package to the last verified tag. For the 0.8C24 public-test candidate, v0.3.2 is the audited 0.8C20 predecessor and immutable v0.1.6 remains the old-graphics 0.7G fallback. Do not downgrade or overwrite a packaged or locally recorded game baseline automatically; back up the XDG state tree and use a separate state directory for fallback validation.

If an upstream public-test update is incompatible, keep the prior pin only while its official URL and terms remain valid. Clearly report that status and never call a public test stable.
