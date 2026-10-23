# Covenant of Embers

An original, open-source co-op (1–4 players) Borderlands-style loot FPS built on a small custom C++20 / Vulkan engine. Inspired by the spirit of Magewar and by biblical themes; not a copy of either.

Status: **M1 – gunplay prototype in progress**. M0 foundations (SDL3 window + Vulkan 1.3 triangle, CI, asset lint, cooker stub) are done; the engine/game split, the 60 Hz fixed-timestep loop, the input layer (actions per tick, mouse look per frame) and a first-person camera with a reverse-Z depth buffer the mesh pipeline (fastgltf + VMA: a lit Kenney blaster loaded from the cooked assets), the data-defined Midden greybox arena (TOML, 2× MSAA, fog) a Jolt physics world built from its boxes and a first-person controller (Jolt CharacterVirtual: WASD walk 4 m/s, LShift sprint 7 m/s on a Breath pool, Space jump, Ctrl/C crouch, crouch while sprinting to slide, Q dash with 2 charges, head bob and landing dip, mouse look, steps and ramps) and the Magewar spell data model (staffs and wands from data/magic/wieldables.toml; LMB casts a ray-swept, element-coloured bolt on the wieldable's cooldown, 1–4 pick one of the four bases; each cast spends the wieldable's mana from Magewar's 100-point pool, which regenerates 3/s after 1.5 s without casting; RMB focuses (FOV 75° → 55° in 0.2 s, mouse look scaled to match) and casts leave along a spread cone from the wieldable's accuracy, stance and bloom) are in. See [docs/PLAN.md](docs/PLAN.md) for the full design and [ADR-0001](docs/adr/0001-language-and-libraries.md) for the language (C++20) and library choices.

## Build (Linux)
```sh
cmake --preset debug
cmake --build --preset debug
./build/debug/covenant
```
Requires CMake ≥ 3.25, Ninja, a C++20 compiler (GCC 13+/Clang 17+), and the Vulkan SDK pieces (headers, loader, glslc; validation layers recommended). SDL3 is used from the system when installed; otherwise CMake fetches and builds a pinned release (force with `-DCOE_FETCH_SDL3=ON`). GLM (header-only math) is always fetched at a pinned, hash-checked release.

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

## Layout
- `engine/` – reusable runtime (`coe_engine` library): `core/` (fixed-timestep loop, clock), `input/` (SDL3 action map, per-tick edges, per-frame mouse look), `render/` (Vulkan renderer; `camera.*`: right-handed +Y-up view, reverse-Z infinite-far Vulkan projection, 75° vertical FOV, 5 cm near plane). `physics/` is the separate `coe_physics` library: a Jolt Physics world behind a pimpl (static/dynamic boxes, fixed-tick stepping, raycasts) and `character.*` (CharacterVirtual capsule: slide, steps, slopes, crouch shape), so nothing else includes Jolt.
- `game/` – the `covenant` executable (main loop) on top of `coe_game` (gameplay code shared with tests): `world/level.*` loads data-defined greybox levels (toml++), `world/level_physics.*` turns their boxes into static Jolt colliders, `world/headless_checks.*` verifies headless frames, `player/player_controller.*` is the FPS controller (Magewar cogito_player numbers: walk/sprint/crouch/slide/jump), `player/stats.*` the Breath pool (sprint/dash resource), `player/dash.*` the dash (charges, i-frames, air dash), `player/mana.*` the Magewar mana pool (casting resource), `player/camera_feel.*` head bob + landing dip (reduced-motion aware), `magic/wieldable.*` Magewar staffs/wands (data/magic/wieldables.toml), `magic/projectile.*` ray-swept spell bolts, `magic/casting.*` cooldown-gated casting, `magic/accuracy.*` focus (ADS) FOV tween and accuracy/spread cone, `data/toml_read.*` the shared strict TOML readers.
- `data/` – hand-authored game data read at runtime (TOML). `data/levels/midden_greybox.toml`: the M1 greybox arena as boxes (`kind` ground/wall/ramp/crate/heap/platform, `center`/`size` in metres, `rotation` in degrees applied Y·X·Z like Godot, `color` tint; `[player_start]` = the player's feet + yaw).
- `tests/` – unit tests. `tools/` – asset lint and cooker. `cmake/` – build helpers.

The simulation advances in fixed 60 Hz ticks; rendering runs at the display rate and interpolates between the last two ticks (`alpha`). Long hitches are clamped to 0.25 s so the loop never spirals.

Register every test with `coe_add_test(NAME … COMMAND … [WORKING_DIRECTORY …] [LABELS …] [PROPERTIES …])` from `cmake/CoeTesting.cmake`, never plain `add_test()`: it applies the sanitizer environment in `asan` builds, and configure fails if a test bypasses it.

## Run / smoke tests
```sh
./build/debug/covenant                 # window (Midden greybox: WASD walk, LShift sprint, Space jump, LCtrl/C crouch / slide from sprint, Q dash, LMB cast, 1-4 pick staff/wand, mouse look), Esc to quit
./build/debug/covenant --seconds 3     # auto-quits after 3 s, logs ~180 fixed ticks
./build/debug/covenant --headless      # offscreen level render, checks floor/walls/sky on the resolved 2x MSAA image (writes midden.ppm)
./build/debug/covenant --level FILE    # another level TOML (errors are reported as file:line)
./build/debug/covenant --reduced-motion # no head bob / landing dip
./build/debug/covenant --crate         # also drop step 13's demo crate in front of the player (walk into it to push it)
./build/debug/covenant --wieldables FILE  # staff/wand bases (default data/magic/wieldables.toml)
./build/debug/covenant --elements FILE    # element names/colours/chart (default data/magic/elements.toml)
./build/debug/covenant --model [SRC]   # step 11's tumbling model view instead (default: Kenney blaster-a); --headless writes mesh.ppm
./build/debug/covenant --input-debug   # prints actions per fixed tick + mouse look (Esc quits; mouse is captured)
ctest --test-dir build/debug           # smoke tests, unit tests, asset lint, cooker tests
./build/debug/coe_tests -sf=*test_damage.cpp  # one doctest file by hand (coe_tests --help for filters)
```
The Khronos validation layer is enabled automatically when installed (`vulkan-validation-layers`); otherwise the app warns and runs without it. Any validation error fails the run.

## Asset cooker (stub)
```sh
./build/debug/asset_cooker assets/kenney/blaster-kit   # -> build/cooked/ + manifest.json
cmake --build --preset debug --target cook             # all of assets/ -> build/debug/cooked/
```
For now it validates `.gltf/.glb/.png/.ogg` containers (pulling in files a glTF references) and copies them verbatim; `manifest.json` lists source, cooked path, type, size, FNV-1a hash and deps, sorted and timestamp-free. Real conversion (KTX2, meshoptimizer) comes later.
