// SPDX-License-Identifier: Apache-2.0
// glTF loading + cooked manifest tests (BUILD_PLAN step 11; textures + KHR_texture_transform
// step 21). Plain checks, not yet ported to doctest (step 20 notes).
//   test_gltf_loader                 synthetic glTF files written to a temp dir
//   test_gltf_loader --cooked DIR    the cooked Kenney blaster kit (ctest fixture
//                                    cooked_blaster) through the manifest
#include "engine/assets/gltf_loader.hpp"
#include "engine/assets/hash.hpp"
#include "engine/assets/manifest.hpp"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <random>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using namespace coe::assets;

namespace {
int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

bool near(float a, float b, float eps = 1e-5f) { return std::fabs(a - b) <= eps; }
bool near(glm::vec3 a, glm::vec3 b, float eps = 1e-5f) { return near(a.x, b.x, eps) && near(a.y, b.y, eps) && near(a.z, b.z, eps); }

void put(const fs::path& p, const std::string& data) {
    fs::create_directories(p.parent_path());
    std::ofstream(p, std::ios::binary) << data;
}

// One right triangle (0,0,0) (1,0,0) (0,1,0), CCW seen from +Z, plus uint16 indices.
std::string triBuffer(uint16_t last = 2) {
    std::string b;
    const float pos[9] = {0, 0, 0, 1, 0, 0, 0, 1, 0};
    b.append(reinterpret_cast<const char*>(pos), sizeof pos);
    const uint16_t idx[3] = {0, 1, last};
    b.append(reinterpret_cast<const char*>(idx), sizeof idx);
    return b;   // 42 bytes
}

// Two primitives on one mesh (indexed + non-indexed) under a parent node translated
// by +1 X; the child mirrors X (scale -1), so winding must be flipped by the loader.
std::string sceneGltf(const std::string& nodes, const std::string& extraPrim = "") {
    return std::string(R"({"asset":{"version":"2.0"},"buffers":[{"uri":"tri.bin","byteLength":42}],)") +
           R"("bufferViews":[{"buffer":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":6}],)"
           R"("accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},)"
           R"({"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],)"
           R"("materials":[{"pbrMetallicRoughness":{"baseColorFactor":[0.5,0.25,1,1]},"doubleSided":true}],)"
           R"("meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1,"material":0},)"
           R"({"attributes":{"POSITION":0}})" + extraPrim + R"(]}],)" + nodes + "}";
}
const std::string kNodes = R"("nodes":[{"translation":[1,0,0],"children":[1]},{"scale":[-1,1,1],"mesh":0}],"scenes":[{"nodes":[0]}],"scene":0)";

void syntheticTests(const fs::path& tmp) {
    put(tmp / "ok/tri.bin", triBuffer());
    put(tmp / "ok/scene.gltf", sceneGltf(kNodes, R"(,{"attributes":{"POSITION":0},"mode":0})"));
    MeshData m;
    std::string err = loadGltfMesh(tmp / "ok/scene.gltf", m);
    CHECK(err.empty());
    if (!err.empty()) std::printf("  %s\n", err.c_str());
    CHECK(m.triangleCount() == 2);                  // points primitive skipped
    CHECK(m.vertices.size() == 6);
    CHECK(m.submeshes.size() == 2);
    if (m.submeshes.size() == 2) {
        CHECK(m.submeshes[0].firstIndex == 0 && m.submeshes[0].indexCount == 3);
        CHECK(m.submeshes[1].firstIndex == 3 && m.submeshes[1].indexCount == 3);
        CHECK(m.submeshes[0].doubleSided && m.submeshes[0].material == 0);
        CHECK(!m.submeshes[1].doubleSided && m.submeshes[1].material == -1);
    }
    // x' = 1 - x: the mirrored triangle spans x in [0, 1] again.
    CHECK(near(m.boundsMin, {0, 0, 0}) && near(m.boundsMax, {1, 1, 0}));
    if (m.vertices.size() == 6) {
        CHECK(near(m.vertices[0].position, {1, 0, 0}));
        CHECK(near(m.vertices[1].position, {0, 0, 0}));
        CHECK(near(m.vertices[2].position, {1, 1, 0}));
        CHECK(near(m.vertices[0].color.r, 0.5f) && near(m.vertices[0].color.g, 0.25f) && near(m.vertices[0].color.b, 1.0f));
        CHECK(near(m.vertices[3].color.r, 1.0f));   // default material is white
        for (const auto& v : m.vertices) CHECK(near(v.normal, {0, 0, 1}));   // generated, still facing +Z
    }
    for (uint32_t i : m.indices) CHECK(i < m.vertices.size());
    // Winding: after the flip each triangle is CCW seen from +Z again (cross product +Z).
    for (size_t t = 0; t + 2 < m.indices.size(); t += 3) {
        const glm::vec3 a = m.vertices[m.indices[t]].position, b = m.vertices[m.indices[t + 1]].position,
                        c = m.vertices[m.indices[t + 2]].position;
        CHECK(glm::cross(b - a, c - a).z > 0.0f);
    }

    // inspectGltf (cooker path): external buffer listed with its byteLength, no file reads.
    {
        const std::string json = sceneGltf(kNodes);
        GltfSummary s;
        err = inspectGltf(std::span(reinterpret_cast<const std::byte*>(json.data()), json.size()), s);
        CHECK(err.empty());
        CHECK(s.externals.size() == 1 && s.externals[0].path == "tri.bin" && s.externals[0].minBytes == 42 &&
              s.externals[0].kind == GltfExternal::Kind::Buffer);
        CHECK(s.meshes == 1 && s.primitives == 2 && s.triangles == 2 && !s.indexRangesChecked);
    }

    struct Bad { const char* name; std::string json; std::string bin; };
    const Bad bad[] = {
        {"truncated .bin", sceneGltf(kNodes), triBuffer().substr(0, 20)},
        {"index out of range", sceneGltf(kNodes), triBuffer(9)},
        {"node cycle", sceneGltf(R"("nodes":[{"children":[1]},{"children":[0],"mesh":0}],"scenes":[{"nodes":[0]}],"scene":0)"), triBuffer()},
        {"only points", std::string(R"({"asset":{"version":"2.0"},"buffers":[{"uri":"tri.bin","byteLength":42}],)") +
             R"("bufferViews":[{"buffer":0,"byteLength":36}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]}],)"
             R"("meshes":[{"primitives":[{"attributes":{"POSITION":0},"mode":0}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]})", triBuffer()},
        {"not json", "{\"asset\":", triBuffer()},
        {"missing .bin", sceneGltf(kNodes), ""},
    };
    int n = 0;
    for (const Bad& b : bad) {
        const fs::path dir = tmp / ("bad" + std::to_string(n++));
        put(dir / "scene.gltf", b.json);
        if (!b.bin.empty()) put(dir / "tri.bin", b.bin);
        MeshData out;
        err = loadGltfMesh(dir / "scene.gltf", out);
        std::printf("%s %s -> %s\n", err.empty() ? "FAIL" : "ok  ", b.name, err.c_str());
        CHECK(!err.empty());
        CHECK(out.vertices.empty() && out.indices.empty());
    }
    MeshData out;
    CHECK(!loadGltfMesh(tmp / "nope.glb", out).empty());
}

// Step 21: a textured triangle. 2x1 RGBA PNG (red, half-transparent blue), NEAREST
// without mips, clamp / mirrored wrap, and KHR_texture_transform from the extension's
// own example (offset [0,1], rotation pi/2, scale 0.5: the lower-left quadrant).
const std::string kPng2x1(
    "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x02\x00\x00\x00\x01"
    "\x08\x06\x00\x00\x00\xf4\x22\x7f\x8a\x00\x00\x00\x0e\x49\x44\x41\x54\x78\x9c\x63\xf8\xcf\xc0\x00"
    "\x42\x0d\x00\x0f\x7a\x03\x7e\x77\xe9\x7f\x97\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82", 71);

std::string texturedBuffer() {
    std::string b = triBuffer().substr(0, 36);   // positions
    const float uv[6] = {0, 0, 1, 0, 0, 1};
    b.append(reinterpret_cast<const char*>(uv), sizeof uv);   // 36..60
    return b;
}

std::string texturedGltf(const std::string& imageUri, const std::string& transform) {
    return std::string(R"({"asset":{"version":"2.0"},"extensionsUsed":["KHR_texture_transform"],)") +
           R"("buffers":[{"uri":"tex.bin","byteLength":60}],)"
           R"("bufferViews":[{"buffer":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":24}],)"
           R"("accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},)"
           R"({"bufferView":1,"componentType":5126,"count":3,"type":"VEC2"}],)"
           R"("images":[{"uri":")" + imageUri + R"("}],)"
           R"("samplers":[{"magFilter":9728,"minFilter":9728,"wrapS":33071,"wrapT":33648}],)"
           R"("textures":[{"sampler":0,"source":0}],)"
           R"("materials":[{"name":"tex","pbrMetallicRoughness":{"baseColorTexture":{"index":0)" + transform + R"(}}}],)"
           R"("meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":1},"material":0}]}],)"
           R"("nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}],"scene":0})";
}

void textureTests(const fs::path& tmp) {
    const std::string xf =
        R"(,"extensions":{"KHR_texture_transform":{"offset":[0,1],"rotation":1.5707963268,"scale":[0.5,0.5]}})";
    put(tmp / "tex/tex.bin", texturedBuffer());
    put(tmp / "tex/px.png", kPng2x1);
    put(tmp / "tex/scene.gltf", texturedGltf("px.png", xf));
    MeshData m;
    std::string err = loadGltfMesh(tmp / "tex/scene.gltf", m);
    CHECK(err.empty());
    if (!err.empty()) std::printf("  %s\n", err.c_str());
    CHECK(m.images.size() == 1 && m.materials.size() == 1 && m.submeshes.size() == 1);
    if (m.images.size() == 1) {
        const ImageData& im = m.images[0];
        CHECK(im.width == 2 && im.height == 1 && im.rgba.size() == 8);
        const uint8_t want[8] = {255, 0, 0, 255, 0, 0, 255, 128};
        CHECK(im.rgba.size() == 8 && std::memcmp(im.rgba.data(), want, 8) == 0);
    }
    if (m.materials.size() == 1) {
        const MaterialData& mat = m.materials[0];
        CHECK(mat.name == "tex" && mat.baseColorImage == 0);
        CHECK(mat.sampler.mag == Filter::Nearest && mat.sampler.min == Filter::Nearest && !mat.sampler.mipmaps);
        CHECK(mat.sampler.wrapU == Wrap::ClampToEdge && mat.sampler.wrapV == Wrap::MirroredRepeat);
    }
    if (m.vertices.size() == 3) {   // lower-left quadrant: (0,0)->(0,1), (1,0)->(0,0.5), (0,1)->(0.5,1)
        CHECK(near(m.vertices[0].uv.x, 0.0f, 1e-5f) && near(m.vertices[0].uv.y, 1.0f, 1e-5f));
        CHECK(near(m.vertices[1].uv.x, 0.0f, 1e-5f) && near(m.vertices[1].uv.y, 0.5f, 1e-5f));
        CHECK(near(m.vertices[2].uv.x, 0.5f, 1e-5f) && near(m.vertices[2].uv.y, 1.0f, 1e-5f));
    } else CHECK(m.vertices.size() == 3);

    // No transform: the UVs pass through.
    put(tmp / "tex/plain.gltf", texturedGltf("px.png", ""));
    MeshData plain;
    CHECK(loadGltfMesh(tmp / "tex/plain.gltf", plain).empty());
    CHECK(plain.vertices.size() == 3 && near(plain.vertices[1].uv.x, 1.0f) && near(plain.vertices[2].uv.y, 1.0f));

    // A corrupt image or a missing one is an error naming the image, not a silent white texture.
    put(tmp / "tex/bad.png", kPng2x1.substr(0, 40));
    put(tmp / "tex/bad.gltf", texturedGltf("bad.png", ""));
    put(tmp / "tex/missing.gltf", texturedGltf("nope.png", ""));
    for (const char* f : {"bad.gltf", "missing.gltf"}) {
        MeshData out;
        err = loadGltfMesh(tmp / "tex" / f, out);
        std::printf("%s %s -> %s\n", err.empty() ? "FAIL" : "ok  ", f, err.c_str());
        CHECK(!err.empty() && err.find(".png") != std::string::npos);
        CHECK(out.vertices.empty() && out.images.empty());
    }
}

// Manifest error handling on a temp cooked dir.
void manifestTests(const fs::path& tmp) {
    const fs::path dir = tmp / "cooked";
    const std::string data = "hello";
    put(dir / "assets/a.bin", data);
    auto manifest = [&](const std::string& files, int count, const char* format = "coe-cooked-manifest") {
        put(dir / "manifest.json", std::string("{\"format\": \"") + format + "\", \"version\": 1, \"hash\": \"fnv1a64\", \"file_count\": " +
                                        std::to_string(count) + ", \"files\": [" + files + "]}");
    };
    const std::string hash = fnv1a64Hex(data.data(), data.size());
    auto entry = [&](const std::string& cooked, size_t bytes, const std::string& h, const std::string& deps = "") {
        return "{\"source\": \"assets/a.bin\", \"cooked\": \"" + cooked + "\", \"type\": \"bin\", \"bytes\": " +
               std::to_string(bytes) + ", \"hash\": \"" + h + "\", \"deps\": [" + deps + "]}";
    };
    CookedManifest m;
    fs::path p;
    CHECK(!m.load(tmp / "no-such-dir").empty());
    manifest(entry("assets/a.bin", 5, hash), 1);
    CHECK(m.load(dir).empty());
    CHECK(m.entries().size() == 1);
    CHECK(m.resolve("assets/a.bin", p).empty() && p == dir / "assets/a.bin");
    CHECK(!m.resolve("assets/missing.glb", p).empty());
    manifest(entry("assets/a.bin", 6, hash), 1);
    CHECK(m.load(dir).empty() && !m.resolve("assets/a.bin", p).empty());   // size mismatch
    manifest(entry("assets/a.bin", 5, "0000000000000000"), 1);
    CHECK(m.load(dir).empty() && !m.resolve("assets/a.bin", p).empty());   // hash mismatch
    manifest(entry("assets/a.bin", 5, hash, "\"assets/dep.png\""), 1);
    CHECK(m.load(dir).empty() && !m.resolve("assets/a.bin", p).empty());   // dep not in manifest
    manifest(entry("../outside.bin", 5, hash), 1);
    CHECK(!m.load(dir).empty());                                          // escapes the cooked dir
    manifest(entry("/etc/passwd", 5, hash), 1);
    CHECK(!m.load(dir).empty());
    manifest(entry("assets/a.bin", 5, hash), 2);
    CHECK(!m.load(dir).empty());                                          // file_count mismatch
    manifest(entry("assets/a.bin", 5, hash), 1, "something-else");
    CHECK(!m.load(dir).empty());
    put(dir / "manifest.json", "{\"format\": ");
    CHECK(!m.load(dir).empty());                                          // malformed JSON
}

int cookedTests(const fs::path& cooked) {
    CookedManifest m;
    std::string err = m.load(cooked);
    CHECK(err.empty());
    if (!err.empty()) { std::printf("  %s\n", err.c_str()); return 1; }
    // blaster-a: body + child "magazine" node, 470 triangles in total (Kenney Blaster Kit 2.1).
    fs::path p;
    err = m.resolve("assets/kenney/blaster-kit/Models/GLB format/blaster-a.glb", p);
    CHECK(err.empty());
    MeshData a;
    if (err.empty()) err = loadGltfMesh(p, a);
    CHECK(err.empty());
    if (!err.empty()) std::printf("  %s\n", err.c_str());
    std::printf("blaster-a: %zu triangles, %zu vertices, %zu submeshes, bounds (%.3f %.3f %.3f)..(%.3f %.3f %.3f)\n",
                a.triangleCount(), a.vertices.size(), a.submeshes.size(), double(a.boundsMin.x), double(a.boundsMin.y),
                double(a.boundsMin.z), double(a.boundsMax.x), double(a.boundsMax.y), double(a.boundsMax.z));
    CHECK(a.triangleCount() == 470);
    CHECK(a.submeshes.size() == 2);
    for (const auto& s : a.submeshes) CHECK(s.doubleSided);   // UnityGLTF "colormap" material
    // Barrel points along +Z (glTF forward); the magazine (child at y -0.153) hangs below the body.
    CHECK(a.extent().z > a.extent().x && a.extent().z > a.extent().y);
    CHECK(a.boundsMin.y < -0.27f);
    for (const auto& v : a.vertices) CHECK(near(glm::length(v.normal), 1.0f, 1e-3f));

    size_t models = 0, tris = 0, texturedModels = 0;
    for (const auto& e : m.entries()) {
        if (e.type != "glb" && e.type != "gltf") continue;
        MeshData md;
        err = m.resolve(e.source, p);
        if (err.empty()) err = loadGltfMesh(p, md);
        if (!err.empty() || md.triangleCount() == 0) {
            std::printf("FAIL %s: %s\n", e.source.c_str(), err.c_str());
            ++failures;
        }
        for (uint32_t i : md.indices)
            if (i >= md.vertices.size()) { ++failures; break; }
        ++models;
        tris += md.triangleCount();
        // Step 21: every kit model samples the shared colormap.png atlas.
        bool textured = !md.images.empty() && md.images[0].width > 0;
        for (const MaterialData& mat : md.materials) textured = textured && mat.baseColorImage >= 0;
        if (textured) ++texturedModels;
        else std::printf("untextured: %s (%zu images, %zu materials)\n", e.source.c_str(), md.images.size(), md.materials.size());
    }
    std::printf("cooked models: %zu loaded, %zu triangles total, %zu textured\n", models, tris, texturedModels);
    CHECK(models >= 40);
    CHECK(texturedModels == models);
    return failures;
}
} // namespace

int main(int argc, char** argv) {
    if (argc == 3 && !std::strcmp(argv[1], "--cooked")) {
        cookedTests(argv[2]);
    } else {
        const fs::path tmp = fs::temp_directory_path() / ("coe_gltf_test_" + std::to_string(std::random_device{}()));
        fs::remove_all(tmp);
        syntheticTests(tmp);
        textureTests(tmp);
        manifestTests(tmp);
        fs::remove_all(tmp);
    }
    std::printf("%s (%d failure(s))\n", failures ? "FAILED" : "all checks passed", failures);
    return failures ? 1 : 0;
}
