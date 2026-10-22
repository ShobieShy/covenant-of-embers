# SPDX-License-Identifier: Apache-2.0
# covenant: the game executable (gameplay state + main loop) on top of coe_engine.
add_executable(covenant main.cpp)
target_link_libraries(covenant PRIVATE coe_engine coe_warnings)

# Smoke tests run from build/<preset>/ so --headless writes triangle.ppm there.
coe_add_test(NAME smoke_headless COMMAND covenant --headless WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
coe_add_test(NAME smoke_window COMMAND covenant --seconds 3 WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  LABELS window)
