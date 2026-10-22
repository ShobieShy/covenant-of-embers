cmake_minimum_required(VERSION 3.25)
project(CovenantOfEmbers VERSION 0.0.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Sanitizers (PLAN §25, ADR-0001): the `asan` preset sets COE_SANITIZE=ON for
# ASan + UBSan on every target in this tree (incl. a fetched SDL3). UBSan is fatal
# (-fno-sanitize-recover=all) so any report fails the test; frame pointers kept
# for usable stacks. Runtime options for ctest come from coe_add_test() in
# cmake/CoeTesting.cmake.
option(COE_SANITIZE "Build with AddressSanitizer + UndefinedBehaviorSanitizer (GCC/Clang)" OFF)
if(COE_SANITIZE)
  if(NOT CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    message(FATAL_ERROR "COE_SANITIZE needs GCC or Clang")
  endif()
  add_compile_options(-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(Vulkan REQUIRED COMPONENTS glslc)
# Python 3.11+ (stdlib tomllib) for tools/check_assets.py
find_package(Python3 3.11 REQUIRED COMPONENTS Interpreter)
# SDL3: use the system package when present, else fetch a pinned release
# (Ubuntu 24.04 CI images ship no SDL3). -DCOE_FETCH_SDL3=ON forces the fetch.
option(COE_FETCH_SDL3 "Always build SDL3 from source via FetchContent" OFF)
if(NOT COE_FETCH_SDL3)
  find_package(SDL3 CONFIG QUIET)
endif()
if(NOT SDL3_FOUND)
  message(STATUS "SDL3: fetching release-3.4.18 via FetchContent")
  include(FetchContent)
  set(SDL_SHARED OFF CACHE BOOL "" FORCE)
  set(SDL_STATIC ON CACHE BOOL "" FORCE)
  set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
  set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(SDL3
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG release-3.4.18
    GIT_SHALLOW TRUE
    SYSTEM)
  FetchContent_MakeAvailable(SDL3)
endif()

# GLM (math, ADR-0001 step 10): header-only, pinned release tarball + hash, SYSTEM
# so its headers never trip our -Wall -Wextra -Wpedantic.
include(FetchContent)
set(GLM_BUILD_LIBRARY OFF CACHE BOOL "" FORCE)   # INTERFACE glm::glm, nothing to compile
set(GLM_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLM_BUILD_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_Declare(glm
  URL https://github.com/g-truc/glm/archive/refs/tags/1.0.3.tar.gz
  URL_HASH SHA256=6775e47231a446fd086d660ecc18bcd076531cfedd912fbd66e576b118607001
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SYSTEM)
FetchContent_MakeAvailable(glm)

# Binaries land in build/<preset>/ (not per-subdir) so paths stay
# ./build/debug/covenant and ./build/debug/asset_cooker.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

# Shared warning flags for our own targets (third-party deps are SYSTEM).
add_library(coe_warnings INTERFACE)
target_compile_options(coe_warnings INTERFACE
  $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall -Wextra -Wpedantic -Wno-missing-field-initializers>)

enable_testing()
include(cmake/CoeTesting.cmake)   # coe_add_test(): use it for every test, in every directory

# Layout (PLAN §24): engine/ = reusable runtime (core, render, ...), game/ = the
# Covenant executable and gameplay, tests/ = unit tests.
add_subdirectory(engine)
add_subdirectory(game)
add_subdirectory(tests)

# Asset license lint (PLAN §25): every folder under assets/ must be in ASSETS.toml
# with license + source. No `window` label, so CI runs it.
coe_add_test(NAME asset_license_lint
  COMMAND Python3::Interpreter ${CMAKE_SOURCE_DIR}/tools/check_assets.py --root ${CMAKE_SOURCE_DIR})
coe_add_test(NAME asset_license_lint_selftest
  COMMAND Python3::Interpreter ${CMAKE_SOURCE_DIR}/tools/check_assets.py --self-test)

# Asset cooker stub (BUILD_PLAN step 6): validates + copies glTF/GLB/PNG/OGG
# into a cooked dir with manifest.json. `cmake --build --preset debug --target cook`
# cooks assets/ into build/<preset>/cooked.
add_executable(asset_cooker tools/asset_cooker/main.cpp)
target_link_libraries(asset_cooker PRIVATE coe_warnings)
add_custom_target(cook
  COMMAND asset_cooker --root ${CMAKE_SOURCE_DIR} --out ${CMAKE_BINARY_DIR}/cooked ${CMAKE_SOURCE_DIR}/assets
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} COMMENT "Cooking assets/ -> ${CMAKE_BINARY_DIR}/cooked" VERBATIM)
coe_add_test(NAME asset_cooker_selftest COMMAND asset_cooker --self-test)
coe_add_test(NAME asset_cooker_blaster_kit
  COMMAND asset_cooker --root ${CMAKE_SOURCE_DIR} --out ${CMAKE_BINARY_DIR}/cooked_test
          ${CMAKE_SOURCE_DIR}/assets/kenney/blaster-kit
  PROPERTIES FIXTURES_SETUP cooked_blaster)
coe_add_test(NAME asset_cooker_manifest_check
  COMMAND Python3::Interpreter ${CMAKE_SOURCE_DIR}/tools/asset_cooker/check_manifest.py
          --root ${CMAKE_SOURCE_DIR} --cooked ${CMAKE_BINARY_DIR}/cooked_test --source assets/kenney/blaster-kit
  PROPERTIES FIXTURES_REQUIRED cooked_blaster)

# Sanitizer runtime env is applied per test by coe_add_test() (cmake/CoeTesting.cmake);
# this fails configure if any test anywhere in the tree bypassed the helper.
coe_verify_tests()
