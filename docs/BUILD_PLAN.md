# Covenant of Embers – Build Plan

## Standing rules (every hourly run)
1. Building the next step is the priority.
2. Review the Magewar references in the project and in `~/game/magewar` (read-only), and make sure the build follows them. Reinterpret, don't copy.
3. Look for plan improvements: refine future steps, or go back and fix bugs from earlier steps.
4. Log any such changes in the history in `docs/build_state.json`.

Design source of truth: [PLAN.md](PLAN.md) (§26 milestones, §30 loot-shooter spec). Progress: [build_state.json](build_state.json) (`next_step`).
Each step is sized at ~1 hour. Every step must keep `cmake --build --preset debug` warning-free and `ctest --test-dir build/debug` green, and ends with a local commit (never push). Third-party libraries come in via CMake FetchContent (no system installs); every new asset goes into ASSETS.toml + CREDITS.md.

Goal: a **minimal playable vertical slice**. One player walks a greybox Midden, fights Gnawers and Heaps with procedurally rolled Sidearms/Repeaters, picks up loot, levels up, clears a Breach room slice with a mini-boss, hears Kenney audio, and saves/loads.

---

## M0 – Foundations

**1. Plan + loot-shooter spec** ✅ `3b54564`. Does: docs/PLAN.md incl. §30. Files: docs/PLAN.md. Done: §30 present.

**2. Repo scaffold** ✅ `3b54564`. Does: Apache-2.0, CMake C++20, ASSETS.toml/CREDITS.md, 4 Kenney CC0 packs. Files: root files, assets/kenney/. Done: builds; manifest lists all 4 packs.

**3. Window + Vulkan triangle** ✅ `1c436e7`. Does: SDL3 window, Vulkan 1.3 device/swapchain, dynamic rendering, optional validation, headless test. Files: src/main.cpp, src/render/vk_renderer.*, shaders/. Done: both ctest smoke tests pass.

**4. CI workflow file**
- Does: GitHub Actions workflow (Ubuntu, clang, Ninja, lavapipe) that builds and runs `ctest -LE window`. File only; not pushed.
- Files: .github/workflows/ci.yml.
- Done: YAML parses (`python -c "import yaml..."`); `ctest -LE window` passes locally.

**5. Asset license lint**
- Does: script that fails if any top-level folder under assets/ is missing from ASSETS.toml, or an entry lacks license/source. Registered as a ctest.
- Files: tools/check_assets.py, CMakeLists.txt.
- Done: ctest `asset_license_lint` passes; temporarily adding an untracked folder makes it fail.

**6. Asset cooker stub**
- Does: `tools/asset_cooker` CLI that copies/validates the glTF/PNG/OGG files it is given into build/cooked/ with a manifest (real conversion comes later).
- Files: tools/asset_cooker/main.cpp, CMakeLists.txt.
- Done: running it on assets/kenney/blaster-kit writes build/cooked/manifest.json listing the files.

**7. ADR-0001 language choice**
- Does: records C++20 (vs Rust) decision and library choices.
- Files: docs/adr/0001-language-and-libraries.md.
- Done: ADR has Context/Decision/Consequences; README links it. **M0 complete.**

## M1 – Gunplay prototype

**8. Engine/game split + fixed-timestep loop**
- Does: move renderer into engine/, add game/ target, 60 Hz fixed update + variable render with interpolation alpha.
- Files: engine/{core,render}/, game/, src/main.cpp → game/main.cpp, CMakeLists.txt.
- Done: triangle still renders; `--seconds 3` logs ~180 fixed ticks.

**9. Input layer**
- Does: action map (MoveForward, Jump, Fire, Aim, Reload, Sprint, Dash, Crouch, Interact, Weapon1–4) on SDL3 keyboard/mouse, relative mouse mode.
- Files: engine/input/input.{hpp,cpp}.
- Done: unit test maps synthetic key events to actions; actions print in a debug run.

**10. Math, camera and depth buffer**
- Does: GLM via FetchContent, per-frame camera UBO/push constants, depth attachment, rotating cube.
- Files: engine/render/{camera,vk_renderer}.*, shaders/basic.*.
- Done: headless test checks a cube pixel is lit and depth image exists; no validation errors.

**11. Mesh pipeline + glTF loading**
- Does: fastgltf via FetchContent, GPU vertex/index buffers (VMA via FetchContent), draw a Kenney blaster model.
- Files: engine/render/mesh.*, engine/assets/gltf_loader.*.
- Done: loads `blaster-kit` model with N>0 triangles; headless pixel check shows non-clear centre.

**12. Greybox Midden arena**
- Does: data-defined boxes (TOML) forming ground, walls, ramps, crates; simple directional lighting.
- Files: data/levels/midden_greybox.toml, game/world/level.*.
- Done: level loads ≥10 boxes; screenshot (headless .ppm) shows floor and walls.

**13. Jolt physics world**
- Does: Jolt via FetchContent, static colliders from the greybox, physics step on fixed tick.
- Files: engine/physics/physics.*.
- Done: test drops a dynamic box onto the floor and it comes to rest at the expected height (±0.05 m).

**14. FPS controller: walk, jump, crouch, look**
- Does: Jolt CharacterVirtual, mouse look with pitch clamp, jump, crouch height change.
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
- Does: ADS FOV tween, spread cone with stance multipliers and per-shot bloom/decay (§30.1).
- Files: game/weapons/accuracy.*, engine/render/camera.*.
- Done: tests: ADS spread = 0.35× hip; bloom decays to base within configured time.

**20. Damage formula + test framework**
- Does: doctest via FetchContent; implement §30.1 formula (Base×1.13^(ilvl−1), Grade, parts, essence match, resist cap 60 %, crit, falloff).
- Files: game/combat/damage.*, tests/test_damage.cpp.
- Done: ≥8 doctest cases incl. resist cap and weak-point crit pass.

**21. Repeater, weapon slots and viewmodel**
- Does: auto-fire Repeater, 2 unlocked slots with 1/2 swap and equip time, viewmodel draws the Kenney blaster mesh.
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

**27. Weapon stats from parts**
- Does: compute final WeaponInstance stats from rolled parts + affixes; generated names.
- Files: game/loot/assemble.*, game/weapons/weapon.*.
- Done: tests: higher Grade ⇒ higher damage; name built from strongest bonus + Workshop.

**28. Loot drops on kill**
- Does: per-player drop roll on kill event (drop chance per enemy table), spawn world item with Grade-coloured light pillar.
- Files: game/loot/drop_table.*, game/world/world_item.*, data/enemies/*.toml.
- Done: test: 1000 Gnawer kills produce drop rate within ±2 % of table; pillar colour matches Grade.

**29. Pickup + auto-collect**
- Does: Interact to pick up weapons; Tallies/ammo auto-collect in radius; loot feed log.
- Files: game/loot/pickup.*.
- Done: tests: pickup moves item to inventory; Tallies auto-collect within 2 m only.

**30. Inventory and equip**
- Does: 30-slot backpack, equip to weapon slots, drop, salvage to Scrap.
- Files: game/inventory/inventory.*.
- Done: tests for add/full/equip/swap/salvage.

**31. XP curve and levels**
- Does: XP(L)=120×1.35^(L−1), cap 50, level-up +health/+Breath/+Oil, XP from kill events (§30.5).
- Files: game/progression/xp.*, tests/test_xp.cpp.
- Done: tests for curve values, multi-level gain and cap.

**32. UI renderer (text + sprites)**
- Does: 2D quad batcher in Vulkan, Kenney Future font (assets/kenney/ui-pack/Font) via stb_truetype, Kenney UI PNG panels.
- Files: engine/ui/{ui_renderer,font}.*, shaders/ui.*.
- Done: headless test renders a text string; pixel check finds non-background pixels in its rect.

**33. HUD**
- Does: crosshair + hit markers, health/shield/Breath bars, ammo/mag counter, XP bar + level, loot feed.
- Files: game/ui/hud.*.
- Done: values on HUD update when shooting/reloading/levelling in a window run; headless snapshot test.

**34. Inventory screen**
- Does: Tab opens backpack grid with compare card (green/red stat deltas), equip/salvage buttons, mouse + keyboard.
- Files: game/ui/inventory_screen.*.
- Done: equipping from the screen changes the active weapon; compare deltas match computed stats in a test.

**35. Key-bindings config**
- Does: load/save `config/bindings.toml` (user dir via SDL_GetPrefPath), defaults on first run, mouse sensitivity/invert-Y, simple rebind menu.
- Files: engine/input/bindings.*, game/ui/options_screen.*.
- Done: test: rebinding Jump writes file; reload restores it; malformed file falls back to defaults.

**36. Breach room slice: layout**
- Does: greybox Breach (entrance → 2 combat rooms → mini-boss arena → loot vault) with door triggers and arena lock.
- Files: data/levels/breach_slice.toml, game/world/{doors,triggers}.*.
- Done: walking through triggers advances room state; doors lock during combat and open on clear.

**37. Mini-boss (2 phases)**
- Does: "Midden Spawn" mini-boss: phase 1 sludge lob; phase 2 at 50 % adds ooze spawns and faster cadence; boss health bar.
- Files: game/bosses/midden_spawn.*, game/ui/boss_bar.*.
- Done: tests: phase switches at 50 %; boss bar visible; killing it opens the vault door.

**38. Vault + guaranteed boss loot**
- Does: per-player guaranteed Gold+ drop from boss, vault chest, room-clear state.
- Files: game/loot/boss_rewards.*, game/world/chest.*.
- Done: test: boss kill always yields ≥ Gold; chest opens once.

**39. Audio engine**
- Does: miniaudio via FetchContent, buses (Master/SFX/UI/Music) with volumes, 3D positional one-shots.
- Files: engine/audio/audio.*.
- Done: unit test loads a Kenney OGG and plays to the null device without error; volumes clamp.

**40. Audio hookup with Kenney sounds**
- Does: map events to Kenney sounds: shots/hits (impact-sounds), UI clicks/pickups/level-up (interface-sounds, ui-pack/Sounds); data-driven sound table.
- Files: data/audio/sounds.toml, game/audio/sound_events.*.
- Done: every sound path in sounds.toml exists and is covered by ASSETS.toml (lint); audible in window run.

**41. Save format**
- Does: character save (level, XP, Tallies, inventory items as seed+parts, equipped slots, bindings untouched) as versioned JSON/TOML in pref path.
- Files: game/save/save.*.
- Done: save file written on quit/Interact at camp marker; schema version field present.

**42. Save round-trip + load**
- Does: load on start, version migration hook, corruption fallback.
- Files: game/save/save.*, tests/test_save.cpp.
- Done: test: save → load → save produces byte-identical file; regenerated items equal originals.

**43. Main menu + flow**
- Does: title screen (Continue/New/Options/Quit), Midden → Breach transition, death/respawn flow.
- Files: game/ui/main_menu.*, game/core/game_flow.*.
- Done: full flow reachable by keyboard only in a window run.

**44. Playtest pass 1 – automated**
- Does: scripted headless bot run (`--playtest`) that spawns, kills a wave, picks loot, levels, saves, reloads; asserts no validation errors.
- Files: game/debug/playtest.*, CMakeLists.txt (ctest).
- Done: ctest `playtest_bot` passes.

**45. Playtest pass 2 – manual + fixes**
- Does: 15-minute manual run with checklist (feel, balance, readability, crashes); fix top issues; record findings.
- Files: docs/playtests/2026-xx-xx.md, any fixes.
- Done: checklist filled, no blocker bugs left, README "How to play" updated. **Vertical slice complete** (tag `v0.1-slice` locally).
