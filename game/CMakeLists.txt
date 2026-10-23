# SPDX-License-Identifier: Apache-2.0
# coe_game: gameplay code shared by the covenant executable and unit tests.
# data/toml_read.*: shared strict TOML readers (step 17; toml++ is PRIVATE and
# TOML_EXCEPTIONS=0 is set in toml_read.hpp, included only by coe_game .cpp files, so no
# other target sees the toml++ headers).
# world/level.*: data-defined greybox levels (step 12, data/levels/*.toml).
# world/level_physics.*: level boxes -> static Jolt colliders via coe_physics (step 13).
# player/player_controller.*: FPS walk/jump/crouch/look on physics::Character (step 14).
# player/stats.*: Breath pool (sprint/dash resource, step 15).
# player/mana.*: Magewar mana pool, spent per cast, regen after a delay (step 18).
# player/dash.*, player/camera_feel.*: dash charges/i-frames and head bob/landing dip (step 16).
# magic/wieldable.*, magic/projectile.*, magic/casting.*: Magewar staffs/wands from
# data/magic/wieldables.toml, ray-swept spell bolts, cooldown-gated casting (step 17).
# magic/accuracy.*: Magewar focus (ADS) FOV tween, accuracy -> spread cone + bloom (step 19).
# combat/element.*, combat/damage.*: Magewar elements + effectiveness chart from
# data/magic/elements.toml, the damage formula (rarity, parts, resist cap, weak point) (step 20).
# magic/loadout.*: Staff + Wand slots, equip-time swaps, per-slot cooldowns (step 21).
# render/viewmodel.*: greybox staff/wand viewmodel poses, meshes, cast point, head check (step 21).
# enemies/enemy.*: enemy types (data/enemies/*.toml), health, affinity/resist, weak-point
# hitboxes on the Enemy physics layer, bolt hits -> resolveHit, death (step 22).
# ui/damage_numbers.*: floating element-coloured damage numbers (pure logic; drawn by
# covenant through coe_ui's ImGui overlay) (step 22).
# ai/state_machine.hpp, ai/gnawer.*: enemy FSM + the Gnawer melee rusher brain (idle ->
# detect -> chase -> attack, knockback, straight-line steering on Static geometry) (step 23).
add_library(coe_game STATIC
  data/toml_read.cpp
  world/level.cpp
  world/level_physics.cpp
  world/headless_checks.cpp
  player/player_controller.cpp
  player/stats.cpp
  player/mana.cpp
  player/dash.cpp
  player/camera_feel.cpp
  magic/wieldable.cpp
  magic/projectile.cpp
  magic/casting.cpp
  magic/accuracy.cpp
  magic/loadout.cpp
  render/viewmodel.cpp
  combat/element.cpp
  combat/damage.cpp
  enemies/enemy.cpp
  ai/gnawer.cpp
  ui/damage_numbers.cpp)
target_link_libraries(coe_game PUBLIC coe_engine coe_physics PRIVATE tomlplusplus::tomlplusplus coe_warnings)

# covenant: the game executable (gameplay state + main loop) on top of coe_engine.
add_executable(covenant main.cpp)
target_link_libraries(covenant PRIVATE coe_game coe_engine coe_ui coe_warnings)
# The game loads models through build/<preset>/cooked/manifest.json (root CMakeLists `cook`)
# and level data straight from the source tree's data/ (cooking data/ comes later).
target_compile_definitions(covenant PRIVATE COE_COOKED_DIR="${CMAKE_BINARY_DIR}/cooked"
  COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
add_dependencies(covenant cook)

# Smoke tests run from build/<preset>/ so --headless writes midden.ppm / mesh.ppm there.
# smoke_headless is step 12's done-check: the Midden greybox renders with floor + walls
# visible, every drawn sample on a level box, 2x MSAA resolved (see headless_checks.cpp).
coe_add_test(NAME smoke_headless COMMAND covenant --headless WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
coe_add_test(NAME smoke_headless_model COMMAND covenant --headless --model WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
coe_add_test(NAME smoke_window COMMAND covenant --seconds 3 WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  LABELS window)
coe_add_test(NAME smoke_window_model COMMAND covenant --seconds 2 --model WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  LABELS window)
coe_add_test(NAME input_script_window COMMAND covenant --seconds 2 --input-debug --input-script
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR} LABELS window)
# Step 23 done-check (window half): a Gnawer spawned 7 m ahead of the standing player
# detects, chases and bites it (>= 2 bites spaced by the cooldown); RESULT: PASS/FAIL.
coe_add_test(NAME gnawer_window COMMAND covenant --seconds 4 --gnawer-check
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR} LABELS window)
# Asset/level errors must fail loudly (not render nothing): unknown model, missing cooked
# dir, missing level. Matched on output instead of WILL_FAIL so a sanitizer report or
# crash can't pass as the expected failure.
set(COE_ASSET_ERROR_PROPS
  PASS_REGULAR_EXPRESSION "\\[assets\\] "
  FAIL_REGULAR_EXPRESSION "Sanitizer|runtime error|RESULT: PASS")
coe_add_test(NAME smoke_headless_missing_model COMMAND covenant --headless --model assets/nope.glb
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR} PROPERTIES ${COE_ASSET_ERROR_PROPS})
coe_add_test(NAME smoke_headless_bad_cooked_dir
  COMMAND covenant --headless --model --cooked ${CMAKE_BINARY_DIR}/no-such-cooked-dir
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR} PROPERTIES ${COE_ASSET_ERROR_PROPS})
coe_add_test(NAME smoke_headless_missing_level
  COMMAND covenant --headless --level ${CMAKE_BINARY_DIR}/no-such-level.toml
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  PROPERTIES PASS_REGULAR_EXPRESSION "\\[level\\] .*cannot open"
             FAIL_REGULAR_EXPRESSION "Sanitizer|runtime error|RESULT: PASS")
# Step 20: a missing elements.toml fails loudly too.
coe_add_test(NAME smoke_headless_missing_elements
  COMMAND covenant --headless --elements ${CMAKE_BINARY_DIR}/no-such-elements.toml
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  PROPERTIES PASS_REGULAR_EXPRESSION "\\[magic\\] .*cannot open"
             FAIL_REGULAR_EXPRESSION "Sanitizer|runtime error|RESULT: PASS")
# Step 22: so does a missing enemy table.
coe_add_test(NAME smoke_headless_missing_enemies
  COMMAND covenant --headless --enemies ${CMAKE_BINARY_DIR}/no-such-enemies.toml
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  PROPERTIES PASS_REGULAR_EXPRESSION "\\[enemy\\] .*cannot open"
             FAIL_REGULAR_EXPRESSION "Sanitizer|runtime error|RESULT: PASS")
