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
cd packaging/aur
SRCDEST="$OLDPWD/dist" makepkg --verifysource
```

Run the complete publication procedure in `docs/RELEASING.md`. After submission, set the AUR package-base keywords to `game`, `games`, `racing`, `simulator`, `wine`, and `lfs`, then verify them through the AUR package page and RPC before announcing catalog search visibility.

## Dependencies

The package provisions the exact authenticated Wine 11.15-1 runtime privately. It declares the runtime's host libraries and does not depend on system Wine, so a newer unrelated Wine package does not block installation or upgrades. Every runtime file and link is checked before execution. DXVK is deployed privately from its verified upstream archive.

The package directly requires:

- `7zip` to extract the verified official NSIS archive without executing its installer stub
- `gnupg` to verify the pinned Wine package against the shipped Arch certificate
- `libarchive` for verified private Wine package extraction
- the Vulkan loader and one `vulkan-driver` provider
- PulseAudio client compatibility for Wine audio
- `python`, `python-gobject`, and `gtk4>=4.10` for the branded native setup window
- `zenity` for the selectable fallback dialogs
- `xdg-utils` for the optional support link
- `xdotool` for a clean in-game `/exit` request

It does not depend on Bottles, Steam, Lutris, Gamescope, or a launcher daemon.
