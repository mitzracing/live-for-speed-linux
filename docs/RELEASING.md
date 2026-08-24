# Release Procedure

## Wrapper release

1. Run `make test`.
2. Build a staged filesystem with `make DESTDIR="$PWD/pkgroot" install`.
3. Validate the desktop file and AppStream metadata.
4. Build the AUR package from a real signed or immutable project tag.
5. Install the staged package in a disposable environment.
6. Run a clean `lfs-linux install`.
7. Run `lfs-linux doctor`.
8. Run a cold GUI launch on the project display.
9. Confirm DXVK, Vulkan device, audio stream, and clean exit.
10. Publish wrapper source only.

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
- exact Wine package version, immutable archive URL, size, SHA-256 digest, and complete runtime-manifest pins

The wrapper extracts the verified NSIS archive with 7-Zip and does not execute the installer stub. For 0.8, verify and extract every nested archive into its audited destination. Remove `$PLUGINSDIR`, `inst_tmp`, and `UninstallLFS.exe`, then regenerate the LFS manifest with `scripts/generate-payload-manifest.py lfs`. Extract the exact Wine package and regenerate its manifest with the `wine` profile. Review player-owned exclusions before accepting either manifest.

Delete a randomly selected immutable file that is not one of the separately pinned representative files. Confirm `doctor` and `launch` fail, `install` restores its exact hash, and player-owned paths remain byte-identical. Perform the same drift-and-reprovision check on one non-entry-point Wine DLL.

Then test an in-place upgrade from every digest listed in `LFS_UPGRADE_FROM_SHA256S`. Require its complete protected predecessor migration manifest, compare player-owned paths before and after the atomic swap, interrupt each swap state to prove recovery, and confirm that the complete new stock tree passes validation. Prove a changed predecessor stock file and unknown out-of-session executable drift are rejected before game-tree mutation. Remove a digest and predecessor manifest when that path is no longer supported.

Simulate an in-game update from a fully validated launch. Require a newer `data/versions/*.txt` marker, changed `LFS.exe`, and at least one added protected file. Confirm the foreground launcher records a local manifest after Wine exits, `ready` succeeds, next launch uses that baseline without downloading the packaged installer, `doctor` passes, explicit `install` preserves it, and later out-of-session drift fails closed.

Then run the full wrapper release procedure.

Do not copy an existing user prefix into a release. A clean prefix is mandatory.

## AUR publication

The AUR recipe uses the deterministic archive created by `make release-archive`, not GitHub's generated source snapshot.

1. Run `make release-archive` twice and compare SHA-256 digests.
2. Confirm the digest equals `packaging/aur/PKGBUILD`.
3. Upload that exact archive as `live-for-speed-linux-<version>.tar.gz` on the matching GitHub release.
4. Run `makepkg --verifysource`.
5. Run `makepkg --cleanbuild --syncdeps` in a clean Arch environment.
6. Run `namcap` when available.
7. Generate `.SRCINFO` with `makepkg --printsrcinfo`.
8. Compare generated `.SRCINFO` with the committed file.
9. Inspect package contents for proprietary files and home paths.
10. Recheck that the AUR package name is available, then submit.

GitHub release publication and AUR submission require explicit owner approval.

## Rollback

Revert the wrapper package to the last verified tag. For the 0.8C20 public-test release, v0.2.2 is the audited 0.8C19 predecessor and immutable v0.1.6 remains the old-graphics 0.7G fallback. Do not downgrade or overwrite a packaged or locally recorded game baseline automatically; back up the XDG state tree and use a separate state directory for fallback validation.

If an upstream public-test update is incompatible, keep the prior pin only while its official URL and terms remain valid. Clearly report that status and never call a public test stable.
