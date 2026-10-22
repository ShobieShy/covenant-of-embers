cmake_minimum_required(VERSION 3.25)
project(CovenantOfEmbers VERSION 0.0.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Vulkan REQUIRED COMPONENTS glslc)
find_package(SDL3 REQUIRED CONFIG)

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
