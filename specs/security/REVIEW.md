# 0.4.0 release security review

Type: direct in-session review. Base: `4355f776cc5c0f6d2bd160986945a687666d5886`. Scope: pending 0.4.0 launcher, UI, packaging, support, and release-publication changes. No independent reviewer is claimed.

## Findings

No unresolved high-confidence HIGH security finding identified in the reviewed changes. This is code review, not certification or a penetration test.

- Download URLs, sizes, digests, Wine signer, and extraction manifests remain authenticated. Unsafe archive members fail before activation.
- Installed game content belongs to LFS and the player. Removing same-user fingerprints does not remove download authentication; documentation no longer claims local game authentication.
- Existing games and player files survive compatibility repair. Missing/linked executables stop setup without replacement. Legacy recovery never discards a surviving game tree automatically.
- Private lock ownership, process identity, updater restart waiting, and owned-worker cancellation remain. No automatic gameplay termination is added.
- GTK accepts bounded JSON dialog requests through an owner-private socket. It cannot select installer commands. View failure does not replay an operation.
- Support previews exclude known private fields; issue-title scanning and exact redacted-placeholder handling have regression coverage. Public reports still require user review.
- Packages contain wrapper files, public certificates, manifests, and documentation—not game payloads, prefixes, credentials, or private audit evidence.
- Release changes add project guidance and truthful prerelease links/metadata. They do not change runtime code, runtime pins, privileges, or remote security settings.

## Proof limits and follow-up

Security/runtime/preservation regressions are part of `make test`. Final release command receipts remain in `artifacts/release-0.4.0/`; CI must pass before publication. Coverage percentages and a configured typechecker are not available and are not claimed.

Duplicate Wine verification and source-layout-coupled tests are nonblocking performance/maintenance findings. They are not changed in this release. Real gameplay, graphical package installation, and store availability remain open as documented in `docs/RELEASE-CANDIDATE.md`.

Maintainers own wrapper/runtime security. LFS and the player own installed game content. Recovery must not downgrade game data; published corrections require a new immutable release version.
