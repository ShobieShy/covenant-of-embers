// SPDX-License-Identifier: Apache-2.0
#include "game/magic/casting.hpp"

#include "engine/render/camera.hpp"
#include "game/player/player_controller.hpp"

#include <algorithm>

namespace coe::game {

CastAim playerAim(const PlayerController& p) {
    Camera view;
    view.yaw = p.yaw();
    view.pitch = p.pitch();
    return {p.eyePosition(), view.forward(), p.character().innerBody()};
}

bool Caster::tick(bool firePressed, bool fireHeld, float dt, const CastAim& aim, ProjectileSystem& out) {
    cooldown_ = std::max(0.0, cooldown_ - double(dt));
    const bool want = firePressed || (holdToRepeat_ && fireHeld);
    if (!want || !wieldable_) return false;
    if (cooldown_ > 1e-9) { if (firePressed) ++blocked_; return false; }
    if (spendMana_ && !spendMana_(wieldable_->manaCost())) { if (firePressed) ++blocked_; return false; }
    cooldown_ = double(wieldable_->cooldown());
    ProjectileSpawn s;
    s.origin = aim.origin;
    s.direction = aim.direction;
    s.speed = wieldable_->projectileSpeed();
    s.range = wieldable_->range();
    s.element = wieldable_->element();
    s.damage = wieldable_->damage();
    s.ignore = aim.ignore;
    out.spawn(s);
    ++casts_;
    return true;
}

} // namespace coe::game
