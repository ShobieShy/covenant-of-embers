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

# simdjson (ADR-0001 step 11): JSON DOM parser behind fastgltf and for reading
# cooked/manifest.json. Pinned to 4.6.11, the version fastgltf 0.9.1 targets. We
# build its amalgamated singleheader/simdjson.cpp ourselves and expose it as
# simdjson::simdjson *before* fastgltf is added, so fastgltf links it instead of
# downloading an unhashed copy into its source dir (cmake/dependencies.cmake there).
# SOURCE_SUBDIR points at a directory without a CMakeLists.txt: populate only.
FetchContent_Declare(simdjson
  URL https://github.com/simdjson/simdjson/archive/refs/tags/v4.6.11.tar.gz
  URL_HASH SHA256=61d948fc24f0d793829ad658058e7597d064988a89b4607ea02e401a82df98ff
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SOURCE_SUBDIR coe-populate-only
  SYSTEM)
FetchContent_MakeAvailable(simdjson)
add_library(coe_simdjson STATIC ${simdjson_SOURCE_DIR}/singleheader/simdjson.cpp)
target_include_directories(coe_simdjson SYSTEM PUBLIC ${simdjson_SOURCE_DIR}/singleheader)
add_library(simdjson::simdjson ALIAS coe_simdjson)

# fastgltf (ADR-0001 step 11): glTF 2.0 / GLB parser for the runtime loader and the
# cooker. Install rules off (they cannot export our simdjson target).
set(FASTGLTF_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(FASTGLTF_COMPILE_AS_CPP20 ON CACHE BOOL "" FORCE)
FetchContent_Declare(fastgltf
  URL https://github.com/spnda/fastgltf/archive/refs/tags/v0.9.1.tar.gz
  URL_HASH SHA256=d8705a496deb2831775baeef5009be36d24bf3d10f8d29ab016e977d0119c872
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SYSTEM)
FetchContent_MakeAvailable(fastgltf)

# stb_image (BUILD_PLAN step 21): PNG/JPEG decoding for glTF base-colour textures.
# Header-only and untagged upstream, so a pinned master commit tarball + hash; only
# populated (no CMake project). The implementation is compiled once in
# engine/assets/image.cpp; the include dir is SYSTEM so its warnings stay out of ours.
FetchContent_Declare(stb
  URL https://github.com/nothings/stb/archive/003501f6d7a8668ce8b6d875e34dd97ad0d5d5b5.tar.gz
  URL_HASH SHA256=a6c31950b3bdf05eb92258768ba2a11bd44449490574b1aac67028452288c40d
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SOURCE_SUBDIR coe-populate-only
  SYSTEM)
FetchContent_MakeAvailable(stb)
add_library(coe_stb_image INTERFACE)
target_include_directories(coe_stb_image SYSTEM INTERFACE ${stb_SOURCE_DIR})

# Vulkan Memory Allocator (ADR-0001 step 11): header-only; the implementation is
# compiled once in engine/render/vma_impl.cpp.
set(VMA_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_Declare(VulkanMemoryAllocator
  URL https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator/archive/refs/tags/v3.4.0.tar.gz
  URL_HASH SHA256=822aa850c6ce77346ae96a8a1d351d52e77e85929f35363849a0a4e638e0a2a1
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SYSTEM)
FetchContent_MakeAvailable(VulkanMemoryAllocator)

# toml++ (ADR-0001 step 12): header-only TOML parser for data files (levels first;
# weapons, loot, patches and bindings later). Pinned release tarball + hash, SYSTEM.
# Used without exceptions (TOML_EXCEPTIONS=0 on the consuming target) so parse
# errors come back as values with line numbers.
FetchContent_Declare(tomlplusplus
  URL https://github.com/marzer/tomlplusplus/archive/refs/tags/v3.4.0.tar.gz
  URL_HASH SHA256=8517f65938a4faae9ccf8ebb36631a38c1cadfb5efa85d9a72e15b9e97d25155
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SYSTEM)
FetchContent_MakeAvailable(tomlplusplus)

# Jolt Physics (ADR-0001 step 13): rigid bodies + collision for the greybox (static
# level boxes now, CharacterVirtual in step 14, raycasts for hitscan in step 17).
# Pinned release tarball + hash, SYSTEM. Only the core library: GPU compute
# back-ends (Vulkan/DX12/Metal/CPU), debug renderer, profiler, ObjectStream, install
# rules, LTO and Jolt's own -Werror are switched off; Jolt keeps its default x86-64
# SIMD level (SSE4.2/AVX2/F16C/FMA/LZCNT/TZCNT/BMI, PUBLIC compile options). Single
# precision. Asserts follow the build type (Jolt defines JPH_DEBUG when !NDEBUG).
# Its CMakeLists only touches CMAKE_CXX_FLAGS inside its own directory scope.
foreach(opt TARGET_UNIT_TESTS TARGET_HELLO_WORLD TARGET_PERFORMANCE_TEST TARGET_SAMPLES TARGET_VIEWER
            ENABLE_INSTALL ENABLE_ALL_WARNINGS INTERPROCEDURAL_OPTIMIZATION OVERRIDE_CXX_FLAGS
            DEBUG_RENDERER_IN_DEBUG_AND_RELEASE PROFILER_IN_DEBUG_AND_RELEASE ENABLE_OBJECT_STREAM
            JPH_USE_DX12 JPH_USE_VK JPH_USE_MTL JPH_USE_CPU_COMPUTE DOUBLE_PRECISION)
  set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()
# RTTI on (Jolt defaults to -fno-rtti): the rest of the tree has RTTI, and UBSan's vptr
# check (asan preset) needs typeinfo for Jolt's polymorphic classes. Exceptions stay off.
set(CPP_RTTI_ENABLED ON CACHE BOOL "" FORCE)
FetchContent_Declare(JoltPhysics
  URL https://github.com/jrouwe/JoltPhysics/archive/refs/tags/v5.6.0.tar.gz
  URL_HASH SHA256=6e069ee0172478cc78182047aac87e5310ba14a67a53348ae14cc37801fd3f8e
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SOURCE_SUBDIR Build
  SYSTEM)
FetchContent_MakeAvailable(JoltPhysics)

# doctest (ADR-0001 step 20): header-only unit-test framework for the one coe_tests
# runner (tests/CMakeLists.txt). Pinned release tarball + hash, SYSTEM. Only the
# INTERFACE header target: no self-tests, no prebuilt main library, no install rules.
foreach(opt DOCTEST_WITH_TESTS DOCTEST_WITH_MAIN_IN_STATIC_LIB)
  set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()
set(DOCTEST_NO_INSTALL ON CACHE BOOL "" FORCE)
FetchContent_Declare(doctest
  URL https://github.com/doctest/doctest/archive/refs/tags/v2.5.3.tar.gz
  URL_HASH SHA256=174ebc4e769928959614789c5b4e9c3d0a0f81a62bb608756b127bfebfb21331
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SYSTEM)
FetchContent_MakeAvailable(doctest)

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

# Asset cooker (BUILD_PLAN steps 6 + 11): validates (glTF/GLB via fastgltf, incl.
# accessors/buffers) + copies glTF/GLB/PNG/OGG into a cooked dir with manifest.json.
# `cmake --build --preset debug --target cook` cooks assets/ into build/<preset>/cooked;
# `covenant` depends on it (the runtime loads models through the manifest). The cook
# re-runs only when the cooker or a file under assets/ changes (CONFIGURE_DEPENDS
# re-globs on every build, so added/removed assets are noticed too).
add_executable(asset_cooker tools/asset_cooker/main.cpp)
target_link_libraries(asset_cooker PRIVATE coe_assets coe_warnings)
file(GLOB_RECURSE COE_ASSET_FILES CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/assets/*)
set(COE_COOKED_MANIFEST ${CMAKE_BINARY_DIR}/cooked/manifest.json)
add_custom_command(OUTPUT ${COE_COOKED_MANIFEST}
  COMMAND asset_cooker --root ${CMAKE_SOURCE_DIR} --out ${CMAKE_BINARY_DIR}/cooked ${CMAKE_SOURCE_DIR}/assets
  DEPENDS asset_cooker ${COE_ASSET_FILES}
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} COMMENT "Cooking assets/ -> ${CMAKE_BINARY_DIR}/cooked" VERBATIM)
add_custom_target(cook DEPENDS ${COE_COOKED_MANIFEST})
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
