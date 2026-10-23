// SPDX-License-Identifier: Apache-2.0
// Dash (BUILD_PLAN step 16, PLAN §30.8): 6 m in 0.15 s, 2 charges, 25 Breath, 0.1 s
// i-frames, usable once in the air.
//
// Magewar has no dash (cogito_player/magewar_player only sprint, slide and bunny-hop),
// so this is our own verb on top of the reinterpreted controller:
//   * tryStart(): refused (and nothing is spent) while a dash is running, with no charge
//     left, in the air once the air dash is used, or when Breath::spend(25) refuses
//     (value < 25, which also covers an exhausted pool: exhausted means < 20). spend()
//     restarts Breath's 1 s regen delay.
//   * advance(dt), once per fixed tick: returns the fraction of this tick the dash
//     covers (1 on full ticks, the remainder on the last one, 0 when idle), so the
//     distance is exactly speed() x duration at any tick rate. PlayerController blends
//     the horizontal velocity: dash x fraction + normal x (1 - fraction); the character
//     sweep (Jolt CharacterVirtual) still collides, so walls stop it.
//   * Charges recharge one at a time, 1.5 s each, starting when the first one is spent
//     (PLAN §30.8 gives no time; 1.5 s keeps 2 back-to-back dashes = 50 Breath and a
//     ~3 s full refill, so Breath stays the real limiter while sprinting).
//   * The air dash is consumed by a dash started off the ground and given back on landing
//     (land()); a dash started on the ground that carries off a ledge doesn't use it.
//   * setBonusCharges(): hook for a 3rd charge (PLAN §30.8 "Sandals"; gear/Consecration).
#pragma once
#include "game/player/stats.hpp"

#include <glm/glm.hpp>

#include <cstdint>

namespace coe::game {

struct DashTuning {
    float distance = 6.0f;           // m
    float duration = 0.15f;          // s (speed = 40 m/s)
    int charges = 2;
    float breathCost = 25.0f;
    float invulnerability = 0.1f;    // i-frames from the dash start, s
    float rechargeSeconds = 1.5f;    // per charge, one at a time (our choice, see above)
    int airDashes = 1;               // per airborne stretch
};

class Dash {
public:
    explicit Dash(const DashTuning& tuning = {});

    // `dir`: horizontal direction (normalised here; zero length is refused).
    bool tryStart(const glm::vec3& dir, bool grounded, Breath& breath);
    // One fixed tick (call every tick, dashing or not): advances the dash, i-frames and
    // recharge. Returns the fraction of this tick covered by the dash, in [0, 1].
    float advance(float dt);
    void land() { airDashesUsed_ = 0; }   // touched the ground: the air dash is back

    bool active() const { return timeLeft_ > 0.0; }
    // I-frames cover every tick that starts within 0.1 s of the dash start (6 at 60 Hz);
    // step 24's damage check reads this after the controller's tick.
    bool invulnerable() const { return invulnTick_; }
    int charges() const { return charges_; }
    int maxCharges() const { return tuning_.charges + bonusCharges_; }
    // Progress of the charge currently recharging, [0, 1) (0 when full).
    float rechargeProgress() const { return float(recharge_ / double(tuning_.rechargeSeconds)); }
    bool airDashAvailable() const { return airDashesUsed_ < tuning_.airDashes; }
    glm::vec3 direction() const { return dir_; }
    float speed() const { return tuning_.distance / tuning_.duration; }
    std::uint64_t dashes() const { return dashes_; }
    void setBonusCharges(int n);
    const DashTuning& tuning() const { return tuning_; }

private:
    DashTuning tuning_;
    int bonusCharges_ = 0;
    int charges_;
    double recharge_ = 0.0;     // seconds into the current charge's recharge
    double timeLeft_ = 0.0;     // of the running dash
    double invulnLeft_ = 0.0;
    bool invulnTick_ = false;   // this tick started inside the i-frame window
    int airDashesUsed_ = 0;
    glm::vec3 dir_{0.0f};
    std::uint64_t dashes_ = 0;
};

} // namespace coe::game
