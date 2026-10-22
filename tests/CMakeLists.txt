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
