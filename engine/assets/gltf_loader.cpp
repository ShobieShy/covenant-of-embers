#include "engine/assets/gltf_loader.hpp"

#include <fastgltf/core.hpp>
#include <fastgltf/tools.hpp>
#include <fastgltf/types.hpp>

#include <glm/gtc/matrix_inverse.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <cmath>
#include <functional>
#include <limits>
#include <optional>
#include <variant>

namespace coe::assets {
namespace {

namespace fg = fastgltf;

// Extensions we accept. Anything the file lists as *required* beyond these makes the
// parse fail (fastgltf reports MissingExtensions/UnsupportedExtensions). Kenney's
// UnityGLTF exports use KHR_texture_transform (texturing: BUILD_PLAN step 21).
constexpr fg::Extensions kExtensions =
    fg::Extensions::KHR_texture_transform | fg::Extensions::KHR_mesh_quantization |
    fg::Extensions::KHR_materials_emissive_strength | fg::Extensions::KHR_materials_unlit |
    fg::Extensions::KHR_lights_punctual;

std::string errorText(fg::Error e) {
    return std::string(fg::getErrorName(e)) + " (" + std::string(fg::getErrorMessage(e)) + ")";
}

// Bytes actually held for a buffer, or nullopt when not loaded (external URI).
std::optional<std::size_t> loadedSize(const fg::Buffer& b) {
    if (auto* a = std::get_if<fg::sources::Array>(&b.data)) return a->bytes.size_bytes();
    if (auto* v = std::get_if<fg::sources::Vector>(&b.data)) return v->bytes.size();
    if (auto* bv = std::get_if<fg::sources::ByteView>(&b.data)) return bv->bytes.size();
    return std::nullopt;
}

// Loaded buffers must hold at least byteLength bytes; validate() trusts byteLength.
// Returns whether every buffer is loaded (so accessor data may be read).
std::string checkBufferSizes(const fg::Asset& asset, bool requireLoaded, bool& allLoaded) {
    allLoaded = true;
    for (std::size_t i = 0; i < asset.buffers.size(); ++i) {
        const auto& b = asset.buffers[i];
        const auto size = loadedSize(b);
        if (!size) {
            allLoaded = false;
            if (requireLoaded) return "buffer " + std::to_string(i) + " has no data";
            continue;
        }
        if (*size < b.byteLength)
            return "buffer " + std::to_string(i) + " holds " + std::to_string(*size) +
                   " bytes but declares byteLength " + std::to_string(b.byteLength);
    }
    return {};
}

std::string where(std::size_t mesh, std::size_t prim) {
    return "mesh " + std::to_string(mesh) + " primitive " + std::to_string(prim) + ": ";
}

const fg::Accessor* attribute(const fg::Asset& asset, const fg::Primitive& p, std::string_view name) {
    auto it = p.findAttribute(name);
    if (it == p.attributes.end() || it->accessorIndex >= asset.accessors.size()) return nullptr;
    return &asset.accessors[it->accessorIndex];
}

bool isFloatVec(const fg::Accessor& a, fg::AccessorType t) {
    return a.type == t && a.componentType == fg::ComponentType::Float;
}

// Structural checks on every triangle primitive (+ index ranges when data is loaded).
std::string checkPrimitives(const fg::Asset& asset, bool dataLoaded, GltfSummary* summary) {
    for (std::size_t m = 0; m < asset.meshes.size(); ++m) {
        const auto& mesh = asset.meshes[m];
        for (std::size_t pi = 0; pi < mesh.primitives.size(); ++pi) {
            const auto& p = mesh.primitives[pi];
            if (summary) ++summary->primitives;
            for (const auto& attr : p.attributes)
                if (attr.accessorIndex >= asset.accessors.size())
                    return where(m, pi) + "attribute " + std::string(attr.name) + " has a bad accessor index";
            if (p.type != fg::PrimitiveType::Triangles) {
                if (summary) ++summary->skippedPrimitives;
                continue;
            }
            const fg::Accessor* pos = attribute(asset, p, "POSITION");
            if (!pos) return where(m, pi) + "no POSITION attribute";
            if (!isFloatVec(*pos, fg::AccessorType::Vec3)) return where(m, pi) + "POSITION must be float VEC3";
            if (pos->count > std::numeric_limits<std::uint32_t>::max())
                return where(m, pi) + "too many vertices";
            for (const auto& attr : p.attributes) {
                const auto& acc = asset.accessors[attr.accessorIndex];
                if (acc.count != pos->count)
                    return where(m, pi) + "attribute " + std::string(attr.name) + " count " +
                           std::to_string(acc.count) + " != POSITION count " + std::to_string(pos->count);
            }
            if (const auto* n = attribute(asset, p, "NORMAL"); n && !isFloatVec(*n, fg::AccessorType::Vec3))
                return where(m, pi) + "NORMAL must be float VEC3";
            if (const auto* uv = attribute(asset, p, "TEXCOORD_0"); uv && uv->type != fg::AccessorType::Vec2)
                return where(m, pi) + "TEXCOORD_0 must be VEC2";

            std::size_t count = pos->count;
            if (p.indicesAccessor) {
                if (*p.indicesAccessor >= asset.accessors.size()) return where(m, pi) + "bad indices accessor";
                const auto& idx = asset.accessors[*p.indicesAccessor];
                const auto ct = idx.componentType;
                if (idx.type != fg::AccessorType::Scalar ||
                    (ct != fg::ComponentType::UnsignedByte && ct != fg::ComponentType::UnsignedShort &&
                     ct != fg::ComponentType::UnsignedInt))
                    return where(m, pi) + "indices must be unsigned scalar";
                count = idx.count;
                if (dataLoaded) {
                    std::size_t bad = 0;
                    fg::iterateAccessor<std::uint32_t>(asset, idx, [&](std::uint32_t v) {
                        if (v >= pos->count) ++bad;
                    });
                    if (bad)
                        return where(m, pi) + std::to_string(bad) + " index value(s) >= vertex count " +
                               std::to_string(pos->count);
                }
            }
            if (count % 3 != 0) return where(m, pi) + "vertex/index count " + std::to_string(count) + " is not a multiple of 3";
            if (summary) summary->triangles += count / 3;
        }
    }
    return {};
}

std::string parse(fg::GltfDataGetter& data, const std::filesystem::path& dir, fg::Options opts,
                  fg::Asset& out) {
    fg::Parser parser(kExtensions);
    auto asset = parser.loadGltf(data, dir, opts);
    if (asset.error() != fg::Error::None) return "glTF parse failed: " + errorText(asset.error());
    if (const auto e = fg::validate(asset.get()); e != fg::Error::None)
        return "glTF validation failed: " + errorText(e);
    out = std::move(asset.get());
    return {};
}

glm::mat4 toGlm(const fg::math::fmat4x4& m) { return glm::make_mat4(m.data()); }

// Append one triangle primitive transformed by `world`.
void appendPrimitive(const fg::Asset& asset, const fg::Primitive& p, const glm::mat4& world, MeshData& out) {
    const auto& pos = *attribute(asset, p, "POSITION");
    const auto* nrm = attribute(asset, p, "NORMAL");
    const auto* uv = attribute(asset, p, "TEXCOORD_0");

    Submesh sub;
    sub.firstIndex = static_cast<std::uint32_t>(out.indices.size());
    glm::vec4 color{1.0f};
    if (p.materialIndex && *p.materialIndex < asset.materials.size()) {
        const auto& mat = asset.materials[*p.materialIndex];
        sub.material = static_cast<std::int32_t>(*p.materialIndex);
        sub.doubleSided = mat.doubleSided;
        const auto& f = mat.pbrData.baseColorFactor;
        color = glm::vec4(f[0], f[1], f[2], f[3]);
    }

    const auto base = static_cast<std::uint32_t>(out.vertices.size());
    out.vertices.resize(out.vertices.size() + pos.count);
    Vertex* v = out.vertices.data() + base;
    const glm::mat3 normalMat = glm::inverseTranspose(glm::mat3(world));
    fg::iterateAccessorWithIndex<fg::math::fvec3>(asset, pos, [&](fg::math::fvec3 x, std::size_t i) {
        v[i].position = glm::vec3(world * glm::vec4(x[0], x[1], x[2], 1.0f));
        v[i].color = color;
    });
    if (nrm)
        fg::iterateAccessorWithIndex<fg::math::fvec3>(asset, *nrm, [&](fg::math::fvec3 n, std::size_t i) {
            const glm::vec3 w = normalMat * glm::vec3(n[0], n[1], n[2]);
            const float len = glm::length(w);
            v[i].normal = len > 1e-12f ? w / len : glm::vec3(0.0f, 1.0f, 0.0f);
        });
    if (uv)
        fg::iterateAccessorWithIndex<fg::math::fvec2>(asset, *uv, [&](fg::math::fvec2 t, std::size_t i) {
            v[i].uv = glm::vec2(t[0], t[1]);
        });

    if (p.indicesAccessor)
        fg::iterateAccessor<std::uint32_t>(asset, asset.accessors[*p.indicesAccessor],
                                           [&](std::uint32_t i) { out.indices.push_back(base + i); });
    else
        for (std::uint32_t i = 0; i < pos.count; ++i) out.indices.push_back(base + i);

    // A mirroring transform (negative determinant) turns CCW triangles into CW ones.
    std::uint32_t* idx = out.indices.data() + sub.firstIndex;
    const std::size_t n = out.indices.size() - sub.firstIndex;
    if (glm::determinant(glm::mat3(world)) < 0.0f)
        for (std::size_t t = 0; t + 2 < n; t += 3) std::swap(idx[t + 1], idx[t + 2]);

    if (!nrm) {
        // Area-weighted vertex normals from the (already world-space) triangles.
        for (std::size_t i = 0; i < pos.count; ++i) v[i].normal = glm::vec3(0.0f);
        for (std::size_t t = 0; t + 2 < n; t += 3) {
            Vertex& a = out.vertices[idx[t]];
            Vertex& b = out.vertices[idx[t + 1]];
            Vertex& c = out.vertices[idx[t + 2]];
            const glm::vec3 fn = glm::cross(b.position - a.position, c.position - a.position);
            a.normal += fn;
            b.normal += fn;
            c.normal += fn;
        }
        for (std::size_t i = 0; i < pos.count; ++i) {
            const float len = glm::length(v[i].normal);
            v[i].normal = len > 1e-20f ? v[i].normal / len : glm::vec3(0.0f, 1.0f, 0.0f);
        }
    }

    sub.indexCount = static_cast<std::uint32_t>(n);
    if (sub.indexCount) out.submeshes.push_back(sub);
}

}  // namespace

std::string inspectGltf(std::span<const std::byte> bytes, GltfSummary& out) {
    out = {};
    auto data = fg::GltfDataBuffer::FromBytes(bytes.data(), bytes.size());
    if (data.error() != fg::Error::None) return "cannot buffer glTF: " + errorText(data.error());
    fg::Asset asset;
    if (auto why = parse(data.get(), ".", fg::Options::None, asset); !why.empty()) return why;

    for (std::size_t i = 0; i < asset.buffers.size(); ++i) {
        const auto& b = asset.buffers[i];
        if (const auto* u = std::get_if<fg::sources::URI>(&b.data)) {
            if (!u->uri.isLocalPath()) return "buffer " + std::to_string(i) + " has a non-local URI: " + std::string(u->uri.string());
            out.externals.push_back({GltfExternal::Kind::Buffer, std::string(u->uri.path()), b.byteLength});
        }
    }
    for (std::size_t i = 0; i < asset.images.size(); ++i) {
        if (const auto* u = std::get_if<fg::sources::URI>(&asset.images[i].data)) {
            if (!u->uri.isLocalPath()) return "image " + std::to_string(i) + " has a non-local URI: " + std::string(u->uri.string());
            out.externals.push_back({GltfExternal::Kind::Image, std::string(u->uri.path()), 0});
        }
    }
    bool allLoaded = false;
    if (auto why = checkBufferSizes(asset, false, allLoaded); !why.empty()) return why;
    out.meshes = asset.meshes.size();
    out.indexRangesChecked = allLoaded;
    return checkPrimitives(asset, allLoaded, &out);
}

std::string loadGltfMesh(const std::filesystem::path& path, MeshData& out) {
    out = {};
    std::error_code ec;
    if (!std::filesystem::is_regular_file(path, ec)) return "no such model file: " + path.string();
    auto data = fg::GltfDataBuffer::FromPath(path);
    if (data.error() != fg::Error::None) return "cannot read " + path.string() + ": " + errorText(data.error());
    fg::Asset asset;
    if (auto why = parse(data.get(), path.parent_path(), fg::Options::LoadExternalBuffers, asset); !why.empty())
        return path.filename().string() + ": " + why;
    bool allLoaded = false;
    if (auto why = checkBufferSizes(asset, true, allLoaded); !why.empty()) return path.filename().string() + ": " + why;
    if (auto why = checkPrimitives(asset, true, nullptr); !why.empty()) return path.filename().string() + ": " + why;

    // Roots: the default scene, or (no scenes) every node that is nobody's child.
    std::vector<std::size_t> roots;
    if (!asset.scenes.empty()) {
        const std::size_t s = asset.defaultScene.value_or(0);
        if (s >= asset.scenes.size()) return path.filename().string() + ": bad default scene";
        roots.assign(asset.scenes[s].nodeIndices.begin(), asset.scenes[s].nodeIndices.end());
    } else {
        std::vector<bool> isChild(asset.nodes.size(), false);
        for (const auto& n : asset.nodes)
            for (auto c : n.children)
                if (c < isChild.size()) isChild[c] = true;
        for (std::size_t i = 0; i < asset.nodes.size(); ++i)
            if (!isChild[i]) roots.push_back(i);
    }

    // Explicit DFS with an on-stack flag: fastgltf::iterateSceneNodes has no cycle guard.
    std::vector<char> onStack(asset.nodes.size(), 0);
    std::string err;
    std::function<void(std::size_t, const glm::mat4&)> visit = [&](std::size_t i, const glm::mat4& parent) {
        if (!err.empty()) return;
        if (i >= asset.nodes.size()) { err = "node index " + std::to_string(i) + " out of range"; return; }
        if (onStack[i]) { err = "node graph has a cycle at node " + std::to_string(i); return; }
        onStack[i] = 1;
        const auto& node = asset.nodes[i];
        const glm::mat4 world = parent * toGlm(fg::getLocalTransformMatrix(node));
        if (node.meshIndex && *node.meshIndex < asset.meshes.size())
            for (const auto& p : asset.meshes[*node.meshIndex].primitives)
                if (p.type == fg::PrimitiveType::Triangles) appendPrimitive(asset, p, world, out);
        for (auto c : node.children) visit(c, world);
        onStack[i] = 0;
    };
    for (auto r : roots) visit(r, glm::mat4(1.0f));
    if (!err.empty()) { out = {}; return path.filename().string() + ": " + err; }

    if (out.indices.empty()) { out = {}; return path.filename().string() + ": no triangles in the default scene"; }
    if (out.indices.size() > std::numeric_limits<std::uint32_t>::max()) { out = {}; return "model too large"; }
    out.boundsMin = glm::vec3(std::numeric_limits<float>::max());
    out.boundsMax = glm::vec3(std::numeric_limits<float>::lowest());
    for (const auto& v : out.vertices) {
        if (!std::isfinite(v.position.x) || !std::isfinite(v.position.y) || !std::isfinite(v.position.z)) {
            out = {};
            return path.filename().string() + ": non-finite vertex position";
        }
        out.boundsMin = glm::min(out.boundsMin, v.position);
        out.boundsMax = glm::max(out.boundsMax, v.position);
    }
    return {};
}

}  // namespace coe::assets
