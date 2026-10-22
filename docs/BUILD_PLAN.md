# Covenant of Embers – Build Plan

## Standing rules (every hourly run)
1. Building the next step is the priority.
2. Review the Magewar references in the project and in `~/game/magewar` (read-only), and make sure the build follows them. Reinterpret, don't copy.
3. Look for plan improvements: refine future steps, or go back and fix bugs from earlier steps.
4. Log any such changes in the history in `docs/build_state.json`.

Design source of truth: [PLAN.md](PLAN.md) (§26 milestones, §30 loot-shooter spec). Progress: [build_state.json](build_state.json) (`next_step`).
Each step is sized at ~1 hour. Every step must keep `cmake --build --preset debug` warning-free and `ctest --test-dir build/debug` green (from step 8 on, also `ctest --test-dir build/asan -LE window`), and ends with a local commit (never push). Register every test with `coe_add_test()` (cmake/CoeTesting.cmake); configure fails on a plain `add_test()`. Third-party libraries come in via CMake FetchContent, pinned + `SYSTEM` (no system installs; library list in [ADR-0001](adr/0001-language-and-libraries.md)); every new asset goes into ASSETS.toml + CREDITS.md.

Goal: a **minimal playable vertical slice**. One player walks a greybox Midden, fights Gnawers and Heaps with procedurally rolled Sidearms/Repeaters, picks up loot, levels up, clears a Breach room slice with a mini-boss, hears Kenney audio, and saves/loads.

---

## M0 – Foundations

**1. Plan + loot-shooter spec** ✅ `3b54564`. Does: docs/PLAN.md incl. §30. Files: docs/PLAN.md. Done: §30 present.

**2. Repo scaffold** ✅ `3b54564`. Does: Apache-2.0, CMake C++20, ASSETS.toml/CREDITS.md, 4 Kenney CC0 packs. Files: root files, assets/kenney/. Done: builds; manifest lists all 4 packs.

**3. Window + Vulkan triangle** ✅ `1c436e7`. Does: SDL3 window, Vulkan 1.3 device/swapchain, dynamic rendering, optional validation, headless test. Files: src/main.cpp, src/render/vk_renderer.*, shaders/. Done: both ctest smoke tests pass.

**4. CI workflow file** ✅ `05275cd`. Does: GitHub Actions workflow (ubuntu-24.04, clang, Ninja, lavapipe forced via VK_DRIVER_FILES, validation layers installed) that builds and runs `ctest -LE window`; SDL3 falls back to FetchContent (pinned release-3.4.18, `-DCOE_FETCH_SDL3=ON`) because Ubuntu 24.04 has no SDL3 package. File only; not pushed. Files: .github/workflows/ci.yml, CMakeLists.txt. Done: YAML parses; `ctest -LE window` passes locally (system SDL3 and CI-emulated fetched SDL3 + clang + lavapipe).

**5. Asset license lint** ✅ `5aca0bc`. Does: tools/check_assets.py (stdlib `tomllib`, Python ≥ 3.11) fails if any asset unit under assets/ is missing from ASSETS.toml or an entry lacks name/path/license/source, has a bad/missing/duplicate path, or has no CREDITS.md row. Asset unit = each dir directly under assets/, except vendor grouping folders that only hold sub-folders (assets/kenney/) whose children (each pack) are the units instead; loose files must be covered too; dotfiles ignored. Files: tools/check_assets.py, CMakeLists.txt. Done: ctests `asset_license_lint` + `asset_license_lint_selftest` (13 fixture cases) pass, no `window` label; temp untracked folders at assets/ and assets/kenney/ both made it fail (removed).

**6. Asset cooker stub** ✅ `68d1c88`. Does: `tools/asset_cooker` CLI (`[--root R] [--out build/cooked] PATH...`, dirs walked) validates `.gltf/.glb/.png/.ogg` containers (PNG signature/IHDR/IEND, Ogg capture pattern, GLB magic/v2/length/JSON chunk, glTF JSON object with `asset`), follows glTF/GLB external URIs (missing or out-of-root ⇒ error; referenced files cooked too), copies verbatim mirroring the source layout, and writes a deterministic `manifest.json` (source, cooked, type, bytes, FNV-1a 64 hash, deps). Any error ⇒ exit 1, no manifest. Refuses to cook into assets/. `cook` CMake target cooks all of assets/. Files: tools/asset_cooker/{main.cpp,check_manifest.py}, CMakeLists.txt, README.md. Done: running it on assets/kenney/blaster-kit writes build/cooked/manifest.json (86 files: 40 glb + 46 png); ctests `asset_cooker_selftest` (15 fixture cases), `asset_cooker_blaster_kit` + `asset_cooker_manifest_check` (every source file listed, cooked bytes/hash match).

**7. ADR-0001 language choice** ✅ `63dc078`. Does: [docs/adr/0001-language-and-libraries.md](adr/0001-language-and-libraries.md) (Context/Decision/Consequences) records C++20 over Rust, FetchContent-only pinned deps (no vcpkg/CPM), SDL3 system-or-FetchContent policy, and the per-step library table (GLM, VMA, fastgltf+simdjson, toml++, Jolt, doctest, ImGui, stb_truetype, miniaudio). `asan` configure/build/test presets: `COE_SANITIZE=ON` adds `-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer`; ctest env (ASAN/UBSAN/LSAN_OPTIONS + `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1` so dlclose'd Mesa ICDs don't show up as `<unknown module>` leaks) set in CMakeLists.txt; documented, empty `tools/sanitizers/lsan.supp`. CI is a `debug`/`asan` matrix (two jobs). Windows/MSVC, clang-tidy, clang-format deferred to step 51. Files: docs/adr/0001-language-and-libraries.md, CMakePresets.json, CMakeLists.txt, .github/workflows/ci.yml, tools/sanitizers/lsan.supp, README.md. Done: ADR has Context/Decision/Consequences; README links it; `cmake --preset asan && ctest --test-dir build/asan -LE window` passes (GCC + RADV, and clang + fetched SDL3 + lavapipe CI emulation). **M0 complete.**

## M1 – Gunplay prototype

**8. Engine/game split + fixed-timestep loop** ✅ `36a0509`. Does: renderer moved to engine/render (`coe_engine` static lib, includes rooted at the repo: `engine/...`, `game/...`; shader build lives in engine/CMakeLists.txt); game/ builds `covenant` (binaries still land in build/<preset>/); shared `coe_warnings` interface target. `coe::FixedTimestep` (engine/core) accumulates in exact integer ns×hz units (N s of frames ⇒ exactly N×hz ticks, no float drift), 60 Hz, `alpha()` in [0,1), 0.25 s hitch clamp with dropped-time counter; `monotonicNs()` clock. Placeholder `game::SpinDemo` spins the triangle on the tick and renders `lerp(prev, curr, alpha)` via a vertex push constant (wrap after blend). `--seconds N` logs frames + fixed ticks and fails on a tick-count mismatch. `coe_add_test(NAME COMMAND [WORKING_DIRECTORY] [LABELS] [PROPERTIES])` in cmake/CoeTesting.cmake applies `COE_SANITIZER_TEST_ENV` in the defining dir; `coe_verify_tests()` fails configure if any test in our tree bypasses it. Files: engine/{CMakeLists.txt,core/{fixed_timestep,clock}.*,render/vk_renderer.*}, game/{CMakeLists.txt,main.cpp,core/spin_demo.hpp}, tests/{CMakeLists.txt,test_fixed_timestep.cpp}, cmake/CoeTesting.cmake, shaders/triangle.vert, CMakeLists.txt, README.md, ci.yml. Done: headless + window smoke pass (validation on, 0 messages); `--seconds 3` logs 180 fixed ticks at ~127 fps; `ctest --test-dir build/asan -N --show-only=json-v1` shows ASAN/UBSAN/LSAN_OPTIONS + loader env on all 8 tests (root, game/, tests/); ctest `fixed_timestep` (180 ticks at 30/60/144/240 fps and jitter, alpha, clamp, 120 Hz, spin interpolation/wrap).

**9. Input layer** ✅ `62334fa`. Does: `coe::input` (engine/input) action map (MoveForward/Back/Left/Right, Jump, Fire, Aim, Reload, Sprint, Dash, Crouch, Interact, Weapon1–4) on SDL3 physical keys (scancodes) + mouse buttons, several bindings per action (held while any is down), key auto-repeat ignored, focus loss releases everything; default layout WASD/Space/LMB/RMB/R/LShift/Q/C+LCtrl/F/1–4. `InputState::handleEvent()` per render frame; `consumeTick()` per fixed tick returns held state + press/release edges (+ press count) latched since the previous tick, so a frame with 0 ticks can't drop a press and a frame with 2+ ticks can't double it; `takeLook()` per render frame returns accumulated relative mouse motion (applied per frame for latency, never per tick). covenant turns on relative mouse mode, applies look at 0.25°/count (Magewar's default) to the placeholder triangle until the camera lands, `--input-debug` prints per-tick edges/held actions and per-frame look, `--input-script` pushes scripted synthetic SDL events through the real queue and fails unless every scripted press reached exactly one tick. Files: engine/input/input.{hpp,cpp}, tests/test_input.cpp, game/main.cpp, engine/CMakeLists.txt, game/CMakeLists.txt, tests/CMakeLists.txt, tools/sanitizers/lsan.supp. Done: ctest `input` (synthetic SDL_Events → actions; tap across 0-tick frames consumed exactly once; press in a 2-tick frame not doubled; double tap counts 2; repeats/multi-binding; focus loss; rebind; per-frame look; 4000-frame jittered loop ×3 seeds: presses seen = taps) and window ctest `input_script_window` (`covenant --seconds 2 --input-debug --input-script`: each scripted action printed once per press, 120 ticks, 0 validation messages).

**10. Math, camera and depth buffer** ✅ `cfa9092`. Does: GLM 1.0.3 via FetchContent (release tarball + URL_HASH SHA256, SYSTEM, header-only `glm::glm` with `GLM_BUILD_LIBRARY OFF`; `GLM_FORCE_RADIANS` + `GLM_FORCE_DEPTH_ZERO_TO_ONE` PUBLIC on `coe_engine`). `coe::Camera` (engine/render/camera.*): right-handed, +Y up, −Z forward at yaw 0, yaw positive = turn left, pitch clamp `kMaxPitch` ±89°, 75° *vertical* FOV and 0.05 m near plane (Godot Camera3D defaults that Magewar's cogito_player keeps), Vulkan-native projection (clip Y down) with reverse-Z and an infinite far plane (depth = near/distance; Godot's 4000 m far is unnecessary). Renderer: D32_SFLOAT depth (D32_SFLOAT_S8 fallback, format features queried; headless also needs TRANSFER_SRC) created with the swapchain, one image shared by both frames in flight with an EARLY|LATE_FRAGMENT_TESTS barrier, cleared to 0, `GREATER` test, back-face culling (CCW from outside); `FrameParams{Camera camera; glm::mat4 model}` becomes `{viewProj(aspect of the target), model}` = exactly 128 B of vertex push constants. shaders/basic.{vert,frag} (replace triangle.*) generate a unit cube from `gl_VertexIndex` (36 verts, no vertex buffer until step 11) with Lambert + 0.2 ambient from a fixed directional light. `game::CubeDemo` (replaces SpinDemo) tumbles yaw/pitch per fixed tick and renders `lerp(prev, curr, alpha)` wrapped after blending; mouse look now turns the camera. Headless renders the tick-0 pose and reads back colour + depth (writes cube.ppm). Files: engine/render/{camera,vk_renderer}.*, shaders/basic.*, game/core/cube_demo.hpp, game/main.cpp, tests/{test_camera,test_fixed_timestep}.cpp, CMakeLists.txt, engine/CMakeLists.txt, tests/CMakeLists.txt, README.md, ADR-0001. Done: `covenant --headless` (validation on, 0 messages): corner rgb(5,5,13) depth 0.0 (clear), centre rgb(142,71,21) lit with depth 0.0326 > cube-origin depth 0.0227 (front face wins), 39 cube samples with red 51..229 (several faces shaded differently); ctest `camera` (near→1, depth = near/d, ∞→0, behind-camera w<0, world up → NDC −y, vertical FOV edge at ±1 for any aspect, yaw/pitch signs, translation) and `fixed_timestep` cube interpolation/wrap; debug 11/11 incl. window tests, asan 9/9 `-LE window`, clang `-Werror` 9/9, warning-free.

**11. Mesh pipeline + glTF loading** ✅ `a5c4b7d`. Does: fastgltf 0.9.1, VMA 3.4.0 and simdjson 4.6.11 via FetchContent (release tarballs + URL_HASH SHA256, SYSTEM); simdjson's single-header amalgamation is our own static `coe_simdjson` aliased `simdjson::simdjson` before fastgltf, so fastgltf skips its unhashed download. New CPU-only `coe_assets` lib (engine/assets, shared by asset_cooker and coe_engine): `assets::Vertex` {pos, normal, uv, rgba} 48 B, `MeshData` {vertices, uint32 indices, submeshes {firstIndex, indexCount, material, doubleSided}, bounds}; `loadGltfMesh()` walks the default scene (explicit DFS, cycle guard), bakes node world matrices (normals by inverse-transpose, winding flipped when det<0), generates area-weighted normals when NORMAL is missing, makes non-indexed primitives sequential, skips non-triangle modes, takes material baseColorFactor + doubleSided, errors on 0 triangles/out-of-range indices/short buffers; `inspectGltf()` (cooker) checks accessors/bufferViews/buffers, index ranges, POSITION, local URIs and lists external files with minimum sizes. `CookedManifest` reads `cooked/manifest.json` with simdjson (format/version/count checks, rejects absolute or `..` paths) and `resolve()` verifies size + fnv1a64 of the file and its deps before use. Renderer: VMA for attachments + buffers (findMemoryType gone), `uploadMesh()` → `MeshId` (staging copy, one-shot submit), vertex input from `vertexLayout()`, two pipelines (back-face cull / double-sided), `FrameParams{camera, draws: [DrawItem{mesh, model}]}` with per-draw push constants. shaders/basic.* take position/normal/colour attributes (back faces of double-sided materials use the flipped normal). covenant depends on the `cook` target and loads `--model` (default Kenney blaster-a.glb) from `--cooked` (default build/<preset>/cooked), fitted to 1 m, turned side-on and tumbled by `game::TumbleDemo` (renamed CubeDemo); headless writes mesh.ppm. `coe_add_test()` now applies a default TIMEOUT (120 s, `COE_TEST_TIMEOUT`). Files: engine/assets/{mesh_data,hash,gltf_loader,manifest}.*, engine/render/{mesh,vma_impl,vk_renderer}.*, shaders/basic.*, game/{main.cpp,CMakeLists.txt,core/tumble_demo.hpp}, tools/asset_cooker/main.cpp, tests/{test_gltf_loader,test_fixed_timestep}.cpp, tests/CMakeLists.txt, cmake/CoeTesting.cmake, CMakeLists.txt, engine/CMakeLists.txt, README.md, ADR-0001. Done: `covenant --headless` (validation on, 0 messages): `[mesh] blaster-a.glb: 470 triangles, 820 vertices, 2 submesh(es)`; corner rgb(5,5,13) depth 0 (clear), centre rgb(154,154,154) depth 0.02363 > model-origin depth 0.02331 (non-clear, front surface), 30 model samples luma 51..252; ctest `gltf_loader` (mirrored child under a translated parent: positions, CCW winding restored, generated +Z normals, indexed + non-indexed submeshes, points skipped, material colour/doubleSided; truncated/missing .bin, index out of range, node cycle, points-only, bad JSON rejected; manifest size/hash/dep/path/count/format errors) and `gltf_cooked_blaster_kit` (all 40 cooked models load, 13638 triangles; blaster-a 470 tris, unit normals); cooker self-test +9 glTF cases; `smoke_headless_missing_model`/`_bad_cooked_dir` fail with an `[assets]` error; debug 15/15 incl. window tests, asan 13/13 `-LE window`, clang `-Werror` 13/13, warning-free.

**12. Greybox Midden arena**
- Does: data-defined boxes (TOML, parsed with toml++ via FetchContent per ADR-0001) forming ground, walls, ramps, crates; simple directional lighting. Boxes go through step 11's mesh path: build one unit-cube `assets::MeshData` in code (24 verts with per-face normals, `Vertex.color` = per-box tint) and `uploadMesh()` it once, then one `DrawItem{mesh, model}` per box (model = translate × rotate × non-uniform scale, so the vertex shader must switch to the inverse-transpose normal matrix `transpose(inverse(mat3(model)))`; step 11 assumes uniform scale). Headless check replaces step 11's centred-model test (keep `--model` for the blaster view). The step-10 push constants are full (128 B = viewProj + model), so move per-frame data (viewProj, camera position, light direction/colour, ambient; today hard-coded in shaders/basic.frag) into a per-frame-in-flight UBO and keep only the model matrix in push constants. Add 2× MSAA colour + depth with resolve to the swapchain (Magewar runs `msaa_3d = 2×`; query `framebufferColorSampleCounts & framebufferDepthSampleCounts`); the headless check reads the resolved image.
- Files: data/levels/midden_greybox.toml, game/world/level.*.
- Done: level loads ≥10 boxes; screenshot (headless .ppm) shows floor and walls.

**13. Jolt physics world**
- Does: Jolt via FetchContent, static colliders from the greybox, physics step on fixed tick.
- Files: engine/physics/physics.*.
- Done: test drops a dynamic box onto the floor and it comes to rest at the expected height (±0.05 m).

**14. FPS controller: walk, jump, crouch, look**
- Does: Jolt CharacterVirtual driven by `coe::input::TickInput` each tick (`moveForward()/moveRight()` axes, Jump on the `wasPressed` edge, Crouch hold), mouse look from `InputState::takeLook()` applied per render frame (yaw/pitch, 0.25°/count default, pitch clamp ±89° to avoid the gimbal flip at Magewar's ±90°); each tick reads the latest yaw for the move direction. Builds on step 10: game/main.cpp already maps look to `coe::Camera` yaw/pitch (mouse right → negative yaw = turn right, clamp `Camera::kMaxPitch`); the controller takes over yaw/pitch ownership and sets `camera.position` = body + eye height, reinterpreting Magewar's cogito_player (Neck node +0.7 m above the body origin, crouch lowers the head by 0.9 m `CROUCHING_DEPTH`) for our capsule. The tumbling-model demo (game/core/tumble_demo.hpp, step 11's `TumbleDemo` with the fitted blaster) is replaced by the greybox from step 12.
- Files: game/player/player_controller.*.
- Done: playable in window; test: 1 s forward input moves ≈ walk speed × 1 s.

**15. Sprint, Breath and slide**
- Does: Breath pool (100, −20/s sprint, +30/s after 1 s), sprint speed, slide from sprint (§30.8).
- Files: game/player/{player_controller,stats}.*.
- Done: unit tests for Breath drain/regen timings; slide triggers only from sprint.

**16. Dash + camera feel**
- Does: 6 m/0.15 s dash, 2 charges, 25 Breath, 0.1 s i-frames, one air dash; head bob/landing dip with reduced-motion flag.
- Files: game/player/dash.*, game/player/camera_feel.*.
- Done: tests for charges/recharge and distance ±0.3 m.

**17. Weapon data model + Sidearm hitscan**
- Does: WeaponDef/WeaponInstance (family, fire mode, mag, rate), hitscan raycast via Jolt, muzzle flash debug line.
- Files: game/weapons/{weapon,firing}.*, data/weapons/families.toml.
- Done: test fires at a target box and registers a hit at the right distance; fire rate respected.

**18. Ammo, magazine and reload**
- Does: magazine + reserve, tactical vs empty reload times, reload cancel on sprint/swap.
- Files: game/weapons/ammo.*.
- Done: unit tests for tactical/empty timings and cancel behaviour.

**19. ADS, spread and bloom**
- Does: ADS FOV tween, spread cone with stance multipliers and per-shot bloom/decay (§30.1). FOV is vertical (`Camera::fovYDeg`): hip 75° (`Camera::kDefaultFovYDeg`, Magewar/Godot default) → per-family ADS FOV in WeaponDef (Magewar: staff 55°, Cogito pistols 65°) tweened over 0.2 s like Magewar's wieldable_staff; scale mouse look by tan(ads/2)/tan(hip/2) while aimed; the first-person viewmodel keeps its own fixed 75° FOV (Magewar's `viewmodel_fov` shader global) so zooming doesn't distort the gun.
- Files: game/weapons/accuracy.*, engine/render/camera.*.
- Done: tests: ADS spread = 0.35× hip; bloom decays to base within configured time.

**20. Damage formula + test framework**
- Does: doctest via FetchContent (one `coe_tests` doctest runner via `coe_add_test`; port tests/test_fixed_timestep.cpp from plain CHECKs); implement §30.1 formula (Base×1.13^(ilvl−1), Grade, parts, essence match, resist cap 60 %, crit, falloff).
- Files: game/combat/damage.*, tests/test_damage.cpp.
- Done: ≥8 doctest cases incl. resist cap and weak-point crit pass.

**21. Repeater, weapon slots and viewmodel**
- Does: auto-fire Repeater, 2 unlocked slots with 1/2 swap and equip time, viewmodel draws the Kenney blaster mesh (loaded via step 11's manifest + `loadGltfMesh`). Reinterpret Magewar's Cogito wieldable scenes: the blaster model is rotated 180° about Y (glTF +Z barrel → camera −Z) and scaled 0.8 under the camera, drawn after the world with its own near-range projection/depth so it never clips walls. Add colormap texturing here: stb_image (FetchContent, URL_HASH) decodes the GLB's embedded PNG, one sampled image + sampler per material (descriptor set), UVs already in `assets::Vertex`, honour `KHR_texture_transform` (Kenney's colormap uses it) by baking offset/scale into the UVs at load time.
- Files: game/weapons/loadout.*, game/render/viewmodel.*.
- Done: swap test respects equip time; viewmodel visible in window run.

**22. Enemy entity, health and damage numbers**
- Does: enemy component (health, armour type, weak-point hitbox), death, floating damage numbers (debug text via ImGui, FetchContent).
- Files: game/enemies/enemy.*, game/ui/damage_numbers.*, engine/ui/imgui_layer.*.
- Done: shooting a dummy reduces health by formula value and shows a number; dies at 0.

**23. Gnawer AI (rusher)**
- Does: idle → detect (15 m) → aggro (10 m) → chase → melee with cooldown (§7); straight-line steering on the greybox.
- Files: game/ai/{state_machine,gnawer}.*, data/enemies/gnawer.toml.
- Done: tests for state transitions at ranges; in window, Gnawer chases and damages the player.

**24. Heap AI (tank) + player health/shield**
- Does: slow tank with glowing weak-point seam (×2), player shield with delayed regen then health, death/respawn at start.
- Files: game/enemies/heap.*, game/player/health.*.
- Done: tests: weak-point hit doubles damage; shield regen starts after delay.

**25. Enemy spawner + kill events**
- Does: spawn points in level data, wave of Gnawers/Heaps, kill event carrying XP and Tally values. **M1 gunplay complete.**
- Files: game/world/spawner.*, game/core/events.*.
- Done: clearing the wave emits N kill events; ctest passes.

## Vertical slice – loot, progression, UI, dungeon, audio, saves

**26. Item model: parts and Grades**
- Does: Frame/Barrel/Chamber/Grip/Sight part data, 5 Grades with weights 52/26/13/6/3 and multipliers, deterministic generation from seed (§30.2). Magewar reference: staff parts + rarity multiplier → reinterpreted.
- Files: game/loot/{item,parts,grades,generator}.*, data/loot/parts.toml, tests/test_loot.cpp.
- Done: same seed ⇒ identical item; 100k rolls within ±1 % of weights; affix exclusivity test.

**27. Patterns + part constraints**
- Does: data-driven Patterns (ordered part categories with pick min/max, allow_repeat, weighted, optional), inheritance with replace/override/append merges flattened at load, `requires`/`forbids` by part id or tag, rolled in Pattern order (PLAN §31.1–31.2).
- Files: game/loot/{pattern,constraints}.*, data/loot/patterns/*.toml, tests/test_patterns.cpp, tools/asset_cooker/ (Pattern check pass, sharing the loot loader as a library).
- Done: tests: merge modes produce expected flattened lists; a forbidden combo never rolls in 10k rolls; cooker check reports reachable-build count and fails on a deliberate dead-end Pattern.

**28. Weapon stats from parts**
- Does: compute final WeaponInstance stats from rolled parts + affixes; generated names.
- Files: game/loot/assemble.*, game/weapons/weapon.*.
- Done: tests: higher Grade ⇒ higher damage; name built from strongest bonus + Workshop.

**29. Ember Mark item codes**
- Does: versioned bit-packed item code `EM1-…` (Crockford base32, CRC-16) from an append-only Part Index Table; decode with host-side validation (PLAN §31.5).
- Files: game/loot/ember_mark.*, data/loot/part_index_v1.toml, tests/test_ember_mark.cpp.
- Done: 100k random items round-trip `encode(decode(x)) == x`; a 1-char typo fails CRC; an illegal-constraint code is rejected by validation.

**30. Balance patch loader**
- Does: `data/patches/*.toml` typed edits (`set`, `set_if`, `append`, `remove`, `table_row`) applied in phases `boot` / `level:<id|*>` / `enemy:<id|*>`; re-flattens Patterns after boot; bad lines logged and skipped (PLAN §31.6).
- Files: engine/data/patch.*, data/patches/0001_example.toml, tests/test_patch.cpp.
- Done: tests: set_if skips when old value differs; level-phase patch applies only on matching level; malformed line doesn't abort load; active-patch count exposed.

**31. Loot drops on kill**
- Does: per-player drop roll on kill event (drop chance per enemy table), spawn world item with Grade-coloured light pillar.
- Files: game/loot/drop_table.*, game/world/world_item.*, data/enemies/*.toml.
- Done: test: 1000 Gnawer kills produce drop rate within ±2 % of table; pillar colour matches Grade.

**32. Pickup + auto-collect**
- Does: Interact to pick up weapons; Tallies/ammo auto-collect in radius; loot feed log.
- Files: game/loot/pickup.*.
- Done: tests: pickup moves item to inventory; Tallies auto-collect within 2 m only.

**33. Inventory and equip**
- Does: 30-slot backpack, equip to weapon slots, drop, salvage to Scrap.
- Files: game/inventory/inventory.*.
- Done: tests for add/full/equip/swap/salvage.

**34. XP curve and levels**
- Does: XP(L)=120×1.35^(L−1), cap 50, level-up +health/+Breath/+Oil, XP from kill events (§30.5).
- Files: game/progression/xp.*, tests/test_xp.cpp.
- Done: tests for curve values, multi-level gain and cap.

**35. Weight model + Vigil plumbing**
- Does: shared weight model `base × Π(modifiers)` with live attributes (player count, health %, ammo %, Vigil tier) and named tiers; Vigil tier 0–2 data path scaling enemy stats and rewards on separate curves, seeded Omen pick (one sample Omen) stored in the save (PLAN §31.4).
- Files: game/loot/weights.*, game/progression/vigil.*, data/loot/weight_tiers.toml, data/vigil/*.toml.
- Done: tests: contextual health drop weight rises below 40 % health; same Vigil seed ⇒ same Omens; reward curve independent of difficulty curve.

**36. UI renderer (text + sprites)**
- Does: 2D quad batcher in Vulkan, Kenney Future font (assets/kenney/ui-pack/Font) via stb_truetype, Kenney UI PNG panels.
- Files: engine/ui/{ui_renderer,font}.*, shaders/ui.*.
- Done: headless test renders a text string; pixel check finds non-background pixels in its rect.

**37. HUD**
- Does: crosshair + hit markers, health/shield/Breath bars, ammo/mag counter, XP bar + level, loot feed.
- Files: game/ui/hud.*.
- Done: values on HUD update when shooting/reloading/levelling in a window run; headless snapshot test.

**38. Inventory screen**
- Does: Tab opens backpack grid with compare card (green/red stat deltas), equip/salvage buttons, mouse + keyboard. While any UI screen is open, relative mouse mode is off (cursor visible, like Magewar's inventory/menu) and gameplay actions are released (`InputState::releaseAll()`); both restored on close.
- Files: game/ui/inventory_screen.*.
- Done: equipping from the screen changes the active weapon; compare deltas match computed stats in a test.

**39. Key-bindings config**
- Does: load/save `config/bindings.toml` (user dir via SDL_GetPrefPath) serialising the step-9 `coe::input::ActionMap` (keys by SDL scancode name, `Mouse N` for buttons; unknown names ⇒ that action keeps its defaults), defaults on first run, mouse sensitivity (default 0.25°/count)/invert-Y (default off; Magewar's options loader defaults invert to on, not copied), hold-vs-toggle for Crouch and Aim (Magewar has TOGGLE_CROUCH), simple rebind menu, gamepad bindings + stick look noted as post-slice (PLAN §20; Magewar binds joypad buttons for every action), plus a frame-rate cap / vsync (present mode) option (Magewar caps at 120 fps via `run/max_fps`; the sim stays 60 Hz either way).
- Files: engine/input/bindings.*, game/ui/options_screen.*.
- Done: test: rebinding Jump writes file; reload restores it; malformed file falls back to defaults.

**40. Breach room slice: layout**
- Does: greybox Breach (entrance → 2 combat rooms → mini-boss arena → loot vault) with door triggers and arena lock; built as a persistent level + `_combat`/`_dynamic` layers addressable by balance patches (PLAN §31.7).
- Files: data/levels/breach_slice.toml, game/world/{doors,triggers}.*.
- Done: walking through triggers advances room state; doors lock during combat and open on clear.

**41. Mini-boss (2 phases)**
- Does: "Midden Spawn" mini-boss: phase 1 sludge lob; phase 2 at 50 % adds ooze spawns and faster cadence; boss health bar.
- Files: game/bosses/midden_spawn.*, game/ui/boss_bar.*.
- Done: tests: phase switches at 50 %; boss bar visible; killing it opens the vault door.

**42. Vault + guaranteed boss loot**
- Does: per-player guaranteed Gold+ drop from boss, vault chest, room-clear state.
- Files: game/loot/boss_rewards.*, game/world/chest.*.
- Done: test: boss kill always yields ≥ Gold; chest opens once.

**43. Consecrations**
- Does: separate post-parts "generic" roll on Silver+ boss/vault loot with a "none" entry and Calling-aware weighting; 3 sample Consecrations hooked to verbs (dash, Release, full shield) (PLAN §31.4).
- Files: game/loot/consecration.*, data/loot/consecrations.toml.
- Done: tests: Calling-specific weight rises per matching party member; effects trigger on their verb; Ember Mark encodes the consecration id.

**44. Audio engine**
- Does: miniaudio via FetchContent, buses (Master/SFX/UI/Music) with volumes, 3D positional one-shots.
- Files: engine/audio/audio.*.
- Done: unit test loads a Kenney OGG and plays to the null device without error; volumes clamp.

**45. Audio hookup with Kenney sounds**
- Does: map events to Kenney sounds: shots/hits (impact-sounds), UI clicks/pickups/level-up (interface-sounds, ui-pack/Sounds); data-driven sound table.
- Files: data/audio/sounds.toml, game/audio/sound_events.*.
- Done: every sound path in sounds.toml exists and is covered by ASSETS.toml (extend tools/check_assets.py with a `--paths-from data/audio/sounds.toml` mode reusing its coverage rule, as a ctest); audible in window run.

**46. Save format**
- Does: character save (level, XP, Tallies, inventory items as Ember Marks, equipped slots, bindings untouched) as versioned JSON/TOML in pref path.
- Files: game/save/save.*.
- Done: save file written on quit/Interact at camp marker; schema version field present.

**47. Save round-trip + load**
- Does: load on start, version migration hook, corruption fallback.
- Files: game/save/save.*, tests/test_save.cpp.
- Done: test: save → load → save produces byte-identical file; regenerated items equal originals; saves containing every historic Ember Mark version load.

**48. Main menu + flow**
- Does: title screen (Continue/New/Options/Quit), Midden → Breach transition, death/respawn flow.
- Files: game/ui/main_menu.*, game/core/game_flow.*.
- Done: full flow reachable by keyboard only in a window run.

**49. Playtest pass 1 – automated**
- Does: scripted headless bot run (`--playtest`) that spawns, kills a wave, picks loot, levels, saves, reloads; asserts no validation errors.
- Files: game/debug/playtest.*, CMakeLists.txt (ctest).
- Done: ctest `playtest_bot` passes.

**50. Playtest pass 2 – manual + fixes**
- Does: 15-minute manual run with checklist (feel, balance, readability, crashes); fix top issues; record findings.
- Files: docs/playtests/2026-xx-xx.md, any fixes.
- Done: checklist filled, no blocker bugs left, README "How to play" updated. **Vertical slice complete** (tag `v0.1-slice` locally).

## After the slice

**51. CI breadth (deferred from step 7)**
- Does: `.clang-format` + `.clang-tidy` baselines and CI jobs (format check, tidy on changed files); Windows/MSVC job (`windows` preset, MSVC `/W4 /WX`, `/fsanitize=address` only since MSVC has no UBSan); ADR-0002 if Windows forces a package manager.
- Files: .clang-format, .clang-tidy, CMakePresets.json, .github/workflows/ci.yml.
- Done: all jobs green on a branch push; local `clang-format --dry-run -Werror` clean.
