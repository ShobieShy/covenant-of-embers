# Covenant of Embers – Build Plan

## Standing rules (every hourly run)
1. Building the next step is the priority.
2. Review the Magewar references in the project and in `~/game/magewar` (read-only), and make sure the build follows them. The weapon/loot/crafting system follows Magewar's design directly (ShobieShy's own IP, approved 2026-10-22: staffs, wands, parts, rarities, equipment, crafting); other systems are reinterpreted.
3. Look for plan improvements: refine future steps, or go back and fix bugs from earlier steps.
4. Log any such changes in the history in `docs/build_state.json`.

Design source of truth: [PLAN.md](PLAN.md) (§26 milestones, §30 loot-shooter spec). Progress: [build_state.json](build_state.json) (`next_step`).
Each step is sized at ~1 hour. Every step must keep `cmake --build --preset debug` warning-free and `ctest --test-dir build/debug` green (from step 8 on, also `ctest --test-dir build/asan -LE window`), and ends with a local commit (never push). Register every test with `coe_add_test()` (cmake/CoeTesting.cmake); configure fails on a plain `add_test()`. Third-party libraries come in via CMake FetchContent, pinned + `SYSTEM` (no system installs; library list in [ADR-0001](adr/0001-language-and-libraries.md)); every new asset goes into ASSETS.toml + CREDITS.md.

Goal: a **minimal playable vertical slice**. One player walks a greybox Midden, fights Gnawers and Heaps with Magewar-style staffs and wands, picks up rarity-coloured parts and equipment, crafts at a Magic Assembly Station, levels up, clears a Breach room slice with a mini-boss, hears Kenney audio, and saves/loads.

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

**12. Greybox Midden arena** ✅ `a532c06`. Does: toml++ v3.4.0 via FetchContent (release tarball + URL_HASH SHA256, SYSTEM, header-only `tomlplusplus::tomlplusplus`, PRIVATE to the new `coe_game` static lib shared by covenant and tests; `TOML_EXCEPTIONS 0` + `parse_result`). data/levels/midden_greybox.toml: 17 boxes — 40×40 m ground, four 4 m walls (30 m arena, 4 m south entrance), a 1.5 m scrap ledge reached by two 20.6° ramps, three rotated heaps, five crates (one stacked) — plus `[environment]` sky/ambient/fog, `[sun]` to-light + colour and `[camera]` start view; palette/light reinterpreted from Magewar's Ashen Midden (sky horizon, SicklyLight, ambient hue; not copied). `game::loadLevel/parseLevel` (game/world/level.*) validates strictly with `file:line: message` errors (bad TOML, missing tables, unknown keys/kinds, non-3-vectors, non-finite numbers, size ≤ 0, colour outside [0,1], duplicate names, zero sun vector, |pitch| > 89°, no boxes); `LevelBox::rotation()` = Ry·Rx·Rz (Godot's Y-X-Z Euler order, degrees), `model()` = T·R·S over the unit cube, `surfaceDistance`/`Level::boxAtSurface`. `makeUnitCube()`: 24 verts with per-face normals, 36 CCW indices, white vertex colour, uploaded once; one `DrawItem{cube, model, tint}` per box. Plan correction: "Vertex.color = per-box tint" can't coexist with one shared cube, so the tint is a per-draw push constant (`{mat4 model; vec4 tint}` = 80 B). Renderer: per-frame-in-flight set-0 `Frame` UBO (shaders/frame.glsl, std140 144 B: viewProj, camera pos, to-light, light colour, ambient, fog colour + density) with descriptor pool/sets, written after each frame fence; `FrameParams{camera, lighting, clearColor, draws}`; vertex shader uses `transpose(inverse(mat3(model)))`; fragment shader adds exp fog toward the sky colour (glslc include tracked as a DEPENDS). 2× MSAA (Magewar `msaa_3d = 2×`): sample count = `framebufferColorSampleCounts & framebufferDepthSampleCounts` + per-format image-properties check (falls back to 1× with a warning), transient MSAA colour + MSAA depth with the swapchain, colour resolved with `RESOLVE_MODE_AVERAGE` in dynamic rendering. `renderHeadless()` returns the resolved RGBA8 + depth (SAMPLE_ZERO resolve, sample-0 position reported) + viewProj; the checks moved out of the engine into game/world/headless_checks.*: `checkLevelView` unprojects a 32×32 depth grid through inverse(viewProj) and attributes each sample to the box surface it lies on, `checkModelView` is step 11's test for `--model`. covenant now shows the level by default (`--level FILE`, default data/levels/midden_greybox.toml; window mouse look starts at the level's yaw/pitch), `--model [SRC]` keeps the tumbling blaster; headless writes midden.ppm (level) / mesh.ppm (model). Files: data/levels/midden_greybox.toml, game/world/{level,headless_checks}.*, game/{main.cpp,CMakeLists.txt}, engine/render/vk_renderer.*, shaders/{frame.glsl,basic.vert,basic.frag}, tests/{test_level.cpp,CMakeLists.txt}, CMakeLists.txt, engine/CMakeLists.txt, README.md, ADR-0001. Done: `covenant --headless` (validation on, 0 messages): `[level] midden_greybox: 17 boxes (1 ground, 5 wall, 2 ramp, 5 crate, 3 heap, 1 platform)`, `[vk] MSAA: 2x`, 1024 samples: ground 530 (mean y 189 of 256, lower half), walls 71, other boxes 73, sky 350 (0 off-colour), unexplained 0, 218 resolved edge pixels → floor/walls/sky/geometry/msaa ok, RESULT: PASS (midden.ppm shows floor, north + side walls, ramps, heaps, crates); `--headless --model` still passes step 11's check under 2× MSAA; ctest `level` (≥10 boxes incl. ground/walls/ramps/crates, ramp tops meet the ledge edge, Y-X-Z order, T·R·S corners, inverse-transpose vs naive normal on a slanted plane under non-uniform scale, cube winding/normals, 11 rejection cases with line numbers, empty frame fails the check); `smoke_headless_missing_level` fails with `[level] …cannot open`; debug 19/19 incl. window tests, asan 16/16 `-LE window`, warning-free.

**13. Jolt physics world** ✅ `a575603`. Does: Jolt Physics v5.6.0 via FetchContent (release tarball + URL_HASH SHA256, `SOURCE_SUBDIR Build`, SYSTEM; core library only: GPU compute back-ends, debug renderer, profiler, ObjectStream, install, LTO, Jolt's own `-Werror` and its CMAKE_CXX_FLAGS override off; RTTI on so UBSan's vptr check links; default x86-64 SIMD level, single precision, asserts in Debug via Jolt's `JPH_DEBUG`). New static `coe_physics` (engine/physics, no TOML/Vulkan/SDL): `physics::PhysicsWorld` hides Jolt behind a pimpl (only physics.cpp includes it; ref-counted Jolt globals, Trace/AssertFailed hooks, 8 MB temp allocator, `JobSystemSingleThreaded` by default or a thread pool with `workerThreads > 0`), opaque `BodyHandle`, `BoxDesc{center, halfExtents, rotation, layer, friction, restitution, density}`, `addStaticBox/addDynamicBox/removeBody/optimizeBroadPhase`, `step(dt)` (one collision step, false on Jolt update errors), `state()` {position, rotation, velocities, active}, `layer()`, `halfExtents()`, `setLinearVelocity()`, `castRay()` → {body, fraction, point, normal}. Object layers `Static` (level; static-vs-static never tested) and `Moving`, two broad-phase trees — reinterpreting Magewar's "Environment"/"Interactables" layers. Gravity 9.8 m/s² (Godot's default that Magewar keeps; Jolt's own is 9.81). game/world/level_physics.*: `buildLevelPhysics(level, world)` adds one static `BoxShape(size / 2)` per `LevelBox` at `center` with `quat_cast(LevelBox::rotation())` (the renderer's Ry·Rx·Rz), layer from `objectLayerFor(BoxKind)` (all static for now), friction from `frictionFor(BoxKind)` (Jolt's 0.2 for now), then optimises the broad phase; bodies indexed like `level.boxes`. covenant (level mode) builds the world from the level, steps it once per fixed 60 Hz tick and drops a tumbling 0.6 m ember-orange demo crate in front of the start camera, drawn interpolated (lerp/slerp of the last two tick poses); the window run fails unless physics steps == fixed ticks with no update errors. Magewar fix: the start eye height is 1.5 m, not 1.7 m (cogito_player's body origin is 0.8 m above the feet, Neck +0.7 m), `[camera]` y changed to 1.5. Files: CMakeLists.txt, engine/physics/physics.*, engine/CMakeLists.txt, game/world/level_physics.*, game/{main.cpp,CMakeLists.txt}, data/levels/midden_greybox.toml, tests/{test_physics.cpp,CMakeLists.txt}, README.md, ADR-0001. Done: ctest `physics`: a 0.5 m box dropped at (0, 2, 8) onto `ground` rests at y 0.230 (0.25 − Jolt's 2 cm penetration slop; ±0.05 m) at (0, 8) and sleeps after 66 ticks; a tilted drop lands on a face at y 0.2499; the same drop is bit-identical on a rerun and with 3 worker threads; a box dropped at (−4.5, 2, −7.5) over `ramp_west` slides downhill (+Z, up to 2.73 m/s on the ramp) and rests on the ground at z −3.18, y 0.2499; all 17 colliders match their LevelBox centre/half size/rotation (as matrices) on the Static layer and don't simulate; 5776 down-rays over the arena hit up-facing box faces (4804 ground at y 0, 972 other boxes), every hit on its box's surface (±1 cm) and found by `Level::boxAtSurface`; ramp rays hit the analytic plane at 20.56°, a horizontal ray stops on the north wall's face. `covenant --seconds 3`: `[physics] Jolt world: 17 static box colliders`, `180 steps (one per tick)`, demo crate asleep on the ground; `smoke_headless` still passes from the 1.5 m eye; debug 20/20 incl. window tests, asan 17/17 `-LE window`, warning-free (clean rebuild).

**14. FPS controller: walk, jump, crouch, look** ✅ `90b2923`. Does: `physics::Character` (engine/physics/character.*, Jolt pimpl like PhysicsWorld; `PhysicsWorld::Impl` + layer tables moved to the private engine/physics/physics_impl.hpp so character.cpp shares them) wraps Jolt's `CharacterVirtual`: capsule radius 0.3 m, 1.7 m standing / 0.7 m crouched (Magewar's 0.6 × 1.7 × 0.6 / 0.6 × 0.7 × 0.6 m box colliders as capsules), offset so `position()` is the feet; supporting volume below the lower hemisphere centre, max slope 45° (Godot's floor_max_angle default, kept by Magewar), mass 70 kg / strength 100 N; `update(dt)` = `ExtendedUpdate` with stair step-up 0.35 m (Magewar STEP_HEIGHT) and 0.5 m stick-to-floor; `setCrouched()` swaps shapes and refuses to stand up into geometry; a kinematic inner body on the new object layer `Layers::Character` (= 2, in the Moving broad-phase tree, collides with Static + Moving + Character) makes the player visible to rays (step 17) and moving bodies. `game::PlayerController` (game/player/player_controller.*) reinterprets Magewar's cogito_player.gd with `PlayerTuning` (cogito_player.tscn overrides): per fixed tick, move direction = input axes (`moveForward()/moveRight()`, normalised) turned by the latest look yaw, smoothed at LERP_SPEED 10/s on the ground / AIR_LERP_SPEED 6/s in the air only while a move key is held; speed eases at 10/s toward walk 4 m/s / crouch 3 m/s (CROUCHING_SPEED, newly noted); vertical 0 on the ground, gravity 9.8 m/s² in the air; Jump on the `wasPressed` edge from the ground only: 4.5 m/s standing, 3.0 m/s crouched (a crouch-jump stays crouched until landing; Magewar jumps while Jump is *held* with a jump timer, our edge is the deliberate plan choice); Crouch held (TOGGLE_CROUCH false), starts on the ground only, can't stand up under a ceiling (Magewar's CrouchRayCast); eye 1.5 m standing / 0.6 m crouched, eased at 10/s; ground velocity added when standing on movers; a "rising" flag ignores Jolt's predictive OnGround for the ticks right after take-off. Mouse look per render frame via `addLook()` (0.25°/count, mouse right → negative yaw, pitch clamp ±`Camera::kMaxPitch`, yaw wrapped); `camera(alpha)` interpolates feet + eye between the last two ticks. Level data: step 12's `[camera]` table became `[player_start]` (`position` = feet, `yaw_deg`; pitch starts level; validated to lie on a box surface within 5 cm), named so step 25's `[[spawn]]` array can share the file (TOML can't have both `[spawn]` and `[[spawn]]`); Midden start (0, 0, 12.5) facing north. covenant level mode spawns the controller, ticks it before `physics.step()`, renders from its eye; the demo crate is now behind `--crate` (push target), TumbleDemo runs only under `--model`; `--input-script` also fails unless the scripted W + Space walked the player forward (> 0.2 m) and jumped (apex > 0.5 m), and in script mode real keyboard/mouse events are dropped (scripted ones carry a device-id tag) so a stray desktop key press cannot flake it; headless view = start eye, pitch 0. Files: engine/physics/{character.*,physics_impl.hpp,physics.*}, engine/CMakeLists.txt, game/player/player_controller.*, game/{main.cpp,CMakeLists.txt}, game/world/level.*, data/levels/midden_greybox.toml, tests/{test_player.cpp,test_level.cpp,CMakeLists.txt}, README.md, ADR-0001. Done: ctest `player`: 1 s of W from the Midden start moves 3.667 m (walk 4 m/s × 1 s ± 0.5; the 10/s direction easing costs ~0.33 m) straight north and ends at 4.000 m/s, eases to rest, diagonals not faster; settled on `ground` the eye is 1.5000 m above the ray-measured floor; walking north into `ramp_west` stays grounded on the slope (feet y 0.787 at z −7 vs analytic 0.75: hemisphere + 2 cm padding) and ends on `scrap_ledge` at y 1.500; a 0.35 m step is climbed (feet y 0.350, walks on) and a 0.5 m step blocks (y 0, stopped at z −2.68 against the face at −3); jump apex 1.071 m standing / 0.484 m crouched (v²/2g = 1.033 / 0.459 plus the one-tick discretisation, ± 0.05), no air jumps, held Jump doesn't re-jump; crouch eye 0.600 m, speed 3.000 m/s under a 1 m slab, stays crouched there, stands again outside; look clamp/wrap and walking follows yaw; a ray hits the inner body on `Layers::Character`. `covenant --input-script`: walked 2.32 m forward, 1 jump, apex 1.07 m; `--seconds 3`: player spawned on-ground at eye 1.50 m, 180 physics steps; `smoke_headless` passes from the level start eye; debug 21/21 incl. window tests, asan 18/18 `-LE window`, warning-free clean rebuild; script test stress: 1 failure in 30 runs before the real-input filter (a real S press), 0 in 12 after.

**15. Sprint, Breath and slide** ✅ `HASH15`. Does: `game::Breath` (game/player/stats.*; PLAN §30.8, reinterpreting Magewar's CogitoStaminaAttribute 30 max / 3/s / 2/s after 2 s): `BreathTuning{max 100, drain 20/s, regen 30/s, regenDelay 1 s, resumeAt 20}`, `tick(draining, dt)` (regen counts only the part of a tick past the delay, double-precision time since last use, so timings are exact at 60 and 144 Hz), `spend()` (step 16 dash), `setMaxBonus()` (Magewar Belt/Shoes stamina_bonus, level-up +5; no free refill), `refill()`; deliberate deviation: an emptied pool stays `exhausted()` until 20 is back (Magewar re-allows sprint at > 0, which stutters; `resumeAt 0` = Magewar). `PlayerTuning` gains sprint 7 m/s (cogito_player.tscn SPRINTING_SPEED override; script default 8), SLIDING_SPEED 5, SlidingTimer 1.5 s, SLIDE_JUMP_MOD 1.3 (tscn override; script 1.5). `PlayerController::tick`: Sprint held starts on the ground only with a move key held, not while crouched or exhausted, keeps going in the air while held, eases at LERP_SPEED like walk/crouch, drains 20/s (standing still with Sprint held doesn't); Crouch on the ground while sprinting (previous tick) + move key starts a slide along the entry wish direction (mouse look doesn't steer it, as Magewar free-looks while sliding) at (timeLeft/1.5 + 0.5) × 5 m/s = 7.5 → 2.5 m/s, ending on timeout, on releasing Crouch or Sprint, or on leaving the ground; no re-trigger while held (crouched ⇒ not sprinting); Jump during a slide = slide jump 4.5 × 1.3 m/s, stands up in the air and keeps the slide speed until landing; slides don't drain Breath. `setSpeedMultiplier()` hook (Magewar Shoes speed_modifier scales walk/sprint/crouch, not the slide). Accessors `sprinting()/sliding()/slides()/slideJumps()/breath()`; covenant's end-of-run `[player]` line prints Breath and slides. Not taken from Magewar (deliberate): its jump stamina cost (5 of 30) and slope-dependent run drain — Breath stays a sprint/dash resource. Files: game/player/{player_controller,stats}.*, game/{CMakeLists.txt,main.cpp}, tests/{test_breath.cpp,test_player.cpp,CMakeLists.txt}, README.md. Done: ctest `breath`: 1 s sprint → 80.000, empty after exactly 300 ticks, exhausted; regen none on tick 60 after the last drain, +0.5 on tick 61, +30.000 at 2 s (60 Hz: 89.9997, 144 Hz: 90.0012 from 60); empty → sprint again after 100 ticks (1 + 20/30 s), full after 260 (1 + 100/30 s); a 1-tick drain or a 25-pt spend restarts the delay, spend refuses when short; max bonus +15 → 115 without refill, clamps back. ctest `player` (sprint/slide added): sprint 2 s = 7.000 m/s, Breath 60.00; ran dry after 300 ticks, walk 4 m/s, sprinting again 101 ticks later; crouch + sprint = 3 m/s, no drain, no slide; speed ×1.1 → 4.4 / 7.7 m/s; slide from sprint: 90 ticks, 7.583 m (analytic 7.5), entry 7.500 m/s, 0.000 m sideways after turning the view 90° mid-slide, then crouch 3.000 m/s, Breath regenerating (80 → 95.5); no slide from walk + Crouch, crouch-then-Sprint, standing Sprint + Crouch, or exhausted; releasing Sprint ends it; slide jump apex 1.795 m ((5.85)²/2g = 1.746 + tick discretisation), stood up in the air, air speed constant 6.944 m/s, landing with Crouch held doesn't re-slide. Debug 22/22 incl. window tests, asan 19/19 `-LE window`, warning-free.

**16. Dash + camera feel**
- Does: 6 m/0.15 s dash, 2 charges, 25 Breath (`player.breath().spend(25)`, which also restarts the 1 s regen delay; refused when short, so an exhausted pool can't dash either), 0.1 s i-frames, one air dash; a dash ends an active slide (clear the slide timer, keep crouch rules); head bob/landing dip with reduced-motion flag. The dash sets the controller's horizontal velocity for 0.15 s (physics::Character sweeps it, so walls stop it); head bob/dip offset `PlayerController::camera()`'s eye (which already eases crouch height at 10/s).
- Files: game/player/dash.*, game/player/camera_feel.*.
- Done: tests for charges/recharge and distance ±0.3 m.

**17. Spell data model: staffs, wands + Arcane bolt**
- Does: Magewar weapon model (PLAN §30.1): `WieldableDef` {type Staff|Wand, base_rarity, primary element, base damage, mana cost, cooldown, projectile speed} and `WieldableInstance` (def + attached parts, empty until step 28). Casting = a fast spell projectile (Jolt ray swept per tick at projectile speed, so shots still hit at the right distance; body filter skips the caster's step-14 `physics::Character::innerBody()` on `Layers::Character`), element-coloured debug line. Data: data/magic/wieldables.toml with Magewar's four bases (Apprentice Fire Staff 10 dmg/5 mana/0.40 s, Earthward Battlestaff 14/6/0.55, Novice Arcane Wand 7/3/0.25, Swift Wind Wand 6/2.5/0.18). Parse like step 12's level.cpp (toml++ `TOML_EXCEPTIONS 0`, unknown keys/out-of-range values rejected with file:line); move shared helpers from game/world/level.cpp into game/data/toml_read.*.
- Files: game/magic/{wieldable,casting,projectile}.*, game/data/toml_read.*, data/magic/wieldables.toml, tests/test_casting.cpp.
- Done: test casts at a target box and registers a hit at the right distance and travel time (±1 tick); cooldown respected (Swift Wind Wand: max 1 cast per 0.18 s); the caster's own capsule is never hit.

**18. Mana pool (replaces ammo/reload)**
- Does: Magewar mana_attribute: mana 100 base, each cast spends the wieldable's mana cost, no cast when mana < cost, regen 3/s after a 1.5 s delay since the last cast, `equipment_regen_bonus` hook (filled by step 30 gear). No magazines or reloads; Reload action is freed for later (step 36 uses Interact, not Reload).
- Files: game/player/mana.*, tests/test_mana.cpp.
- Done: tests: 20 casts of a 5-mana staff empty 100 mana and the 21st fails; regen starts exactly 1.5 s after the last cast and refills at 3/s; regen bonus adds.

**19. Focus (ADS), accuracy and spread**
- Does: Aim = focus: FOV tween hip 75° → staff 55° / wand 65° over 0.2 s (Magewar wieldable_staff), mouse look scaled by tan(ads/2)/tan(hip/2); viewmodel keeps a fixed 75°. Magewar accuracy 0–100 % (base 50 + head/handle/charm bonuses, clamped) maps to a spread cone `s = s_max × (1 − acc/100) × stance` (focus 0.35, crouch 0.8, moving 1.3, airborne 1.8) with small per-cast bloom that decays.
- Files: game/magic/accuracy.*, engine/render/camera.*.
- Done: tests: 100 % accuracy ⇒ zero spread; focused spread = 0.35× hip; bloom decays to base within its configured time; FOV reaches 55° in 0.2 s.

**20. Damage formula + elements + doctest**
- Does: doctest via FetchContent (one `coe_tests` runner via `coe_add_test`; port test_fixed_timestep.cpp). Magewar formula: `dmg = base × RarityMult(base_rarity) + Σ part damage_bonus`, then `× ElementEffectiveness × (1 − resist, cap 60 %) × crit (weak point ×2)`. Elements Fire/Water/Earth/Air/Light/Dark + Arcane (none): cycle Fire > Earth > Air > Water > Fire (1.5 strong, 0.5 weak), Light ⇄ Dark 1.5 both ways, same/Arcane 1.0 (magic_element.gd). Element colours in data/magic/elements.toml (§30.4).
- Files: game/combat/{damage,element}.*, data/magic/elements.toml, tests/test_damage.cpp.
- Done: ≥10 doctest cases: full 7×7 effectiveness table, rarity multipliers ×1.0…×3.0, part bonus sum, resist cap, weak-point crit.

**21. Staff + wand slots and viewmodel**
- Does: loadout = 1 Staff slot (main hand) + 1 Wand slot (Magewar: wand is an equipable), 1/2 swap with 0.4 s equip time; viewmodel draws a staff/wand mesh (greybox: cylinder shaft + element-tinted head; Kenney blaster kept as fallback until art), rotated/scaled under the camera, drawn after the world with its own projection and depth clear. Add colormap texturing (stb_image FetchContent + URL_HASH, one sampler per material, bake `KHR_texture_transform` into UVs). Push constants are `{model, tint}` (80/128 B); viewmodel uses a second `Frame` UBO slot.
- Files: game/magic/loadout.*, game/render/viewmodel.*.
- Done: swap test respects equip time; casting uses the active slot's stats; viewmodel visible in window run, head tinted by element colour.

**22. Enemy entity, health and damage numbers**
- Does: enemy component (health, element affinity for step 20's table, weak-point hitbox), death, floating damage numbers coloured by element (debug text via ImGui, FetchContent).
- Files: game/enemies/enemy.*, game/ui/damage_numbers.*, engine/ui/imgui_layer.*.
- Done: casting at a dummy reduces health by formula value and shows a number; Fire vs an Earth dummy does ×1.5; dies at 0.

**23. Gnawer AI (rusher)**
- Does: idle → detect (15 m) → aggro (10 m) → chase → melee with cooldown (§7); straight-line steering on the greybox. (Magewar's mutant rat is the reference.)
- Files: game/ai/{state_machine,gnawer}.*, data/enemies/gnawer.toml.
- Done: tests for state transitions at ranges; in window, Gnawer chases and damages the player.

**24. Heap AI (tank) + player health/shield**
- Does: slow tank (Magewar garbage golem reference, Earth affinity) with glowing weak-point seam (×2), player shield with delayed regen then health, death/respawn at start.
- Files: game/enemies/heap.*, game/player/health.*.
- Done: tests: weak-point hit doubles damage; shield regen starts after delay.

**25. Enemy spawner + kill events**
- Does: spawn points in level data (`[[spawn]]` tables in data/levels/midden_greybox.toml: `kind`, `position`, `yaw_deg`, validated by level.cpp alongside `[[box]]`; a spawn must stand on a box via `Level::boxAtSurface`, like step 14's `[player_start]`), wave of Gnawers/Heaps, kill event carrying XP and Tally values. **M1 spellcasting complete.**
- Files: game/world/spawner.*, game/core/events.*.
- Done: clearing the wave emits N kill events; ctest passes.

## Vertical slice – loot, crafting, progression, UI, dungeon, audio, saves

**26. Rarity tiers + part model**
- Does: Magewar's six rarities as data (data/loot/rarities.toml): Basic #B3B3B3 ×1.0 w50, Uncommon #33CC33 ×1.25 w25, Rare #3366FF ×1.5 w15, Mythic #991AE6 ×2.0 w7, Primordial #FF9900 ×2.75 w2, Unique #FFD900 ×3.0 w1; `roll_rarity(luck)` (luck −5/pt on Basic/Uncommon, min 1; +2/pt on Rare+). Part model with Magewar's five part types: Head (staff + wand, gem slots, element), Exterior (fire-rate modifier), Interior (base damage), Handle (accuracy/handling; optional on wands), Charm (staff only, optional extra augment). Deterministic generation from seed (§30.2).
- Files: game/loot/{rarity,part,generator}.*, data/loot/rarities.toml, tests/test_loot.cpp.
- Done: same seed ⇒ identical part; 100k rolls within ±1 % of weights 50/25/15/7/2/1; luck 3 shifts Rare+ share up; every rarity name/colour/multiplier matches the table.

**27. Part stat rolls, gems and names**
- Does: Magewar loot_generator ranges × rarity multiplier: Head dmg 1–5, acc 0–10, gem slots 1 (+1 at Rare+, +1 at Primordial+, max 3); Exterior fire-rate ×1.0 (×0.5–1.0 at Rare+); Interior dmg 2–8; Handle acc 5–20, handling 2–10; Charm dmg 0–3, acc 0–8, fire-rate modifier. Element rolled per Head/Interior/Charm. Generated names ("Rare Fire Crystal Head", material ladder per rarity for Exteriors/Handles) via data/loot/part_names.toml. Patterns (§31.1) become per-part-type stat tables with `requires`/`forbids` tags (e.g. Charm `requires tag:staff`).
- Files: game/loot/{part_rolls,part_names,constraints}.*, data/loot/parts.toml, data/loot/part_names.toml, tests/test_parts.cpp.
- Done: 10k rolls per type stay within range × multiplier; gem-slot counts match rarity exactly; a Charm never rolls for a wand; names include rarity + element.

**28. Staff/wand assembly rules + final stats**
- Does: assemble a wieldable from parts (magic_assembly_station.gd rules): Staff needs Head + Exterior + Interior + Handle (+ optional Charm) = 4–5 parts; Wand needs Head + Exterior (+ optional Handle) = 2–3. Assembled rarity = floor(mean part rarity). Final stats: damage per step 20; cooldown = base × Exterior × Charm modifiers, min 0.1 s; accuracy = 50 + Head + Handle + Charm, clamp 0–100; element = Head element if set, else base element. Stats summary string `[Rare] Staff - Fire / Damage / Fire Rate / Accuracy / Mana Cost`.
- Files: game/loot/assemble.*, game/magic/wieldable.*, tests/test_assemble.cpp.
- Done: tests: missing required part ⇒ refused with reason; a Basic+Rare+Rare+Mythic staff is Rare; cooldown never below 0.1 s; Head element overrides base; summary matches.

**29. Base wieldables + drop pools**
- Does: base staffs/wands carry their own rarity (Bible: "base staff/wand have rarities") and are the spell; parts modify it. Data-driven pools of bases and parts per enemy/level (Patterns §31.1 reused as pools with weights); constraint validation in the cooker (no dead-end pool).
- Files: game/loot/pools.*, data/loot/pools/*.toml, tools/asset_cooker/ (pool check pass).
- Done: tests: every pool resolves; a deliberately empty pool fails the cooker check; base rarity rolls follow step 26 weights.

**30. Equipment items**
- Does: Magewar equipables: Hat (mana, spell dmg, mana regen), Clothes/Robes (health, mana, Rare+ elemental resist 5–15 %), Belt (health 3–8, Breath max +5–15), Shoes (speed ×1.02–1.10, Breath max +3–10; Magewar loot_generator ranges kept as flat points on our 100-pt pool), Grimoire (spell dmg 2–8, mana 10–25, regen 0.5–2), all × rarity multiplier; Potion quick-slot (health/mana potions, not rolled). Equipping applies bonuses to health/mana/Breath/regen/speed (step 18 regen hook; step 15 hooks `Breath::setMaxBonus()` (no free refill) and `PlayerController::setSpeedMultiplier()`, which like Magewar scales walk/sprint/crouch but not the slide).
- Files: game/loot/equipment.*, game/player/stats.*, data/loot/equipment.toml, tests/test_equipment.cpp.
- Done: tests: rolls within range × multiplier per slot; equipping a Grimoire raises spell damage and mana regen; resist capped at 60 %.

**31. Ember Mark item codes**
- Does: versioned bit-packed code `EM1-…` (Crockford base32, CRC-16) from an append-only Part Index Table, covering parts, assembled staffs/wands (base + up to 5 parts + gems) and equipment; host-side validation (PLAN §31.5).
- Files: game/loot/ember_mark.*, data/loot/part_index_v1.toml, tests/test_ember_mark.cpp.
- Done: 100k random items round-trip `encode(decode(x)) == x`; a 1-char typo fails CRC; an illegal assembly (Charm on a wand) is rejected.

**32. Balance patch loader**
- Does: `data/patches/*.toml` typed edits (`set`, `set_if`, `append`, `remove`, `table_row`) applied in phases `boot` / `level:<id|*>` / `enemy:<id|*>`; re-resolves pools after boot; bad lines logged and skipped (PLAN §31.6). Rarity weights/multipliers patchable.
- Files: engine/data/patch.*, data/patches/0001_example.toml, tests/test_patch.cpp.
- Done: tests: set_if skips when old value differs; level-phase patch applies only on matching level; malformed line doesn't abort load; active-patch count exposed.

**33. Loot drops on kill**
- Does: per-player drop roll on kill event (parts, base staffs/wands, equipment, potions per enemy table), world item with a rarity-coloured light pillar (step 26 hex). World items are dynamic Jolt bodies on a pickup/interactables layer (Magewar layer 2: collides with level, not characters); per-kind friction (revisit `frictionFor(BoxKind)` so loot doesn't skate down ramps).
- Files: game/loot/drop_table.*, game/world/world_item.*, data/enemies/*.toml.
- Done: test: 1000 Gnawer kills produce drop rate within ±2 % of table; pillar colour equals the item's rarity colour.

**34. Pickup + auto-collect**
- Does: Interact to pick up parts/wieldables/equipment; Tallies/potions auto-collect in radius; loot feed log with rarity-coloured names.
- Files: game/loot/pickup.*.
- Done: tests: pickup moves item to inventory; Tallies auto-collect within 2 m only.

**35. Inventory and equip**
- Does: 30-slot backpack (parts stack by type filter), equip Staff/Wand slots + Hat/Clothes/Belt/Shoes/Grimoire/Potion slots, drop, salvage to Scrap (amount by rarity).
- Files: game/inventory/inventory.*.
- Done: tests for add/full/equip/swap/salvage; equipping gear applies step 30 bonuses and unequipping removes them exactly.

**36. Magic Assembly Station (crafting core)**
- Does: Bible rule "staffs and wands may only be customized at a Magic Assembly Station": station interactable in the Midden (Interact within 2 m), session API select part per slot / preview (no consumption) / assemble (consumes parts, outputs wieldable) / disassemble a wieldable back into its parts. Crafting outside a station is refused.
- Files: game/crafting/assembly_station.*, game/world/interactable.*, data/levels/midden_greybox.toml (station placement), tests/test_crafting.cpp.
- Done: tests: preview == assembled stats and leaves inventory untouched; assemble removes exactly the used parts; disassemble restores identical parts (Ember Marks equal); refused away from the station.

**37. Crafting extras: gems and part salvage**
- Does: element gems socket into Head gem slots (1–3) at the station: first gem sets element, extra gems add +X % elemental damage; salvage parts into Arcane Dust by rarity; spend Dust to upgrade a part one rarity tier (re-scale its rolls by the new multiplier, Unique not reachable by upgrade).
- Files: game/crafting/{gems,salvage,upgrade}.*, data/crafting/*.toml, tests/test_crafting_extras.cpp.
- Done: tests: can't exceed the Head's gem slots; upgrade Rare→Mythic scales stats by 2.0/1.5; Unique never produced by upgrade; Dust totals match table.

**38. XP curve and levels**
- Does: XP(L)=120×1.35^(L−1), cap 50, level-up +health, +5 Breath max and +5 mana max with both refilled (Magewar magewar_player `_level_up`; `Breath::setMaxBonus` + `refill()`), XP from kill events (§30.5).
- Files: game/progression/xp.*, tests/test_xp.cpp.
- Done: tests for curve values, multi-level gain and cap.

**39. Weight model + Vigil plumbing**
- Does: shared weight model `base × Π(modifiers)` with live attributes (player count, health %, mana %, Vigil tier, luck feeding `roll_rarity`); Vigil tier 0–2 scaling enemy stats and rewards on separate curves, seeded Omen pick stored in the save (PLAN §31.4).
- Files: game/loot/weights.*, game/progression/vigil.*, data/loot/weight_tiers.toml, data/vigil/*.toml.
- Done: tests: contextual potion weight rises below 40 % health; same Vigil seed ⇒ same Omens; reward curve independent of difficulty curve.

**40. UI renderer (text + sprites)**
- Does: 2D quad batcher in Vulkan, Kenney Future font (assets/kenney/ui-pack/Font) via stb_truetype, Kenney UI PNG panels.
- Files: engine/ui/{ui_renderer,font}.*, shaders/ui.*.
- Done: headless test renders a text string; pixel check finds non-background pixels in its rect.

**41. HUD**
- Does: crosshair + hit markers, health/shield/Breath bars, mana bar (Magewar mana_bar_ui), active staff/wand with element icon + cooldown, XP bar + level, loot feed in rarity colours.
- Files: game/ui/hud.*.
- Done: values on HUD update when casting/regenerating/levelling in a window run; headless snapshot test.

**42. Inventory + equipment screen**
- Does: Tab opens backpack grid with rarity-coloured borders/names, equipment panel (Staff, Wand, Hat, Clothes, Belt, Shoes, Grimoire, Potion; Magewar equipment_panel), compare card (green/red deltas), equip/salvage buttons. While any UI screen is open, relative mouse mode is off and gameplay actions are released (`InputState::releaseAll()`).
- Files: game/ui/inventory_screen.*.
- Done: equipping from the screen changes the active wieldable/gear; compare deltas and border colours match computed stats/rarity in a test.

**43. Assembly Station UI**
- Does: station screen (Magewar assembly_station_ui): one slot per part type filtered from inventory, Staff/Wand toggle (hides Interior/Charm for wands), live preview card with assembled rarity colour and stats summary, Assemble/Disassemble/Socket gem buttons.
- Files: game/ui/assembly_screen.*.
- Done: test drives the screen to build a staff and the result equals step 36's assemble; Assemble disabled until required parts are set.

**44. Key-bindings config**
- Does: load/save `config/bindings.toml` (SDL_GetPrefPath) serialising the step-9 `coe::input::ActionMap` (scancode names, `Mouse N`; unknown names keep defaults), mouse sensitivity (0.25°/count), invert-Y (default off), hold-vs-toggle for Crouch and Aim, simple rebind menu, gamepad noted post-slice, frame-rate cap / vsync option (sim stays 60 Hz).
- Files: engine/input/bindings.*, game/ui/options_screen.*.
- Done: test: rebinding Jump writes file; reload restores it; malformed file falls back to defaults.

**45. Breach room slice: layout**
- Does: greybox Breach (entrance → 2 combat rooms → mini-boss arena → loot vault) with door triggers and arena lock; persistent level + `_combat`/`_dynamic` layers (PLAN §31.7).
- Files: data/levels/breach_slice.toml, game/world/{doors,triggers}.*.
- Done: walking through triggers advances room state; doors lock during combat and open on clear.

**46. Mini-boss (2 phases)**
- Does: "Midden Spawn" mini-boss (Magewar The Filth reference): phase 1 sludge lob; phase 2 at 50 % adds ooze spawns and faster cadence; boss health bar.
- Files: game/bosses/midden_spawn.*, game/ui/boss_bar.*.
- Done: tests: phase switches at 50 %; boss bar visible; killing it opens the vault door.

**47. Vault + guaranteed boss loot**
- Does: per-player guaranteed Mythic+ drop from boss (part, base wieldable or equipment), vault chest, room-clear state.
- Files: game/loot/boss_rewards.*, game/world/chest.*.
- Done: test: boss kill always yields ≥ Mythic; chest opens once.

**48. Consecrations (enchantments)**
- Does: separate post-assembly roll on Rare+ boss/vault wieldables with a "none" entry and Calling-aware weighting; 3 sample effects hooked to verbs (dash, Light summon, full shield) (PLAN §31.4).
- Files: game/loot/consecration.*, data/loot/consecrations.toml.
- Done: tests: Calling weight rises per matching party member; effects trigger on their verb; Ember Mark encodes the consecration id.

**49. Audio engine**
- Does: miniaudio via FetchContent, buses (Master/SFX/UI/Music) with volumes, 3D positional one-shots.
- Files: engine/audio/audio.*.
- Done: unit test loads a Kenney OGG and plays to the null device without error; volumes clamp.

**50. Audio hookup with Kenney sounds**
- Does: map events to Kenney sounds: casts/hits (impact-sounds), UI clicks/pickups/crafting/level-up (interface-sounds, ui-pack/Sounds); data-driven sound table.
- Files: data/audio/sounds.toml, game/audio/sound_events.*.
- Done: every sound path in sounds.toml exists and is covered by ASSETS.toml (`check_assets.py --paths-from data/audio/sounds.toml` ctest); audible in window run.

**51. Save format**
- Does: character save (level, XP, Tallies, Arcane Dust, inventory parts/wieldables/equipment as Ember Marks, equipped slots) as versioned TOML in pref path.
- Files: game/save/save.*.
- Done: save file written on quit/Interact at camp marker; schema version field present.

**52. Save round-trip + load**
- Does: load on start, version migration hook, corruption fallback.
- Files: game/save/save.*, tests/test_save.cpp.
- Done: test: save → load → save byte-identical; regenerated items equal originals; every historic Ember Mark version loads.

**53. Main menu + flow**
- Does: title screen (Continue/New/Options/Quit), Midden → Breach transition, death/respawn flow.
- Files: game/ui/main_menu.*, game/core/game_flow.*.
- Done: full flow reachable by keyboard only in a window run.

**54. Playtest pass 1 – automated**
- Does: scripted headless bot (`--playtest`): spawn, kill a wave, pick up parts, assemble a staff at the station, level, save, reload; assert no validation errors.
- Files: game/debug/playtest.*, CMakeLists.txt (ctest).
- Done: ctest `playtest_bot` passes.

**55. Playtest pass 2 – manual + fixes**
- Does: 15-minute manual run with checklist (feel, balance, readability, crafting flow, crashes); fix top issues; record findings.
- Files: docs/playtests/2026-xx-xx.md, any fixes.
- Done: checklist filled, no blocker bugs left, README "How to play" updated. **Vertical slice complete** (tag `v0.1-slice` locally).

## After the slice

**56. CI breadth (deferred from step 7; was step 51)**
- Does: `.clang-format` + `.clang-tidy` baselines and CI jobs (format check, tidy on changed files); Windows/MSVC job (`windows` preset, MSVC `/W4 /WX`, `/fsanitize=address` only since MSVC has no UBSan); ADR-0002 if Windows forces a package manager.
- Files: .clang-format, .clang-tidy, CMakePresets.json, .github/workflows/ci.yml.
- Done: all jobs green on a branch push; local `clang-format --dry-run -Werror` clean.
