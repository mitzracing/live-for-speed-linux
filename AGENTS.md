# Wrapper mission

Help players get Live for Speed running in a few clicks, then get out of its way.

## Non-negotiable behavior

- One application-menu icon: install once, play, update inside LFS, restart, fully exit, and reopen. Normal use requires no terminal or Wine configuration.
- The wrapper owns setup and compatibility components. LFS and the player own installed game files and updates.
- Never gate an installed game on fingerprints, version allowlists, update journals, rebaselining, or wrapper approval of an LFS update.
- Compatibility repair preserves the entire existing game and player data. Never downgrade an updated game to the bootstrap or automatically discard either surviving recovery tree.
- Authenticate downloads and wrapper-owned Wine/DXVK inputs. Reject unsafe extraction and incomplete executables without overwriting player files. These safeguards are not installed-game ownership.
- Preserve updater-restarted game processes. Never kill a running game because its original Wine parent or graphical feedback exits.
- Keep the launcher lightweight: no background GUI, daemon, second installer, or speculative management framework. GTK and Zenity share one controller.

## Working discipline

- Inspect current source and the actual installed wrapper; do not confuse them. Read `docs/ARCHITECTURE.md` for ownership and `docs/RELEASE-CANDIDATE.md` for current proof limits.
- Make the smallest change that improves the player journey. Do not introduce a fork, rewrite, dependency, or broader support matrix without approval.
- Keep existing user work and executable modes. Never mutate a real prefix or player data as a side effect of building, publishing, or testing.
- Use focused behavioral regressions while developing. Run the full release checks after freezing the candidate, not after every prose change.
- Preserve public lifecycle tests in `tests/test-upgrade.sh`, controller tests in `tests/test-desktop.py`, and player safety tests in `tests/test-player-safety.py`. Prefer public behavior over assertions about source layout.
- Discover checks from `Makefile` and `.github/workflows/ci.yml`: `make test`, `make gtk-check` on an owned display, and package checks in supported disposable environments. Follow `docs/RELEASING.md` for publication.
- Report evidence honestly: fixture, package, and widget checks do not prove real gameplay or graphical-store installation. Public tests must disclose open acceptance checks; never invent supported store listings.
- Stop when the agreed player outcome and checks are satisfied. Record nonblocking improvements separately rather than expanding the release.
