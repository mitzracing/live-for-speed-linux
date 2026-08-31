# Low-Maintenance Contract

The project is a separate launcher, not a game fork.

## Maintainer workload target

Normal wrapper changes must fit one of these small units:

- one release-manifest pin update
- one shell compatibility fix
- one package metadata update
- one focused test
- one documentation correction

A normal audited bootstrap update changes outer and nested payload fields, regenerates the protected stock-file manifest, records the prior executable digest plus complete predecessor migration and full seed manifests, and runs clean-install, repair, atomic migration, interruption-recovery, trusted in-game update continuity, and unknown out-of-session drift checks. Users do not need that wrapper release before launching a versioned update completed by LFS itself. A Wine update similarly regenerates its complete runtime manifest. Neither path requires editing game assets or reverse engineering the executable.

## Stable interfaces

- `share/lfs-linux/release.env` owns audited versions, archives, and manifest digests.
- `share/lfs-linux/*.manifest` owns complete extraction seeds, immutable game inventories, predecessor migration references, and the Wine inventory.
- `libexec/lfs-linux-core` owns prefix lifecycle and launch behavior.
- `bin/lfs-linux` only locates and delegates to the core.
- `bin/lfs-linux-desktop` owns first-run terminal selection and then replaces itself with the CLI launcher.
- Distribution packages only install project files.
- The verified official installer archive defines the stock game tree.
- LFS owns player settings and account unlock state; extraction merges preserve those paths.

## Automated aid

CI performs syntax, metadata, package-boundary, and failure-path checks.

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
- the pinned Arch Wine package disappears from the immutable archive or drops required PE32 behavior
- upstream grants official Flatpak participation
- LFS changes its data layout in a way that threatens player data
- the public-test updater changes stock files without a distinct executable digest

Until then, prefer small manifest or shell patches.
