cmake_minimum_required(VERSION 3.25)
project(CovenantOfEmbers VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Vulkan)

add_executable(covenant src/main.cpp)
target_compile_options(covenant PRIVATE $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall -Wextra -Wpedantic>)
if(Vulkan_FOUND)
  target_link_libraries(covenant PRIVATE Vulkan::Vulkan)
  target_compile_definitions(covenant PRIVATE COE_HAS_VULKAN=1)
endif()
