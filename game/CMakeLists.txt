# SPDX-License-Identifier: Apache-2.0
# covenant: the game executable (gameplay state + main loop) on top of coe_engine.
add_executable(covenant main.cpp)
target_link_libraries(covenant PRIVATE coe_engine coe_warnings)
# The game loads models through build/<preset>/cooked/manifest.json (root CMakeLists `cook`).
target_compile_definitions(covenant PRIVATE COE_COOKED_DIR="${CMAKE_BINARY_DIR}/cooked")
add_dependencies(covenant cook)

# Smoke tests run from build/<preset>/ so --headless writes mesh.ppm there.
coe_add_test(NAME smoke_headless COMMAND covenant --headless WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
coe_add_test(NAME smoke_window COMMAND covenant --seconds 3 WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  LABELS window)
coe_add_test(NAME input_script_window COMMAND covenant --seconds 2 --input-debug --input-script
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR} LABELS window)
# Asset errors must fail loudly (not render nothing): unknown model, missing cooked dir.
# Matched on output instead of WILL_FAIL so a sanitizer report or crash can't pass as
# the expected failure.
set(COE_ASSET_ERROR_PROPS
  PASS_REGULAR_EXPRESSION "\\[assets\\] "
  FAIL_REGULAR_EXPRESSION "Sanitizer|runtime error|RESULT: PASS")
coe_add_test(NAME smoke_headless_missing_model COMMAND covenant --headless --model assets/nope.glb
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR} PROPERTIES ${COE_ASSET_ERROR_PROPS})
coe_add_test(NAME smoke_headless_bad_cooked_dir
  COMMAND covenant --headless --cooked ${CMAKE_BINARY_DIR}/no-such-cooked-dir
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR} PROPERTIES ${COE_ASSET_ERROR_PROPS})
