# SPDX-License-Identifier: Apache-2.0
# Unit tests (plain asserts until doctest arrives in step 20, ADR-0001).
add_executable(test_fixed_timestep test_fixed_timestep.cpp)
target_link_libraries(test_fixed_timestep PRIVATE coe_engine coe_warnings)
target_include_directories(test_fixed_timestep PRIVATE ${PROJECT_SOURCE_DIR})
coe_add_test(NAME fixed_timestep COMMAND test_fixed_timestep)

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

# Step 17: wieldables.toml (Magewar's four bases + rejections), ray-swept bolts hitting a
# target at the right distance/time, Swift Wind Wand cooldown, caster's capsule never hit.
add_executable(test_casting test_casting.cpp)
target_link_libraries(test_casting PRIVATE coe_game coe_physics coe_warnings)
target_compile_definitions(test_casting PRIVATE COE_DATA_DIR="${PROJECT_SOURCE_DIR}/data")
coe_add_test(NAME casting COMMAND test_casting)
