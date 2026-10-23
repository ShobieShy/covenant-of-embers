// SPDX-License-Identifier: Apache-2.0
#include "game/magic/accuracy.hpp"

#include "engine/render/camera.hpp"
#include "game/player/player_controller.hpp"

#include <algorithm>
#include <cmath>

namespace coe::game {

float focusFovFor(WieldableType t, const FocusTuning& tuning) {
    return t == WieldableType::Wand ? tuning.wandFovDeg : tuning.staffFovDeg;
}

Focus::Focus(FocusTuning t)
    : t_(t), fov_(t.hipFovDeg), prevFov_(t.hipFovDeg), from_(t.hipFovDeg), target_(t.hipFovDeg),
      adsFov_(t.staffFovDeg) {}

void Focus::tick(bool aimHeld, const WieldableInstance* w, float dt) {
    prevFov_ = fov_;
    focused_ = aimHeld && w != nullptr;
    if (w) adsFov_ = focusFovFor(w->type(), t_);
    const double target = focused_ ? adsFov_ : double(t_.hipFovDeg);
    if (target != target_) {   // new tween from where the FOV is now (Godot tween_property)
        from_ = fov_;
        target_ = target;
        elapsed_ = 0.0;
    }
    if (fov_ == target_) return;
    elapsed_ += double(dt);
    const double k = t_.tweenSeconds > 0.0f ? elapsed_ / double(t_.tweenSeconds) : 1.0;
    fov_ = k >= 1.0 - 1e-9 ? target_ : from_ + (target_ - from_) * k;
}

float Focus::fov(float alpha) const { return float(prevFov_ + (fov_ - prevFov_) * double(alpha)); }

float Focus::amount() const {
    const double span = double(t_.hipFovDeg) - adsFov_;
    if (std::fabs(span) < 1e-9) return focused_ ? 1.0f : 0.0f;
    return float(std::clamp((double(t_.hipFovDeg) - fov_) / span, 0.0, 1.0));
}

float Focus::lookScale(float alpha) const { return Camera::lookScaleForFov(fov(alpha), t_.hipFovDeg); }

Stance stanceOf(const PlayerController& p, const Focus& f, const SpreadTuning& t) {
    Stance s;
    s.focus = f.amount();
    s.airborne = !p.onGround();
    s.crouched = p.crouched();
    s.moving = p.horizontalSpeed() > t.movingSpeed;
    return s;
}

float stanceMultiplier(const Stance& s, const SpreadTuning& t) {
    const float focus = 1.0f + (t.focusMul - 1.0f) * std::clamp(s.focus, 0.0f, 1.0f);
    float body = 1.0f;
    if (s.airborne) body = t.airborneMul;
    else {
        if (s.crouched) body *= t.crouchMul;
        if (s.moving) body *= t.movingMul;
    }
    return focus * body;
}

float spreadConeDeg(float accuracy, float stanceMul, float bloomDeg, const SpreadTuning& t) {
    const float miss = 1.0f - std::clamp(accuracy, 0.0f, 100.0f) / 100.0f;
    return (t.maxSpreadDeg + bloomDeg) * miss * stanceMul;
}

glm::vec3 coneDirection(glm::vec3 dir, float halfAngleRad, float u1, float u2) {
    if (halfAngleRad <= 0.0f) return dir;
    const float cosMax = std::cos(halfAngleRad);
    const float cosT = 1.0f - u1 * (1.0f - cosMax);
    const float sinT = std::sqrt(std::max(0.0f, 1.0f - cosT * cosT));
    const float phi = 6.2831853f * u2;
    const glm::vec3 helper = std::fabs(dir.y) < 0.99f ? glm::vec3(0, 1, 0) : glm::vec3(1, 0, 0);
    const glm::vec3 right = glm::normalize(glm::cross(dir, helper));
    const glm::vec3 up = glm::cross(right, dir);
    return glm::normalize(dir * cosT + (right * std::cos(phi) + up * std::sin(phi)) * sinT);
}

Spread::Spread(SpreadTuning t, std::uint64_t seed) : t_(t), rng_(seed) {}

float Spread::next01() {   // splitmix64 -> 24-bit float in [0, 1)
    std::uint64_t z = (rng_ += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    z ^= z >> 31;
    return float(z >> 40) * (1.0f / 16777216.0f);
}

void Spread::tick(float dt) {
    if (bloom_ <= 0.0) return;
    const double rate = t_.bloomRecoverySeconds > 0.0f ? double(t_.bloomMaxDeg) / double(t_.bloomRecoverySeconds) : 1e30;
    bloom_ -= rate * double(dt);
    if (bloom_ < 1e-6) bloom_ = 0.0;
}

void Spread::onCast() { bloom_ = std::min(double(t_.bloomMaxDeg), bloom_ + double(t_.bloomPerCastDeg)); }

float Spread::coneDeg(float accuracy, const Stance& s) const {
    return spreadConeDeg(accuracy, stanceMultiplier(s, t_), float(bloom_), t_);
}

CastAim Spread::apply(const CastAim& aim, float accuracy, const Stance& s) {
    lastCone_ = coneDeg(accuracy, s);
    const float u1 = next01(), u2 = next01();
    CastAim out = aim;
    out.direction = coneDirection(aim.direction, glm::radians(lastCone_), u1, u2);
    return out;
}

} // namespace coe::game
