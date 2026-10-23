// SPDX-License-Identifier: Apache-2.0
// The single doctest runner (BUILD_PLAN step 20, ADR-0001): coe_tests links every
// doctest test file; ctest runs it once per file with -sf (tests/CMakeLists.txt).
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
