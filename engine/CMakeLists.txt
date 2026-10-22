# SPDX-License-Identifier: Apache-2.0
# coe_assets: CPU-side asset code (glTF loading via fastgltf, cooked manifest via
# simdjson); no Vulkan/SDL, so tools/asset_cooker links it too.
# coe_engine: reusable runtime (core loop utilities, Vulkan renderer). No gameplay.

# --- shaders -> SPIR-V (build/<preset>/shaders) ---
set(SHADER_SRC ${PROJECT_SOURCE_DIR}/shaders/basic.vert ${PROJECT_SOURCE_DIR}/shaders/basic.frag)
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

add_library(coe_assets STATIC
  assets/gltf_loader.cpp
  assets/manifest.cpp)
target_include_directories(coe_assets PUBLIC ${PROJECT_SOURCE_DIR})
target_compile_definitions(coe_assets PUBLIC GLM_FORCE_RADIANS GLM_FORCE_DEPTH_ZERO_TO_ONE)
target_link_libraries(coe_assets PUBLIC glm::glm PRIVATE fastgltf::fastgltf simdjson::simdjson coe_warnings)

add_library(coe_engine STATIC
  core/fixed_timestep.cpp
  input/input.cpp
  render/camera.cpp
  render/mesh.cpp
  render/vk_renderer.cpp
  render/vma_impl.cpp)
add_dependencies(coe_engine shaders)
# Includes are rooted at the repo: #include "engine/core/fixed_timestep.hpp".
target_include_directories(coe_engine PUBLIC ${PROJECT_SOURCE_DIR})
target_compile_definitions(coe_engine PRIVATE COE_SHADER_DIR="${SPV_DIR}")
# GLM conventions for everything that includes engine headers: radians only and
# Vulkan's [0,1] clip depth for any glm::perspective* helper (Camera builds its own
# reverse-Z matrix, but stray helpers must not silently assume OpenGL's [-1,1]).
target_compile_definitions(coe_engine PUBLIC GLM_FORCE_RADIANS GLM_FORCE_DEPTH_ZERO_TO_ONE)
target_link_libraries(coe_engine PUBLIC coe_assets Vulkan::Vulkan SDL3::SDL3 glm::glm
  PRIVATE GPUOpen::VulkanMemoryAllocator coe_warnings)
target_compile_definitions(coe_engine PRIVATE VMA_STATIC_VULKAN_FUNCTIONS=1 VMA_DYNAMIC_VULKAN_FUNCTIONS=0)
