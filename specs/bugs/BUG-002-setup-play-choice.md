# BUG-002: Ask before playing after graphical setup

## Problem and cause

The owner reported that game setup finished and launched LFS without a completion choice. Installed 0.4.0 confirms this behavior: after the `install` worker succeeds, the shared desktop controller continues into `launch`. The initial button says “Install and play,” but the requested behavior is now a separate choice after setup finishes.

Scope: the shared controller used by GTK and Zenity, its regression tests, and affected documentation. The owner subsequently authorized review, fixes, commit and deployment. That approval does not permit an unverified graphics workaround, game reset or driver change. Live game checks request a separate launch confirmation. Security impact: no exploit path identified; unexpected launch and input capture are usability failures.

## Plan and acceptance

1. Reproduce refusal of post-setup play with a failing controller regression.
2. Label setup actions Install or Repair. After successful setup, show “Setup complete” with Play now and Close choices. Dismissal or dialog failure must not launch, repeat setup, or remove installed data.
3. Preserve immediate ordinary launch for ready games. Choosing Close after setup must allow a later menu launch without repeating setup or asking for update approval.
4. Cover acceptance, Close, dialog failure, resume and repair. Retain cancellation, renderer failure, private process lifetime, installed update/restart/reopen and player-preservation checks.
5. Record exact tests and distinguish fixture behavior from installed/native desktop acceptance.

Maintenance owner: project maintainer. Recovery: reverse this narrow source patch without touching player data. Publication is now authorized, but its verification gates remain mandatory. The installed 0.4.0 package and immutable release assets remain unchanged until a verified successor is ready.

## Separate unresolved display failure

The same report includes an invisible/unusable game window and game clicks while interacting with the desktop. Read-only inspection found LFS alive, its 1920×1080 X11 window marked fullscreen, and another window active. The launcher had passed `/windowed=yes`. DXVK initialized the NVIDIA Vulkan device; initial Mesa EGL warnings do not establish causation.

Only the verified LFS window was minimized as temporary containment. Its process remained alive. The owner later confirmed closing LFS and clarified that the game itself, not only its taskbar preview, was invisible. This is not proof of a Wine, driver, compositor or focus root cause, and the completion-choice patch does not claim to fix rendering. No game configuration or driver changes are part of this patch.

## Source verification checkpoint

The new refusal regression failed because the controller still launched after installation, then passed with the completion choice. `tests/test-desktop.py` passed 20 tests, `tests/test-player-safety.py` passed 17, and display-free `tests/test-gtk-dialog.py` passed 4. `bash tests/test-upgrade.sh`, shell/Python syntax, ShellCheck and `git diff --check` passed.

After the owner closed LFS and authorized review/fix/commit/deploy, `make gtk-check` passed all 10 native GTK tests on owned Xephyr display :111 with disposable workers. The new completion Close test passed without launching any real game. Two live-game confirmation attempts expired before approval, so no real game was started. The invisible-game failure remains a separate release blocker; native widget tests do not prove it fixed.

Evidence: `artifacts/launch-focus-20260915T125849Z/` in the maintainer checkout. This private evidence is not shipped in packages.
