#pragma once
// CPU-side mesh data produced by the glTF loader (BUILD_PLAN step 11) and consumed
// by the renderer's upload path (engine/render/mesh.hpp). Plain data, no Vulkan.

#include <glm/glm.hpp>

#include <cstddef>
#include <cstdint>
#include <vector>

namespace coe::assets {

// Interleaved vertex. `uv` is carried for the texturing step (BUILD_PLAN step 21)
// but not yet bound by the pipeline; `color` is the material's baseColorFactor.
struct Vertex {
    glm::vec3 position{0.0f};
    glm::vec3 normal{0.0f, 1.0f, 0.0f};
    glm::vec2 uv{0.0f};
    glm::vec4 color{1.0f};
};
static_assert(sizeof(Vertex) == 48, "Vertex layout is mirrored by engine/render/mesh.cpp");

// One glTF primitive after flattening: a range of `MeshData::indices`.
struct Submesh {
    std::uint32_t firstIndex = 0;
    std::uint32_t indexCount = 0;
    std::int32_t material = -1;  // glTF material index, -1 = default material
    bool doubleSided = false;    // glTF material.doubleSided -> drawn without culling
};

// A whole model with node transforms baked in (one draw per submesh, CCW front faces).
struct MeshData {
    std::vector<Vertex> vertices;
    std::vector<std::uint32_t> indices;
    std::vector<Submesh> submeshes;
    glm::vec3 boundsMin{0.0f};
    glm::vec3 boundsMax{0.0f};

    std::size_t triangleCount() const { return indices.size() / 3; }
    glm::vec3 center() const { return (boundsMin + boundsMax) * 0.5f; }
    glm::vec3 extent() const { return boundsMax - boundsMin; }
};

}  // namespace coe::assets
