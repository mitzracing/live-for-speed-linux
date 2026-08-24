# Prior Art and Decision

Date: 2026-08-14

## Candidates

| Candidate | Source | Verdict | Reason |
|---|---|---|---|
| Bottles | <https://usebottles.com/> | Extend for local proof only | It proved LFS compatibility, but adds a managed runtime and GUI outside the lean public launch path. |
| Native Wine | <https://www.winehq.org/> | Adopt with exact pin | Direct execution and no launcher daemon; wrapper accepts only the audited Arch 11.15-1 payload. |
| DXVK | <https://github.com/doitsujin/dxvk> | Adopt | Official D3D11-to-Vulkan implementation with manual prefix deployment documented upstream. |
| `dxvk-bin` AUR | <https://aur.archlinux.org/packages/dxvk-bin> | Study, do not depend | It proves current package availability. A direct private DXVK archive avoids a second AUR dependency. |
| Lutris/Steam/Heroic | Respective projects | Do not require | Useful user tools, but unnecessary for one direct executable and a latency-focused path. |
| Flathub | <https://docs.flathub.org/docs/for-app-authors/requirements> | Gate | Flathub accepts Wine-based Windows apps only as official upstream submissions. |
| AUR | <https://aur.archlinux.org/> | Adopt first | A thin source package can expose the wrapper in Pamac and other Arch software tools. |

## Decision

Build one distro-neutral shell core. Package that core for AUR first.

Do not submit a community Wine wrapper to Flathub under current policy. Prepare an upstream authorization request and technical proposal only.

Do not redistribute or modify LFS. Download the official installer at runtime after user action.

## Evidence

Flathub requirement:

> Windows software submissions that are using Wine ... will only be accepted if they are submitted officially by upstream with the intention of maintaining it in an official capacity.

Arch Wine announcement:

> We are transitioning the wine and wine-staging package to a pure wow64 build.

DXVK manual installation:

> copy or symlink the DLLs ... then open winecfg and manually add native DLL overrides

LFS terms:

> Improvements, fixes and/or changes made to the game, are to be expected.
