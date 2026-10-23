// SPDX-License-Identifier: Apache-2.0
// Floating damage numbers (BUILD_PLAN step 22): one label per hit, at the impact point,
// coloured by the bolt's element (ElementTable::color, data/magic/elements.toml). Each
// rises kRise m and fades over kLifetime s; a weak-point crit draws larger, a strong
// (x1.5) hit slightly larger and a weak (x0.5) one smaller. Pure logic: labels() projects
// to pixels and the game draws them with the ImGui overlay (engine/ui/imgui_layer), so
// tests check positions/colours without a GPU.
//
// Magewar shows no damage numbers (its spell_projectile.gd only prints "Super
// Effective!" / "Not Very Effective..." to the log); these are a plan addition. Step 41's
// HUD adds hit markers and the effectiveness callouts from DamageResult::strong()/weak().
#pragma once
#include "game/combat/damage.hpp"
#include "game/combat/element.hpp"
#include "engine/render/vk_renderer.hpp"

#include <glm/glm.hpp>

#include <string>
#include <vector>

namespace coe::game {

struct DamageNumber {
    glm::vec3 world{0.0f};   // spawn point (impact)
    float amount = 0.0f;
    glm::vec3 color{1.0f};   // linear RGB (element colour)
    float age = 0.0f;
    float scale = 1.0f;      // 1 normal, kCritScale weak point, kStrongScale / kWeakScale
    float driftX = 0.0f;     // small sideways spread so stacked hits stay readable (m)
};

struct DamageLabel {
    glm::vec2 screen{0.0f};  // pixel centre (+y down)
    glm::vec3 color{1.0f};
    float alpha = 1.0f;
    float scale = 1.0f;
    std::string text;
};

class DamageNumbers {
public:
    static constexpr float kLifetime = 1.0f;     // s
    static constexpr float kRise = 0.8f;         // m over the lifetime
    static constexpr float kFadeStart = 0.6f;    // fraction of the lifetime before fading
    static constexpr float kCritScale = 1.5f;
    static constexpr float kStrongScale = 1.2f;
    static constexpr float kWeakScale = 0.85f;
    static constexpr std::size_t kMax = 64;      // oldest dropped beyond this

    void add(const glm::vec3& world, const DamageResult& r, Element element, const ElementTable& elements);
    void tick(float dt);
    void clear() { numbers_.clear(); }
    const std::vector<DamageNumber>& numbers() const { return numbers_; }

    // Visible labels for a camera: behind-camera points are skipped. `viewport` in pixels.
    void labels(const glm::mat4& viewProj, const glm::vec2& viewport, std::vector<DamageLabel>& out) const;

    static glm::vec3 position(const DamageNumber& n);   // current world position (rising)
    static float alpha(const DamageNumber& n);
    // "15", "7.5", "0" -- one decimal when not a whole number (rounded to 0.1).
    static std::string format(float amount);

private:
    std::vector<DamageNumber> numbers_;
    unsigned spawned_ = 0;
};

// Headless/window done-check: within `radius` px of `centre`, counts pixels that differ
// from the same frame rendered without the overlay (`without`) and point the same way
// in linear RGB as `color` (cos >= 0.97, decoded when the frame is sRGB) -- the drawn
// glyphs of a label. Passes with >= minPixels; `report` gets a one-line summary.
bool checkLabelPixels(const HeadlessFrame& with, const HeadlessFrame& without, const glm::vec2& centre, float radius,
                      const glm::vec3& color, std::size_t minPixels, std::string& report);

} // namespace coe::game
