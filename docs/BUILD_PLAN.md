# Covenant of Embers – Build Plan (Godot 4)

## Standing rules (every hourly run)
1. Building the next step is the priority.
2. Review the Magewar references in `~/game/magewar` and `~/game/Magewar Bible.md` (read-only; copies in `assets/magewar/`). The weapon/loot/crafting system follows Magewar's design directly (ShobieShy's own IP: staffs, wands, parts, rarities, equipment, crafting); other systems are reinterpreted, not copied.
3. Look for plan improvements: refine future steps, or go back and fix bugs from earlier steps.
4. Log any such changes in the history in `docs/build_state.json`.
5. Kept decisions: resistance cap 60 % per element (not Magewar's 90 %); Breath/dash/mana numbers in PLAN §30.8/§30.1.

Design source of truth: [PLAN.md](PLAN.md) (§30 loot-shooter + Magewar weapon/loot/crafting spec, §31 loot architecture). Engine decision: [ADR-0002](adr/0002-switch-to-godot.md). Progress: [build_state.json](build_state.json) (`next_step`).

Every step is ~1 hour, written in GDScript (typed), keeps `tools/run_tests.sh` green (headless import, `tests/run_tests.gd` unit tests, `-- --seconds 2` smoke run, asset lint), adds its tests under `tests/unit/test_*.gd`, and ends with a local commit (never push). Gameplay tests drive nodes by stepping physics frames deterministically. Every new asset goes into ASSETS.toml + CREDITS.md (Kenney/CC0 and Magewar's own assets OK; no Borderlands or paid assets). Porting steps 3–12 reimplement the design and numbers already validated in the archived C++ engine (`archive/cpp-engine/`, branch `archive/cpp-vulkan-engine`); use its tests as the reference for expected values.

Goal: a **minimal playable vertical slice**: walk a greybox Midden, fight Gnawers and Heaps with Magewar-style staffs and wands, pick up rarity-coloured parts and equipment, craft at a Magic Assembly Station, level up, clear a Breach room with a mini-boss, hear Kenney audio, save/load.

## M0 – Foundations

**1. Godot 4 project setup** ✅
- Does: Godot 4.7.2 (pacman `godot`), project.godot (Forward+, Jolt Physics, 60 Hz, MSAA 2×), scenes/main.tscn, scripts/core/main.gd (`-- --seconds N`), tests/run_tests.gd + tests/test_case.gd (addon-free runner; GUT optional later), tools/run_tests.sh, Kenney packs kept, Magewar resources copied to assets/magewar (.gdignore'd reference), C++ engine archived, ADR-0002.
- Done: `tools/run_tests.sh` green: 4 unit tests (Godot 4, Forward+/60 Hz, main scene, Kenney blaster-a.glb imports), 2 s headless run logs 120 physics ticks, asset lint OK.

**2. Midden greybox + CI workflow**
- Does: Port data/levels/midden_greybox.toml to scenes/levels/midden.tscn (17 boxes as StaticBody3D/CSG, same sizes/rotations Y-X-Z, palette/fog, PlayerStart marker at (0,0,12.5) facing north, eye 1.5 m). tools/toml_to_scene.py or a GDScript importer so data stays the source. New .github/workflows/ci.yml (Godot 4.7.2 headless, import + run_tests.sh), not pushed.
- Done: test_level.gd: 17 boxes with kinds/counts as the TOML, ramp tops meet ledge, 400 down-raycasts hit up-facing surfaces; ci.yml parses (`python3 -c yaml.safe_load`).

## M1 – Spellcasting prototype (ports first)

**3. FPS controller: walk, jump, crouch, look (port of old 14)**
- Does: scripts/player/player.gd on CharacterBody3D + PlayerTuning Resource: walk 4, crouch 3 m/s, LERP 10/AIR 6, jump 4.5/3.0 m/s on press edge, gravity 9.8, capsule 0.3×1.7/0.7, eye 1.5/0.6, step 0.35 m, floor_max_angle 45°, 0.25°/count look, pitch ±89°, InputMap actions (WASD/Space/LMB/RMB/LShift/Q/C+LCtrl/F/1–4).
- Done: test_player.gd (simulated physics frames): 1 s W ≈ 3.67 m ±0.5, apex 1.07/0.48 m ±0.06, crouch eye 0.6 and can't stand under a 1 m slab, 0.35 m step climbed / 0.5 m blocked, ramp → ledge y 1.5.

**4. Sprint, Breath and slide (port of old 15)**
- Does: scripts/player/breath.gd (max 100, drain 20/s, regen 30/s after 1 s, resume at 20, max bonus), sprint 7 m/s, slide (5 m/s × (t/1.5 + 0.5), 1.5 s, slide jump ×1.3), speed multiplier hook.
- Done: test_breath.gd: empty after 300 ticks, resume after 100, full after 260; test_player slide 90 ticks ≈ 7.5 m, no slide from walk/exhausted.

**5. Dash + camera feel (port of old 16)**
- Does: scripts/player/dash.gd (6 m in 0.15 s, 2 charges, 1.5 s recharge each, 25 Breath, 0.1 s i-frames, 1 air dash), camera_feel.gd (head bob walk/sprint/crouch, landing dip 0.12 m, reduced-motion setting).
- Done: test_dash.gd: 6.000 m ±0.05 in 9 ticks, 3rd refused, recharge 90/180 ticks, wall stop; test_camera_feel: bob amplitudes, dip 0 below 2 m/s, max 0.12 m, reduced motion = 0.

**6. Elements + damage formula (port of old 20)**
- Does: resources/magic/elements.tres (Magewar names/colours, chart Fire>Earth>Air>Water>Fire, Light⇄Dark, ×1.5/×0.5, same/Arcane ×1.0), scripts/combat/damage.gd: base × rarity mult + Σ part bonus, × effectiveness × (1 − resist, cap **0.6**) × weak point 2.
- Done: test_damage.gd: full 7×7 chart = Magewar get_effectiveness, resist 0.8→0.6, worked example 12×1.5×0.7×2 = 25.2.

**7. Wieldable data + Arcane bolt casting (port of old 17)**
- Does: Resource classes WieldableDef/WieldablePart/WieldableInstance, resources/wieldables/*.tres for the 4 Magewar bases (10/5/0.40/30/50, 14/6/0.55/22/45, 7/3/0.25/40/35, 6/2.5/0.18/55/40), caster.gd semi-auto on Fire press with cooldown ≥ 0.1 s, bolt = per-tick raycast from the eye (PhysicsRayQuery, exclude self), fizzle at range, element-coloured tracer.
- Done: test_casting.gd: 20 m wall hit at 20.000 m in D/v s ±1 tick for all 4 bases, Swift Wind never casts twice within 0.18 s, self never hit.

**8. Mana pool (port of old 18)**
- Does: scripts/player/mana.gd: 100, regen 3/s after 1.5 s since last successful spend, refusal doesn't reset delay, regen/max bonus hooks; caster spends mana; no ammo/reload.
- Done: test_mana.gd: Fire staff 20 casts to 0, 21st refused, casts again at tick 646 ±1; empty → full 34.83 s.

**9. Focus, accuracy and spread (port of old 19)**
- Does: Focus tween FOV 75→55 in 0.2 s (staff and wand), look scale tan ratio 0.6784, accuracy 50 + Head/Handle/Charm clamp 0–100, spread cone (4°, focus 0.35, crouch 0.8, moving 1.3, air 1.8, bloom +1°/cast cap 4° clears in 0.5 s), seeded RNG.
- Done: test_accuracy.gd: 55° exactly at tick 12, 100 % accuracy = zero spread, 50 % hip 2.0°/focused 0.7°, bloom clears in 30 ticks.

**10. Staff + wand slots and viewmodel (port of old 21)**
- Does: loadout.gd: Staff/Wand slots, per-slot cooldown, 0.4 s swap (1/2), viewmodel SubViewport/layer at 75° FOV with Magewar default_position poses, greybox shaft + element-coloured gem, focus slide, cast point tracer.
- Done: test_loadout.gd: swap 24 ticks no cast during, Earthward cooldown survives swap; headless render check of gem colour (cos ≥ 0.97) via viewport texture.

**11. Enemy entity, training dummies, damage numbers (port of old 22)**
- Does: scripts/enemies/enemy.gd (health, affinity, resistances, weak-point head Area), resources/enemies/training_dummies.tres, Label3D floating damage numbers in element colour, death at 0 HP, dummies placed in Midden.
- Done: test_enemy.gd: Fire staff vs Earth dummy = 15 per hit, Water dummy 5, head ×2, dies at 0.

**12. Gnawer AI (port of old 23)**
- Does: gnawer.gd state machine Idle/Detect/Chase/Attack/Knockback/Dead (Magewar enemy_base + mutant rat: detect 8, aggro 6, walk 3, sprint 5.5, bite 3 Earth / 0.8 s, knockback > 10 dmg), NavigationAgent3D chase around walls (baked NavMesh), i-frame dodge.
- Done: test_gnawer.gd: transitions at 8/6/1 m, bites 48 ticks apart, chases around a wall to the player.

**13. Heap AI (tank) + player health/shield**
- Does: Heap tank (slow, high HP, slam), player health + shield (shield first, regen delay), resolveHit for enemy hits, i-frames from dash, player death/respawn.
- Done: test_heap.gd + test_player_health.gd: damage order shield→health, regen timing, dash i-frames ignore a bite, death at 0.

**14. Enemy spawner + kill events**
- Does: Spawn points/waves from level data, EventBus autoload (enemy_killed, player_damaged), Gnawer separation.
- Done: test_spawner.gd: wave counts, kill events fire once per death.

## M2 – Loot, crafting, progression

**15. Rarity tiers + part model (Magewar)**
- Does: Rarity resource (Basic #B3B3B3 ×1.0 w50, Uncommon #33CC33 ×1.25 w25, Rare #3366FF ×1.5, Mythic #991AE6 ×2.0, Primordial #FF9900 ×2.75, Unique #FFD900 ×3.0), Part types Head/Exterior/Interior/Handle/Charm, imported from assets/magewar part .tres values.
- Done: test_rarity.gd: colours/multipliers/weights match PLAN §30.2 and the Magewar part resources.

**16. Part stat rolls, gems, names**
- Does: Seeded stat rolls per part/rarity, gem sockets, generated names.
- Done: test_parts.gd: deterministic rolls per seed, ranges per rarity.

**17. Assembly rules + final stats**
- Does: Staff 4–5 parts, wand 2–3; rarity = average of parts; cooldown × Exterior × Charm ≥ 0.1; Head element override.
- Done: test_assembly.gd: invalid builds rejected, worked examples from §30.

**18. Base wieldables + drop pools**
- Does: Drop pools per enemy/level, weighted.
- Done: test_pools.gd: 10 000 rolls within 2 % of weights.

**19. Equipment items**
- Does: Hat/Clothes/Belt/Shoes/Grimoire/Potion with Magewar bonuses (mana, regen, stamina, speed, resist ≤ 60 %).
- Done: test_equipment.gd: bonuses applied/removed exactly, resist cap 0.6.

**20. Ember Mark item codes**
- Does: EM1-… encode/decode of any item.
- Done: test_item_codes.gd: round-trip 1000 random items, bad codes rejected.

**21. Balance patch loader**
- Does: Hotfix-style JSON data patches over resources (§31).
- Done: test_patches.gd: patch applies, invalid keys rejected.

**22. Loot drops on kill**
- Does: enemy_killed → roll pool → spawn rarity-coloured pickup with light beam.
- Done: test_drops.gd: kill spawns drop with correct rarity colour.

**23. Pickup + auto-collect**
- Does: Interact pickup, auto-collect for mana/dust, compare card data.
- Done: test_pickup.gd: walk-over collects, Interact picks item.

**24. Inventory and equip**
- Does: Inventory grid model, equip to staff/wand/equipment slots.
- Done: test_inventory.gd: capacity, equip/unequip updates stats.

**25. Magic Assembly Station (crafting core)**
- Does: Assemble/disassemble at a station node (Magewar).
- Done: test_station.gd: assemble then disassemble returns the same parts.

**26. Crafting extras: gems, salvage, upgrade**
- Does: Gem sockets, salvage parts → Arcane Dust, upgrade a part one tier with Dust (our additions, flagged).
- Done: test_crafting_extras.gd: dust amounts, tier cap at Unique.

**27. XP curve and levels**
- Does: XP from kills, level-ups (+5 max mana/Breath + refill).
- Done: test_xp.gd: curve values, level-up hooks.

**28. Weight model + Vigil plumbing**
- Does: Vigil tiers 1–10 with Omens shifting rarity weights (§31).
- Done: test_vigil.gd: weights shift per tier as specified.

## M3 – UI, dungeon, audio, saves, playtests

**29. HUD**
- Does: Control-based HUD: health/shield/mana/Breath bars, crosshair (hidden while focused, spread-sized), slot icons with rarity colours, Kenney UI Pack.
- Done: test_hud.gd: bars track values; headless screenshot non-empty.

**30. Inventory + equipment screen**
- Does: Inventory UI with rarity colours and compare cards.
- Done: test_inventory_ui.gd: open/close, equip via UI.

**31. Assembly Station UI**
- Does: Station UI for assemble/disassemble/salvage/upgrade.
- Done: test_station_ui.gd: assemble via UI produces the item.

**32. Key-bindings config**
- Does: Rebind UI + user://keybinds.cfg, invert-Y, hip FOV, focus hold/toggle, Reload unbound.
- Done: test_keybinds.gd: save/load round-trip, rebind applies.

**33. Breach room slice: layout**
- Does: Breach room scene with entrance, arena, vault door.
- Done: test_breach.gd: scene loads, navmesh baked, spawns valid.

**34. Mini-boss (2 phases)**
- Does: Two-phase mini-boss state machine.
- Done: test_boss.gd: phase switch at 50 %, death opens vault.

**35. Vault + guaranteed boss loot**
- Does: Vault chest with guaranteed rarity floor.
- Done: test_vault.gd: drop rarity ≥ floor across 1000 seeds.

**36. Consecrations (enchantments)**
- Does: Our version of anointments on parts/equipment.
- Done: test_consecrations.gd: effects trigger as specified.

**37. Audio: buses + Kenney sounds**
- Does: Audio buses (Master/SFX/UI/Music), cast/hit/footstep/UI sounds from Kenney packs, 3D AudioStreamPlayer3D.
- Done: test_audio.gd: every referenced stream loads, buses exist.

**38. Save format, round-trip + load**
- Does: Versioned JSON save in user:// (player, inventory, items via Ember Mark codes, progress), load from menu.
- Done: test_save.gd: save→load round-trip equal, old version rejected cleanly.

**39. Main menu + flow**
- Does: Main menu → Midden → Breach → back, pause menu, settings.
- Done: test_flow.gd: scene transitions headless.

**40. Playtest pass 1 – automated**
- Does: Scripted bot plays the slice headless (move, cast, kill, loot, craft, save).
- Done: playtest.gd completes the slice in headless mode, no errors.

**41. Playtest pass 2 – manual + fixes**
- Does: ShobieShy plays; fix reported issues.
- Done: Issues list closed or deferred in plan.

## After the slice

**42. CI breadth**
- Does: gdlint/gdformat (gdtoolkit) check, Windows + Linux export presets built headless in CI.
- Done: all jobs green locally via act or scripted equivalent; exports run --seconds 2.
