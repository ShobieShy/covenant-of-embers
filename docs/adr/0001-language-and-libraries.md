# ADR-0001: Language (C++20) and third-party libraries

- Status: Accepted
- Date: 2026-10-22
- Milestone: M0 (BUILD_PLAN step 7)
- Supersedes: the open "C++20 or Rust, decide at M0 with an ADR" row in [PLAN.md §23](../PLAN.md#23-technical-architecture)

## Context

Covenant of Embers is a small custom Vulkan engine plus a co-op loot FPS (PLAN §2, §23).
By the end of M0 the repo already contains C++20 code: an SDL3 window, a Vulkan 1.3
renderer with dynamic rendering + synchronization2 (step 3), CI on clang + lavapipe (step 4),
and the C++ asset cooker (step 6). PLAN §23 left the language open between:

- **C++20**: the most mature Vulkan ecosystem (VMA, volk, Dear ImGui, Jolt, fastgltf,
  miniaudio, EnTT), every library we plan to use is native C/C++, and contributors are easy to find.
- **Rust** (ash + gpu-allocator, Rapier, egui, …): memory safety by construction, but
  Jolt/RmlUi/GameNetworkingSockets need FFI bindings, Vulkan code is mostly `unsafe`
  anyway, and the existing M0 code would have to be rewritten.

Magewar (the Godot project in `~/game`, read-only reference) taught two relevant lessons
(PLAN §1, §22, §25): systems shipped without automated tests broke silently, and its
headless test runner is trusted because it fails on *any* runtime `ERROR` line, not
only on assertion failures. Magewar keeps no decision records; its decisions live in
the Bible and commit messages, which made the "why" hard to recover later. This ADR
(and `docs/adr/` in general, PLAN §24) is the reinterpretation: one short file per
lasting decision.

Constraints: Linux first (Luna runs Garuda; CI is Ubuntu 24.04), Windows later; no
system installs required beyond a compiler, CMake, Ninja, the Vulkan loader/headers and
glslc; everything must build offline-reproducibly from pinned sources.

## Decision

### Language and toolchain

- **C++20** (`CMAKE_CXX_STANDARD 20`, extensions off). GCC 13+ and Clang 17+ supported;
  CI uses clang, local default is GCC, so both stay warning-free with
  `-Wall -Wextra -Wpedantic`. MSVC comes later (see Consequences).
- **Build**: CMake ≥ 3.25 + Ninja via `CMakePresets.json` (`debug`, `release`, `asan`).
- **Memory safety is bought with tooling, not the language** (this is what tips the
  balance against Rust): an `asan` preset (ASan + UBSan) whose `ctest -LE window` run is
  a required CI job, the Vulkan validation layer failing every GPU test on any error,
  and headless tests for every new system (PLAN §25).

### The `asan` preset

- `cmake --preset asan` = Debug + `COE_SANITIZE=ON`, which adds
  `-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer` to
  every target in the tree (including a fetched SDL3). UBSan is fatal so a report fails the test.
- `ctest --test-dir build/asan -LE window` (or `ctest --preset asan`). The test
  environment is set in CMakeLists.txt, so plain `ctest` and CI get the same options:
  `ASAN_OPTIONS` (leaks on, stack-use-after-return, init-order checks),
  `UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1`,
  `LSAN_OPTIONS=suppressions=tools/sanitizers/lsan.supp`, and
  `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1`.
- Why the loader variable: by default the Vulkan loader `dlclose()`s ICDs and layers in
  `vkDestroyInstance`. That unmaps Mesa's globals that still point at one-time
  `pthread_once` allocations, so LSan reports 2–3 × 128 B "leaks" with `<unknown module>`
  frames (seen on RADV and lavapipe) that no suppression can match. The loader's own
  switch for leak tools keeps the libraries mapped; leak detection stays fully on for
  our code. `lsan.supp` is currently empty; any future entry must name a system library,
  the test and driver that hit it, and why it is not our bug.
- Running a sanitized binary by hand: export the same variables
  (at least `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1`), otherwise LSan exits 1 at shutdown.

### Libraries

Policy: third-party code comes in via **CMake FetchContent**, pinned to a release tarball
`URL` + `URL_HASH SHA256=…` (from step 10 on; a tag alone can be moved), declared `SYSTEM`
so its headers don't trip our warnings, and only when a step needs it. If a library would
download a further dependency itself without a hash, we provide that target first (see
simdjson below). SDL3's optional fallback fetch predates this and still uses
`GIT_TAG release-3.4.18` + `GIT_SHALLOW`; it moves to a hashed tarball with its next bump. No vcpkg/CPM/Conan (PLAN §23's "vcpkg or CPM" is replaced by this).
Only the Vulkan SDK pieces (loader, headers, glslc, optional validation layer) and
Python ≥ 3.11 (stdlib only, for tools) come from the system.

| Area | Choice | License | Arrives | Notes |
|---|---|---|---|---|
| Window, input, gamepad | **SDL3** | Zlib | step 3 | **System-or-FetchContent**: `find_package(SDL3 CONFIG)` first; if absent (Ubuntu 24.04 has no package) or `-DCOE_FETCH_SDL3=ON`, fetch pinned `release-3.4.18` as a static lib. CI forces the fetch with `SDL_UNIX_CONSOLE_BUILD=ON` (no X11/Wayland dev packages). Bumping the pin is a one-line change that must keep both paths green. |
| GPU API | **Vulkan 1.3** (dynamic rendering, sync2), linked to the system loader | Apache-2.0 | step 3 | volk deferred until per-device dispatch or startup cost matters. |
| Shaders | **GLSL → SPIR-V with glslc** at build time (`-Werror`) | Apache-2.0 | step 3 | Slang re-evaluated when the material system lands (post-slice ADR). |
| GPU memory | **VMA** | MIT | step 11 | v3.4.0 tarball (URL_HASH, SYSTEM, `GPUOpen::VulkanMemoryAllocator`); `VMA_IMPLEMENTATION` in engine/render/vma_impl.cpp, static Vulkan functions (`VMA_STATIC_VULKAN_FUNCTIONS=1`, private to `coe_engine`); public headers only forward-declare `VmaAllocator`/`VmaAllocation`. |
| Math | **GLM** | MIT | step 10 | 1.0.3 release tarball via FetchContent (URL_HASH SHA256, SYSTEM), header-only (`GLM_BUILD_LIBRARY OFF`); `GLM_FORCE_RADIANS` + `GLM_FORCE_DEPTH_ZERO_TO_ONE` are PUBLIC on `coe_engine` |
| glTF | **fastgltf** | MIT | step 11 | v0.9.1 tarball (URL_HASH, SYSTEM, `FASTGLTF_COMPILE_AS_CPP20`). In `coe_assets` (CPU-only lib shared by the cooker and the engine). |
| JSON reads | **simdjson** | Apache-2.0 | step 11 | v4.6.11 tarball (URL_HASH); we build its single-header amalgamation as `coe_simdjson` and alias it `simdjson::simdjson` *before* fastgltf, so fastgltf's own unhashed download is skipped. Reads `cooked/manifest.json`; JSON we *write* stays hand-rolled, sorted and timestamp-free for determinism. |
| TOML (data files) | **toml++** | MIT | step 12 | v3.4.0 tarball (URL_HASH, SYSTEM, `tomlplusplus::tomlplusplus`, header-only). Linked PRIVATE to `coe_game`; each parser .cpp sets `TOML_EXCEPTIONS 0` before the include (`parse_result` API, errors carry file:line). Levels, weapons, loot, patches, bindings; tools keep Python `tomllib`. |
| Physics | **Jolt Physics** | MIT | step 13 | v5.6.0 tarball (URL_HASH SHA256 `6e069ee0…3f8e`, `SOURCE_SUBDIR Build`, SYSTEM, target `Jolt`). Linked PRIVATE to `coe_physics` only (pimpl: no Jolt header outside engine/physics/*.cpp and its private physics_impl.hpp; step 14 adds character.cpp). Options: GPU compute (VK/DX12/MTL/CPU), debug renderer, profiler, ObjectStream, install, IPO, `ENABLE_ALL_WARNINGS` (-Werror) and `OVERRIDE_CXX_FLAGS` off; `CPP_RTTI_ENABLED` on (UBSan vptr); exceptions off; single precision; asserts follow the build type (`JPH_DEBUG` when !NDEBUG). Default x86-64 SIMD level: Jolt adds PUBLIC `-mavx2 -mbmi -mpopcnt -mlzcnt -mf16c -mfma` (x86-64-v3 CPUs, 2013+) — revisit with the min-spec decision. Single-threaded job system by default, thread pool optional. |
| Unit tests | **doctest** | MIT | step 20 | Until then each tool has a `--self-test` ctest. |
| Debug UI | **Dear ImGui** | MIT | step 22 | |
| Game UI text | **stb_truetype** | MIT / public domain | step 36 | RmlUi (PLAN §23) deferred past the slice. |
| Audio | **miniaudio** | MIT-0 / public domain | step 44 | |
| Later (own ADRs) | EnTT, RmlUi, sol2/Lua, GameNetworkingSockets or ENet, KTX2/BasisU, meshoptimizer | — | post-slice | Not pulled in before a step needs them. |

## Consequences

- Good: no rewrite of M0; direct access to the C/C++ Vulkan ecosystem; one build system;
  pinned, reproducible dependencies; sanitizer + validation runs catch the memory and
  API bugs Rust would have prevented at compile time (and some it would not).
- Bad: memory safety depends on discipline: the `asan` CI job must stay green, and new
  tests must run under it (no `window` label unless they truly need a display). The
  sanitized test env is applied to tests registered in the top-level CMakeLists.txt;
  when targets move into `engine/` and `game/` (step 8) the helper must cover
  tests added in subdirectories too.
- Bad: FetchContent rebuilds dependencies per build dir (slower clean builds, CI caches `_deps`).
- Deferred until after the vertical slice (BUILD_PLAN step 51): Windows/MSVC CI job,
  clang-tidy and clang-format jobs (PLAN §25). They need a `.clang-format`/`.clang-tidy`
  baseline and an MSVC sanitizer story (`/fsanitize=address` only, no UBSan).
- Revisit this ADR if: a dependency stops building under ASan/UBSan, Windows support
  forces a package manager, or a large safety-critical subsystem (netcode) would be
  better written in Rust behind a C ABI.
