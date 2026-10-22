# Covenant of Embers

An original, open-source co-op (1–4 players) Borderlands-style loot FPS built on a small custom C++20 / Vulkan engine. Inspired by the spirit of Magewar and by biblical themes; not a copy of either.

Status: **M0 – foundations complete**: SDL3 window + Vulkan 1.3 (dynamic rendering, sync2) triangle, CI, asset lint, cooker stub. See [docs/PLAN.md](docs/PLAN.md) for the full design and [ADR-0001](docs/adr/0001-language-and-libraries.md) for the language (C++20) and library choices.

## Build (Linux)
```sh
cmake --preset debug
cmake --build --preset debug
./build/debug/covenant
```
Requires CMake ≥ 3.25, Ninja, a C++20 compiler (GCC 13+/Clang 17+), and the Vulkan SDK pieces (headers, loader, glslc; validation layers recommended). SDL3 is used from the system when installed; otherwise CMake fetches and builds a pinned release (force with `-DCOE_FETCH_SDL3=ON`).

### Sanitizers (ASan + UBSan)
```sh
cmake --preset asan
cmake --build --preset asan
ctest --test-dir build/asan -LE window     # or: ctest --preset asan
```
UBSan is fatal and leak checking is on; ctest sets the sanitizer and Vulkan-loader environment (see [ADR-0001](docs/adr/0001-language-and-libraries.md)). To run a sanitized binary by hand, export `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1` first.

## CI
`.github/workflows/ci.yml` builds with clang + Ninja on Ubuntu 24.04 in two jobs (`debug` and `asan` presets) and runs `ctest -LE window` in each on Mesa lavapipe (software Vulkan) with validation layers installed, so any validation error fails CI. Tests labelled `window` need a display and run only locally. Windows/MSVC, clang-tidy and clang-format jobs are deferred until after the vertical slice.

## Licenses
- Code: Apache-2.0 (see `LICENSE`).
- Original assets: CC BY-SA 4.0 (`LICENSE-ASSETS`, to be added with the first original asset).
- Third-party assets keep their own licenses; every one is listed in `ASSETS.toml` and `CREDITS.md`.

## Run / smoke tests
```sh
./build/debug/covenant                 # window, Esc to quit
./build/debug/covenant --seconds 3     # auto-quits after 3 s
./build/debug/covenant --headless      # offscreen render + pixel check (writes triangle.ppm)
ctest --test-dir build/debug           # smoke tests, asset lint, cooker tests
```
The Khronos validation layer is enabled automatically when installed (`vulkan-validation-layers`); otherwise the app warns and runs without it. Any validation error fails the run.

## Asset cooker (stub)
```sh
./build/debug/asset_cooker assets/kenney/blaster-kit   # -> build/cooked/ + manifest.json
cmake --build --preset debug --target cook             # all of assets/ -> build/debug/cooked/
```
For now it validates `.gltf/.glb/.png/.ogg` containers (pulling in files a glTF references) and copies them verbatim; `manifest.json` lists source, cooked path, type, size, FNV-1a hash and deps, sorted and timestamp-free. Real conversion (KTX2, meshoptimizer) comes later.
