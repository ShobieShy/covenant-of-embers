#pragma once
// glTF 2.0 / GLB loading via fastgltf (BUILD_PLAN step 11).
//
// fastgltf::validate() covers the spec's structural rules (accessors inside their
// bufferView, bufferViews inside their buffer's byteLength, ...). On top of that we
// check what it does not: that the actual buffer bytes are at least byteLength,
// that index values stay below the vertex count, attribute types/counts, and that
// the node graph has no cycles. Both entry points return "" on success, otherwise a
// human-readable reason.

#include "engine/assets/mesh_data.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <span>
#include <string>
#include <vector>

namespace coe::assets {

struct GltfExternal {
    enum class Kind { Buffer, Image };
    Kind kind = Kind::Buffer;
    std::string path;            // percent-decoded, relative to the glTF file
    std::uint64_t minBytes = 0;  // buffers: declared byteLength (file must be >= this)
};

struct GltfSummary {
    std::vector<GltfExternal> externals;
    std::size_t meshes = 0;
    std::size_t primitives = 0;
    std::size_t triangles = 0;      // over all triangle primitives (not per instance)
    std::size_t skippedPrimitives = 0;  // points/lines/strips/fans: not drawn
    bool indexRangesChecked = false;    // false when index data lives in external files
};

// Parse + validate glTF/GLB bytes without reading external files (used by the cooker,
// which checks the referenced files itself). Rejects non-local URIs.
std::string inspectGltf(std::span<const std::byte> bytes, GltfSummary& out);

// Load a .gltf/.glb from disk (external buffers resolved next to it), flatten the
// default scene (node transforms baked into positions/normals, winding fixed for
// mirrored transforms), generate area-weighted normals when missing. Fails when the
// result has no triangles.
std::string loadGltfMesh(const std::filesystem::path& path, MeshData& out);

}  // namespace coe::assets
