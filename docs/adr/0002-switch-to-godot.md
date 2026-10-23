# ADR-0002: Switch from the custom C++20/Vulkan engine to Godot 4

- Status: Accepted
- Date: 2026-10-23
- Supersedes: [ADR-0001](0001-language-and-libraries.md) (engine, language and library choices)
- Approved by: ShobieShy ("Yes, switch to Godot", 2026-10-23)

## Context
After 23 of 56 hourly steps the custom engine had a renderer, Jolt physics, an FPS controller,
Magewar-style casting, mana, focus/spread, slots, a viewmodel, dummies and the Gnawer. Much of the
remaining slice (UI renderer, audio engine, navigation, save plumbing, exports) is engine work that
Godot already provides. Magewar itself is a Godot 4 project, so its resources and conventions map directly.

## Decision
- Engine: **Godot 4.7.2 stable** (Arch `godot` package), Forward+ renderer, built-in Jolt Physics, 60 Hz physics ticks, MSAA 2×.
- Language: typed GDScript. Data in Godot Resources (.tres); level/balance data may stay TOML/JSON converted by tools.
- Tests: addon-free headless runner `tests/run_tests.gd` (GUT can be added later if needed); `tools/run_tests.sh` is the single green gate.
- The C++ engine is kept, not deleted: branch `archive/cpp-vulkan-engine` and folder `archive/cpp-engine/` (Godot-ignored).
- Design (PLAN.md, especially §30 Magewar weapon/loot/crafting and the 60 % resistance cap) is unchanged.

## Consequences
- Finished gameplay is re-implemented in GDScript (BUILD_PLAN steps 3–12) with the archived C++ tests as the reference values.
- Fewer steps (42 vs 56): no UI renderer, audio engine, asset cooker or Vulkan work.
- Licensing unchanged: Apache-2.0 code; Godot is MIT; asset rules (Kenney/CC0, Magewar's own assets, no Borderlands or paid assets) unchanged.
