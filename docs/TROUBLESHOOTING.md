# Troubleshooting

## Start with diagnostics

```bash
lfs-linux doctor
lfs-linux status
```

Read the newest launch log:

```bash
less ~/.local/state/lfs-linux/latest.log
grep 'lfs-linux event=' ~/.local/state/lfs-linux/latest.log
```

Version 0.3.1 and later write timestamped wrapper events into each launch log: session ID and epoch, verified baseline, Wine parent status, updater-restart waits, Wine wait result, update-recording result, and final status. Raw Wine and DXVK output remains in the same file. Desktop stderr also remains available in the user journal:

```bash
journalctl --user --since today | grep lfs-linux
```

For one diagnostic terminal launch, set Wine's standard debug channels explicitly:

```bash
WINEDEBUG=+timestamp,+seh,+tid lfs-linux launch
```

This can produce a large local log. Review and redact home paths, server details, and other private values before sharing it.

## Stop a stuck game

Try the in-game command:

```text
/exit
```

Then run:

```bash
lfs-linux stop
```

The command targets only processes with this wrapper's private `WINEPREFIX`.

## Vulkan or DXVK failure

Run:

```bash
vulkaninfo --summary
lfs-linux doctor
```

Install a current Vulkan driver for the GPU. On Arch, select the matching `vulkan-driver` provider.

The wrapper verifies the private DXVK archive plus its D3D11 and DXGI prefix copies. Run `lfs-linux install` to repair a failed DXVK check.

## Wine package signature failure

Version 0.3.2 verifies the pinned Arch Wine package size, SHA-256 digest, detached signature, exact public certificate, and signer fingerprint before extraction. Delete the cached Wine archive and signature with `lfs-linux purge-cache`, then retry `lfs-linux install`. If verification still fails, do not bypass it; report the exact wrapper error. The Arch signature authenticates the archived package and its packager, not reproducible correspondence to Wine source.

## Missing audio

Open the system audio mixer while LFS runs. Confirm that an `LFS.exe` stream exists and is not muted.

Press `W` in LFS to initialize sound again. Press `N` only to switch sound on or off.

Install the Wine audio dependencies recommended by the distribution when no stream appears.

## Full-screen recovery

Press `Shift+F4` to return to windowed mode.

Every wrapper launch passes `/windowed=yes`. This gives a recoverable default without editing `cfg.txt`.

## Setup reports an incomplete stock tree

The wrapper does not execute the NSIS installer under Wine. It extracts the verified official archive and its pinned nested payloads with 7-Zip, then verifies every protected stock file against the shipped 0.8C20 manifest. Player-owned account/configuration state, debug logs, caches, downloaded mods and skins, settings, setups, layouts, replays, AI knowledge, training content, and similar mutable paths are excluded from local update inventories and preserved during repair. If packaged stock is absent or changed, diagnostics fail and `lfs-linux install` restores it from the verified archive before writing a new marker.

## Upstream update detected

Run:

```bash
lfs-linux update-check
```

A review-required result exits with status 2. It identifies whether the official stable or new-graphics public-test bootstrap changed. It is not an installation failure, does not alter the game, and does not block a newer version that LFS recorded during a trusted session.

In the repository's weekly workflow, status 2 creates or refreshes one `upstream-drift` maintenance issue and leaves the run successful with a warning. A red run now means the initial checker, downloads-page network request, workflow script, or GitHub issue synchronization failed and needs investigation. An inconclusive pinned-installer header probe is recorded as `unknown` in the issue instead of being trusted.

Do not bypass checksum checks. Do not patch `LFS.exe`.

## LFS updated itself but later launch fails

Version 0.3.0 and later support this flow: launch a verified game, accept its in-game update, close LFS normally, then launch the updated game later without a wrapper update or full game download. The wrapper waits for private Wine processes to exit and records a local protected-file manifest only when LFS adds a newer version marker during that session. Version 0.3.1 stores new manifests as `~/.local/share/lfs-linux/game-update-<sha256>.manifest`; it still reads the legacy v0.3.0 `game-update.manifest` file.

Version 0.3.0 could mistake an updater-restarted game for lingering Wine services after 60 seconds and stop it before recording the new baseline. Version 0.3.1 fixes this: launch never performs an automatic prefix-wide kill. It waits while restarted `LFS.exe` is active. If non-game Wine services remain after the grace period, it leaves them running, retains `~/.local/share/lfs-linux/launch-session.env`, and tells you to run `lfs-linux stop`. Protected changes are not recorded automatically on that failure path.

Run `lfs-linux status`. `Installed` should show the newer version and `game-update baseline` after normal completion. If status instead reports interrupted launch evidence, inspect `latest.log`, confirm LFS performed the update and the private prefix is stopped, then run:

```bash
lfs-linux recover-update
lfs-linux doctor
```

Recovery validates exact-schema pending evidence, prior baseline hashes, matching launch-log session/epoch, ownership, and newer version marker. It acquires an owner-private, non-symlink launch lock and requires a stopped prefix. Before asking, it snapshots and validates current protected files and shows that snapshot digest. After confirmation it rechecks evidence, marker, log, version, process state, and a second protected-file inventory; the two inventory digests must match. Missing, changed, or raced evidence or content fails without modifying the previous marker/manifest pair. Do not create recovery metadata manually, bypass confirmation, or use recovery for arbitrary out-of-session drift.

If no recovery evidence exists, or protected files changed after LFS closed, diagnostics reject that drift. Restore the recorded files or install a reviewed wrapper containing the newer bootstrap. Do not delete player data. Version 0.2.x did not record updates after exit. Wrapper 0.3.0 directly recognizes exact official 0.8C20, so an existing C19-to-C20 in-game update can be adopted with `lfs-linux install` without redownloading the game when its protected tree matches.

## Upgrade stops before changing the game

Wrapper 0.3.x upgrades only a complete, exact LFS 0.8C19 protected payload to its packaged 0.8C20 bootstrap. It preserves files outside both protected manifests and swaps a needed verified tree atomically. A player file that collides with a newly added stock path is retained by content hash under `~/.local/share/lfs-linux/migration-conflicts/`. A valid locally recorded newer game is preserved instead of replaced. Unknown or unrecorded protected-file drift stops before mutation.

## Wine runtime problem

Wrapper 0.3.x accepts only the complete audited Arch Wine 11.15-1 payload. It uses that exact system package or provisions the pinned archive privately. Back up the state directory before manual recovery:

```bash
cp -a ~/.local/share/lfs-linux ~/lfs-linux-backup
```

Run `lfs-linux install` to reprovision a missing or changed private runtime, then run `lfs-linux doctor`. A different Wine version is rejected; maintainers must publish new archive and runtime-manifest pins after compatibility testing. Do not delete the prefix unless the backup is complete.

## Remove cache without removing player data

```bash
lfs-linux purge-cache
```

This command keeps the Wine prefix, profiles, settings, replays, and unlock state.

## Remove everything

```bash
lfs-linux remove
```

The command asks for confirmation because it removes game-owned player data in the private prefix. Package removal alone preserves this data.

## Controller and force feedback

Connect the controller before launch. Configure it in **Options > Controls**.

Input can work when force feedback does not. Force feedback depends on the wheel and Linux kernel driver.

Do not report controller support without the device model, kernel version, and a real input test.
