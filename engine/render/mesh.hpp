// SPDX-License-Identifier: Apache-2.0
#pragma once
// GPU-side meshes (BUILD_PLAN step 11): device-local vertex + index buffers allocated
// through VMA, uploaded once via a staging buffer (VkRenderer::uploadMesh).

#include "engine/assets/mesh_data.hpp"

#include <vulkan/vulkan.h>

#include <array>
#include <cstdint>
#include <vector>

// Same declaration VMA's VK_DEFINE_HANDLE produces; keeps vk_mem_alloc.h out of
// public headers (VMA is a private dependency of coe_engine).
typedef struct VmaAllocation_T* VmaAllocation;

namespace coe {

struct GpuBuffer {
    VkBuffer buffer = VK_NULL_HANDLE;
    VmaAllocation allocation = nullptr;
    VkDeviceSize size = 0;
    void* mapped = nullptr;  // persistently mapped host-visible buffers only
};

struct GpuMesh {
    GpuBuffer vertices, indices;
    std::vector<assets::Submesh> submeshes;
    uint32_t vertexCount = 0, indexCount = 0;
};

using MeshId = uint32_t;
inline constexpr MeshId kInvalidMesh = UINT32_MAX;

// Vertex input matching assets::Vertex and shaders/basic.vert:
// location 0 position, 1 normal, 2 colour. (uv stays in the stride for step 21.)
struct VertexLayout {
    VkVertexInputBindingDescription binding{};
    std::array<VkVertexInputAttributeDescription, 3> attributes{};
};
VertexLayout vertexLayout();

} // namespace coe
