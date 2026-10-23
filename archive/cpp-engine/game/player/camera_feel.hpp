// SPDX-License-Identifier: Apache-2.0
// Camera feel (BUILD_PLAN step 16, PLAN §30 "Feel"): head bob and landing dip as an eye
// offset that PlayerController::camera() adds on top of the eased crouch eye height.
//
// Head bob reinterprets Magewar's cogito_player "wiggle" (read-only reference):
//   * a phase advances while grounded with a move key held and not sliding/dashing, at
//     12 rad/s walking, 16 sprinting, 8 crouched; target offset y = sin(phase) x I / 2,
//     x (along the view's right) = sin(phase / 2) x I, with intensity I 0.03 / 0.05 /
//     0.08 m, eased toward the target (and back to 0 when not bobbing) at LERP_SPEED 10/s.
//   * deliberate changes: Magewar's sway is sin(phase/2) + 0.5, a constant 0.5 x I shift
//     to the right while walking; ours is centred. Magewar's HEADBOBBLE strength scales
//     walk/sprint only; our bobScale scales all three (and 0 = off).
// Landing dip (Magewar plays a 0.3 s "landing" camera-tilt animation at <= -5 m/s and a
// head drop + roll at <= -7.5 m/s; we use one positional dip instead, no roll):
//   * on landing at impact speed s >= 2 m/s (Magewar's landing_threshold), the eye drops
//     by maxDip x clamp((s - 2) / (8 - 2), 0, 1) (Magewar's min/max landing velocity),
//     0.12 m at 8 m/s: ease-out down over 0.1 s, cosine back up by 0.3 s (the Magewar
//     animation's keys).
// Reduced motion (PLAN §26 accessibility; option persisted by step 44): no bob, no dip;
// the offset is exactly zero.
#pragma once
#include <glm/glm.hpp>

namespace coe::game {

enum class Gait { Walk, Sprint, Crouch };

struct CameraFeelTuning {
    float walkIntensity = 0.03f, walkRate = 12.0f;      // WIGGLE_ON_WALKING_*
    float sprintIntensity = 0.05f, sprintRate = 16.0f;  // WIGGLE_ON_SPRINTING_*
    float crouchIntensity = 0.08f, crouchRate = 8.0f;   // WIGGLE_ON_CROUCHING_*
    float lerpSpeed = 10.0f;                            // LERP_SPEED
    float landMinSpeed = 2.0f;                          // landing_threshold / min_landing_velocity
    float landMaxSpeed = 8.0f;                          // max_landing_velocity
    float maxDip = 0.12f;                               // m at landMaxSpeed
    float dipDownTime = 0.1f, dipTotalTime = 0.3f;      // "landing" animation keys
};

struct CameraFeelInput {
    bool bobbing = false;     // grounded, move key held, not sliding or dashing
    Gait gait = Gait::Walk;
    bool landed = false;      // this tick touched down after being airborne
    float landingSpeed = 0;   // downward speed at touch-down, m/s (positive)
};

class CameraFeel {
public:
    explicit CameraFeel(const CameraFeelTuning& tuning = {}) : tuning_(tuning) {}

    void tick(const CameraFeelInput& in, float dt);

    // Eye offset after the last tick: x along the view's right, y up (bob + dip).
    glm::vec2 offset() const { return bob_ + glm::vec2(0.0f, dip_); }
    // Interpolated between the last two ticks (like the feet/eye in camera(alpha)).
    glm::vec2 offset(float alpha) const { return glm::mix(prev_, offset(), alpha); }
    glm::vec2 bob() const { return bob_; }
    float dip() const { return dip_; }   // <= 0
    float landingDepth() const { return dipDepth_; }   // depth of the current/last dip

    void setReducedMotion(bool on);
    bool reducedMotion() const { return reduced_; }
    void setBobScale(float s) { bobScale_ = s < 0.0f ? 0.0f : s; }
    float bobScale() const { return bobScale_; }
    const CameraFeelTuning& tuning() const { return tuning_; }

private:
    CameraFeelTuning tuning_;
    bool reduced_ = false;
    float bobScale_ = 1.0f;     // Magewar HEADBOBBLE (options slider later)
    float phase_ = 0.0f;
    glm::vec2 bob_{0.0f}, prev_{0.0f};
    float dip_ = 0.0f, dipDepth_ = 0.0f;
    double dipTime_ = -1.0;     // seconds since the landing, < 0 = no dip running
};

} // namespace coe::game
