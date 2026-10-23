// SPDX-License-Identifier: Apache-2.0
#include "game/player/dash.hpp"

#include <algorithm>

namespace coe::game {

namespace {
constexpr double kEps = 1e-6;   // float dt sums: 9 x (1/60 s) must end a 0.15 s dash exactly
}

Dash::Dash(const DashTuning& tuning) : tuning_(tuning), charges_(tuning.charges) {}

bool Dash::tryStart(const glm::vec3& dir, bool grounded, Breath& breath) {
    const glm::vec3 flat(dir.x, 0.0f, dir.z);
    const float len = glm::length(flat);
    if (active() || charges_ <= 0 || len < 1e-6f) return false;
    if (!grounded && !airDashAvailable()) return false;
    if (!breath.spend(tuning_.breathCost)) return false;   // short (or exhausted): refused, no cost
    dir_ = flat / len;
    timeLeft_ = double(tuning_.duration);
    invulnLeft_ = double(tuning_.invulnerability);
    invulnTick_ = invulnLeft_ > 0.0;
    if (charges_ == maxCharges()) recharge_ = 0.0;   // the first spent charge starts the clock
    --charges_;
    if (!grounded) ++airDashesUsed_;
    ++dashes_;
    return true;
}

float Dash::advance(float dt) {
    const double step = double(dt);
    float covered = 0.0f;
    if (timeLeft_ > 0.0) {
        const double c = std::min(timeLeft_, step);
        timeLeft_ -= c;
        if (timeLeft_ < kEps) timeLeft_ = 0.0;
        covered = float(std::min(1.0, c / step));
    }
    invulnTick_ = invulnLeft_ > 0.0;
    if (invulnLeft_ > 0.0) {
        invulnLeft_ -= step;
        if (invulnLeft_ < kEps) invulnLeft_ = 0.0;
    }
    if (charges_ < maxCharges()) {
        recharge_ += step;
        const double t = double(tuning_.rechargeSeconds);
        while (charges_ < maxCharges() && recharge_ >= t - kEps) {
            ++charges_;
            recharge_ = std::max(0.0, recharge_ - t);
        }
        if (charges_ >= maxCharges()) recharge_ = 0.0;
    }
    return covered;
}

void Dash::setBonusCharges(int n) {
    bonusCharges_ = std::max(0, n);
    charges_ = std::min(charges_, maxCharges());
    if (charges_ >= maxCharges()) recharge_ = 0.0;
}

} // namespace coe::game
