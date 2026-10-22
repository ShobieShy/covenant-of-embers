# Covenant of Embers – Build Plan

## Standing rules (every hourly run)
1. Building the next step is the priority.
2. Review the Magewar references in the project and in `~/game/magewar` (read-only), and make sure the build follows them. Reinterpret, don't copy.
3. Look for plan improvements: refine future steps, or go back and fix bugs from earlier steps.
4. Log any such changes in the history in `build_state.json`.

Design source of truth: [docs/PLAN.md](docs/PLAN.md) (§26 milestones, §30 loot-shooter spec). Current progress: `build_state.json`.

## Steps
| # | Step | Milestone | Status |
|---|---|---|---|
| 1 | Plan + loot-shooter spec (docs/PLAN.md §30) | M0 | done (`3b54564`) |
| 2 | Repo scaffold: Apache-2.0, CMake C++20, ASSETS.toml/CREDITS.md, Kenney CC0 starter assets | M0 | done (`3b54564`) |
| 3 | SDL3 window, Vulkan 1.3 instance/device/swapchain, triangle, optional validation, headless smoke test | M0 | done (`1c436e7`) |
| 4 | CI (GitHub Actions workflow file, Linux clang; lavapipe headless smoke test) – file only, no push | M0 | next |
| 5 | Asset cooker stub (`tools/asset_cooker`) + ASSETS.toml license lint | M0 | todo |
| 6 | ADR-0001: C++20 vs Rust (docs/adr) | M0 | todo |
| 7 | Engine split (engine/ vs game/), fixed-timestep loop, input, camera, depth buffer, mesh pipeline (glTF via fastgltf) | M1 | todo |
| 8 | FPS controller: sprint, slide, dash (§30.8) + Jolt physics | M1 | todo |
| 9 | Weapons: one Workshop, Sidearm + Repeater, ammo/reload/ADS, damage formula (§30.1), damage numbers | M1 | todo |
| 10 | Gnawers + Heaps with basic AI; greybox Midden | M1 | todo |
| 11 | Save round-trip + damage/loot headless tests (§30.9) | M1 | todo |
| 12 | M2 loot core (parts, Grades, Workbench, inventory, essences, Tallies, instanced loot) | M2 | todo |

## Known issues / follow-ups
- `vulkan-validation-layers` not installed on Luna: renders have not been validation-checked yet. Re-run `ctest --test-dir build/debug` after it is installed.
