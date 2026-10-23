// SPDX-License-Identifier: Apache-2.0
// Placeholder game state for M1 (step 10's CubeDemo, renamed in step 11 when the cube
// became a loaded glTF model): the model tumbles on the 60 Hz fixed tick and is
// rendered interpolated between the last two ticks (lerp by alpha, wrapped after
// blending). Replaced by the greybox level (step 12) and real gameplay state from
// step 14 on.
#pragma once
#include <cmath>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

namespace coe::game {

struct TumbleDemo {
    static constexpr double kYawRadPerSecond = 0.75;
    static constexpr double kPitchRadPerSecond = 0.45;
    // Start tilted so several surfaces (different light angles) face the camera.
    static constexpr double kStartYaw = 0.6, kStartPitch = 0.45;
    static constexpr float kDistance = 2.2f;   // model centre, metres in front of the start camera

    double prevYaw = kStartYaw, currYaw = kStartYaw;         // unwrapped radians at the last two ticks
    double prevPitch = kStartPitch, currPitch = kStartPitch;

    void tick(double dt) {
        prevYaw = currYaw; prevPitch = currPitch;
        currYaw += kYawRadPerSecond * dt;
        currPitch += kPitchRadPerSecond * dt;
    }

    // Interpolated angles, wrapped to [0, 2pi) after blending so the wrap point
    // never produces a backwards spin.
    static double blend(double a, double b, double alpha) {
        constexpr double kTwoPi = 6.283185307179586;
        return std::fmod(a + (b - a) * alpha, kTwoPi);
    }
    float renderYaw(double alpha) const { return float(blend(prevYaw, currYaw, alpha)); }
    float renderPitch(double alpha) const { return float(blend(prevPitch, currPitch, alpha)); }

    glm::mat4 renderModel(double alpha) const {
        glm::mat4 m = glm::translate(glm::mat4(1.0f), glm::vec3(0.0f, 0.0f, -kDistance));
        m = glm::rotate(m, renderYaw(alpha), glm::vec3(0, 1, 0));
        return glm::rotate(m, renderPitch(alpha), glm::vec3(1, 0, 0));
    }
};

} // namespace coe::game
