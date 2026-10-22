# SPDX-License-Identifier: Apache-2.0
# Unit tests (plain asserts until doctest arrives in step 20, ADR-0001).
add_executable(test_fixed_timestep test_fixed_timestep.cpp)
target_link_libraries(test_fixed_timestep PRIVATE coe_engine coe_warnings)
target_include_directories(test_fixed_timestep PRIVATE ${PROJECT_SOURCE_DIR})
coe_add_test(NAME fixed_timestep COMMAND test_fixed_timestep)
