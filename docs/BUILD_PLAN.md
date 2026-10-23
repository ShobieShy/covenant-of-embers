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

**1. Godot 4 project setup** ✅ `f199578`
- Does: Godot 4.7.2 (pacman `godot`), project.godot (Forward+, Jolt Physics, 60 Hz, MSAA 2×), scenes/main.tscn, scripts/core/main.gd (`-- --seconds N`), tests/run_tests.gd + tests/test_case.gd (addon-free runner; GUT optional later), tools/run_tests.sh, Kenney packs kept, Magewar resources copied to assets/magewar (.gdignore'd reference), C++ engine archived, ADR-0002.
- Done: `tools/run_tests.sh` green: 4 unit tests (Godot 4, Forward+/60 Hz, main scene, Kenney blaster-a.glb imports), 2 s headless run logs 120 physics ticks, asset lint OK.

**2. Midden greybox + CI workflow** ✅ `5179adc`
- Does: Port data/levels/midden_greybox.toml to scenes/levels/midden.tscn (17 boxes as StaticBody3D/CSG, same sizes/rotations Y-X-Z, palette/fog, PlayerStart marker at (0,0,12.5) facing north, eye 1.5 m). tools/toml_to_scene.py or a GDScript importer so data stays the source. New .github/workflows/ci.yml (Godot 4.7.2 headless, import + run_tests.sh), not pushed.
- Done: test_level.gd: 17 boxes with kinds/counts as the TOML, ramp tops meet ledge, 400 down-raycasts hit up-facing surfaces; ci.yml parses (`python3 -c yaml.safe_load`).
- Result: tools/toml_to_scene.py (stdlib tomllib; same validation as the C++ loader, `--check` + `--self-test` run first in run_tests.sh) generates scenes/levels/midden.tscn: Boxes/<name> StaticBody3D (meta `kind`) + BoxMesh/BoxShape3D (size in the shape, no node scale for Jolt), Y-X-Z Euler, linear TOML colours written as sRGB, exp fog 0.006, Sun +Z = to_light, PlayerStart/Eye (1.5 m), EnemySpawns markers from `[[enemy]]`. scripts/world/level_toml.gd = GDScript TOML-subset reader so tests compare against the TOML itself. main.tscn instances the Midden; camera sits at PlayerStart/Eye. 14 unit tests green (9 level, 5 smoke); 400/400 rays (ground 338, platform 32, heap 20, ramp 8, crate 2).
- Fixed from step 1: tests/run_tests.gd ran inside `_initialize` (root not yet in its World3D → no physics queries); tests now run on the first physics frame. run_tests.sh Godot calls got timeouts. ci.yml extended (setup-python 3.12, cached Godot, timeout, separate import step).
- Magewar check: landfill_tutorial authors its palette as sRGB Colors; our TOML (from the C++ engine) treats the same numbers as linear, so the Midden is lighter/less saturated than Magewar's landfill. Kept (matches the validated C++ look); revisit in step 41's playtest. Magewar wraps level geometry in a NavigationRegion3D → folded into step 12.

## M1 – Spellcasting prototype (ports first)

**3. FPS controller: walk, jump, crouch, look (port of old 14)** ✅ `b7a2d40`
- Does: player spawns at the Midden's PlayerStart (eye = PlayerStart/Eye, replacing main.gd's placeholder camera); scripts/player/player.gd on CharacterBody3D + PlayerTuning Resource: walk 4, crouch 3 m/s, LERP 10/AIR 6, jump 4.5/3.0 m/s on press edge, gravity 9.8, capsule 0.3×1.7/0.7, eye 1.5/0.6, step 0.35 m, floor_max_angle 45°, 0.25°/count look, pitch ±89°, InputMap actions (WASD/Space/LMB/RMB/LShift/Q/C+LCtrl/F/1–4).
- Done: test_player.gd (simulated physics frames): 1 s W ≈ 3.67 m ±0.5, apex 1.07/0.48 m ±0.06, crouch eye 0.6 and can't stand under a 1 m slab, 0.35 m step climbed / 0.5 m blocked, ramp → ledge y 1.5.
- Result: scenes/player/player.tscn = Player (CharacterBody3D, origin at the feet, layer 2 "character", mask 1) + CollisionShape3D (own CapsuleShape3D, resized for crouch) + Head (eye) + Camera3D (75°, near 0.05). scripts/player/player.gd ports the C++ tick (direction/speed lerps, ground-only jump on press edge with a rising guard, held crouch, crouch-jump stays crouched, stand-up shape query for head room, eye easing) on move_and_slide (floor_max_angle 45°, snap 0.5 m); step climbing = Cogito-style probe up 0.37 / forward past the edge / down onto a walkable top ≤ 0.35 m. PlayerTuning Resource (resources/player/player_tuning.tres), PlayerInput (held/pressed per tick; from_input() in game, hold() in tests). InputMap in project.godot with Magewar's action names (forward/back/left/right/jump/crouch/sprint/interact/action_primary/action_secondary) + dash, slot_1–4. main.tscn: placeholder Camera3D replaced by the Player, spawned at PlayerStart (camera = PlayerStart/Eye). 24 unit tests green (10 player): walk 3.667 m, apex 1.072/0.485 m, crouch eye 0.600 under the slab, 0.35 step → y 0.351, 0.5 step blocked at z −2.70, ramp_west → (−4.5, 1.500, −11.11).
- Fixed from step 2: during the runner's first physics frame Node.get_physics_process_delta_time() is 0, so move_and_slide() didn't move; tests now run on the second physics frame. test_smoke checks the player camera instead of the removed placeholder.
- Magewar check: action names match Magewar's project.godot; crouch adds LCtrl (C++ design); MOUSE_SENS 0.25 kept, pitch ±89° vs Magewar ±90° (kept: avoids the look-straight-up flip). Not yet mapped: Magewar `menu` (Esc) → step 39, `inventory` (Tab) → step 30, `quickslot_prev/next_wieldable` (mouse wheel) → step 10, `free_look` (Alt) left out of the slice; Cogito's head smoothing over steps (step_height_camera_lerp 2.5) → step 5.

**4. Sprint, Breath and slide (port of old 15)** ✅ `7f16c9c`
- Does: (hooks into Player.tick: speed base selection, crouch handling) scripts/player/breath.gd (max 100, drain 20/s, regen 30/s after 1 s, resume at 20, max bonus), sprint 7 m/s, slide (5 m/s × (t/1.5 + 0.5), 1.5 s, slide jump ×1.3), speed multiplier hook.
- Done: test_breath.gd: empty after 300 ticks, resume after 100, full after 260; test_player slide 90 ticks ≈ 7.5 m, no slide from walk/exhausted.
- Result: scripts/player/breath.gd = `Breath` (RefCounted, `from_tuning()`): `tick(draining, dt)` drains 20/s (floored, float drift snapped so 300 ticks hit exactly 0) or regenerates 30/s for only the part of a tick past the 1 s delay (exact at 60 and 144 Hz), `spend()` (step 5 dash; a refusal leaves the delay alone), `exhausted` from empty until 20 is back (`resume_at` 0 = Magewar), `set_max_bonus()` (no refill), `refill()`, `fraction()/regenerating()`. PlayerTuning gains sprint 7, slide 5 / 1.5 s / jump ×1.3 and the Breath numbers (PLAN §30.8). Player.tick: slide check (Crouch on the ground while sprinting last tick + move key; ends on timeout or on releasing Crouch/Sprint or leaving the ground), crouch, sprint (`sprinting`: Sprint held + move key, not crouched/exhausted, ground start, kept in the air), `breath.tick()`, slide speed along the entry direction (look doesn't steer), base speed crouch/sprint/walk × `speed_multiplier`, slide jump 4.5 × 1.3 (stands up in the air, speed kept until landing); counters `slides/slide_jumps`. main.gd prints a `[player]` exit line (Breath, jumps, slides). 35 unit tests green (6 breath, 15 player): empty at tick 300, regen +30.000 after 1 s delay + 1 s at 60/144 Hz, resume after 100, full after 260; sprint 7.000 m/s, Breath 60.00 after 2 s, dry at 300, sprinting again 101 ticks later; ×1.1 → 4.400/7.700/3.300 m/s; slide 89 ticks (timer ends within the 90th tick), 7.542 m north, entry 7.500 m/s, 0.000 m sideways after a 90° look, then crouch 3.000 m/s, Breath 80 → 95 (no drain); no slide from walk + Crouch, crouch-then-Sprint, standing Sprint + Crouch or exhausted; releasing Sprint ends it; slide jump apex 1.795 m (same as the C++ engine), air speed 6.944 m/s constant, landing with Crouch held doesn't re-slide.
- Fixed from step 3: nothing broken found; step 3's tests still pass unchanged (walk 3.667 m, apex 1.072/0.485 m).
- Magewar check (Cogito cogito_player + magewar_player.gd): sprint 7 m/s (tscn override), SLIDING_SPEED 5, SlidingTimer 1.5 s, SLIDE_JUMP_MOD 1.3 and the slide formula match. Kept decisions over Magewar: Breath 100 / −20/s / +30/s after 1 s (Cogito stamina 30 / 3/s / 2/s after 2 s), no jump cost (Cogito jump_exhaustion 5), resume at 20 (Magewar re-allows at > 0, which stutters). Magewar's Shoes `speed_modifier` scales walk, sprint **and** crouch (magewar_player `_update_movement_speed`); we do the same (the C++ port did too), not the slide. Not ported: Cogito CAN_BUNNYHOP (sprint-jump acceleration; a looter-shooter doesn't need it). Mismatches scheduled: Magewar declares `stamina_bonus` (Leather Belt 15, Traveler Shoes 5) but `_apply_equipment_bonuses` never applies it → step 19 applies it via `Breath.set_max_bonus`; Magewar `_level_up` gives +5 stamina max **and refills** → step 27; Cogito's TOGGLE_CROUCH option → step 32.

**5. Dash + camera feel (port of old 16)** ✅ `5e4514d`
- Does: scripts/player/dash.gd (6 m in 0.15 s, 2 charges, 1.5 s recharge each, 25 Breath, 0.1 s i-frames, 1 air dash), camera_feel.gd (head bob walk/sprint/crouch, landing dip 0.12 m, reduced-motion setting).
- Does (step 4 notes): the dash costs `player.breath.spend(25)` (refused when short/exhausted; restarts the 1 s delay), ends an active slide (`slide_left = 0`, crouch rules unchanged), no slide starts while dashing; head bob skips sliding.
- Does (step 3 notes): also ease the Head over a climbed step (Cogito step_height_camera_lerp 2.5; Player.steps_climbed / the lift height tell camera_feel).
- Done: test_dash.gd: 6.000 m ±0.05 in 9 ticks, 3rd refused, recharge 90/180 ticks, wall stop; test_camera_feel: bob amplitudes, dip 0 below 2 m/s, max 0.12 m, reduced motion = 0.
- Result: scripts/player/dash.gd = `Dash` (RefCounted, `from_tuning()`, port of the C++ dash): `try_start(dir, grounded, breath)` (needs a charge, Breath 25 via `breath.spend`, in the air only the one air dash per jump; `land()` gives it back), `advance(dt)` returns the covered fraction of the tick (40 m/s for 0.15 s, partial last tick), charges refill one at a time every 1.5 s, `invulnerable()` for the first 0.1 s, `set_bonus_charges()` hook. scripts/player/camera_feel.gd = `CameraFeel`: head bob walk 0.03/12, sprint 0.05/16, crouch 0.08/8 (Cogito wiggle numbers, centred), landing dip 0.12 m × clamp((v−2)/6) (sin down 0.1 s, cosine back by 0.3 s), step smoothing (`add_step`, eases to 0 at 2.5/s), `set_reduced_motion()` zeroes bob + dip (step smoothing stays: it removes motion), `set_bob_scale()`. PlayerTuning gains Dash + Camera feel groups. Player.tick: dash on the Dash press edge along the move keys (or look when none), ends a slide, blocks new slides, velocity blended by the covered fraction so walls stop it (move_and_slide); landings / last_landing_speed; Head = eye + `feel.offset()`; `camera_position()` (eye_position() stays the un-bobbed cast origin), `camera_offset()`, `dashing()`, `invulnerable()`, `set_reduced_motion()`. main [player] line counts dashes. 50 unit tests green (9 dash, 6 camera feel): 6.0000 m in 9 ticks (also sideways), 3rd refused, back after 90/180 ticks, i-frames 6 ticks at 60 Hz / 15 at 144 Hz, wall at z −3 stops at −2.700, one air dash per jump (Breath 75), refused under 25 Breath and while exhausted, dash out of a slide then crouch 3 m/s; bob y ±0.0101/x ±0.0263 walk, ±0.0142/0.0404 sprint, 0.0323/0.0751 crouch; dip −0.060 at 5 m/s, −0.120 at 8 and 12 m/s, back by tick 18; reduced motion 0; real landing 4.65 m/s dips 0.053 m; 0.35 m step climbed with the camera eased (−0.337 offset, ≤ 0.015 m/tick), walking back down ≤ 0.038 m/tick.
- Fixed from step 4: nothing broken found; all 35 earlier tests pass unchanged. Not done: step-down smoothing; the capsule's round bottom rolls off a 0.35 m ledge and falls (already smooth), so there is no snap to ease.
- Magewar check (Cogito cogito_player.gd; Magewar's player sets no overrides): Magewar/Cogito have **no dash**, it's our verb (PLAN §30.8). Bob uses Cogito's WIGGLE intensities/rates; Cogito's sway adds a +0.5 bias on x (head sits off to one side); we centre it. Cogito HEADBOBBLE (Minimal 0.1 / Average 0.7 / Full 1) scales walk/sprint only and is declared `int` (0.1/0.7 probably end up 0 = no bob); our `bob_scale` is a float that scales all gaits → step 32. Cogito's landing is an animation at ≤ −5 m/s plus a head drop + roll at ≤ −7.5 m/s; we use one positional dip from 2 m/s (C++ design), no roll. Cogito landing sound volume/pitch over −2..−8 m/s → step 37 (`landings`, `last_landing_speed`). step_height_camera_lerp 2.5 matches.

**6. Elements + damage formula (port of old 20)** ✅ `09552e4`
- Does: resources/magic/elements.tres (Magewar names/colours, chart Fire>Earth>Air>Water>Fire, Light⇄Dark, ×1.5/×0.5, same/Arcane ×1.0), scripts/combat/damage.gd: base × rarity mult + Σ part bonus, × effectiveness × (1 − resist, cap **0.6**) × weak point 2.
- Done: test_damage.gd: full 7×7 chart = Magewar get_effectiveness, resist 0.8→0.6, worked example 12×1.5×0.7×2 = 25.2.
- Result: scripts/combat/element_table.gd = `ElementTable` (Resource): `Element` enum in Magewar's order (ARCANE = Magewar NONE, shown "Arcane"), `IDS`, `parse()/id_of()`, `strong` 1.5 / `weak` 0.5, `elements: Array[ElementDef]` (scripts/combat/element_def.gd: id, display_name, color, strong_against, weak_against), `effectiveness(a, d)` (same or Arcane = ×1.0 in code, else a cached 7×7 chart from the data; `rebuild()` after a patch), `display_name()/color()/def()`, `validate()` (the C++ loader's checks: multipliers in range, unknown/duplicate/missing ids, no self/Arcane/both-lists/duplicates, Arcane lists empty, colour 0..1, names set), `load_default()` (shared, validated once). resources/magic/elements.tres holds Magewar's names/colours and the chart (Fire > Earth > Air > Water > Fire, Light ⇄ Dark). scripts/combat/damage.gd = `Damage`: `RESIST_CAP` 0.6, `WEAK_POINT_MULTIPLIER` 2, `wieldable_damage(base, rarity mult, part bonuses)`, `clamp_resist()`, `Target` (affinity, per-element uncapped resist, weak_point), `Result` (amount, effectiveness, resist, crit, strong()/weak()), `resolve_hit(dmg, element, target, table = default)` (negative damage → 0). 61 unit tests green (11 damage): 49/49 cells = an independent transcription of Magewar get_effectiveness (6 strong, 4 weak), same/Arcane/empty table ×1.0, names/colours = Magewar ELEMENT_NAMES/COLORS and PLAN §30.4 hex (±0.5/255), .tres = data/magic/elements.toml (C++ data, read with LevelToml), 14 bad tables rejected, patched chart rebuilds without touching the shared one, ×1.0…×3.0 and part bonuses after rarity (14 × 1.25 + 8 = 25.5; bases 10/17.5/7/7.5), resist 0.25 → 75, 0.8 and 0.9 → 0.6 (40), negative → 0, per element only, weak point 12 → 24, Fire vs Earth 15 / Air vs Earth 5, worked example 25.2000 and capped/body 7.2.
- Fixed from step 5: nothing broken found; all 50 earlier tests pass unchanged. data/magic/elements.toml (C++ engine data) kept as the cross-check source for the .tres (test_tres_matches_cpp_elements_toml) instead of being dropped.
- Magewar check (magic_element.gd, spell_projectile.gd, enemy_base.gd, networked_combat_bridge.gd, staff_wieldable_item.gd, magewar_player.gd): chart, ×1.5/×0.5, enum order, names and colours match; `get_final_damage` (base × rarity + flat part bonuses) matches. Mismatches: Magewar `get_elemental_resistance` (equipment with matching `element_affinity`, clamp 0.9) is **never called**, so its resistances do nothing → ours apply via `Damage.resolve_hit` (step 13 player hits, step 19 equipment sum, cap 0.6 kept decision); Magewar enemies have only an affinity, no resistances (our per-element enemy resist and weak-point ×2 are plan additions, step 11); Magewar's Light heal / Dark corruption on hit (MagicSpecialEffects) is reinterpreted as Redemption (PLAN §30.4), outside the slice; "Super Effective!" / "Not Very Effective..." text → step 11 damage numbers.

**7. Wieldable data + Arcane bolt casting (port of old 17)**
- Does: Resource classes WieldableDef/WieldablePart/WieldableInstance, resources/wieldables/*.tres for the 4 Magewar bases (10/5/0.40/30/50, 14/6/0.55/22/45, 7/3/0.25/40/35, 6/2.5/0.18/55/40), caster.gd semi-auto on Fire press with cooldown ≥ 0.1 s, bolt = per-tick raycast from the eye (`player.eye_position()`, the un-bobbed eye, not `camera_position()`; PhysicsRayQuery, exclude self), fizzle at range, element-coloured tracer.
- Does (step 6 notes): WieldableDef.element is an `ElementTable.Element` (ids parsed with `ElementTable.parse`), `WieldableInstance.damage()` = `Damage.wieldable_damage(base, rarity mult, part bonuses)` (until step 15 a basic 1.0 / uncommon 1.25 lookup that step 15 replaces with the Rarity resource), the tracer tint = `ElementTable.load_default().color(element)`; a bolt hit calls `Damage.resolve_hit(instance.damage(), element, target)`.
- Done: test_casting.gd: 20 m wall hit at 20.000 m in D/v s ±1 tick for all 4 bases, Swift Wind never casts twice within 0.18 s, self never hit; final damage 10 / 17.5 / 7 / 7.5 for the 4 bases (data/magic/wieldables.toml rarities).

**8. Mana pool (port of old 18)**
- Does: scripts/player/mana.gd: 100, regen 3/s after 1.5 s since last successful spend, refusal doesn't reset delay, regen/max bonus hooks; caster spends mana; no ammo/reload.
- Done: test_mana.gd: Fire staff 20 casts to 0, 21st refused, casts again at tick 646 ±1; empty → full 34.83 s.

**9. Focus, accuracy and spread (port of old 19)**
- Does: Focus tween FOV 75→55 in 0.2 s (staff and wand), look scale tan ratio 0.6784, accuracy 50 + Head/Handle/Charm clamp 0–100, spread cone (4°, focus 0.35, crouch 0.8, moving 1.3, air 1.8, bloom +1°/cast cap 4° clears in 0.5 s), seeded RNG.
- Done: test_accuracy.gd: 55° exactly at tick 12, 100 % accuracy = zero spread, 50 % hip 2.0°/focused 0.7°, bloom clears in 30 ticks.

**10. Staff + wand slots and viewmodel (port of old 21)**
- Does: loadout.gd: Staff/Wand slots, per-slot cooldown, 0.4 s swap (slot_1/slot_2 + mouse wheel as Magewar's quickslot_prev/next_wieldable actions), viewmodel SubViewport/layer at 75° FOV with Magewar default_position poses, greybox shaft + element-coloured gem, focus slide, cast point tracer.
- Does (step 5 notes): the viewmodel follows the Head (so it bobs with it); recoil kick and screen shake go through CameraFeel as extra offsets that `set_reduced_motion(true)` zeroes (PLAN Feel + accessibility), with a test.
- Done: test_loadout.gd: swap 24 ticks no cast during, Earthward cooldown survives swap; headless render check of gem colour (cos ≥ 0.97) via viewport texture.

**11. Enemy entity, training dummies, damage numbers (port of old 22)**
- Does: scripts/enemies/enemy.gd (health, affinity, resistances, weak-point head Area), resources/enemies/training_dummies.tres, Label3D floating damage numbers in element colour, death at 0 HP, dummies spawned at the Midden's EnemySpawns markers (generated from the TOML `[[enemy]]` entries; meta `enemy` = id).
- Does (step 6 notes): each enemy owns a `Damage.Target` (affinity, per-element resist, `weak_point` set when the head Area is hit) and takes `Damage.resolve_hit()`; the damage number shows Magewar's "Super Effective!" / "Not Very Effective..." from `Result.strong()/weak()`. data/enemies/training_dummies.toml uses inline tables (`resist = { air = 0.25 }`, `weak_point = {...}`) that LevelToml can't read yet: extend LevelToml with single-line inline tables (+ a parse test) so test_enemy compares the .tres with the TOML like test_damage does for elements.
- Done: test_enemy.gd: Fire staff vs Earth dummy = 15 per hit, Water dummy 5, head ×2, dies at 0, Swift Wind vs the Water dummy (air resist 0.25) = 7.5 × 1.5 × 0.75 = 8.4375.

**12. Gnawer AI (port of old 23)**
- Does: gnawer.gd state machine Idle/Detect/Chase/Attack/Knockback/Dead (Magewar enemy_base + mutant rat: detect 8, aggro 6, walk 3, sprint 5.5, bite 3 Earth / 0.8 s, knockback > 10 dmg), NavigationAgent3D chase around walls (baked NavMesh: toml_to_scene.py emits a NavigationRegion3D around Boxes like Magewar's landfill, baked from the StaticBodies at load), i-frame dodge.
- Done: test_gnawer.gd: transitions at 8/6/1 m, bites 48 ticks apart, chases around a wall to the player.

**13. Heap AI (tank) + player health/shield**
- Does: Heap tank (slow, high HP, slam), player health + shield (shield first, regen delay), resolveHit for enemy hits, i-frames from dash, player death/respawn.
- Does (step 5 notes): enemy hits on the player are ignored while `player.invulnerable()` (first 0.1 s of a dash = 6 ticks at 60 Hz).
- Does (step 6 notes): enemy hits on the player go through `Damage.resolve_hit(dmg, element, player.damage_target)` (Gnawer bite = Earth; player affinity Arcane, so only resist applies). Magewar computes `get_elemental_resistance` but never calls it, so Magewar player resistances do nothing; ours apply (flagged fix).
- Done: test_heap.gd + test_player_health.gd: damage order shield→health, regen timing, dash i-frames ignore a bite, death at 0, 0.3 Earth resist turns a 3 bite into 2.1.

**14. Enemy spawner + kill events**
- Does: Spawn points/waves from level data (EnemySpawns markers; waves as a new TOML table, extend toml_to_scene.py + LevelToml), EventBus autoload (enemy_killed, player_damaged), Gnawer separation.
- Done: test_spawner.gd: wave counts, kill events fire once per death.

## M2 – Loot, crafting, progression

**15. Rarity tiers + part model (Magewar)**
- Does: Rarity resource (Basic #B3B3B3 ×1.0 w50, Uncommon #33CC33 ×1.25 w25, Rare #3366FF ×1.5, Mythic #991AE6 ×2.0, Primordial #FF9900 ×2.75, Unique #FFD900 ×3.0), Part types Head/Exterior/Interior/Handle/Charm, imported from assets/magewar part .tres values.
- Does (step 6 notes): `Damage.wieldable_damage()` takes `Rarity.multiplier`; drop step 7's temporary basic/uncommon lookup.
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
- Does (step 4 notes): `stamina_bonus` (Belt 15, Shoes 5) → `player.breath.set_max_bonus(Σ equipped + level bonus)` (Magewar declares it but never applies it: fixed here, flagged); `speed_modifier` product (Shoes ×1.15) → `player.set_speed_multiplier()` (walk/sprint/crouch, like Magewar).
- Does (step 6 notes): resist like Magewar's `get_elemental_resistance`: sum `elemental_resistance` of the equipped Hat/Clothes/Belt/Shoes/Grimoire whose `element_affinity` matches, stored uncapped in `player.damage_target.resist[element]` (the UI can show over-cap), capped at 0.6 only inside `Damage.resolve_hit` (Magewar clamps 0.9).
- Done: test_equipment.gd: bonuses applied/removed exactly, resist cap 0.6 (two 0.4 Fire robes → 0.8 stored, 0.6 applied), Belt → Breath max 115 without refill, Shoes → walk 4.6 m/s.
- Does (step 5 notes): Magewar equipment has no dash stat; PLAN's Sandals 3rd dash charge waits for step 36 (Consecration) via `player.dash.set_bonus_charges()`.

**20. Ember Mark item codes**
- Does: EM1-… encode/decode of any item.
- Done: test_item_codes.gd: round-trip 1000 random items, bad codes rejected.

**21. Balance patch loader**
- Does: Hotfix-style JSON data patches over resources (§31).
- Does (step 6 notes): patches may tune `ElementTable` (`strong`, `weak`, `elements[i].strong_against/weak_against`) then call `rebuild()` and must pass `validate()` (else the patch is rejected and the table left as it was).
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
- Does (step 4 notes): level-up Breath = +5 to the level part of `Breath.set_max_bonus` (kept separate from equipment so unequipping doesn't eat it) then `refill()` (Magewar `_level_up`).
- Done: test_xp.gd: curve values, level-up hooks (Breath 105/105 after a level).

**28. Weight model + Vigil plumbing**
- Does: Vigil tiers 1–10 with Omens shifting rarity weights (§31).
- Done: test_vigil.gd: weights shift per tier as specified.

## M3 – UI, dungeon, audio, saves, playtests

**29. HUD**
- Does: Control-based HUD: health/shield/mana/Breath bars (Breath = `player.breath.fraction()`, tinted while `exhausted`), crosshair (hidden while focused, spread-sized), slot icons with rarity colours, Kenney UI Pack.
- Does (step 5 notes): dash charge pips from `player.dash.charges` / `max_charges()` with `recharge_progress()` filling the next one.
- Done: test_hud.gd: bars track values; headless screenshot non-empty.

**30. Inventory + equipment screen**
- Does: Inventory UI with rarity colours and compare cards, opened by an `inventory` action on Tab (Magewar's name/key).
- Done: test_inventory_ui.gd: open/close, equip via UI.

**31. Assembly Station UI**
- Does: Station UI for assemble/disassemble/salvage/upgrade.
- Done: test_station_ui.gd: assemble via UI produces the item.

**32. Key-bindings config**
- Does: Rebind UI over the project.godot InputMap actions (PlayerInput.ACTIONS) + user://keybinds.cfg, invert-Y, hip FOV, focus hold/toggle, crouch hold/toggle (Cogito TOGGLE_CROUCH; the slide needs Crouch held, so toggle mode keeps it "held" until pressed again), Reload unbound.
- Does (step 5 notes): accessibility in the same settings file: reduced motion (`player.set_reduced_motion`) and head bob strength 0 / 0.1 / 0.7 / 1.0 (Cogito HEADBOBBLE presets, kept as a float: `player.feel.set_bob_scale`), applied at spawn; test the round-trip.
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
- Does (step 5 notes): include PLAN's "Sandals: +1 dash charge" via `player.dash.set_bonus_charges(1)` (set_bonus_charges clamps charges when removed).
- Done: test_consecrations.gd: effects trigger as specified.

**37. Audio: buses + Kenney sounds**
- Does: Audio buses (Master/SFX/UI/Music), cast/hit/footstep/UI sounds from Kenney packs, 3D AudioStreamPlayer3D.
- Does (step 5 notes): landing sound when `player.landings` goes up, volume/pitch from `last_landing_speed` over 2..8 m/s (Cogito's min/max landing velocity); dash whoosh on `dash.dashes`.
- Done: test_audio.gd: every referenced stream loads, buses exist.

**38. Save format, round-trip + load**
- Does: Versioned JSON save in user:// (player, inventory, items via Ember Mark codes, progress), load from menu.
- Done: test_save.gd: save→load round-trip equal, old version rejected cleanly.

**39. Main menu + flow**
- Does: Main menu → Midden → Breach → back, pause menu on a `menu` action (Esc, Magewar's name; Player releases the mouse), settings.
- Done: test_flow.gd: scene transitions headless.

**40. Playtest pass 1 – automated**
- Does: Scripted bot plays the slice headless (move, cast, kill, loot, craft, save).
- Done: playtest.gd completes the slice in headless mode, no errors.

**41. Playtest pass 2 – manual + fixes**
- Does: ShobieShy plays; fix reported issues. Also judge the Midden palette vs Magewar's landfill (step 2 note: TOML colours are linear, Magewar's sRGB).
- Done: Issues list closed or deferred in plan.

## After the slice

**42. CI breadth**
- Does: gdlint/gdformat (gdtoolkit) check, Windows + Linux export presets built headless in CI.
- Done: all jobs green locally via act or scripted equivalent; exports run --seconds 2.
