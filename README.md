# Covenant of Embers

An original, open-source co-op (1–4 players) Borderlands-style loot FPS built on a small custom C++20 / Vulkan engine. Inspired by the spirit of Magewar and by biblical themes; not a copy of either.

Status: **M0 – foundations**: SDL3 window + Vulkan 1.3 (dynamic rendering, sync2) triangle. See [docs/PLAN.md](docs/PLAN.md) for the full design.

## Build (Linux)
```sh
cmake --preset debug
cmake --build --preset debug
./build/debug/covenant
```
Requires CMake ≥ 3.25, Ninja, a C++20 compiler (GCC 13+/Clang 17+), and the Vulkan SDK pieces (headers, loader, glslc; validation layers recommended). SDL3 is used from the system when installed; otherwise CMake fetches and builds a pinned release (force with `-DCOE_FETCH_SDL3=ON`).

## CI
`.github/workflows/ci.yml` builds with clang + Ninja on Ubuntu 24.04 and runs `ctest -LE window` on Mesa lavapipe (software Vulkan) with validation layers installed, so any validation error fails CI. Tests labelled `window` need a display and run only locally.

## Licenses
- Code: Apache-2.0 (see `LICENSE`).
- Original assets: CC BY-SA 4.0 (`LICENSE-ASSETS`, to be added with the first original asset).
- Third-party assets keep their own licenses; every one is listed in `ASSETS.toml` and `CREDITS.md`.

## Run / smoke tests
```sh
./build/debug/covenant                 # window, Esc to quit
./build/debug/covenant --seconds 3     # auto-quits after 3 s
./build/debug/covenant --headless      # offscreen render + pixel check (writes triangle.ppm)
ctest --test-dir build/debug           # runs both smoke tests
```
The Khronos validation layer is enabled automatically when installed (`vulkan-validation-layers`); otherwise the app warns and runs without it. Any validation error fails the run.
