# SPDX-License-Identifier: Apache-2.0
# coe_game: gameplay code shared by the covenant executable and unit tests.
# world/level.*: data-defined greybox levels (toml++, private: TOML_EXCEPTIONS=0 is set
# in level.cpp before the include, so no other target sees the toml++ headers).
add_library(coe_game STATIC
  world/level.cpp
  world/headless_checks.cpp)
target_link_libraries(coe_game PUBLIC coe_engine PRIVATE tomlplusplus::tomlplusplus coe_warnings)

# covenant: the game executable (gameplay state + main loop) on top of coe_engine.
add_executable(covenant main.cpp)
target_link_libraries(covenant PRIVATE coe_game coe_engine coe_warnings)
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
