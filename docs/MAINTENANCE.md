# Low-Maintenance Contract

The project is a separate launcher, not a game fork.

## Maintainer workload target

Normal wrapper changes must fit one of these small units:

- one release-manifest pin update
- one shell compatibility fix
- one package metadata update
- one focused test
- one documentation correction

An audited bootstrap update changes outer and nested payload fields and regenerates the stock and complete seed manifests. Test clean installation, interrupted downloads, runtime repair, existing-game preservation, and update → restart → exit → desktop relaunch. Existing games are never migrated to a wrapper's bootstrap. LFS owns their updates; no executable allowlist or version-marker observation is needed. A Wine update regenerates its complete runtime manifest. Neither path requires editing game assets or reverse engineering the executable.

## Stable interfaces

- `share/lfs-linux/release.env` owns audited versions, archives, and manifest digests.
- `share/lfs-linux/*.manifest` owns complete extraction seeds, bootstrap stock inventories, historical predecessor references, and the Wine inventory. Historical predecessor files are not launch or migration gates.
- `libexec/lfs-linux-core` owns prefix lifecycle and launch behavior.
- `bin/lfs-linux` only locates and delegates to the core.
- `bin/lfs-linux-desktop` dispatches graphical actions. `libexec/lfs-linux-ui` owns dialog requests, progress, cancellation, and report previews for both views. The core owns state validation and mutations.
- `libexec/lfs-linux-gtk`, `libexec/lfs_linux_dialog.py`, and `libexec/lfs_linux_gtk.py` provide the private GTK view. They do not implement another installer.
- Distribution packages only install project files.
- The verified official installer archive defines the stock game tree.
- LFS and the player own the entire installed game directory. Runtime repair leaves it untouched.

## Automated aid

CI performs syntax, metadata, package-boundary, and failure-path checks.

Maintainers keep both views in the shared-controller tests. `make gtk-check` exercises real GTK widgets with disposable workers. Debian 13 and Ubuntu 24.04 checks include this gate.

`LFS_LINUX_UI=zenity` provides a reversible fallback for a GTK regression. A view change does not require a player-state migration. New dialog types require transport, widget, and shared-controller coverage.

The weekly upstream check has three outcomes:

| Checker result | Repository action | Workflow result |
|---|---|---|
| current pin (0) | close any managed drift issue | success |
| valid drift (2) | HEAD-check the pinned installer and create or refresh one deduplicated issue | success with warning |
| downloads-page network, script, or GitHub API failure | no trust or pin change | failure |

The issue uses the dedicated `upstream-drift` label plus `status:needs-maintainer`. Repeated identical reports are no-ops; changed reports update the same issue once. When repository pins match again, automation comments and closes the issue.

Default maintainer action:

- pinned installer available at the audited byte size: monitor and batch rapid public-test updates
- pinned installer missing or changed: audit the new bootstrap immediately
- compatibility regression or stable-channel change: audit immediately

Automation must not:

- download the full proprietary installer during the scheduled check
- calculate and accept new digests without review
- modify a user installation
- commit, open a pin-update pull request, tag, or publish
- upload proprietary payloads
- message upstream developers or file upstream reports automatically

## Bus-factor reduction

Release steps are command-based and documented in `docs/RELEASING.md`.

No maintainer needs a private build server, proprietary SDK, game source, or persistent service.

At least two maintainers should review pin updates after the public repository gains contributors.

## Escalation triggers

Stop and redesign only if one of these changes occurs:

- the official NSIS archive can no longer be extracted reproducibly with the supported 7-Zip version
- anti-cheat or upstream policy prohibits DXVK
- the pinned Arch Wine package or detached signature disappears, the signer changes, or the runtime drops required PE32 behavior
- upstream grants official Flatpak participation
- LFS changes its data layout in a way that threatens player data
- an upstream change prevents normal update, restart, or later launch

Until then, prefer small manifest or shell patches. Do not rebuild local game fingerprinting to handle update changes. Legacy update records are ignored and left in place; only explicit state removal deletes known records. Downgrading to a fingerprint-enforcing wrapper can recreate the launch failure, so test rollback in separate state without downgrading the game.
