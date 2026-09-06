# Contributing

Thank you for improving Linux support for Live for Speed.

## Boundaries

Contributions can change the wrapper, package metadata, tests, and documentation.

Do not commit:

- Live for Speed binaries or proprietary assets
- modified cars, tracks, shaders, textures, or executables
- account names, passwords, unlock codes, or private logs
- copied official logos without written permission
- a Flathub submission manifest without upstream authorization

## Development setup

Tests require Bash, Python 3 with PyYAML, Node.js, Chromium or Google Chrome, ShellCheck, desktop-file-utils, AppStream, and libxml2 tools.

Run static checks:

```bash
make test
```

Native view tests also require system Python with PyGObject, GTK 4.10 or later, and a disposable display. The workers use fixtures, not game downloads.

```bash
# Use the configured Xephyr display, or run: xvfb-run -a make gtk-check
make gtk-check
```

`LFS_LINUX_UI=zenity` selects the fallback for manual checks. `LFS_LINUX_UI=gtk` requires GTK. The default selects GTK when available.

Run a disposable install with explicit XDG directories:

```bash
export LFS_LINUX_STATE_DIR=/tmp/lfs-linux-test/state
export LFS_LINUX_CACHE_DIR=/tmp/lfs-linux-test/cache
export LFS_LINUX_LOG_DIR=/tmp/lfs-linux-test/log
LFS_LINUX_DATA_DIR="$PWD/share/lfs-linux" \
LFS_LINUX_LIBEXEC_DIR="$PWD/libexec" \
./bin/lfs-linux install
```

## Workspace GUI display

Maintainer release evidence uses an isolated Xephyr display `:111`. Start the local nested X server, then set:

```bash
export DISPLAY=:111
export XAUTHORITY="$XDG_RUNTIME_DIR/xephyr-111-desktop/Xauthority"
```

Contributors can use another isolated display when `:111` is unavailable, but must record it in test evidence. Do not use nested-display frame rates as native performance evidence.

## Select contributor work

1. Open the [sanitized `help wanted` queue](https://github.com/mitzracing/live-for-speed-linux/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22+-label%3A%22status%3Apossible-sensitive%22).
2. Reproduce the report.
3. Comment that you plan to work on it. A maintainer assignment is not required.
4. Do not work on a ticket with `status:possible-sensitive` or `status:needs-maintainer`.
5. Open a pull request with `Closes #NUMBER` after the focused checks pass.

## Change process

1. Explain the user problem.
2. Keep the stock-game boundary.
3. Add a focused regression check.
4. Run `make test`.
5. Run `lfs-linux doctor`.
6. For setup changes, test application-menu first run and direct later launch.
7. For runtime changes, perform a clean install and GUI launch on the configured isolated display.
8. Record exact commands and proof limits.

## Release-pin changes

A pin update requires:

- official source URL, channel, byte size, and SHA-256 digest
- exact nested-payload inventory and complete stock manifest
- clean prefix install and stock `LFS.exe` digest
- migration preservation, interruption recovery, and unknown out-of-session update rejection
- trusted-session in-game update recording plus next-launch acceptance without redownload
- required DXVK DLL digests and initialization evidence
- native Vulkan, audio stream, gameplay, and clean-exit evidence
- updated release notes that call a public test a public test

Do not auto-merge game or runtime pin updates.

## Issue reports

Use the player forms in [`SUPPORT.md`](SUPPORT.md). Attach the latest wrapper log only after you inspect it for personal data. Never attach Wine registry files or LFS unlock data.

The triage automation and maintainer dashboard are documented in [`docs/TRIAGE.md`](docs/TRIAGE.md).
