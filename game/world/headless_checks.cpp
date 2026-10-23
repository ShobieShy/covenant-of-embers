// SPDX-License-Identifier: Apache-2.0
#include "game/world/headless_checks.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace coe::game {
namespace {
constexpr int kGrid = 32;   // 32 x 32 samples

const uint8_t* px(const HeadlessFrame& f, uint32_t x, uint32_t y) { return f.rgba.data() + (size_t(y) * f.width + x) * 4; }
float depthAt(const HeadlessFrame& f, uint32_t x, uint32_t y) { return f.depth[size_t(y) * f.width + x]; }
int luma(const uint8_t* c) { return (c[0] * 2 + c[1] * 5 + c[2]) / 8; }
int diffTo(const uint8_t* c, const glm::vec3& ref) {
    int d = 0;
    for (int i = 0; i < 3; ++i) d += std::abs(int(c[i]) - int(ref[i] * 255.0f + 0.5f));
    return d;
}
bool isClear(const uint8_t* c, const glm::vec3& ref) {
    for (int i = 0; i < 3; ++i)
        if (std::abs(int(c[i]) - int(ref[i] * 255.0f + 0.5f)) > 3) return false;
    return true;
}
bool sane(const HeadlessFrame& f) {
    return f.width >= kGrid && f.height >= kGrid && f.rgba.size() == size_t(f.width) * f.height * 4 &&
           f.depth.size() == size_t(f.width) * f.height;
}
} // namespace

bool checkLevelView(const Level& level, const HeadlessFrame& f, const glm::vec3& cameraPos,
                    const glm::vec3& clearColor, LevelViewStats& st, std::string& report) {
    st = {};
    if (!sane(f)) { report = "[headless] frame too small or incomplete"; return false; }
    const glm::mat4 inv = glm::inverse(f.viewProj);
    double groundY = 0, skyY = 0, groundDiff = 0, wallDiff = 0;
    for (int gy = 0; gy < kGrid; ++gy)
        for (int gx = 0; gx < kGrid; ++gx) {
            const auto x = uint32_t((gx + 0.5) * f.width / kGrid), y = uint32_t((gy + 0.5) * f.height / kGrid);
            const uint8_t* c = px(f, x, y);
            const float d = depthAt(f, x, y);
            ++st.samples;
            if (d <= 0.0f) {
                ++st.sky; skyY += y;
                if (!isClear(c, clearColor)) ++st.skyWrongColor;   // MSAA edge (sample 0 missed) or a bug
                continue;
            }
            // Depth was taken at sample 0's position inside the pixel; unproject there.
            const glm::vec2 ndc = (glm::vec2(float(x), float(y)) + f.depthSamplePos) /
                                      glm::vec2(float(f.width), float(f.height)) * 2.0f - 1.0f;
            glm::vec4 w = inv * glm::vec4(ndc, d, 1.0f);
            const glm::vec3 world = glm::vec3(w) / w.w;
            const float dist = glm::length(world - cameraPos);
            const int box = level.boxAtSurface(world, 0.02f + 0.004f * dist);
            if (box < 0) { ++st.unexplained; continue; }
            const BoxKind k = level.boxes[size_t(box)].kind;
            ++st.perKind[size_t(k)];
            const int l = luma(c);
            if (k == BoxKind::Ground) {
                groundY += y; groundDiff += diffTo(c, clearColor);
                st.groundLumaMin = std::min(st.groundLumaMin, l); st.groundLumaMax = std::max(st.groundLumaMax, l);
            } else if (k == BoxKind::Wall) {
                wallDiff += diffTo(c, clearColor);
                st.wallLumaMin = std::min(st.wallLumaMin, l); st.wallLumaMax = std::max(st.wallLumaMax, l);
            }
        }
    const size_t ground = st.perKind[size_t(BoxKind::Ground)], walls = st.perKind[size_t(BoxKind::Wall)];
    st.groundMeanY = ground ? groundY / double(ground) : 0;
    st.skyMeanY = st.sky ? skyY / double(st.sky) : 0;
    st.groundSkyDiff = ground ? groundDiff / double(ground) : 0;
    st.wallSkyDiff = walls ? wallDiff / double(walls) : 0;

    // Full-image scan for resolved silhouette edges against the sky. Depth is one sample
    // (sample 0) per pixel, colour the average of all samples, so an edge pixel shows as
    // either (a) depth empty but colour not the clear colour (another sample was covered),
    // or (b) depth on geometry, sky directly above/left, and the colour pulled toward the
    // sky compared with the next pixel inward (another sample saw sky). Flat-shaded
    // greybox faces barely change over one pixel, so without MSAA (b) is ~0.
    for (uint32_t y = 1; y + 1 < f.height; ++y)
        for (uint32_t x = 1; x + 1 < f.width; ++x) {
            const uint8_t* c = px(f, x, y);
            const int cd = diffTo(c, clearColor);
            if (depthAt(f, x, y) <= 0.0f) {
                if (cd > 2) ++st.msaaEdgePixels;
                continue;
            }
            const bool up = depthAt(f, x, y - 1) <= 0.0f && depthAt(f, x, y + 1) > 0.0f;
            const bool left = depthAt(f, x - 1, y) <= 0.0f && depthAt(f, x + 1, y) > 0.0f;
            if ((up && cd + 4 < diffTo(px(f, x, y + 1), clearColor)) ||
                (left && cd + 4 < diffTo(px(f, x + 1, y), clearColor)))
                ++st.msaaEdgePixels;
        }

    const size_t drawn = st.samples - st.sky;
    const bool floorOk = ground >= st.samples * 15 / 100 && st.groundMeanY > f.height * 0.5 && st.groundSkyDiff > 30;
    const bool wallsOk = walls >= st.samples * 5 / 100 && st.wallSkyDiff > 30 && st.wallLumaMax - st.wallLumaMin > 8;
    const bool skyOk = st.sky >= st.samples * 3 / 100 && st.skyMeanY < f.height * 0.5 && st.skyWrongColor * 10 <= st.sky;
    const bool geometryOk = st.unexplained * 100 <= drawn;   // <= 1%: transforms reproduce the data
    // 1x (no 2x support): nothing to prove; with MSAA, the silhouette must be resolved.
    const bool msaaOk = f.samples <= 1 || st.msaaEdgePixels >= 16;
    char buf[512];
    std::snprintf(buf, sizeof buf,
                  "[headless] level '%s' (%zu boxes), %ux MSAA: %zu samples: ground %zu (mean y %.0f, luma %d..%d), "
                  "walls %zu (luma %d..%d), other boxes %zu, sky %zu (%zu off-colour), unexplained %zu | "
                  "MSAA edge pixels %zu | floor %s walls %s sky %s geometry %s msaa %s",
                  level.id.c_str(), level.boxes.size(), f.samples, st.samples, ground, st.groundMeanY,
                  st.groundLumaMin, st.groundLumaMax, walls, st.wallLumaMin, st.wallLumaMax,
                  drawn - ground - walls - st.unexplained, st.sky, st.skyWrongColor, st.unexplained, st.msaaEdgePixels,
                  floorOk ? "ok" : "FAIL", wallsOk ? "ok" : "FAIL", skyOk ? "ok" : "FAIL", geometryOk ? "ok" : "FAIL",
                  msaaOk ? "ok" : "FAIL");
    report = buf;
    return floorOk && wallsOk && skyOk && geometryOk && msaaOk;
}

bool checkModelView(const HeadlessFrame& f, const glm::mat4& model0, const glm::vec3& clearColor, std::string& report) {
    if (!sane(f)) { report = "[headless] frame too small or incomplete"; return false; }
    const uint32_t W = f.width, H = f.height;
    const uint8_t* corner = px(f, 2, 2);
    const uint8_t* centre = px(f, W / 2, H / 2);
    const float cornerDepth = depthAt(f, 2, 2), centreDepth = depthAt(f, W / 2, H / 2);
    const glm::vec4 originClip = f.viewProj * model0[3];
    const float originDepth = originClip.z / originClip.w;
    int minL = 255, maxL = 0, samples = 0;
    for (uint32_t y = H / 16; y < H; y += H / 32)
        for (uint32_t x = W / 16; x < W; x += W / 32)
            if (depthAt(f, x, y) > 0.0f) {
                const int l = luma(px(f, x, y));
                ++samples; minL = std::min(minL, l); maxL = std::max(maxL, l);
            }
    const bool cornerIsClear = isClear(corner, clearColor) && cornerDepth == 0.0f;
    const int centreDiff = std::abs(int(centre[0]) - int(corner[0])) + std::abs(int(centre[1]) - int(corner[1])) +
                           std::abs(int(centre[2]) - int(corner[2]));
    // Non-clear and lit: clearly above the ambient-only level of a white surface (0.2 * 255).
    const bool centreIsLit = centreDiff > 60 && centreDepth > originDepth && centreDepth <= 1.0f;
    const bool shaded = samples >= 8 && maxL - minL > 20;
    char buf[384];
    std::snprintf(buf, sizeof buf,
                  "[headless] model: corner rgb(%u,%u,%u) depth %.5f | centre rgb(%u,%u,%u) depth %.5f (model origin %.5f) | "
                  "%d model samples, luma %d..%d",
                  corner[0], corner[1], corner[2], double(cornerDepth), centre[0], centre[1], centre[2],
                  double(centreDepth), double(originDepth), samples, minL, maxL);
    report = buf;
    return cornerIsClear && centreIsLit && shaded;
}

bool writePpm(const std::string& path, const HeadlessFrame& f) {
    FILE* out = std::fopen(path.c_str(), "wb");
    if (!out) return false;
    std::fprintf(out, "P6\n%u %u\n255\n", f.width, f.height);
    for (size_t i = 0; i < size_t(f.width) * f.height; ++i) std::fwrite(f.rgba.data() + i * 4, 1, 3, out);
    return std::fclose(out) == 0;
}

} // namespace coe::game
