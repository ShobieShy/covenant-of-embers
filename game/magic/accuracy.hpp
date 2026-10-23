// SPDX-License-Identifier: Apache-2.0
// Focus (ADS), accuracy and spread (BUILD_PLAN step 19, PLAN §30.1).
//
// Focus follows Magewar's wieldable_staff.gd action_secondary (read-only reference; the
// weapon design is followed directly, approved 2026-10-22): holding Aim tweens the camera
// FOV from wherever it is to the wieldable's ads_fov over 0.2 s (Godot tween_property,
// linear), releasing tweens it back to 75 deg over 0.2 s. Staffs *and* wands use 55 deg:
// Magewar's wieldable_wand.tscn runs wieldable_staff.gd without an ads_fov override (65 deg
// is Cogito's toy pistol / laser rifle, not a Magewar wand). The values stay per type so
// they can diverge later. Here the tween advances per fixed tick (double elapsed time, so
// 12 ticks at 60 Hz land exactly on 55 deg) and the render FOV is interpolated between
// the last two ticks. Not from Magewar (plan choices): mouse look is scaled by
// tan(fov/2) / tan(hip/2) (Camera::lookScaleForFov) and the viewmodel keeps a fixed 75 deg
// (Camera::kViewmodelFovYDeg, step 21).
//
// Accuracy is Magewar's get_final_accuracy (WieldableInstance::accuracy(): 50 + Head +
// Handle + Charm, clamped 0..100). Magewar only shows it in the stats summary; turning it
// into a spread cone is our design:
//   cone half-angle = (maxSpreadDeg + bloom) x (1 - accuracy/100) x stance
//   stance = lerp(1, focus 0.35, focus amount) x (airborne 1.8 | crouch 0.8 x moving 1.3)
// The focus amount follows the FOV tween (0 at 75 deg, 1 at the ads FOV), so a quick tap
// of Aim doesn't give full focus accuracy. Each cast adds bloomPerCastDeg (capped at
// bloomMaxDeg) which decays linearly, so a full bloom is gone bloomRecoverySeconds after
// the last cast. 100 % accuracy is a perfect line whatever the stance or bloom.
// Directions are drawn uniformly over the cone's spherical cap from a seeded splitmix64
// stream (deterministic; same seed => same shots).
#pragma once
#include "game/magic/casting.hpp"
#include "game/magic/wieldable.hpp"

#include <glm/glm.hpp>

#include <cstdint>

namespace coe::game {

class PlayerController;

struct FocusTuning {
    float hipFovDeg = 75.0f;     // Camera::kDefaultFovYDeg; Magewar tweens back to 75
    float staffFovDeg = 55.0f;   // wieldable_staff.gd ads_fov
    float wandFovDeg = 55.0f;    // wieldable_wand.tscn: same script, no override
    float tweenSeconds = 0.2f;   // both directions
};

float focusFovFor(WieldableType t, const FocusTuning& tuning = {});

class Focus {
public:
    explicit Focus(FocusTuning t = {});

    // One fixed tick. aimHeld = the Aim action is held; w = the equipped wieldable
    // (nullptr = empty hands: no focus). A change of target (press, release, swapping to a
    // wieldable with another ads FOV) starts a new 0.2 s tween from the current FOV.
    void tick(bool aimHeld, const WieldableInstance* w, float dt);

    bool focused() const { return focused_; }                // aiming with a wieldable
    float fov() const { return float(fov_); }                 // after the last tick
    float fov(float alpha) const;                             // render: between the last two ticks
    float targetFov() const { return float(target_); }
    // 0 at the hip FOV .. 1 at the focused FOV, from the current tween position.
    float amount() const;
    float lookScale(float alpha) const;                       // tan(fov/2) / tan(hip/2)
    const FocusTuning& tuning() const { return t_; }

private:
    FocusTuning t_;
    double fov_, prevFov_, from_, target_, elapsed_ = 0.0;
    double adsFov_;               // focused FOV of the last wieldable (for amount())
    bool focused_ = false;
};

struct SpreadTuning {
    float maxSpreadDeg = 4.0f;         // s_max: cone half-angle at 0 % accuracy, hip, still
    float focusMul = 0.35f;            // fully focused
    float crouchMul = 0.8f;            // crouched on the ground (also while sliding)
    float movingMul = 1.3f;            // on the ground above movingSpeed
    float airborneMul = 1.8f;          // not on the ground (replaces crouch/moving)
    float movingSpeed = 0.5f;          // m/s horizontal
    float bloomPerCastDeg = 1.0f;      // added to s_max per cast (so x (1 - acc/100) too)
    float bloomMaxDeg = 4.0f;          // cap: spamming at most doubles the cone
    float bloomRecoverySeconds = 0.5f; // a full bloom decays to 0 in this time (linear)
};

struct Stance {
    float focus = 0.0f;   // Focus::amount()
    bool crouched = false, moving = false, airborne = false;
};

Stance stanceOf(const PlayerController& p, const Focus& f, const SpreadTuning& t = {});
float stanceMultiplier(const Stance& s, const SpreadTuning& t = {});
// Cone half-angle in degrees for an accuracy (0..100, clamped), stance multiplier and bloom.
float spreadConeDeg(float accuracy, float stanceMul, float bloomDeg, const SpreadTuning& t = {});
// A direction inside the cone around unit `dir`; u1, u2 in [0, 1) pick it uniformly over
// the spherical cap (u1 -> polar angle, u2 -> azimuth). halfAngleRad 0 returns dir as is.
glm::vec3 coneDirection(glm::vec3 dir, float halfAngleRad, float u1, float u2);

class Spread {
public:
    explicit Spread(SpreadTuning t = {}, std::uint64_t seed = 0x434F45ull);

    // Per fixed tick, before casting: bloom decays.
    void tick(float dt);
    // The aim with its direction spread for this accuracy/stance (+ the current bloom).
    // Draws two random numbers per call. lastConeDeg() = the cone used.
    CastAim apply(const CastAim& aim, float accuracy, const Stance& s);
    // After a successful cast: bloom grows.
    void onCast();

    float bloomDeg() const { return float(bloom_); }
    float coneDeg(float accuracy, const Stance& s) const;
    float lastConeDeg() const { return lastCone_; }
    const SpreadTuning& tuning() const { return t_; }

private:
    float next01();
    SpreadTuning t_;
    std::uint64_t rng_;
    double bloom_ = 0.0;
    float lastCone_ = 0.0f;
};

} // namespace coe::game
