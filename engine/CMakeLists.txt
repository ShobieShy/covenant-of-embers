# SPDX-License-Identifier: Apache-2.0
# coe_engine: reusable runtime (core loop utilities, Vulkan renderer). No gameplay.

# --- shaders -> SPIR-V (build/<preset>/shaders) ---
set(SHADER_SRC ${PROJECT_SOURCE_DIR}/shaders/triangle.vert ${PROJECT_SOURCE_DIR}/shaders/triangle.frag)
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

add_library(coe_engine STATIC
  core/fixed_timestep.cpp
  render/vk_renderer.cpp)
add_dependencies(coe_engine shaders)
# Includes are rooted at the repo: #include "engine/core/fixed_timestep.hpp".
target_include_directories(coe_engine PUBLIC ${PROJECT_SOURCE_DIR})
target_compile_definitions(coe_engine PRIVATE COE_SHADER_DIR="${SPV_DIR}")
target_link_libraries(coe_engine PUBLIC Vulkan::Vulkan SDL3::SDL3 PRIVATE coe_warnings)
