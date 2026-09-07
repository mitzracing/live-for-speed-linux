# Release Procedure

## Wrapper release

The owner approved 0.4.0 as a public-test prerelease with the manual acceptance checks in `docs/RELEASE-CANDIDATE.md` still open. Run automated checks and exact-artifact validation before publishing. Mark the GitHub release as a prerelease and disclose open checks on the website and in release notes. This is not full end-to-end acceptance or permission to advertise an unavailable store route.

The complete acceptance procedure remains:

1. Run `make test`.
2. Build a staged filesystem with `make DESTDIR="$PWD/pkgroot" install`.
3. Run `make deb-check` in clean Ubuntu 24.04 and Debian 13 containers.
4. Validate the desktop file and AppStream metadata.
5. Build the AUR package from a real signed or immutable project tag.
6. Install each candidate package in a disposable environment.
7. Open the application-menu entry with no existing prefix or Wine configuration. Complete **Install and play**; test real download cancellation and resume.
8. Run `lfs-linux doctor` as a maintainer check, not as a required player step.
9. Exercise the exact installed desktop entry, native Wayland, and report Save. Test the downloaded-package route and each advertised store route separately.
10. Confirm DXVK, actual GPU, audio, gameplay, updater restart, full exit, and application-menu relaunch without update approval or a terminal.
11. Remove the package and confirm user-owned state remains unchanged.
12. Publish only audited wrapper artifacts.

## Website-only publication

Website changes do not require a new wrapper version or replacement of existing release assets.

Check the media records in `website/assets/README.md`. Current photographs use the Unsplash License, which does not require attribution. When replacing unpublished draft assets, publish the tested candidate from a clean public base so retired files do not remain in public Git history. Keep private draft branches intact. Do not rewrite published history. A successful build or browser test checks the current tree, not every historical asset.

1. Run `bash tests/test-website.sh`, then require successful repository CI on the candidate commit.
2. Use `bash scripts/build-website.sh NEW_OUTPUT_DIRECTORY` to assemble the static site. Its parent directory must exist. The builder refuses an existing output directory, so it cannot retain stale assets or overwrite other work. Browser tests and Pages use this same builder.
3. Review desktop and mobile rendering, download links, keyboard focus, feedback privacy, and media/font credits. Check video pause, reduced-motion and no-JavaScript posters, failed-source recovery, MP4 fallback, and font fallback. Check hero arrows/wrap, pause/resume, hover/focus/offscreen behavior, deferred pictures, failed-image retention, and gallery reflow at 200% text. Keep public-test and simulated-demo limitations visible. Label real-world motorsport photographs as illustrations, not game screenshots.
4. After explicit publication approval, update `main`. The Pages workflow publishes the assembled site, including local fonts, media, and their license/credit records.
5. Confirm successful Pages deployment. Compare every live file with the tested output, including video formats, poster, font, and OFL notice. Recheck immutable package downloads and live browser behavior with `LFS_WEBSITE_URL=https://mitzracing.github.io/live-for-speed-linux/ REQUIRE_BROWSER_E2E=1 node tests/test-feedback-browser.mjs`.

Use a new CSS cache key when styling changes, and update the media-controller script key when that script changes. Browser checks use the same staged builder and one browser harness, including `tests/website-video.mjs` and `tests/website-photos.mjs`. The photo checks use a controlled clock and delayed native-decode fixtures for timer and stale-load behavior; document visibility is simulated. The hero waits seven seconds between automatic changes and keeps template images inert until selected. Media advances automatically only when visible and preferences permit it, or after deliberate opt-in. Retain explicit pause, static/no-JavaScript fallback, last-good-image retention, and readable demonstration steps. Keep the explicit builder list, asset checks/budgets, and credit hashes in sync when intentionally replacing assets.

Website media, fonts, and credits are not part of Linux packages; the existing application icon remains installed. To roll back, revert the website change as a new commit and redeploy; do not rewrite release tags, replace package assets, or change player files.

## Upstream pin update

Update `share/lfs-linux/release.env` as one change:

- LFS version, channel, and public-test family (label public tests explicitly)
- installer filename and URL
- byte size
- installer SHA-256
- bootstrap `LFS.exe` SHA-256 and byte size
- bootstrap stock and complete extraction seed-manifest names, sizes, SHA-256 digests, and entry counts
- required helmet, track, and vehicle asset paths, sizes, and SHA-256 digests
- every nested archive's exact path, destination class, size, and SHA-256 digest
- minimum extracted file count and byte size as secondary sanity checks
- DXVK version, URL, size, archive SHA-256, and required 32-bit D3D11/DXGI DLL sizes and SHA-256 digests
- exact Wine package version, immutable archive and detached-signature URLs, sizes and SHA-256 digests, audited packager-key fingerprint and digest, and complete runtime-manifest pins

The wrapper preflights archive member paths and links, extracts the verified NSIS archive with 7-Zip, and does not execute the installer stub. For 0.8, verify and preflight every nested archive before extracting it into its audited destination. Preserve sorted installer order and explicit replacement semantics: later pinned nested archives intentionally replace earlier seed entries inside disposable staging. A skip-existing policy changes official bytes and must fail the complete seed manifest. Remove `$PLUGINSDIR`, `inst_tmp`, and `UninstallLFS.exe`, then regenerate the LFS manifest with `scripts/generate-payload-manifest.py lfs`. Extract the exact Wine package and regenerate its manifest with the `wine` profile. Review player-owned exclusions before accepting either manifest.

Remove or change a file in a bootstrap fixture and require extraction verification to reject it before activation. Repeat with unsafe archive members and changed nested archives. A game directory appearing during extraction must remain untouched. Corrupt a non-entry-point Wine DLL and a prefix DXVK DLL: execution must reject the runtime, graphical setup must offer repair, and repair must preserve the game.

Test existing games from old and newer bootstraps, including changed stock, new assets, deleted non-executable assets, profiles, account state, skins and linked folders. Setup must preserve the entire game without downloading an older installer. A missing, empty, unreadable or linked executable must stop setup without game-file changes. Legacy swap recovery may restore an absent destination, but must keep both trees if both exist. Historical predecessor digests/manifests are no longer migration or launch gates.

Simulate update → updater restart → gameplay → full exit → application-menu relaunch. Change the executable and assets without adding a newer `data/versions` marker. Make the first Wine parent exit nonzero and restart during the settle-grace boundary; confirm the wrapper waits without killing the game and preserves the exit status. Make `wineserver --wait` fail: retain the error but ensure a later normal launch needs no fingerprint recovery. Old, malformed or missing local update records must not block or get rewritten.

Keep non-game Wine-prefix processes past the wait interval. Confirm launch leaves them running, does not leak its lock to descendants, and only explicit stop or graphical confirmation terminates them. An unrelated native helper with the same `WINEPREFIX` must be ignored. During gameplay, a second launch must not start another game. Public lock directories and lock-file symlinks must fail without truncating their targets.

Finally test the exact installed package on a real supported desktop, not only fixture workers. Verify LFS's displayed version and actual gameplay after updating and reopening. Local fixture or container success cannot replace this publication gate.

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

The AUR recipe uses the deterministic archive created by `make release-archive`, not GitHub's generated source snapshot. The builder normalizes directory and tracked file modes in its disposable copy; it does not change the owner's checkout permissions. Set `VERSION` to a new, unreleased value first: the builder refuses to reuse an archive name whose matching tag already points to another commit. `LFS_LINUX_ALLOW_POST_RELEASE_ARCHIVE=1` is reserved for deterministic test snapshots and must not be used for publication.

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
11. Set the AUR package-base keywords to `game`, `games`, `racing`, `simulator`, `wine`, and `lfs`; verify them on the package page and through the AUR RPC.

GitHub release publication and AUR submission require explicit owner approval.

## Rollback

Revert the wrapper package to the last verified tag. For the 0.8C20 public-test release, v0.2.2 is the audited 0.8C19 predecessor and immutable v0.1.6 remains the old-graphics 0.7G fallback. Do not downgrade or overwrite installed game files. A pre-0.4.0 wrapper can recreate fingerprint refusals after a valid update. Back up XDG state and use a separate state directory for fallback validation; do not call a wrapper downgrade a game repair.

If an upstream public-test update is incompatible, keep the prior pin only while its official URL and terms remain valid. Clearly report that status and never call a public test stable.
