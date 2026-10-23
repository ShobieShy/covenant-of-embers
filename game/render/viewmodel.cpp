// SPDX-License-Identifier: Apache-2.0
#include "game/render/viewmodel.hpp"

#include <glm/gtc/matrix_transform.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace coe::game {
namespace {

// Grip at the lower right; the head ends up right of and below the crosshair at 75 deg
// (16:9 and 1:1), clear of it. Staff: longer, thicker, bigger head; wand: short and thin.
const ViewmodelPose kStaff{{0.33f, -0.26f, -0.53f}, 20.0f, 8.0f, 0.35f, 0.30f, 0.016f, 0.045f, {0.42f, 0.27f, 0.14f}};
const ViewmodelPose kWand{{0.30f, -0.24f, -0.50f}, 16.0f, 10.0f, 0.18f, 0.06f, 0.008f, 0.025f, {0.25f, 0.16f, 0.09f}};

float srgbToLinear(std::uint8_t v) {
    const float c = float(v) / 255.0f;
    return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

glm::vec3 blockMean(const HeadlessFrame& f, const glm::vec2& px, bool decode) {
    glm::vec3 sum(0.0f);
    int n = 0;
    const int cx = int(std::floor(px.x)), cy = int(std::floor(px.y));
    for (int y = cy - 2; y <= cy + 2; ++y)
        for (int x = cx - 2; x <= cx + 2; ++x) {
            if (x < 0 || y < 0 || x >= int(f.width) || y >= int(f.height)) continue;
            const std::uint8_t* p = f.rgba.data() + (size_t(y) * f.width + size_t(x)) * 4;
            for (int c = 0; c < 3; ++c) sum[c] += decode ? srgbToLinear(p[c]) : float(p[c]) / 255.0f;
            ++n;
        }
    return n ? sum / float(n) : glm::vec3(0.0f);
}

} // namespace

const ViewmodelPose& viewmodelPose(WieldableType t) { return t == WieldableType::Staff ? kStaff : kWand; }

glm::mat4 viewmodelTransform(WieldableType t, float focus, float lowered, const ViewmodelTuning& tune) {
    const ViewmodelPose& p = viewmodelPose(t);
    focus = std::clamp(focus, 0.0f, 1.0f);
    lowered = std::clamp(lowered, 0.0f, 1.0f);
    glm::vec3 hand = p.hand;
    hand.x *= 1.0f - tune.adsCentre * focus;
    hand.y += tune.adsRaise * focus - tune.lowerDrop * lowered;
    glm::mat4 m = glm::translate(glm::mat4(1.0f), hand);
    m = glm::rotate(m, glm::radians(p.yawDeg), glm::vec3(0, 1, 0));   // +yaw turns -Z toward -X (centre)
    m = glm::rotate(m, glm::radians(p.pitchDeg - tune.lowerPitchDeg * lowered), glm::vec3(1, 0, 0));   // +pitch tips -Z up
    return m;
}

glm::vec3 viewmodelCastPoint(WieldableType t, const glm::mat4& transform) {
    return glm::vec3(transform * glm::vec4(0.0f, 0.0f, -viewmodelPose(t).castDistance, 1.0f));
}

ViewmodelShown viewmodelShown(const Loadout& l) {
    if (!l.swapping()) return {l.wieldable(), 0.0f};
    const float p = l.swapProgress();
    if (p < 0.5f) return {l.inSlot(l.previous()), p / 0.5f};
    return {l.wieldable(), 1.0f - (p - 0.5f) / 0.5f};
}

glm::vec3 viewmodelToWorld(const glm::vec3& v, const Camera& camera, float vmFovYDeg) {
    const float k = std::tan(glm::radians(camera.fovYDeg) * 0.5f) / std::tan(glm::radians(vmFovYDeg) * 0.5f);
    const glm::vec4 scaled(v.x * k, v.y * k, v.z, 1.0f);
    return glm::vec3(glm::inverse(camera.view()) * scaled);
}

assets::MeshData makeViewmodelShaft() {
    constexpr int kSides = 10;
    assets::MeshData m;
    const float step = 2.0f * 3.14159265f / float(kSides);
    for (int i = 0; i <= kSides; ++i) {   // side: two rings, smooth normals (seam duplicated)
        const float a = float(i) * step;
        const glm::vec3 n(std::cos(a), std::sin(a), 0.0f);
        m.vertices.push_back({{n.x, n.y, 0.0f}, n, {}, glm::vec4(1.0f)});
        m.vertices.push_back({{n.x, n.y, -1.0f}, n, {}, glm::vec4(1.0f)});
    }
    for (int i = 0; i < kSides; ++i) {
        const std::uint32_t b = std::uint32_t(i * 2);   // CCW seen from outside
        m.indices.insert(m.indices.end(), {b, b + 1, b + 2, b + 1, b + 3, b + 2});
    }
    for (int cap = 0; cap < 2; ++cap) {   // flat caps: z = 0 faces +Z, z = -1 faces -Z
        const float z = cap == 0 ? 0.0f : -1.0f;
        const glm::vec3 n(0.0f, 0.0f, cap == 0 ? 1.0f : -1.0f);
        const std::uint32_t c = std::uint32_t(m.vertices.size());
        m.vertices.push_back({{0.0f, 0.0f, z}, n, {}, glm::vec4(1.0f)});
        for (int i = 0; i < kSides; ++i) {
            const float a = float(i) * step;
            m.vertices.push_back({{std::cos(a), std::sin(a), z}, n, {}, glm::vec4(1.0f)});
        }
        for (int i = 0; i < kSides; ++i) {
            const std::uint32_t a = c + 1 + std::uint32_t(i), b = c + 1 + std::uint32_t((i + 1) % kSides);
            if (cap == 0) m.indices.insert(m.indices.end(), {c, a, b});
            else m.indices.insert(m.indices.end(), {c, b, a});
        }
    }
    m.submeshes.push_back({0, std::uint32_t(m.indices.size()), -1, false});
    m.boundsMin = glm::vec3(-1.0f, -1.0f, -1.0f);
    m.boundsMax = glm::vec3(1.0f, 1.0f, 0.0f);
    return m;
}

assets::MeshData makeViewmodelHead() {
    // Octahedron with the z axis 1.6x longer (a gem), flat-shaded: 8 faces x 3 vertices.
    const glm::vec3 v[6] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1.6f}, {0, 0, -1.6f}};
    const int faces[8][3] = {{0, 2, 4}, {2, 1, 4}, {1, 3, 4}, {3, 0, 4}, {2, 0, 5}, {1, 2, 5}, {3, 1, 5}, {0, 3, 5}};
    assets::MeshData m;
    for (const auto& f : faces) {
        const glm::vec3 a = v[f[0]], b = v[f[1]], c = v[f[2]];
        const glm::vec3 n = glm::normalize(glm::cross(b - a, c - a));
        for (const glm::vec3& p : {a, b, c}) {
            m.indices.push_back(std::uint32_t(m.vertices.size()));
            m.vertices.push_back({p, n, {}, glm::vec4(1.0f)});
        }
    }
    m.submeshes.push_back({0, std::uint32_t(m.indices.size()), -1, false});
    m.boundsMin = glm::vec3(-1.0f, -1.0f, -1.6f);
    m.boundsMax = glm::vec3(1.0f, 1.0f, 1.6f);
    return m;
}

void appendViewmodelDraws(const ViewmodelMeshes& m, WieldableType t, const glm::mat4& transform,
                          const glm::vec3& headColor, std::vector<DrawItem>& out) {
    const ViewmodelPose& p = viewmodelPose(t);
    // Shaft from shaftBack behind the hand to just inside the head.
    const float len = p.shaftBack + p.castDistance - p.headRadius;
    const glm::mat4 shaft = glm::scale(glm::translate(transform, glm::vec3(0.0f, 0.0f, p.shaftBack)),
                                       glm::vec3(p.shaftRadius, p.shaftRadius, len));
    out.push_back({m.shaft, shaft, glm::vec4(p.shaftColor, 1.0f)});
    const glm::mat4 head = glm::scale(glm::translate(transform, glm::vec3(0.0f, 0.0f, -p.castDistance)),
                                      glm::vec3(p.headRadius));
    out.push_back({m.head, head, glm::vec4(headColor, 1.0f)});
}

bool viewmodelPixel(const glm::vec3& v, std::uint32_t width, std::uint32_t height, glm::vec2& outPx, float vmFovYDeg,
                    float vmNear) {
    if (width == 0 || height == 0 || v.z >= 0.0f) return false;
    Camera vm;
    vm.fovYDeg = vmFovYDeg;
    vm.nearZ = vmNear;
    const glm::vec4 clip = vm.projection(float(width) / float(height)) * glm::vec4(v, 1.0f);
    if (clip.w <= 0.0f) return false;
    const glm::vec2 ndc(clip.x / clip.w, clip.y / clip.w);   // Vulkan: +y down
    outPx = {(ndc.x * 0.5f + 0.5f) * float(width), (ndc.y * 0.5f + 0.5f) * float(height)};
    return outPx.x >= 0.0f && outPx.y >= 0.0f && outPx.x < float(width) && outPx.y < float(height);
}

bool checkViewmodelHead(const HeadlessFrame& f, const HeadlessFrame* without, const glm::vec2& headPx,
                        const glm::vec3& elementColor, std::string& report) {
    char buf[320];
    if (f.width == 0 || f.height == 0 || f.rgba.size() < size_t(f.width) * f.height * 4 || headPx.x < 0.0f ||
        headPx.y < 0.0f || headPx.x >= float(f.width) || headPx.y >= float(f.height)) {
        std::snprintf(buf, sizeof buf, "[viewmodel] head pixel (%.0f, %.0f) outside the %ux%u frame", double(headPx.x),
                      double(headPx.y), f.width, f.height);
        report = buf;
        return false;
    }
    const glm::vec3 c = blockMean(f, headPx, f.srgb);
    const float lc = glm::length(c), le = glm::length(elementColor);
    const float cosine = lc > 1e-6f && le > 1e-6f ? glm::dot(c, elementColor) / (lc * le) : 0.0f;
    const bool lit = std::max({c.r, c.g, c.b}) > 0.08f;
    bool differs = true;
    float diff = -1.0f;
    if (without) {
        const glm::vec3 w = without->width == f.width && without->height == f.height ? blockMean(*without, headPx, without->srgb)
                                                                                      : glm::vec3(-1.0f);
        diff = std::abs(c.r - w.r) + std::abs(c.g - w.g) + std::abs(c.b - w.b);
        differs = diff > 0.1f;
    }
    const bool tinted = cosine >= 0.97f;
    std::snprintf(buf, sizeof buf,
                  "[viewmodel] head at (%.0f, %.0f): linear rgb(%.3f, %.3f, %.3f) vs element (%.2f, %.2f, %.2f): "
                  "cos %.3f%s%s%s",
                  double(headPx.x), double(headPx.y), double(c.r), double(c.g), double(c.b), double(elementColor.r),
                  double(elementColor.g), double(elementColor.b), double(cosine),
                  without ? (", differs from no-viewmodel frame by " + std::to_string(diff)).c_str() : "",
                  f.srgb ? " (sRGB capture)" : "",
                  tinted && lit && differs ? "" : " MISMATCH (need cos >= 0.97, lit, drawn)");
    report = buf;
    return tinted && lit && differs;
}

} // namespace coe::game
