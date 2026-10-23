# SPDX-License-Identifier: Apache-2.0
# Unit tests. doctest (step 20, ADR-0001): one coe_tests runner holds every doctest test
# file; ctest runs it once per file (-sf = source-file filter) so each file stays its own
# ctest entry with coe_add_test's timeout. A filter that matches no test case fails (the
# summary's "test cases: 0" line), so a renamed file can't pass silently. The other
# test_*.cpp files still use plain checks in their own executables until they are ported
# (as each is next touched; see BUILD_PLAN step 20 notes).
set(COE_DOCTEST_FILES test_fixed_timestep.cpp test_casting.cpp test_damage.cpp)
add_executable(coe_tests doctest_main.cpp ${COE_DOCTEST_FILES})
target_link_libraries(coe_tests PRIVATE coe_game coe_engine coe_physics doctest::doctest coe_warnings)
target_include_directories(coe_tests PRIVATE ${PROJECT_SOURCE_DIR})
target_compile_definitions(coe_tests PRIVATE COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
foreach(file ${COE_DOCTEST_FILES})
  string(REGEX REPLACE "^test_(.*)\\.cpp$" "\\1" name ${file})
  coe_add_test(NAME ${name} COMMAND coe_tests --source-file=*${file} --no-version
    PROPERTIES FAIL_REGULAR_EXPRESSION "test cases: +0 [|]")
endforeach()

add_executable(test_input test_input.cpp)
target_link_libraries(test_input PRIVATE coe_engine coe_warnings)
coe_add_test(NAME input COMMAND test_input)

add_executable(test_camera test_camera.cpp)
target_link_libraries(test_camera PRIVATE coe_engine coe_warnings)
coe_add_test(NAME camera COMMAND test_camera)

# glTF loader + manifest (step 11): CPU-only, links coe_assets (no Vulkan/SDL).
add_executable(test_gltf_loader test_gltf_loader.cpp)
target_link_libraries(test_gltf_loader PRIVATE coe_assets coe_warnings)
coe_add_test(NAME gltf_loader COMMAND test_gltf_loader)
# Every model the cooker produced for the blaster kit loads (manifest hashes checked).
coe_add_test(NAME gltf_cooked_blaster_kit COMMAND test_gltf_loader --cooked ${CMAKE_BINARY_DIR}/cooked_test
  PROPERTIES FIXTURES_REQUIRED cooked_blaster)

# Greybox level data + TOML validation + box/normal math (step 12): CPU-only (coe_game).
add_executable(test_level test_level.cpp)
target_link_libraries(test_level PRIVATE coe_game coe_warnings)
target_compile_definitions(test_level PRIVATE COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
coe_add_test(NAME level COMMAND test_level)

# Jolt physics world + greybox colliders (step 13): boxes dropped on the Midden ground
# and ramp_west, collider poses == render boxes, raycasts land on box surfaces.
add_executable(test_physics test_physics.cpp)
target_link_libraries(test_physics PRIVATE coe_game coe_physics coe_warnings)
target_compile_definitions(test_physics PRIVATE COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
coe_add_test(NAME physics COMMAND test_physics)

# Step 14: FPS controller (CharacterVirtual walk/jump/crouch/look) on the Midden greybox.
add_executable(test_player test_player.cpp)
target_link_libraries(test_player PRIVATE coe_game coe_physics coe_warnings)
target_compile_definitions(test_player PRIVATE COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
coe_add_test(NAME player COMMAND test_player)

# Step 15: Breath pool drain/regen timings (CPU-only); sprint/slide live in test_player.
add_executable(test_breath test_breath.cpp)
target_link_libraries(test_breath PRIVATE coe_game coe_warnings)
coe_add_test(NAME breath COMMAND test_breath)

# Step 16: dash (charges/recharge, 6 m distance, walls, air dash, Breath, slide) and
# camera feel (head bob, landing dip, reduced motion) on a flat Jolt floor.
add_executable(test_dash test_dash.cpp)
target_link_libraries(test_dash PRIVATE coe_game coe_physics coe_warnings)
coe_add_test(NAME dash COMMAND test_dash)

add_executable(test_camera_feel test_camera_feel.cpp)
target_link_libraries(test_camera_feel PRIVATE coe_game coe_physics coe_warnings)
coe_add_test(NAME camera_feel COMMAND test_camera_feel)

# Step 17's casting tests (wieldables.toml, bolt hits, cooldown, own capsule) and step 20's
# damage tests (7x7 chart, rarity, parts, resist cap, weak point) are doctest files above.

# Step 18: Magewar mana pool (100, 3/s after 1.5 s, regen bonus hook), 20 fire-staff casts
# through Caster::setManaSpender, regen timing at 30/60/144 Hz.
add_executable(test_mana test_mana.cpp)
target_link_libraries(test_mana PRIVATE coe_game coe_physics coe_warnings)
target_compile_definitions(test_mana PRIVATE COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
coe_add_test(NAME mana COMMAND test_mana)

# Step 19: focus (ADS) FOV tween 75 -> 55 deg in 0.2 s, Magewar accuracy, spread cone
# (100 % = none, focused = 0.35x hip, stance), bloom recovery, spread bolts on a wall.
add_executable(test_accuracy test_accuracy.cpp)
target_link_libraries(test_accuracy PRIVATE coe_game coe_physics coe_warnings)
target_compile_definitions(test_accuracy PRIVATE COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
coe_add_test(NAME accuracy COMMAND test_accuracy)
