# Security Policy

## Supported versions

Only the latest Live for Speed Linux release receives security fixes.

## Report a vulnerability

Do not open a public issue for a vulnerability that exposes credentials, account data, arbitrary code execution, or unsafe update behavior.

Contact maintainers through [GitHub private vulnerability reporting](https://github.com/mitzracing/live-for-speed-linux/security/advisories/new). Do not publish sensitive proof data.

Include the wrapper version, distribution, Wine version, affected command, minimal reproduction, and expected security boundary. Do not include an LFS password, unlock code, Wine registry, or complete home path.

## Authenticated inputs

The wrapper processes three upstream binary inputs:

1. The official LFS installer from `lfs.net`
2. The exact Arch Wine 11.15-1 package from the immutable Arch Linux Archive
3. The official DXVK release archive from GitHub

The release manifest pins byte sizes and SHA-256 digests. Wine also requires a detached signature from the exact shipped Arch packager certificate and fingerprint. This authenticates the package signer, not reproducible binary-to-source correspondence.

Changed bootstrap inputs fail closed. Before extraction, the wrapper rejects absolute paths, parent traversal, control characters, duplicate normalized names, unsupported member types, and escaping links. It extracts the verified LFS NSIS archive with 7-Zip instead of executing the installer stub. It verifies every nested archive and every final official seed file in private staging before first installation. Activation does not overwrite a destination created during extraction.

Every Wine runtime file or link is verified before any Wine executable runs. Wrapper-owned DXVK DLLs retain size and digest checks. Missing or changed compatibility components require repair; existing game files are kept.

## Installed-game ownership

After first installation, LFS and the user own the entire game directory. The wrapper does not authenticate installed game contents, require a known executable digest, scan local inventories, or approve updates. It checks for a regular, readable, nonempty, non-symlink `LFS.exe` before launch. This is a usability check, not proof of vendor authenticity or complete game assets.

This explicitly replaces the 0.3.x local-fingerprint policy. A local record was not an independent vendor signature: code running as the user could change both the game and its metadata. It also depended on Wine shutdown and version-marker assumptions that could block legitimate updates. Legacy records are now ignored and retained, not rebaselined. The compatibility `recover-update` command does not mutate them.

Setup preserves an existing game rather than replacing it with an older bootstrap. A missing or unsafe executable in an existing directory stops setup before game-file changes. A legacy swap backup is restored only when the destination is absent. If both trees exist, neither is deleted automatically.

## Process and data boundaries

Mutating operations validate an owner-only, non-symlink lock directory and regular lock file before opening the launch lock. The `/tmp` fallback cannot follow a precreated cross-user symlink. Launch takes the lock before starting the game. Wine descendants do not inherit it.

Launch waits for an updater-restarted game without automatic prefix-wide termination. If non-game Wine services remain, it leaves them running. Closing them requires the graphical **Close previous session** confirmation or explicit `lfs-linux stop`. Wine wait failures remain observable but cannot require game-fingerprint recovery on later launch.

The wrapper does not sandbox Wine. Wine applications can access host files available to the user. The private prefix isolates configuration and processes, not filesystem authority. Package removal leaves user state untouched. Explicit per-user removal requires confirmation and retains unrecognized files.

## Update policy

The wrapper never downloads or applies a game update during normal launch. LFS owns its updater. The wrapper does not patch game files or infer the actual game version from old marker filenames.

`update-check` is read-only and never changes pins. Scheduled automation may create or update one sanitized maintenance issue using only `contents: read` and `issues: write`. It cannot commit code, edit pins, open a pull request, tag, or publish. Maintainers review bootstrap updates for new installations; no update may merge or publish automatically.
