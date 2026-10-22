// SPDX-License-Identifier: Apache-2.0
// The single translation unit that compiles the Vulkan Memory Allocator implementation.
// VMA_STATIC_VULKAN_FUNCTIONS=1 / VMA_DYNAMIC_VULKAN_FUNCTIONS=0 come from
// engine/CMakeLists.txt (we link the Vulkan loader directly).
#define VMA_IMPLEMENTATION
#include <vk_mem_alloc.h>
