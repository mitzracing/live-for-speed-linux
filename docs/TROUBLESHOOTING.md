# Troubleshooting

Right-click **Live for Speed Linux** in the application menu and choose **Help and Diagnostic Report**. Preview the summary before saving it or opening support. Normal installation, compatibility repair, play, and updates require no terminal. Commands below are optional advanced diagnostics.

## LFS updated itself

Accept updates inside LFS and follow its restart prompt. After playing and closing the game, reopen **Live for Speed Linux** normally. Wrapper 0.4.0 does not fingerprint the installed game or require update approval, recovery records, or newer version-marker files.

Older wrappers can reject a working updated game with `recorded in-game update baseline drifted outside a trusted LFS session`. That message does not prove an outside change. Do not delete, downgrade, or rebaseline the game to silence it. Use a checked wrapper with the new update policy; the application-menu entry must point to that installed wrapper, not an older user-local copy. The 0.4.0 candidate still needs exact-package and real-game acceptance before publication.

The version displayed inside LFS is the game version. `LFS pin` in wrapper diagnostics describes only the first-install bootstrap. Old `game-update*.manifest` and `launch-session.env` files are retained but ignored. The legacy `recover-update` CLI command explains that normal launch replaces recovery.

## Previous session has not closed

Close LFS normally. If the launcher offers **Close previous session**, use it to stop the remaining processes from this game's private Wine prefix. Launch never kills an updater-restarted game automatically.

For optional CLI control:

```bash
lfs-linux stop
```

Only this wrapper's Wine/Windows processes are targeted. Unrelated applications that inherited `WINEPREFIX` are ignored.

## Download or first setup fails

Check the internet connection and available disk space, then choose **Retry**. Completed verified downloads and partial downloads are reused. Cancel stops only the owned preparation worker and keeps existing player files.

Bootstrap archives, nested archives, final seed files, Wine, and DXVK remain verified. If an integrity failure repeats, open Help and report it. Do not bypass checks or patch `LFS.exe`.

## Compatibility components need repair

Open the launcher and choose **Repair and play** when offered. The setup action can also check and repair components. This repairs Wine/DXVK without replacing the installed game or player files.

Optional diagnostics and repair:

```bash
lfs-linux doctor
lfs-linux install
```

The exact audited Arch Wine 11.15-1 payload is required. Setup provisions it privately when the exact system package is unavailable. A different system Wine version does not need removal or manual configuration.

## Game executable is missing or cannot be opened

The launcher keeps an existing game directory if `LFS.exe` is missing, empty, linked, or unreadable. It will not put an older bootstrap over a partly updated game.

Keep the whole game directory, including profiles, settings, replays, and account state. Restore a known complete game backup or contact support before replacing files. Component repair is not a game rollback. Legacy `.lfs-game-backup` state is restored only when no current game directory exists; if both exist, both are kept.

The wrapper does not verify every installed game asset. If LFS itself reports a missing file, follow the game's supported repair guidance with a backup rather than deleting player data.

## Vulkan or DXVK failure

Install the current Vulkan driver for the GPU through the distribution's driver tools. On Arch, select the matching `vulkan-driver` provider. Repair compatibility components through the launcher if its DXVK files are missing or changed.

Optional GPU check:

```bash
vulkaninfo --summary
lfs-linux doctor
```

## Wine package signature failure

The wrapper checks the Wine archive, detached signature, pinned certificate, and exact signer fingerprint before extraction. Repeated failure requires a maintainer report, not a verification bypass. The signature authenticates the archived package and packager, not reproducible correspondence to Wine source.

## Missing audio

Open the system audio mixer while LFS runs. Confirm that `LFS.exe` is not muted. Press `W` in LFS to initialize sound again; `N` toggles sound. If no stream appears, report the distribution and audio system through Help.

## Full-screen recovery

Press `Shift+F4` to return to windowed mode. Each launch passes `/windowed=yes` without editing `cfg.txt`.

## Advanced diagnostics

```bash
lfs-linux doctor
lfs-linux status
less ~/.local/state/lfs-linux/latest.log
grep 'lfs-linux event=' ~/.local/state/lfs-linux/latest.log
```

Logs include wrapper start, Wine parent exit, updater wait, Wine wait result, and final status. Old logs can contain retired baseline events. Raw Wine/DXVK output can contain private values; do not share it without review and redaction.

```bash
journalctl --user --since today | grep lfs-linux
WINEDEBUG=+timestamp,+seh,+tid lfs-linux launch
```

## Upstream download-page changes

`lfs-linux update-check` is an optional maintainer check, not a play requirement. Status 2 means the recognized stable or public-test bootstrap changed; it does not block the installed game. Scheduled automation records a maintenance issue. Network, parsing, and GitHub failures remain errors; an inconclusive installer-header probe is `unknown`.

## Remove cache or user state

`lfs-linux purge-cache` removes wrapper downloads and shader caches, not the prefix or player data. Normal package removal also preserves user state.

`lfs-linux remove` asks for confirmation because it deletes the private prefix and its player data. Back up data before confirming. Unrecognized state files are retained.

## Controller and force feedback

Connect the controller before launch. Configure it in **Options > Controls**. Force feedback depends on the wheel and Linux kernel driver. Report device model, kernel version, and an actual input test; input alone does not establish force-feedback support.
