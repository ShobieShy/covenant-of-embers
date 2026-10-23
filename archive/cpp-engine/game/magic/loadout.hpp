// SPDX-License-Identifier: Apache-2.0
// Loadout (BUILD_PLAN step 21): one Staff slot and one Wand slot; Weapon1 / Weapon2 pick
// which is held. A swap takes equipTime (0.4 s: the old one lowers for half, the new one
// raises for half) and blocks Fire and Aim until it ends.
//
// Magewar reference (read-only; wieldable_staff.gd / wieldable_wand.gd + Cogito's
// PlayerInteractionComponent and its inventory slots): the player carries one staff and
// one wand in typed equipment slots; switching plays the unequip then equip animation,
// and while `is_changing_wieldables` is set attack / secondary-action input is ignored.
// Reinterpreted here:
//  - The slot type is enforced (a wand can't go in the Staff slot); equip() refuses it.
//  - Each slot keeps its own Caster, so its cooldown is per weapon and keeps counting
//    down while holstered. Magewar resets the node's `_fire_timer` when the wieldable is
//    re-instanced on equip, so swap-cancelling skips the cooldown (an exploit) - logged
//    as a mismatch, fixed by design here.
//  - The active stats (cast, focus FOV, accuracy) are the selected slot's from the moment
//    of the press: the swap delay is the gate, not a window where the old weapon still
//    works. Selecting again mid-swap retargets and restarts the timer.
//  - Focus gets aimHeld && ready(): Aim held through a swap focuses once the swap ends
//    (Magewar left the camera zoomed when a swap interrupted ADS).
#pragma once
#include "game/magic/casting.hpp"
#include "game/magic/wieldable.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <functional>

namespace coe::game {

enum class Slot : std::uint8_t { Staff, Wand };
inline constexpr std::size_t kSlotCount = 2;
const char* slotName(Slot s);
// The slot a wieldable type belongs in.
constexpr Slot slotFor(WieldableType t) { return t == WieldableType::Staff ? Slot::Staff : Slot::Wand; }

struct LoadoutTuning {
    float equipTime = 0.4f;   // s for a whole swap (lower + raise)
};

class Loadout {
public:
    explicit Loadout(LoadoutTuning t = {});

    // Puts w in slot s (nullptr empties it). False (nothing changes) if w's type does not
    // belong in s. Equipping into the active slot takes effect at once (no swap).
    bool equip(Slot s, const WieldableInstance* w);
    const WieldableInstance* inSlot(Slot s) const { return casters_[index(s)].wieldable(); }

    // Starts a swap to s (instant: no swap time, for spawning). False (no-op) if s is
    // already the target or is empty.
    bool select(Slot s, bool instant = false);

    Slot active() const { return active_; }                       // the target of any swap
    Slot previous() const { return previous_; }                   // the slot being lowered in a swap
    const WieldableInstance* wieldable() const { return inSlot(active_); }   // active stats
    bool swapping() const { return swapLeft_ > 1e-9; }
    bool ready() const { return !swapping(); }
    // 0 at the press .. 1 when the swap is done (1 when not swapping).
    float swapProgress() const;
    const LoadoutTuning& tuning() const { return t_; }

    void setHoldToRepeat(bool on);
    void setManaSpender(const std::function<bool(float)>& spend);

    // One fixed tick: the swap timer and every slot's cooldown run down; then the active
    // slot casts if ready. Returns true when a bolt was spawned into `out`.
    bool tick(bool firePressed, bool fireHeld, float dt, const CastAim& aim, ProjectileSystem& out);

    const Caster& caster(Slot s) const { return casters_[index(s)]; }
    const Caster& caster() const { return casters_[index(active_)]; }
    std::uint64_t casts() const;                     // all slots
    std::uint64_t swaps() const { return swaps_; }
    std::uint64_t swapBlocked() const { return swapBlocked_; }   // Fire presses refused by a swap

private:
    static std::size_t index(Slot s) { return static_cast<std::size_t>(s); }
    LoadoutTuning t_;
    std::array<Caster, kSlotCount> casters_{};
    Slot active_ = Slot::Staff, previous_ = Slot::Staff;
    double swapLeft_ = 0.0;   // s; double so 60 Hz ticks don't drift
    std::uint64_t swaps_ = 0, swapBlocked_ = 0;
};

} // namespace coe::game
