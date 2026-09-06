# 0.4.0 release status

**Channel:** [public-test prerelease](https://github.com/mitzracing/live-for-speed-linux/releases/tag/v0.4.0). The owner approved publication with the manual checks below still open. Public availability does not certify the full player journey.

## Mission

Get LFS running in a few clicks, then get out of its way. The wrapper owns setup and compatibility. LFS owns game files and updates. Install, play, update inside LFS, restart, fully exit, and reopen without terminal commands or update approval.

`AGENTS.md` records this contract for future changes. Do not rebuild game fingerprinting or downgrade an existing game during compatibility repair.

## Delivered behavior

- GTK and Zenity share one controller for setup, progress, cancellation, retry, and Help. GTK exits at gameplay handoff.
- First setup authenticates downloads and validates extraction before activation. Wine and DXVK verification remain mandatory.
- Installed games need no fingerprint, version-marker observation, post-exit recording, or update-confirmation prompt. Old records are retained and ignored.
- Compatibility repair preserves the entire existing game. An incomplete executable stops repair without replacing it with an older bootstrap.
- Bootstrap remains official LFS 0.8C20 **PUBLIC TEST**, with Wine 11.15-1 and DXVK 3.0.2. The version shown inside LFS identifies the installed game, not these bootstrap pins.

## Evidence and limits

Source, controller, runtime-trust, preservation, updater-lifetime, packaging, and native GTK tests cover the implementation. The installed desktop fixture performs setup, a simulated C26 update/restart without a newer marker, and later relaunch. Initial setup is its only confirmation.

The owner-approved local wrapper installation matches candidate runtime files. Installed readiness, desktop state, GTK probe, and desktop entry checks passed. Game executable bytes, prefix/runtime metadata, and old records were unchanged. This is not a real gameplay test.

Local evidence remains outside public packages: `artifacts/lean-launch/`, `artifacts/wrapper-install-and-push/`, and `artifacts/release-0.4.0/`. Direct in-session review was authorized; no independent-review certification is claimed.

## Open manual acceptance

- [ ] Install the exact package with a named graphical installer and resolve dependencies, including hosts without Wine and hosts with unrelated system Wine.
- [ ] Complete first setup and cancel/resume a real download.
- [ ] Play, accept an actual LFS update, follow its restart, fully exit, and reopen from the menu without rebaseline or update approval.
- [ ] Repair compatibility components without changing the updated game or player data.
- [ ] Verify native GPU/Vulkan, audio, GNOME/KDE behavior, Wayland, and diagnostic report Save.
- [ ] Verify package removal preserves user state on the actual graphical route.

The owner and maintainers own these checks. A failure blocks promotion to a verified end-to-end release and requires a focused fix, never a game downgrade. Fixture success cannot close these items.

## Distribution and recovery

GitHub hosts test downloads. No AUR, Pamac, GNOME Software, or Discover listing is advertised as available. `packaging/debian/build-catalog.sh` prepares metadata only; it creates no signed repository or update channel.

Release assets are immutable. Correct a published defect with a new version. Never reset user work, change a real prefix during publication, or roll back game files. Older fingerprint-enforcing wrappers can reject updated games and are not a game-repair route.
