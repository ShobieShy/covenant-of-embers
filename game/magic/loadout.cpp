// SPDX-License-Identifier: Apache-2.0
#include "game/magic/loadout.hpp"

#include <algorithm>

namespace coe::game {

const char* slotName(Slot s) { return s == Slot::Staff ? "staff" : "wand"; }

Loadout::Loadout(LoadoutTuning t) : t_(t) {}

bool Loadout::equip(Slot s, const WieldableInstance* w) {
    if (w && slotFor(w->type()) != s) return false;
    casters_[index(s)].equip(w);
    return true;
}

bool Loadout::select(Slot s, bool instant) {
    if (s == active_ || !inSlot(s)) return false;
    previous_ = active_;
    active_ = s;
    if (instant) { swapLeft_ = 0.0; return true; }
    swapLeft_ = double(t_.equipTime);
    ++swaps_;
    return true;
}

float Loadout::swapProgress() const {
    if (!swapping() || t_.equipTime <= 0.0f) return 1.0f;
    return float(std::clamp(1.0 - swapLeft_ / double(t_.equipTime), 0.0, 1.0));
}

void Loadout::setHoldToRepeat(bool on) {
    for (Caster& c : casters_) c.setHoldToRepeat(on);
}

void Loadout::setManaSpender(const std::function<bool(float)>& spend) {
    for (Caster& c : casters_) c.setManaSpender(spend);
}

bool Loadout::tick(bool firePressed, bool fireHeld, float dt, const CastAim& aim, ProjectileSystem& out) {
    swapLeft_ = std::max(0.0, swapLeft_ - double(dt));
    if (swapLeft_ <= 1e-9) swapLeft_ = 0.0;
    // Holstered cooldowns keep running (no fire input reaches them).
    for (std::size_t i = 0; i < kSlotCount; ++i)
        if (i != index(active_)) casters_[i].tick(false, false, dt, aim, out);
    Caster& c = casters_[index(active_)];
    if (swapping()) {
        c.tick(false, false, dt, aim, out);
        if (firePressed && c.wieldable()) ++swapBlocked_;
        return false;
    }
    return c.tick(firePressed, fireHeld, dt, aim, out);
}

std::uint64_t Loadout::casts() const {
    std::uint64_t n = 0;
    for (const Caster& c : casters_) n += c.casts();
    return n;
}

} // namespace coe::game
