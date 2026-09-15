# BUG-003: Game window invisible while receiving input

## Report and evidence

After fresh setup with wrapper 0.4.0, the owner reported that the game itself was invisible while mouse clicks on the desktop produced in-game sounds. This was not only a missing taskbar thumbnail. The owner subsequently closed LFS; its launch log recorded a clean exit.

Host observation: Manjaro, KDE/X11, KWin 6.7.4-7, NVIDIA RTX 3070 mobile, matching NVIDIA kernel/userspace driver 610.57.04, Wine 11.15 and DXVK 3.0.2. The private game process was alive. Its X11 window was viewable, 1920×1080 and marked fullscreen, while another window was active.

LFS reported a windowed render target. The actual command included the documented `/windowed=yes`. DXVK created a 1920×1080 swapchain without a recorded device-creation failure. After the owner closed the game, its saved configuration said `Start Windowed 1` and `Window 80 80 1680 980`. Saved startup preferences do not prove the earlier runtime mode.

During the affected session KWin logged:

```text
Invalid framebuffer status:  "GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT"
0x502: GL_INVALID_OPERATION error generated. Framebuffer name must be generated before being bound.
```

These are relevant correlations, not proof that KWin caused the missing game image. Initial Mesa EGL warnings likewise do not establish the cause; both KWin and DXVK identified the NVIDIA device.

Security impact: no exploit path identified. Usability severity is high because invisible input capture prevents safe normal interaction.

## Investigation and verification plan

- **Reproduce:** obtain one explicit launch confirmation, use the installed menu route and observe the actual game image, input and window state. Two confirmation attempts expired; neither started a game.
- **Isolate:** distinguish rendering/compositing failure from an activation/geometry problem after delayed automatic launch. Compare visible pixels, window state and timestamps before changing settings.
- **Hypotheses:** compositor/import failure (framebuffer errors); launch activation/geometry race (fullscreen metadata and inactive window); upstream game/runtime presentation behavior. Each requires a controlled observation that can falsify it.
- **Verify:** reproduce failure, apply only an evidence-backed change, then prove visible game output, correctly routed input, normal exit and menu reopen. No root cause or graphics fix is currently verified.

The initial containment minimized only the verified LFS window. It did not kill or restart the game, synthesize input, modify player data or change system graphics settings. The owner later closed the game.

## Release boundary

BUG-002's completion choice is a separate controller fix. Its tests do not resolve this display failure. Do not publish a claimed graphics fix, disable global compositing, change drivers, alter runtime pins or edit game settings on this evidence alone. A bounded live check needs the owner's launch confirmation; if unavailable, stop rather than silently launch.

Maintainer owns investigation and any wrapper fix. Owner confirms actual visibility and input behavior. No rollback is needed for graphics code because no graphics change was made. Preserve all game/player files and immutable released artifacts.

Private evidence: `artifacts/launch-focus-20260915T125849Z/`, especially `compositor-inspection.json`, `invisible-game-log-inspection.json`, `post-close-display-inspection.json`, `display-check-blocker.json` and the initial window/process records.
