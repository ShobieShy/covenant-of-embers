// SPDX-License-Identifier: Apache-2.0
#include "game/player/camera_feel.hpp"

#include <algorithm>
#include <cmath>

namespace coe::game {

void CameraFeel::setReducedMotion(bool on) {
    reduced_ = on;
    if (on) {   // snap: nothing may move the view
        bob_ = prev_ = glm::vec2(0.0f);
        dip_ = 0.0f;
        dipTime_ = -1.0;
    }
}

void CameraFeel::tick(const CameraFeelInput& in, float dt) {
    prev_ = offset();
    if (reduced_) {
        bob_ = glm::vec2(0.0f);
        dip_ = 0.0f;
        dipTime_ = -1.0;
        return;
    }

    // Head bob (Magewar wiggle), eased toward its target at LERP_SPEED.
    glm::vec2 target(0.0f);
    if (in.bobbing && bobScale_ > 0.0f) {
        float intensity = tuning_.walkIntensity, rate = tuning_.walkRate;
        if (in.gait == Gait::Sprint) { intensity = tuning_.sprintIntensity; rate = tuning_.sprintRate; }
        else if (in.gait == Gait::Crouch) { intensity = tuning_.crouchIntensity; rate = tuning_.crouchRate; }
        intensity *= bobScale_;
        phase_ = std::fmod(phase_ + rate * dt, 4.0f * 3.14159265f);   // sin(phase/2) has period 4 pi
        target = {std::sin(phase_ * 0.5f) * intensity, std::sin(phase_) * intensity * 0.5f};
    }
    bob_ = glm::mix(bob_, target, std::min(1.0f, dt * tuning_.lerpSpeed));
    if (!in.bobbing && glm::length(bob_) < 1e-5f) bob_ = glm::vec2(0.0f);

    // Landing dip.
    if (in.landed && in.landingSpeed >= tuning_.landMinSpeed) {
        const float k = std::clamp((in.landingSpeed - tuning_.landMinSpeed) /
                                   (tuning_.landMaxSpeed - tuning_.landMinSpeed), 0.0f, 1.0f);
        const float depth = tuning_.maxDip * k;
        if (depth > 0.0f) {
            dipDepth_ = depth;
            dipTime_ = 0.0;
        }
    }
    dip_ = 0.0f;
    if (dipTime_ >= 0.0) {
        dipTime_ += double(dt);
        const double down = double(tuning_.dipDownTime), total = double(tuning_.dipTotalTime);
        const double pi = 3.141592653589793;
        if (dipTime_ >= total) dipTime_ = -1.0;
        else if (dipTime_ < down) dip_ = -dipDepth_ * float(std::sin(0.5 * pi * dipTime_ / down));
        else dip_ = -dipDepth_ * float(0.5 * (1.0 + std::cos(pi * (dipTime_ - down) / (total - down))));
    }
}

} // namespace coe::game
