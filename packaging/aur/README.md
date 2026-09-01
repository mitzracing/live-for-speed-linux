# AUR Packaging

Package name: `live-for-speed-linux`

The AUR RPC reported this name as unused on 2026-08-14. Submission remains pending until the maintainer registers an SSH key with the AUR account. Check the name again immediately before submission.

## Why AUR first

AUR supports community-maintained wrappers and exposes them to Arch software tools. Pamac can show AUR packages when the user enables AUR support.

The package installs only the MIT-licensed wrapper files and the GPL-3.0-or-later public signing certificate. Runtime game downloads happen as the desktop user, never during `makepkg`.

## Source integrity

`PKGBUILD` pins the deterministic archive made by:

```bash
make release-archive
```

The archive excludes local test prefixes, logs, screenshots, LFS binaries, and DXVK binaries. Upload the exact archive to the matching GitHub release before AUR submission.

Local verification can use the already-built archive without downloading it:

```bash
SRCDEST="$PWD/dist" makepkg --verifysource -p packaging/aur/PKGBUILD
```

Run the complete publication procedure in `docs/RELEASING.md`. After submission, set the AUR package-base keywords to `game`, `games`, `racing`, `simulator`, `wine`, and `lfs`, then verify them through the AUR package page and RPC before announcing catalog search visibility.

## Dependencies

The package requires exact `wine=11.15-1`, matching the only runtime payload accepted by wrapper 0.3.x. Source installs can provision that same immutable Arch Linux Archive package privately when the exact system package is unavailable. Every Wine file and link is checked against the shipped runtime manifest. The wrapper privately deploys the audited DXVK D3D11 and DXGI DLLs, so it does not depend on `dxvk-bin`.

The package directly requires:

- `7zip` to extract the verified official NSIS archive without executing its installer stub
- `gnupg` to verify the pinned Wine package against the shipped Arch certificate
- `libarchive` for verified private Wine package extraction
- the Vulkan loader and one `vulkan-driver` provider
- PulseAudio client compatibility for Wine audio
- `xterm` for the guaranteed first-run setup window
- `xdotool` for a clean in-game `/exit` request

It does not depend on Bottles, Steam, Lutris, Gamescope, or a launcher daemon.
