# Flathub Proposal Gate

## Current status

**Blocked by policy until Live for Speed upstream participates officially.**

Flathub states that Windows software using Wine or another translation layer is accepted only when upstream submits and intends to maintain it officially.

This repository therefore does not contain a submit-ready Flatpak manifest. A community submission would misrepresent its eligibility.

## Required authorization

Before any Flathub implementation begins, obtain written confirmation from an authorized Live for Speed developer that:

1. Upstream wants an official Flathub listing.
2. Upstream authorizes use of the product name and approved artwork.
3. Upstream confirms how the proprietary installer can be acquired under Flathub rules.
4. Upstream names at least one responsible maintainer.
5. Upstream accepts the Wine/DXVK support boundary.
6. Upstream approves the app ID and metadata wording.

Store a public link to that authorization in the proposal. Do not store private email addresses or credentials.

## Proposed technical shape after authorization

- App ID controlled or approved by upstream
- Current supported Wine base application
- Supported Freedesktop or GNOME runtime
- 32-bit compatibility extension because LFS 0.8C24 remains PE32
- DXVK D3D11 and DXGI deployment
- Proprietary payload handled according to explicit redistribution permission or `extra-data`
- Persistent game state under the Flatpak app data directory
- Narrow filesystem permissions
- X11 support for current LFS compatibility
- Wayland only after behavioral validation

## Upstream request template

Subject: Official Flathub participation for Live for Speed on Linux

```text
We maintain an open-source Linux compatibility wrapper that downloads and verifies the untouched official LFS installer archive, extracts its stock files locally, and runs the stock game with Wine and DXVK.

Flathub requires Wine-based Windows software to be submitted and maintained officially by upstream. Would the LFS team like to sponsor an official submission?

We need written approval for the listing, app ID, product name, artwork, installer acquisition method, and maintenance owners. No game files will be modified. The wrapper will clearly state the Wine/DXVK support boundary.
```

## Stop conditions

Stop the Flathub work if upstream declines, does not answer, or cannot assign an official maintainer. Continue AUR and distro-neutral releases without claiming Flathub eligibility.
