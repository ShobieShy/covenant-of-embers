cmake_minimum_required(VERSION 3.25)
project(CovenantOfEmbers VERSION 0.0.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Sanitizers (PLAN §25, ADR-0001): the `asan` preset sets COE_SANITIZE=ON for
# ASan + UBSan on every target in this tree (incl. a fetched SDL3). UBSan is fatal
# (-fno-sanitize-recover=all) so any report fails the test; frame pointers kept
# for usable stacks. Runtime options for ctest are set at the bottom of this file.
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

# --- shaders -> SPIR-V (build/shaders) ---
set(SHADER_SRC ${CMAKE_SOURCE_DIR}/shaders/triangle.vert ${CMAKE_SOURCE_DIR}/shaders/triangle.frag)
set(SPV_DIR ${CMAKE_BINARY_DIR}/shaders)
set(SPV_OUT "")
foreach(src ${SHADER_SRC})
  get_filename_component(n ${src} NAME)
  set(out ${SPV_DIR}/${n}.spv)
  add_custom_command(OUTPUT ${out}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${SPV_DIR}
    COMMAND Vulkan::glslc --target-env=vulkan1.3 -Werror -o ${out} ${src}
    DEPENDS ${src} COMMENT "glslc ${n}")
  list(APPEND SPV_OUT ${out})
endforeach()
add_custom_target(shaders ALL DEPENDS ${SPV_OUT})

add_executable(covenant src/main.cpp src/render/vk_renderer.cpp)
add_dependencies(covenant shaders)
target_include_directories(covenant PRIVATE src)
target_compile_definitions(covenant PRIVATE COE_SHADER_DIR="${SPV_DIR}")
target_compile_options(covenant PRIVATE $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall -Wextra -Wpedantic -Wno-missing-field-initializers>)
target_link_libraries(covenant PRIVATE Vulkan::Vulkan SDL3::SDL3)

enable_testing()
add_test(NAME smoke_headless COMMAND covenant --headless)
add_test(NAME smoke_window COMMAND covenant --seconds 3)
set_tests_properties(smoke_window PROPERTIES LABELS window)

# Asset license lint (PLAN §25): every folder under assets/ must be in ASSETS.toml
# with license + source. No `window` label, so CI runs it.
add_test(NAME asset_license_lint
  COMMAND Python3::Interpreter ${CMAKE_SOURCE_DIR}/tools/check_assets.py --root ${CMAKE_SOURCE_DIR})
add_test(NAME asset_license_lint_selftest
  COMMAND Python3::Interpreter ${CMAKE_SOURCE_DIR}/tools/check_assets.py --self-test)

# Asset cooker stub (BUILD_PLAN step 6): validates + copies glTF/GLB/PNG/OGG
# into a cooked dir with manifest.json. `cmake --build --preset debug --target cook`
# cooks assets/ into build/<preset>/cooked.
add_executable(asset_cooker tools/asset_cooker/main.cpp)
target_compile_options(asset_cooker PRIVATE $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall -Wextra -Wpedantic>)
add_custom_target(cook
  COMMAND asset_cooker --root ${CMAKE_SOURCE_DIR} --out ${CMAKE_BINARY_DIR}/cooked ${CMAKE_SOURCE_DIR}/assets
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} COMMENT "Cooking assets/ -> ${CMAKE_BINARY_DIR}/cooked" VERBATIM)
add_test(NAME asset_cooker_selftest COMMAND asset_cooker --self-test)
add_test(NAME asset_cooker_blaster_kit
  COMMAND asset_cooker --root ${CMAKE_SOURCE_DIR} --out ${CMAKE_BINARY_DIR}/cooked_test
          ${CMAKE_SOURCE_DIR}/assets/kenney/blaster-kit)
add_test(NAME asset_cooker_manifest_check
  COMMAND Python3::Interpreter ${CMAKE_SOURCE_DIR}/tools/asset_cooker/check_manifest.py
          --root ${CMAKE_SOURCE_DIR} --cooked ${CMAKE_BINARY_DIR}/cooked_test --source assets/kenney/blaster-kit)
set_tests_properties(asset_cooker_blaster_kit PROPERTIES FIXTURES_SETUP cooked_blaster)
set_tests_properties(asset_cooker_manifest_check PROPERTIES FIXTURES_REQUIRED cooked_blaster)

# Sanitizer runtime options for every ctest (see COE_SANITIZE above, ADR-0001).
# Leak checking stays ON. VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1 is the
# Vulkan loader's own switch for leak tools: without it the loader dlclose()s
# the ICD/layer .so files in vkDestroyInstance, which unmaps their globals that
# still point at one-time driver allocations (Mesa pthread_once state), so LSan
# reports them as leaks with "<unknown module>" frames that no suppression can
# match. tools/sanitizers/lsan.supp holds targeted suppressions for system-lib
# noise if any ever appears (currently empty; each entry must be documented).
if(COE_SANITIZE)
  get_property(coe_all_tests DIRECTORY PROPERTY TESTS)
  set_property(TEST ${coe_all_tests} APPEND PROPERTY ENVIRONMENT
    "ASAN_OPTIONS=detect_leaks=1:abort_on_error=0:halt_on_error=1:strict_string_checks=1:detect_stack_use_after_return=1:check_initialization_order=1:strict_init_order=1"
    "UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1"
    "VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1"
    "LSAN_OPTIONS=suppressions=${CMAKE_SOURCE_DIR}/tools/sanitizers/lsan.supp:print_suppressions=1")
endif()
