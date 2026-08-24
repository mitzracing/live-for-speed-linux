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

A scheduled upstream check can report download-page changes. It must not:

- calculate and accept new digests without review
- modify a user installation
- merge a pin update
- publish an AUR or Flatpak release
- contact upstream automatically

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
