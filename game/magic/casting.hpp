// SPDX-License-Identifier: Apache-2.0
// Casting (BUILD_PLAN step 17): the equipped staff/wand turns a Fire press into a spell
// projectile, gated by the wieldable's cooldown.
//
// Magewar reference (wieldable_staff.gd + Cogito's PlayerInteractionComponent, read-only):
// a cast happens on the Fire *press* (semi-auto: holding does not repeat); a press while
// the cooldown runs is ignored; a cast sets cooldown = final fire rate and the cooldown
// counts down every frame. Here it counts down per fixed tick *before* the press is
// checked, so at 60 Hz the Swift Wind Wand (0.18 s) casts at most every 11 ticks
// (0.183 s) and the Apprentice Fire Staff (0.4 s) every 24 ticks. holdToRepeat (off by
// default, an options toggle in step 44) re-casts while Fire is held.
// Mana (step 18, game/player/mana.hpp; Magewar: spent after the cooldown check, no mana =
// no cast and no cooldown) comes in through setManaSpender with the wieldable's manaCost().
// The bolt starts at the eye along the view so it goes where the crosshair points
// (Magewar spawns at the staff's CastPoint aimed at the camera ray's hit). Step 21: the
// viewmodel's CastPoint comes in as CastAim::visualOffset, so only the tracer starts
// there; per-slot casters and swaps live in game/magic/loadout.hpp.
#pragma once
#include "engine/physics/physics.hpp"
#include "game/magic/projectile.hpp"
#include "game/magic/wieldable.hpp"

#include <cstdint>
#include <functional>

namespace coe::game {

class PlayerController;

struct CastAim {
    glm::vec3 origin{0.0f};
    glm::vec3 direction{0.0f, 0.0f, -1.0f};
    physics::BodyHandle ignore;   // the caster's body (Character::innerBody())
    glm::vec3 visualOffset{0.0f}; // step 21: viewmodel CastPoint - origin (tracer only, see ProjectileSpawn)
};

// The player's aim after its last tick: from the eye (no head bob, so the shot doesn't
// wobble) along the look yaw/pitch, skipping its own inner body.
CastAim playerAim(const PlayerController& p);

class Caster {
public:
    Caster() = default;
    explicit Caster(const WieldableInstance& w) : wieldable_(&w) {}

    // Swaps the wieldable (nullptr = empty hands). The running cooldown is kept so a swap
    // cannot skip it.
    void equip(const WieldableInstance* w) { wieldable_ = w; }
    const WieldableInstance* wieldable() const { return wieldable_; }

    void setHoldToRepeat(bool on) { holdToRepeat_ = on; }
    // Step 18: called with the mana cost after the cooldown check; false = no cast and no
    // cooldown (covenant: [&](float c) { return player.mana().spend(c); }).
    void setManaSpender(std::function<bool(float)> spend) { spendMana_ = std::move(spend); }

    // One fixed tick. Returns true when a bolt was spawned into `out`.
    bool tick(bool firePressed, bool fireHeld, float dt, const CastAim& aim, ProjectileSystem& out);

    float cooldownRemaining() const { return float(cooldown_); }
    std::uint64_t casts() const { return casts_; }
    std::uint64_t blocked() const { return blocked_; }   // presses refused by the cooldown or mana
    std::uint64_t manaRefused() const { return manaRefused_; }   // of those, refused for mana

private:
    const WieldableInstance* wieldable_ = nullptr;
    std::function<bool(float)> spendMana_;
    double cooldown_ = 0.0;      // seconds left; double so 60 Hz ticks don't drift
    bool holdToRepeat_ = false;
    std::uint64_t casts_ = 0, blocked_ = 0, manaRefused_ = 0;
};

} // namespace coe::game
