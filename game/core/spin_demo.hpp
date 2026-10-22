// SPDX-License-Identifier: Apache-2.0
// Placeholder game state for M1 step 8: the triangle's rotation is simulated on
// the 60 Hz fixed tick and rendered interpolated between the last two ticks.
// Replaced by real gameplay state (player, weapons) from step 14 on.
#pragma once
#include <cmath>

namespace coe::game {

struct SpinDemo {
    static constexpr double kRadPerSecond = 0.75;
    double prev = 0.0, curr = 0.0;   // unwrapped radians at the last two ticks

    void tick(double dt) { prev = curr; curr += kRadPerSecond * dt; }

    // Interpolated angle for rendering, wrapped to [0, 2pi) after blending so the
    // wrap point never produces a backwards spin.
    float renderAngle(double alpha) const {
        constexpr double kTwoPi = 6.283185307179586;
        return static_cast<float>(std::fmod(prev + (curr - prev) * alpha, kTwoPi));
    }
};

} // namespace coe::game
