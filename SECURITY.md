# Security Policy

## Supported versions

Only the latest Live for Speed Linux release receives security fixes.

## Report a vulnerability

Do not open a public issue for a vulnerability that exposes credentials, account data, arbitrary code execution, or unsafe update behavior.

Contact the maintainers through [GitHub private vulnerability reporting](https://github.com/mitzracing/live-for-speed-linux/security/advisories/new). Do not publish sensitive proof data.

Include:

- wrapper version
- distribution and Wine version
- affected command
- minimal reproduction
- expected security boundary

Do not include an LFS password, unlock code, Wine registry, or complete home path.

## Trust model

The wrapper processes three upstream binary inputs:

1. The official LFS installer archive from `lfs.net`
2. The exact Arch Wine 11.15-1 package from the immutable Arch Linux Archive
3. The official DXVK release archive from GitHub

The release manifest pins byte sizes and SHA-256 digests. Changed bootstrap inputs fail closed. The wrapper extracts the verified LFS NSIS archive with 7-Zip instead of executing its installer stub. Shipped payload manifests verify every protected non-player game file and every Wine runtime file or link.

Before Wine starts, the wrapper verifies either that packaged game manifest or a locally recorded in-game update manifest. A local baseline is created only after a previously verified LFS session changes protected files, advances its `data/versions/*.txt` marker, and all processes in the private Wine prefix exit. Later launches verify every recorded file plus the protected-path inventory. Changes made outside that session fail closed.

A local game-update baseline proves continuity from a trusted launch, not independent vendor authenticity. LFS and Wine already execute with the user's filesystem authority, so code running as that user can alter both game state and local metadata. Package manifests remain the reproducible maintainer-audited boundary.

The wrapper does not sandbox Wine. Wine applications can access host files available to the user. The private prefix isolates configuration and processes, not filesystem authority.

## Update policy

The wrapper never downloads or applies a game update during launch. LFS can use its own in-game updater. The foreground wrapper records a completed, versioned update after Wine exits; it does not patch game files.

`update-check` performs a read-only check and never changes package pins. Scheduled automation may create or update one maintenance issue using only `contents: read` and `issues: write`; it cannot commit code, edit pins, open a pull request, tag, or publish. Report text is bounded and sanitized before it reaches GitHub. Maintainers still review each bootstrap update for new installs and repairs, and no update may merge or publish automatically.
