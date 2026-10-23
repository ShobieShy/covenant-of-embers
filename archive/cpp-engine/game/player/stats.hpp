// SPDX-License-Identifier: Apache-2.0
// Player resource pools (BUILD_PLAN step 15): Breath, the sprint/dash pool (PLAN §30.8).
//
// Reinterprets Magewar's CogitoStaminaAttribute (read-only reference; 30 max, 3/s run
// drain, 2/s regen after 2 s, a jump costs 5) with our own numbers: 100 max, -20/s
// while sprinting, +30/s once 1 s has passed since the last drain or spend. Like
// Magewar, regen pauses while draining and restarts its delay afterwards; equipment
// (Belt/Shoes, step 30) and level-ups (step 38) raise the max through setMaxBonus().
// Deliberate deviation: Magewar re-allows sprint as soon as stamina > 0, which
// stutters (drain to 0, regen a sliver, sprint a frame, ...). Here an emptied pool is
// "exhausted" until it regains `resumeAt` (20 = 1 s of sprint); resumeAt 0 = Magewar.
#pragma once

namespace coe::game {

struct BreathTuning {
    float max = 100.0f;          // PLAN §30.8 base Breath
    float drainPerSec = 20.0f;   // while sprinting
    float regenPerSec = 30.0f;
    float regenDelay = 1.0f;     // seconds since the last drain/spend before regen starts
    float resumeAt = 20.0f;      // after running dry, sprint needs this much back
};

class Breath {
public:
    explicit Breath(const BreathTuning& tuning = {});

    // One fixed tick. `draining`: the player is sprinting this tick (costs drainPerSec*dt,
    // floored at 0). Otherwise time since the last drain grows and regen runs once it
    // passes regenDelay (the part of the tick after the delay counts, so timing is exact
    // to the sub-tick).
    void tick(bool draining, float dt);
    // Instant cost (step 16 dash: 25). Fails (no change) if value < amount; resets the delay.
    bool spend(float amount);

    float value() const { return value_; }
    float max() const { return tuning_.max + maxBonus_; }
    float fraction() const { return max() > 0.0f ? value_ / max() : 0.0f; }
    bool empty() const { return value_ <= 0.0f; }
    // True from running dry until value >= resumeAt: sprint is refused meanwhile.
    bool exhausted() const { return exhausted_; }
    bool canSprint() const { return !exhausted_ && value_ > 0.0f; }
    double secondsSinceUse() const { return sinceUse_; }
    bool regenerating() const { return sinceUse_ >= tuning_.regenDelay && value_ < max(); }

    // Equipment / level bonus to the max (Magewar stamina_bonus, _level_up +5). Value
    // is clamped to the new max; raising the max does not refill.
    void setMaxBonus(float bonus);
    void refill() { value_ = max(); exhausted_ = false; }
    const BreathTuning& tuning() const { return tuning_; }

private:
    BreathTuning tuning_;
    float maxBonus_ = 0.0f;
    float value_;
    double sinceUse_;   // seconds since the last drain/spend (double: no drift over long runs)
    bool exhausted_ = false;
};

} // namespace coe::game
