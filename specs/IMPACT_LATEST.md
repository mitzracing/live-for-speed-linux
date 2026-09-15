# Impact: graphical setup completion choice

## Target

`libexec/lfs-linux-ui`: transition after a successful `install` worker.

## Dependents

- `bin/lfs-linux-desktop` / core desktop command: fresh, resumed and repaired installations use the same controller.
- GTK and Zenity render the existing question protocol; no renderer or transport change.
- Already-ready launch and stale-service recovery retain their current flow.

## Test coverage

- `tests/test-desktop.py`: public controller decisions, dismissal, failure, cancellation and ordinary launch.
- `tests/test-gtk-view.py`: actual GTK completion response and renderer cleanup on an owned display.
- `tests/test-upgrade.sh`: installed entry point, bootstrap, update/restart/reopen, no recurring update approval.
- `tests/test-player-safety.py`: unchanged game preservation and process boundaries.

Risk: Medium. An intentional extra choice follows setup, but it must not become an approval gate for ordinary play or LFS updates. Add refusal regression first. No release-plan stories exist for this bounded bug fix.

Non-goals: Pamac, runtime pins, game files/configuration, focus workarounds, new dependencies, release assets and website changes. The live rendering/input failure stays open pending causal evidence.
