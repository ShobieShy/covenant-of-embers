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
    // Step 21: one material descriptor set (set 1: base-colour texture + sampler) per
    // submesh, from this mesh's own pool; textures are owned by the renderer.
    std::vector<VkDescriptorSet> submeshSets;
    VkDescriptorPool materialPool = VK_NULL_HANDLE;
    uint32_t vertexCount = 0, indexCount = 0;
};

using MeshId = uint32_t;
inline constexpr MeshId kInvalidMesh = UINT32_MAX;

// Vertex input matching assets::Vertex and shaders/basic.vert:
// location 0 position, 1 normal, 2 colour, 3 uv (step 21).
struct VertexLayout {
    VkVertexInputBindingDescription binding{};
    std::array<VkVertexInputAttributeDescription, 4> attributes{};
};
VertexLayout vertexLayout();

} // namespace coe
