# Legal and Upstream Boundary

Live for Speed Linux is an independent community launcher. It is not affiliated with or endorsed by the Live for Speed developers.

## What this repository distributes

This repository and its Linux packages distribute only:

- open-source shell scripts under the MIT license
- desktop and AppStream metadata
- an original community icon
- checksums and public download URLs
- the public Arch packager certificate used to verify the pinned Wine package
- documentation and tests

The repository does not distribute Live for Speed executables, tracks, cars, textures, account data, or unlock data.

## Game download

The user confirms desktop first-run setup or starts `lfs-linux install`. The wrapper then downloads the official installer directly from `https://www.lfs.net/`.

The wrapper verifies the exact installer size and SHA-256 digest before local extraction. It does not execute or patch the installer, and it does not patch installed game files. LFS can apply its own in-game updates; the wrapper only records their protected-file inventory after the trusted game session exits.

Live for Speed remains proprietary software. Its terms apply separately: <https://www.lfs.net/agreement>.

The terms state that the developers can change LFS and that users must expect updates. They also restrict account credentials and unlock codes. Never report these values in an issue.

## Wine and Arch signing certificate

The wrapper downloads the exact Wine package from the Arch Linux Archive and verifies its detached signature with the shipped Peter Jung packager certificate before extraction. The certificate contains public key and certification packets only; no private key is distributed. It was exported from the Arch Linux keyring, whose package is distributed under GPL-3.0-or-later. Wine remains licensed by its upstream project under LGPL-2.1-or-later.

The package signature authenticates the Arch packager and package bytes. It does not by itself prove reproducible binary-to-source correspondence. The wrapper separately pins the package digest and validates every extracted runtime file and link.

## DXVK

The wrapper downloads an official DXVK release from its upstream GitHub project. DXVK uses the Zlib license.

The wrapper deploys only the audited 32-bit `d3d11.dll` and `dxgi.dll` required by LFS 0.8C20 new graphics. It does not modify either DLL.

## Names and trademarks

Live for Speed and LFS can be trademarks or identifiers of their respective owners. The project name describes compatibility and does not imply endorsement.

The community icon is original. It does not copy the official LFS logo.

## Redistribution and mirrors

Do not add the proprietary game installer to release assets, package repositories, mirrors, or source archives without written permission.

Do not add a Flatpak manifest that bundles or downloads LFS for Flathub submission without upstream authorization. Current Flathub rules require official upstream maintenance for Wine-based Windows applications.

## Takedown or upstream request

Upstream can request a name, metadata, download, or packaging change. Maintainers must pause affected releases and resolve the request before publication resumes.

This document is project policy, not legal advice.
