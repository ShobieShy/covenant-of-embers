// SPDX-License-Identifier: Apache-2.0
#include "game/ui/damage_numbers.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace coe::game {

void DamageNumbers::add(const glm::vec3& world, const DamageResult& r, Element element, const ElementTable& elements) {
    DamageNumber n;
    n.world = world;
    n.amount = r.amount;
    n.color = elements.color(element);
    n.scale = r.crit > 1.0f ? kCritScale : r.strong() ? kStrongScale : r.weak() ? kWeakScale : 1.0f;
    // Alternate -1, +1, 0 x 0.12 m so rapid hits on one spot don't overprint exactly.
    static constexpr float kDrift[3] = {0.0f, -0.12f, 0.12f};
    n.driftX = kDrift[spawned_++ % 3];
    if (numbers_.size() >= kMax) numbers_.erase(numbers_.begin());
    numbers_.push_back(n);
}

void DamageNumbers::tick(float dt) {
    for (DamageNumber& n : numbers_) n.age += dt;
    std::erase_if(numbers_, [](const DamageNumber& n) { return n.age >= kLifetime; });
}

glm::vec3 DamageNumbers::position(const DamageNumber& n) {
    const float t = std::clamp(n.age / kLifetime, 0.0f, 1.0f);
    // Ease-out rise: fast at first, settling as it fades.
    const float rise = kRise * (1.0f - (1.0f - t) * (1.0f - t));
    return n.world + glm::vec3(n.driftX * t, rise, 0.0f);
}

float DamageNumbers::alpha(const DamageNumber& n) {
    const float t = std::clamp(n.age / kLifetime, 0.0f, 1.0f);
    if (t <= kFadeStart) return 1.0f;
    return std::clamp(1.0f - (t - kFadeStart) / (1.0f - kFadeStart), 0.0f, 1.0f);
}

std::string DamageNumbers::format(float amount) {
    const float r = std::round(std::max(0.0f, amount) * 10.0f) / 10.0f;
    char buf[32];
    if (std::fabs(r - std::round(r)) < 1e-3f)
        std::snprintf(buf, sizeof buf, "%.0f", double(r));
    else
        std::snprintf(buf, sizeof buf, "%.1f", double(r));
    return buf;
}

void DamageNumbers::labels(const glm::mat4& viewProj, const glm::vec2& viewport, std::vector<DamageLabel>& out) const {
    for (const DamageNumber& n : numbers_) {
        const glm::vec4 clip = viewProj * glm::vec4(position(n), 1.0f);
        if (clip.w <= 1e-4f) continue;   // behind the camera
        const glm::vec2 ndc = glm::vec2(clip) / clip.w;   // Vulkan: +y down
        if (std::fabs(ndc.x) > 1.2f || std::fabs(ndc.y) > 1.2f) continue;
        DamageLabel l;
        l.screen = (ndc * 0.5f + 0.5f) * viewport;
        l.color = n.color;
        l.alpha = alpha(n);
        l.scale = n.scale;
        l.text = format(n.amount);
        out.push_back(std::move(l));
    }
}

namespace {
float toLinear(std::uint8_t v, bool srgb) {
    const float c = float(v) / 255.0f;
    if (!srgb) return c;
    return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}
glm::vec3 pixel(const HeadlessFrame& f, int x, int y) {
    const std::uint8_t* p = &f.rgba[(std::size_t(y) * f.width + std::size_t(x)) * 4];
    return {toLinear(p[0], f.srgb), toLinear(p[1], f.srgb), toLinear(p[2], f.srgb)};
}
} // namespace

bool checkLabelPixels(const HeadlessFrame& with, const HeadlessFrame& without, const glm::vec2& centre, float radius,
                      const glm::vec3& color, std::size_t minPixels, std::string& report) {
    char buf[256];
    const bool sized = with.width > 0 && with.height > 0 && with.width == without.width &&
                       with.height == without.height && with.rgba.size() >= std::size_t(with.width) * with.height * 4 &&
                       without.rgba.size() == with.rgba.size();
    if (!sized) {
        report = "[damage] label check: frames missing or of different sizes MISMATCH";
        return false;
    }
    const float lc = glm::length(color);
    std::size_t changed = 0, tinted = 0;
    glm::vec2 sum{0.0f};
    const int x0 = std::max(0, int(centre.x - radius)), x1 = std::min(int(with.width) - 1, int(centre.x + radius));
    const int y0 = std::max(0, int(centre.y - radius)), y1 = std::min(int(with.height) - 1, int(centre.y + radius));
    for (int y = y0; y <= y1; ++y)
        for (int x = x0; x <= x1; ++x) {
            const glm::vec3 a = pixel(with, x, y), b = pixel(without, x, y);
            if (std::fabs(a.r - b.r) + std::fabs(a.g - b.g) + std::fabs(a.b - b.b) < 0.1f) continue;
            ++changed;
            const float la = glm::length(a);
            if (la < 1e-4f || lc < 1e-6f || std::max({a.r, a.g, a.b}) < 0.2f) continue;
            if (glm::dot(a, color) / (la * lc) < 0.97f) continue;
            ++tinted;
            sum += glm::vec2(float(x), float(y));
        }
    const bool pass = tinted >= minPixels;
    const glm::vec2 mean = tinted ? sum / float(tinted) : glm::vec2(-1.0f);
    std::snprintf(buf, sizeof buf,
                  "[damage] label near (%.0f, %.0f): %zu px changed, %zu in the element colour (%.2f, %.2f, %.2f), "
                  "centroid (%.0f, %.0f)%s%s",
                  double(centre.x), double(centre.y), changed, tinted, double(color.r), double(color.g), double(color.b),
                  double(mean.x), double(mean.y), with.srgb ? " (sRGB capture)" : "",
                  pass ? "" : (" MISMATCH (need >= " + std::to_string(minPixels) + ")").c_str());
    report = buf;
    return pass;
}

} // namespace coe::game
