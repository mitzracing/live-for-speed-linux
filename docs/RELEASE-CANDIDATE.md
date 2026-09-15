# 0.4.1 release status

**Channel:** [public-test prerelease](https://github.com/mitzracing/live-for-speed-linux/releases/tag/v0.4.1). The owner requested review, fixes, commit and deployment. The manual checks below remain open; public availability does not certify the full player journey.

## Mission

Get LFS running in a few clicks, then get out of its way. The wrapper owns setup and compatibility. LFS owns game files and updates. Install, play, update inside LFS, restart, fully exit, and reopen without terminal commands or update approval.

`AGENTS.md` records this contract. Do not rebuild game fingerprinting or downgrade an existing game during compatibility repair.

## Change in 0.4.1

After graphical setup or repair, choose **Play now** or **Close**. Setup no longer starts the game automatically. Close leaves the installation ready; ordinary application-menu launches still need no confirmation. GTK and Zenity use the same controller.

Bootstrap remains official LFS 0.8C20 **PUBLIC TEST**, Wine 11.15-1 and DXVK 3.0.2. Authentication, extraction safety, private process lifetime and whole-game preservation are unchanged. The version shown inside LFS identifies the installed game, not the bootstrap pins.

## Evidence and limits

The completion-choice source passed full Make checks, 20 controller tests and 10 native GTK tests on an owned display. The installed desktop fixture covers setup, a simulated C26 update/restart and reopen. It expects initial setup consent plus one post-setup play choice, never recurring update approval. These fixtures do not run the real game.

On Manjaro/KDE/X11 with NVIDIA graphics, the owner reported an invisible game receiving desktop clicks, then closed it normally. A separately authorized launch through the installed 0.4.0 desktop executable was visible and working according to the owner. No graphics setting or driver was changed. This was not a recorded physical menu click, an installation of 0.4.1, or proof of the original cause.

**Known limitation:** the earlier invisible-window incident remains unresolved (BUG-003). It did not reproduce on that follow-up. Version 0.4.1 fixes the setup choice only and claims no graphics fix. If the symptom returns, preserve a bounded diagnostic report rather than resetting player data or applying speculative driver changes.

The original Pamac Preparing report also remains unexplained. One controlled 0.4.0 GUI remove/reinstall showed explicit success; reopening the already installed archive exited without another transaction. Backend/package success does not prove every graphical installer path.

Direct review was performed; no independent-review certification is claimed. Private receipts remain in `artifacts/launch-focus-20260915T125849Z/` and `artifacts/release-0.4.1/`. Earlier 0.4.0 evidence remains in its original artifact directories; it is not relabeled as 0.4.1 proof.

## Open manual acceptance

- [ ] Install the exact 0.4.1 package with a named graphical installer and resolve dependencies, including hosts without Wine and hosts with unrelated system Wine.
- [ ] Complete real first setup, test cancellation/resume, and exercise both completion choices with the exact package.
- [ ] Play, accept an actual LFS update, follow its restart, fully exit, and reopen from the menu without rebaseline or update approval.
- [ ] Repair compatibility components without changing the updated game or player data.
- [ ] Verify native GPU/Vulkan, audio, GNOME/KDE behavior, Wayland and diagnostic report Save beyond the bounded owner observation.
- [ ] Verify package removal preserves user state on the actual graphical route.

The owner and maintainers own these checks. A failure blocks promotion to a verified end-to-end release and requires a focused fix, never a game downgrade. Fixture success cannot close these items.

## Distribution and recovery

GitHub hosts test downloads. No AUR, Pamac, GNOME Software or Discover listing is advertised as available. `packaging/debian/build-catalog.sh` prepares metadata only; it creates no signed repository or update channel.

Release assets are immutable. Correct a published defect with a new version. Preserve the existing game and player files during wrapper replacement. Version 0.4.0 remains unchanged; older fingerprint-enforcing wrappers are not a game-repair route.
