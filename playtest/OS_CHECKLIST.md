# Per-OS manual checklist (BUILD_PLAN step 86)

Run on Linux (KDE Wayland + X11) and Windows 10/11. Tick each; note the OS + GPU.

## Gamepad (step 77)
- [ ] Xbox pad (XInput on Windows, xpad/evdev on Linux): left stick moves, right stick looks, triggers cast/focus.
- [ ] PlayStation pad (DS4/DualSense): same buttons by position (A=Cross, B=Circle...).
- [ ] Start opens the pause menu; D-pad/left stick + A navigates every menu (main, pause, settings, inventory, station, fast travel, dialogue choices).
- [ ] Settings > rebind an action with a pad button: keyboard bind kept, tooltip shows the pad bind.
- [ ] Hot-plug a pad mid-game: still works.

## Mouse
- [ ] Click captures the mouse; Esc frees it; mouse look smooth at 144 Hz.
- [ ] Alt+Tab (and Super/Win key) releases the mouse; clicking back recaptures it.
- [ ] No cursor drift out of the window in exclusive fullscreen.

## Display
- [ ] Windowed / Borderless / Exclusive fullscreen switch live from Settings; Alt+Tab out and back in each.
- [ ] Alt+Enter not required (no-op is fine).
- [ ] 125 % / 150 % / 200 % scaling (Windows display settings, KDE scale): UI scale auto readable; manual UI scale overrides.
- [ ] Multi-monitor: fullscreen opens on the current monitor.

## Renderer
- [ ] Default (Vulkan) starts; log shows the driver.
- [ ] Settings > Renderer d3d12 (Windows) / opengl3 -> restart -> override.cfg next to the exe -> that driver in the log.
- [ ] Renderer auto removes override.cfg.
- [ ] Machine without Vulkan (or `--rendering-driver opengl3`) falls back and runs.
