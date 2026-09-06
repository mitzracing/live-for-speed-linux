# BUG-001: LFS updates must survive wrapper restarts

## Problem and acceptance

Owner reported C26 updating, restarting and playing successfully, then failing on application-menu relaunch with `recorded in-game update baseline drifted outside a trusted LFS session`.

Product contract: obtain the installer from the website or a supported software store, install, play, accept LFS updates, close, and reopen. No terminal, Wine configuration, fingerprint approval or rebaseline. Both distribution routes use the same desktop controller. Store availability and real desktop acceptance must not be inferred from fixture tests.

## Root cause analysis

- **Reproduce:** owner reproduced update → updater restart → gameplay → full exit → failed relaunch on installed wrapper 0.3.1. At reproduction time, the new GTK candidate was not installed.
- **Isolate:** the wrapper records an updated game only after Wine settles and a version marker advances. Every later launch/setup requires that recorded fingerprint.
- **Hypothesize:** stale update bookkeeping versus locale-only ordering or corrupt metadata.
- **Verify:** read-only comparison authenticated the saved C24 manifest, found 16 size mismatches (including the executable) and 126 extra paths. Session events show parent exit 0, two Wine wait timeouts, and final `wine-wait-failed`. Current version-marker filenames stop at 8C23. This is not an ordering-only mismatch. The wrapper's stale baseline explains the refusal; it does not establish tampering or an incomplete game. Exact C26 identity and gameplay remain owner-reported.

Related previous fixes normalized ordering and excluded more player files. They retained the faulty launch contract. Fix the contract instead of extending exclusion lists.

Security impact: LOW; no security exploit path identified. Policy changes explicitly: downloaded inputs and wrapper-owned runtime remain authenticated; an installed game is user/LFS-managed, not authenticated by local fingerprints. Local metadata was never an independent vendor signature or a same-user security boundary.

## Scope and plan

1. Add a failing public-command regression for a self-update without a newer marker followed by Wine wait failure, desktop readiness and relaunch.
2. Remove installed-game inventory/hash gates and post-exit recording. Keep private launch locking, runtime verification, updater restart waiting, and no automatic termination of running games.
3. Preserve an existing regular readable nonempty game executable and its entire game directory during setup. Bootstrap only when no game exists. Refuse an incomplete existing game without changing it. Recover a legacy swap backup only when the destination is absent; never discard either existing tree automatically.
4. Remove obsolete snapshot/recovery machinery and GUI approval prompts. Retain `recover-update` as a non-mutating compatibility notice directing callers to normal launch. Leave old local evidence untouched; do not migrate or delete it.
5. Replace tests whose expectations intentionally enforced the old policy. Retain authenticated archive, runtime, cancellation, process, lock and data-preservation checks. Exercise installed desktop dispatch with disposable state.
6. Update safety, user and maintainer documentation. Rebuild and check candidate packages. Preserve the existing uncommitted source baseline and release pins.

Non-goals for the bug fix: payload/runtime changes, host dependencies, or game/prefix/player-data changes. The owner subsequently approved wrapper-only installation and source publication, then 0.4.0 public-test publication and website deployment with manual acceptance still open. Store availability is not claimed.

## Verification and proof ceiling

- [x] Focused RED → GREEN public-command regression.
- [x] Full source and GTK checks; package/archive checks after the final source change.
- [x] Existing-game setup preserves all bytes, links and legacy evidence without game downloads.
- [x] First install still rejects unsafe or unauthenticated payloads.
- [x] Download/cancel/retry and updater restart lifetime remain covered.
- [x] Owner-approved wrapper-only installation; installed readiness, desktop state, GTK probe and desktop entry checks pass.
- [ ] Real C26 relaunch and gameplay.
- [ ] Exact package installation from supported graphical package/store route; native Wayland and report Save.

Fixture evidence is behavioral evidence of wrapper decisions, not outcome evidence of LFS gameplay or storefront availability. The owner owns the last two checks. The approved public-test release discloses these gaps; failure blocks promotion to a verified end-to-end release.

## Maintenance and recovery

Maintainer owns wrapper/runtime provisioning. LFS and the user own installed game files. No new runtime dependency. Source rollback uses the narrow diff against `artifacts/lean-launch/before/`; never reset the existing branch. Old wrappers can reject an updated game again, so rollback must not downgrade game files or be presented as a user repair.

## Resolution

Repository fix and candidate packages complete. The owner approved replacing the installed wrapper, then committing and pushing source. Wrapper 0.4.0 is installed; real C26 relaunch still needs owner acceptance. Full tests, native GTK, ShellCheck, Debian 13/Ubuntu 24.04 compatibility, source archive and Arch/Debian packages passed. Installed desktop fixture covers first setup → simulated C26 update/restart → reopen, with initial setup as the only confirmation.

Repository evidence: `artifacts/lean-launch/REVIEW.md`, `results.json`, `implementation.diff`, and `installed-diagnosis.json`. Installation receipt and backup: `artifacts/wrapper-install-and-push/`. All 25 installed wrapper targets match staged bytes, modes and links. Game executable bytes, prefix/runtime metadata and old records are unchanged. Installed `ready`, `desktop-state` (`ready`), GTK probe and desktop-file validation passed without launching LFS.

Source commit/push, public-test package release, and website deployment are approved. Behavioral fixture and installed readiness evidence do not close the two remaining outcome gates. Current publication scope and limits are in `docs/RELEASE-CANDIDATE.md`.
