# SPDX-License-Identifier: Apache-2.0
# Test registration for Covenant of Embers (BUILD_PLAN step 8).
#
#   coe_add_test(NAME <name> COMMAND <cmd> [args...]
#                [WORKING_DIRECTORY <dir>] [LABELS <label>...] [PROPERTIES <prop> <value>...])
#
# Every test in the tree must be registered through this helper, in any
# directory (root, engine/, game/, tests/). It wraps add_test() and, when
# COE_SANITIZE is on, applies the sanitizer/Vulkan-loader runtime environment.
# This has to happen in the defining directory: before CMake 3.28,
# set_property(TEST) only reaches tests of the current directory, so a single
# loop at the end of the root CMakeLists.txt misses tests in subdirectories.
# coe_verify_tests() (called last in the root) fails configure if any test was
# added with plain add_test() and so would run without the sanitizer env.
include_guard(GLOBAL)

# Sanitizer runtime options (see COE_SANITIZE, ADR-0001). Leak checking stays ON.
# VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1 is the Vulkan loader's own switch
# for leak tools: without it the loader dlclose()s the ICD/layer .so files in
# vkDestroyInstance, which unmaps their globals that still point at one-time
# driver allocations (Mesa pthread_once state), so LSan reports them as leaks
# with "<unknown module>" frames that no suppression can match.
# tools/sanitizers/lsan.supp holds targeted suppressions for system-lib noise if
# any ever appears (currently empty; each entry must be documented).
set(COE_SANITIZER_TEST_ENV
  "ASAN_OPTIONS=detect_leaks=1:abort_on_error=0:halt_on_error=1:strict_string_checks=1:detect_stack_use_after_return=1:check_initialization_order=1:strict_init_order=1"
  "UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1"
  "VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1"
  "LSAN_OPTIONS=suppressions=${PROJECT_SOURCE_DIR}/tools/sanitizers/lsan.supp:print_suppressions=1")

function(coe_add_test)
  cmake_parse_arguments(PARSE_ARGV 0 T "" "NAME;WORKING_DIRECTORY" "COMMAND;LABELS;PROPERTIES")
  if(NOT T_NAME OR NOT T_COMMAND)
    message(FATAL_ERROR "coe_add_test: NAME and COMMAND are required")
  endif()
  if(T_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "coe_add_test(${T_NAME}): unknown arguments: ${T_UNPARSED_ARGUMENTS}")
  endif()
  if(T_WORKING_DIRECTORY)
    add_test(NAME ${T_NAME} COMMAND ${T_COMMAND} WORKING_DIRECTORY ${T_WORKING_DIRECTORY})
  else()
    add_test(NAME ${T_NAME} COMMAND ${T_COMMAND})
  endif()
  if(T_LABELS)
    set_tests_properties(${T_NAME} PROPERTIES LABELS "${T_LABELS}")
  endif()
  if(T_PROPERTIES)
    set_tests_properties(${T_NAME} PROPERTIES ${T_PROPERTIES})
  endif()
  if(COE_SANITIZE)
    set_property(TEST ${T_NAME} APPEND PROPERTY ENVIRONMENT ${COE_SANITIZER_TEST_ENV})
  endif()
  set_property(GLOBAL APPEND PROPERTY COE_REGISTERED_TESTS ${T_NAME})
endfunction()

# Walks every directory of the source tree and fails if a test exists that
# coe_add_test() did not register.
function(coe_verify_tests)
  get_property(registered GLOBAL PROPERTY COE_REGISTERED_TESTS)
  set(dirs "${PROJECT_SOURCE_DIR}")
  set(missing "")
  while(dirs)
    list(POP_FRONT dirs d)
    get_property(tests DIRECTORY "${d}" PROPERTY TESTS)
    foreach(t IN LISTS tests)
      if(NOT t IN_LIST registered)
        list(APPEND missing "${t} (${d})")
      endif()
    endforeach()
    get_property(subs DIRECTORY "${d}" PROPERTY SUBDIRECTORIES)
    foreach(s IN LISTS subs)
      # Only our own directories: FetchContent trees live under the build dir
      # (build/<preset>/_deps), which itself sits inside the source tree.
      cmake_path(IS_PREFIX PROJECT_SOURCE_DIR "${s}" NORMALIZE inside)
      cmake_path(IS_PREFIX CMAKE_BINARY_DIR "${s}" NORMALIZE in_build)
      if(inside AND NOT in_build)
        list(APPEND dirs "${s}")
      endif()
    endforeach()
  endwhile()
  if(missing)
    message(FATAL_ERROR "Tests not registered via coe_add_test() (no sanitizer env): ${missing}")
  endif()
endfunction()
