// SPDX-License-Identifier: Apache-2.0
#include "game/player/mana.hpp"

#include <algorithm>

namespace coe::game {

Mana::Mana(const ManaTuning& tuning)
    : tuning_(tuning), value_(double(tuning.max)), sinceSpend_(double(tuning.regenDelay)) {}

float Mana::regenRate() const { return std::max(0.0f, tuning_.regenPerSec + regenBonus_); }

void Mana::tick(float dt) {
    const double before = sinceSpend_;
    sinceSpend_ += double(dt);
    if (!tuning_.autoRegenerate) return;
    // Only the part of this tick past the delay regenerates. The epsilon keeps
    // 90 x (1/60 s) == 1.5 s despite float dt rounding (same as Breath).
    const double delay = double(tuning_.regenDelay) - 1e-7;
    const double regenTime = std::clamp(sinceSpend_ - std::max(before, delay), 0.0, double(dt));
    if (regenTime > 0.0) value_ = std::min(double(max()), value_ + double(regenRate()) * regenTime);
}

bool Mana::spend(float amount) {
    if (value_ < double(amount)) { ++refusals_; return false; }   // Magewar: no delay reset
    value_ -= double(amount);
    sinceSpend_ = 0.0;
    ++spends_;
    return true;
}

void Mana::setMaxBonus(float bonus) {
    const float delta = bonus - maxBonus_;
    maxBonus_ = bonus;
    if (delta > 0.0f) value_ += double(delta);
    value_ = std::clamp(value_, 0.0, double(max()));
}

} // namespace coe::game
