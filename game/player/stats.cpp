// SPDX-License-Identifier: Apache-2.0
#include "game/player/stats.hpp"

#include <algorithm>

namespace coe::game {

Breath::Breath(const BreathTuning& tuning)
    : tuning_(tuning), value_(tuning.max), sinceUse_(double(tuning.regenDelay)) {}

void Breath::tick(bool draining, float dt) {
    if (draining) {
        value_ = std::max(0.0f, value_ - tuning_.drainPerSec * dt);
        sinceUse_ = 0.0;
        if (value_ <= 0.0f) exhausted_ = true;
        return;
    }
    const double before = sinceUse_;
    sinceUse_ += double(dt);
    // Only the part of this tick past the delay regenerates. A tiny epsilon keeps
    // 60 x (1/60 s) == 1 s despite float dt rounding.
    const double delay = double(tuning_.regenDelay) - 1e-7;
    const double regenTime = std::clamp(sinceUse_ - std::max(before, delay), 0.0, double(dt));
    if (regenTime > 0.0) value_ = std::min(max(), value_ + float(double(tuning_.regenPerSec) * regenTime));
    if (exhausted_ && value_ >= std::min(tuning_.resumeAt, max())) exhausted_ = false;
}

bool Breath::spend(float amount) {
    if (value_ < amount) return false;
    value_ -= amount;
    sinceUse_ = 0.0;
    if (value_ <= 0.0f) exhausted_ = true;
    return true;
}

void Breath::setMaxBonus(float bonus) {
    maxBonus_ = bonus;
    value_ = std::min(value_, max());
}

} // namespace coe::game
