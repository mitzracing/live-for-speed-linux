# Troubleshooting

## Start with diagnostics

```bash
lfs-linux doctor
lfs-linux status
```

Read the newest launch log:

```bash
less ~/.local/state/lfs-linux/latest.log
```

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

## Missing audio

Open the system audio mixer while LFS runs. Confirm that an `LFS.exe` stream exists and is not muted.

Press `W` in LFS to initialize sound again. Press `N` only to switch sound on or off.

Install the Wine audio dependencies recommended by the distribution when no stream appears.

## Full-screen recovery

Press `Shift+F4` to return to windowed mode.

Every wrapper launch passes `/windowed=yes`. This gives a recoverable default without editing `cfg.txt`.

## Setup reports an incomplete stock tree

The wrapper does not execute the NSIS installer under Wine. It extracts the verified official archive and its pinned nested payloads with 7-Zip, then verifies every protected stock file against the shipped 0.8C20 manifest. Player-owned settings, setups, layouts, replays, AI knowledge cache, training content, and similar paths are excluded from that inventory and preserved during repair. If packaged stock is absent or changed, diagnostics fail and `lfs-linux install` restores it from the verified archive before writing a new marker.

## Upstream update detected

Run:

```bash
lfs-linux update-check
```

A review-required result exits with status 2. It identifies whether the official stable or new-graphics public-test bootstrap changed. It is not an installation failure, does not alter the game, and does not block a newer version that LFS recorded during a trusted session.

Do not bypass checksum checks. Do not patch `LFS.exe`.

## LFS updated itself but later launch fails

Version 0.3.0 and later support this flow: launch a verified game, accept its in-game update, close LFS normally, then launch the updated game later without a wrapper update or full game download. The wrapper waits for private Wine processes to exit and writes `~/.local/share/lfs-linux/game-update.manifest` only when LFS adds a newer version marker during that session.

Run `lfs-linux status`. `Installed` should show the newer version and `game-update baseline`. Then run `lfs-linux doctor`. If protected files changed after LFS closed, diagnostics reject that out-of-session drift. Restore the recorded files or install a reviewed wrapper that contains the newer bootstrap. Do not delete player data or bypass the check.

Version 0.2.x did not record updates after exit. Wrapper 0.3.0 directly recognizes exact official 0.8C20, so an existing C19-to-C20 in-game update can be adopted with `lfs-linux install` without redownloading the game when its protected tree matches.

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
