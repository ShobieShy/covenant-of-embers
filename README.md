# Covenant of Embers

An original, open-source co-op (1–4 players) loot FPS with Magewar-style staffs and wands, built on **Godot 4.7.2** (Forward+, GDScript). Inspired by the spirit of Magewar and by biblical themes.

Status: switched from a custom C++20/Vulkan engine to Godot 4 on 2026-10-23 ([ADR-0002](docs/adr/0002-switch-to-godot.md)). The old engine is archived in `archive/cpp-engine/` and on branch `archive/cpp-vulkan-engine`. See [docs/PLAN.md](docs/PLAN.md) for the design and [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) for the step plan.

## Run
```sh
godot --path .                        # play
godot --headless --path . -- --seconds 2   # smoke run
./tools/run_tests.sh                  # import + unit tests + smoke + asset lint
```

## Licenses
- Code: Apache-2.0 (see `LICENSE`).
- Original assets: CC BY-SA 4.0 (`LICENSE-ASSETS`, to be added with the first original asset).
- Third-party assets keep their own licenses; every one is listed in `ASSETS.toml` and `CREDITS.md`.

## Layout
- `engine/` – reusable runtime (`coe_engine` library): `core/` (fixed-timestep loop, clock), `input/` (SDL3 action map, per-tick edges, per-frame mouse look), `render/` (Vulkan renderer; `camera.*`: right-handed +Y-up view, reverse-Z infinite-far Vulkan projection, 75° vertical FOV, 5 cm near plane). `physics/` is the separate `coe_physics` library: a Jolt Physics world behind a pimpl (static/dynamic boxes, fixed-tick stepping, raycasts) and `character.*` (CharacterVirtual capsule: slide, steps, slopes, crouch shape), so nothing else includes Jolt (step 22 adds an `enemy` layer, kinematic boxes and sphere casts). `ui/` is the separate `coe_ui` library: the Dear ImGui overlay pass (`imgui_layer.*`, debug text).
- `game/` – the `covenant` executable (main loop) on top of `coe_game` (gameplay code shared with tests): `world/level.*` loads data-defined greybox levels (toml++), `world/level_physics.*` turns their boxes into static Jolt colliders, `world/headless_checks.*` verifies headless frames, `player/player_controller.*` is the FPS controller (Magewar cogito_player numbers: walk/sprint/crouch/slide/jump), `player/stats.*` the Breath pool (sprint/dash resource), `player/dash.*` the dash (charges, i-frames, air dash), `player/mana.*` the Magewar mana pool (casting resource), `player/camera_feel.*` head bob + landing dip (reduced-motion aware), `magic/wieldable.*` Magewar staffs/wands (data/magic/wieldables.toml), `magic/projectile.*` ray-swept spell bolts, `magic/casting.*` cooldown-gated casting, `magic/accuracy.*` focus (ADS) FOV tween and accuracy/spread cone, `enemies/enemy.*` enemy types (data/enemies/*.toml), health, weak points and death, `ai/state_machine.hpp` a tiny state-machine helper and `ai/gnawer.*` the Gnawer rusher AI (pure transition rules + movement, line of sight, bites), `ui/damage_numbers.*` floating damage numbers, `data/toml_read.*` the shared strict TOML readers.
- `data/` – hand-authored game data read at runtime (TOML). `data/levels/midden_greybox.toml`: the M1 greybox arena as boxes (`kind` ground/wall/ramp/crate/heap/platform, `center`/`size` in metres, `rotation` in degrees applied Y·X·Z like Godot, `color` tint; `[player_start]` = the player's feet + yaw; `[[enemy]]` = an enemy id from data/enemies + its feet + yaw). `data/enemies/training_dummies.toml` and `data/enemies/gnawer.toml`: enemy types (affinity, max_health, resist, size, weak_point, and an optional `ai = { kind = "rusher", ... }` table: ranges, speeds, bite damage/cooldown, knockback).
- `tests/` – unit tests. `tools/` – asset lint and cooker. `cmake/` – build helpers.

The simulation advances in fixed 60 Hz ticks; rendering runs at the display rate and interpolates between the last two ticks (`alpha`). Long hitches are clamped to 0.25 s so the loop never spirals.

Register every test with `coe_add_test(NAME … COMMAND … [WORKING_DIRECTORY …] [LABELS …] [PROPERTIES …])` from `cmake/CoeTesting.cmake`, never plain `add_test()`: it applies the sanitizer environment in `asan` builds, and configure fails if a test bypasses it.

## Run / smoke tests
```sh
./build/debug/covenant                 # window (Midden greybox: WASD walk, LShift sprint, Space jump, LCtrl/C crouch / slide from sprint, Q dash, LMB cast, RMB focus, 1 staff slot / 2 wand slot (0.4 s swap), mouse look), Esc to quit
./build/debug/covenant --seconds 3     # auto-quits after 3 s, logs ~180 fixed ticks
./build/debug/covenant --headless      # offscreen level render, checks floor/walls/sky on the resolved 2x MSAA image (writes midden.ppm), then the staff viewmodel head colour (vmframe.ppm)
./build/debug/covenant --level FILE    # another level TOML (errors are reported as file:line)
./build/debug/covenant --reduced-motion # no head bob / landing dip
./build/debug/covenant --crate         # also drop step 13's demo crate in front of the player (walk into it to push it)
./build/debug/covenant --wieldables FILE  # staff/wand bases (default data/magic/wieldables.toml)
./build/debug/covenant --elements FILE    # element names/colours/chart (default data/magic/elements.toml)
./build/debug/covenant --enemies FILE     # enemy types; repeatable, files are merged (default training_dummies.toml + gnawer.toml)
./build/debug/covenant --seconds 4 --gnawer-check  # step 23 check: a Gnawer 7 m ahead of the standing player must detect, chase and bite it
./build/debug/covenant --staff ID --wand ID  # loadout by wieldables.toml id (default: first staff + first wand)
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
