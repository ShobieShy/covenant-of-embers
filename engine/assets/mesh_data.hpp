#pragma once
// CPU-side mesh data produced by the glTF loader (BUILD_PLAN step 11) and consumed
// by the renderer's upload path (engine/render/mesh.hpp). Plain data, no Vulkan.

#include <glm/glm.hpp>

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace coe::assets {

// Interleaved vertex. `uv` samples the submesh's base-colour texture (step 21), with
// KHR_texture_transform already baked in; `color` is the material's baseColorFactor
// (times any tint), multiplied with the texture in the fragment shader.
struct Vertex {
    glm::vec3 position{0.0f};
    glm::vec3 normal{0.0f, 1.0f, 0.0f};
    glm::vec2 uv{0.0f};
    glm::vec4 color{1.0f};
};
static_assert(sizeof(Vertex) == 48, "Vertex layout is mirrored by engine/render/mesh.cpp");

// Decoded image, tightly packed RGBA8 (sRGB-encoded colour, as glTF base colour is).
struct ImageData {
    std::uint32_t width = 0, height = 0;
    std::vector<std::uint8_t> rgba;   // width * height * 4 bytes, row 0 = top
    std::string name;                 // URI or glTF image name, for messages
};

// glTF sampler state, reduced to what the renderer maps to a VkSampler.
enum class Filter : std::uint8_t { Nearest, Linear };
enum class Wrap : std::uint8_t { Repeat, ClampToEdge, MirroredRepeat };
struct SamplerDesc {
    Filter mag = Filter::Linear, min = Filter::Linear, mip = Filter::Linear;
    bool mipmaps = true;              // false for glTF minFilter NEAREST / LINEAR (no mip)
    Wrap wrapU = Wrap::Repeat, wrapV = Wrap::Repeat;
    bool operator==(const SamplerDesc&) const = default;
};

// A glTF material's base-colour texture (the factor lives in Vertex::color).
struct MaterialData {
    std::string name;
    std::int32_t baseColorImage = -1;  // index into MeshData::images, -1 = untextured
    SamplerDesc sampler;
};

// One glTF primitive after flattening: a range of `MeshData::indices`.
struct Submesh {
    std::uint32_t firstIndex = 0;
    std::uint32_t indexCount = 0;
    std::int32_t material = -1;  // glTF material index = MeshData::materials index, -1 = default
    bool doubleSided = false;    // glTF material.doubleSided -> drawn without culling
};

// A whole model with node transforms baked in (one draw per submesh, CCW front faces).
struct MeshData {
    std::vector<Vertex> vertices;
    std::vector<std::uint32_t> indices;
    std::vector<Submesh> submeshes;
    std::vector<MaterialData> materials;  // one per glTF material (step 21)
    std::vector<ImageData> images;        // decoded base-colour images they reference
    glm::vec3 boundsMin{0.0f};
    glm::vec3 boundsMax{0.0f};

    std::size_t triangleCount() const { return indices.size() / 3; }
    glm::vec3 center() const { return (boundsMin + boundsMax) * 0.5f; }
    glm::vec3 extent() const { return boundsMax - boundsMin; }
};

}  // namespace coe::assets
