// SPDX-License-Identifier: Apache-2.0
// Loadout tests (BUILD_PLAN step 21): Staff + Wand slots, Weapon1/2 swaps.
// Done-check: a swap takes the equip time (0.4 s: 24 ticks at 60 Hz, 58 at 144 Hz) and no
// cast happens until it ends; casting uses the active slot's stats (element, damage,
// speed, range of the spawned bolt). Also: slot types are enforced, per-slot cooldowns
// keep running while holstered (no Magewar-style swap-cancel), select() edge cases.
#include "game/magic/casting.hpp"
#include "game/magic/loadout.hpp"
#include "game/magic/projectile.hpp"
#include "game/magic/wieldable.hpp"

#include <doctest/doctest.h>
#include <glm/glm.hpp>

#include <cmath>
#include <cstdio>
#include <string>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {

using namespace coe::game;

constexpr float kDt = 1.0f / 60.0f;
const CastAim kAim{{0, 1.5f, 0}, {0, 0, -1}, {}, {0.3f, -0.2f, -0.5f}};

WieldableTable loadReal() {
    WieldableTable t;
    const std::string err = loadWieldables(std::string(COE_DATA_DIR) + "/magic/wieldables.toml", t);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    REQUIRE(err.empty());
    return t;
}

// Ticks until the running swap ends, pressing Fire every tick; counts casts on the way.
int ticksToReady(Loadout& l, float dt, ProjectileSystem& bolts, int& castsDuring) {
    int n = 0;
    castsDuring = 0;
    while (l.swapping() && n < 10000) {
        if (l.tick(true, true, dt, kAim, bolts) && l.swapping()) ++castsDuring;
        ++n;
    }
    return n;
}

TEST_CASE("loadout: a swap takes the equip time and blocks casting until it ends") {
    const WieldableTable t = loadReal();
    const WieldableInstance staff(*t.find("apprentice_fire_staff")), wand(*t.find("novice_arcane_wand"));
    for (const float hz : {60.0f, 144.0f}) {
        CAPTURE(hz);
        const float dt = 1.0f / hz;
        Loadout l;
        CHECK((l.equip(Slot::Staff, &staff) && l.equip(Slot::Wand, &wand)));
        CHECK((l.active() == Slot::Staff && l.ready() && l.wieldable() == &staff && l.swapProgress() == 1.0f));
        ProjectileSystem bolts;
        CHECK(l.select(Slot::Wand));
        CHECK((l.swapping() && !l.ready() && l.active() == Slot::Wand && l.previous() == Slot::Staff));
        CHECK(l.swapProgress() == 0.0f);
        CHECK(l.wieldable() == &wand);   // the target's stats from the press
        // Every tick of the swap presses Fire: all refused, none cast.
        int n = 0;
        std::uint64_t spawnedDuring = 0;
        while (l.swapping() && n < 10000) {
            const bool cast = l.tick(true, true, dt, kAim, bolts);
            if (l.swapping()) spawnedDuring += cast ? 1 : 0;
            ++n;
        }
        const int want = int(std::ceil(0.4 * double(hz) - 1e-6));   // 24 at 60 Hz, 58 at 144 Hz
        CHECK(n == want);
        CHECK(spawnedDuring == 0);
        CHECK(l.swapBlocked() == std::uint64_t(want - 1));   // the last tick finishes the swap and casts
        CHECK(l.casts() == 1);   // ... on the tick the swap ends (timer runs before the press check)
        CHECK(l.swaps() == 1);
        std::printf("loadout: swap at %.0f Hz took %d ticks (%.3f s)\n", double(hz), n, double(float(n) * dt));
    }
}

TEST_CASE("loadout: casting uses the active slot's stats") {
    const WieldableTable t = loadReal();
    const WieldableInstance staff(*t.find("apprentice_fire_staff")), wand(*t.find("swift_wind_wand"));
    Loadout l;
    l.equip(Slot::Staff, &staff);
    l.equip(Slot::Wand, &wand);
    ProjectileSystem bolts;
    REQUIRE(l.tick(true, true, kDt, kAim, bolts));
    REQUIRE(bolts.live().size() == 1);
    const ProjectileSpawn& a = bolts.live().back().spawn;
    CHECK((a.element == Element::Fire && a.damage == staff.damage() && a.speed == 30.0f && a.range == 50.0f));
    CHECK((a.visualOffset == kAim.visualOffset && a.origin == kAim.origin));   // the viewmodel CastPoint rides along
    CHECK((l.caster(Slot::Staff).casts() == 1 && l.caster(Slot::Wand).casts() == 0));

    l.select(Slot::Wand);
    int during = 0;
    ticksToReady(l, kDt, bolts, during);   // the tick that ends the swap casts the wand
    CHECK(during == 0);
    REQUIRE(bolts.live().size() == 2);
    const ProjectileSpawn& b = bolts.live().back().spawn;
    CHECK((b.element == Element::Air && b.damage == wand.damage() && b.speed == 55.0f && b.range == 40.0f));
    CHECK((l.caster(Slot::Wand).casts() == 1 && l.caster().wieldable() == &wand && l.casts() == 2));
    // The wand's own 0.18 s cooldown now gates (11 ticks), not the staff's 0.4 s.
    int ticks = 0;
    while (!l.tick(true, true, kDt, kAim, bolts) && ticks < 100) ++ticks;
    CHECK(ticks + 1 == 11);
}

TEST_CASE("loadout: cooldowns are per slot and run while holstered (no swap-cancel)") {
    const WieldableTable t = loadReal();
    const WieldableInstance staff(*t.find("earthward_battlestaff")), wand(*t.find("novice_arcane_wand"));   // 0.55 s
    Loadout l;
    l.equip(Slot::Staff, &staff);
    l.equip(Slot::Wand, &wand);
    ProjectileSystem bolts;
    REQUIRE(l.tick(true, true, kDt, kAim, bolts));
    CHECK(std::fabs(l.caster(Slot::Staff).cooldownRemaining() - 0.55f) < 1e-5f);
    // Swap out and straight back (Magewar re-instanced the staff and reset its _fire_timer).
    CHECK(l.select(Slot::Wand));
    l.tick(false, false, kDt, kAim, bolts);
    CHECK(std::fabs(l.caster(Slot::Staff).cooldownRemaining() - (0.55f - kDt)) < 1e-5f);   // ticking while holstered
    CHECK(l.select(Slot::Staff));   // mid-swap retarget: restarts the timer
    CHECK((l.active() == Slot::Staff && l.previous() == Slot::Wand && l.swapProgress() == 0.0f && l.swaps() == 2));
    int during = 0;
    CHECK(ticksToReady(l, kDt, bolts, during) == 24);
    // 25 ticks gone, 0.55 s cooldown needs 33: the press on the swap's last tick was refused.
    CHECK((l.casts() == 1 && l.caster(Slot::Staff).blocked() == 1));
    CHECK(l.caster(Slot::Staff).cooldownRemaining() > 0.1f);
    int ticks = 0;
    while (!l.tick(true, true, kDt, kAim, bolts) && ticks < 100) ++ticks;
    CHECK(25 + ticks + 1 == 33);   // the full 0.55 s, swap or not
}

TEST_CASE("loadout: slot types, empty / same-slot selects, instant select, mana") {
    const WieldableTable t = loadReal();
    const WieldableInstance staff(*t.find("apprentice_fire_staff")), wand(*t.find("novice_arcane_wand"));
    Loadout l;
    CHECK(!l.equip(Slot::Staff, &wand));   // a wand can't go in the Staff slot
    CHECK(!l.equip(Slot::Wand, &staff));
    CHECK((l.inSlot(Slot::Staff) == nullptr && l.inSlot(Slot::Wand) == nullptr));
    CHECK((slotFor(WieldableType::Staff) == Slot::Staff && slotFor(WieldableType::Wand) == Slot::Wand));
    CHECK((std::string(slotName(Slot::Staff)) == "staff" && std::string(slotName(Slot::Wand)) == "wand"));

    ProjectileSystem bolts;
    CHECK(!l.tick(true, true, kDt, kAim, bolts));   // empty hands: nothing
    CHECK(l.equip(Slot::Staff, &staff));
    CHECK(!l.select(Slot::Wand));    // empty slot: no swap
    CHECK(!l.select(Slot::Staff));   // already held
    CHECK((l.swaps() == 0 && l.ready()));
    CHECK(l.equip(Slot::Wand, &wand));
    CHECK(l.select(Slot::Wand, true));   // instant (spawning): no timer, not counted
    CHECK((l.ready() && l.active() == Slot::Wand && l.swaps() == 0));
    CHECK(l.tick(true, true, kDt, kAim, bolts));

    // The mana spender reaches both slots; a refused cast costs no cooldown.
    float spent = 0.0f;
    bool allow = false;
    l.setManaSpender([&](float c) { if (allow) spent += c; return allow; });
    l.select(Slot::Staff, true);
    CHECK(!l.tick(true, true, kDt, kAim, bolts));
    CHECK((l.caster(Slot::Staff).manaRefused() == 1 && l.caster(Slot::Staff).cooldownRemaining() == 0.0f));
    allow = true;
    CHECK(l.tick(true, true, kDt, kAim, bolts));
    CHECK(spent == staff.manaCost());
    l.select(Slot::Wand, true);
    for (int i = 0; i < 30 && !l.tick(true, true, kDt, kAim, bolts); ++i) {}
    CHECK(spent == staff.manaCost() + wand.manaCost());
    l.setManaSpender(nullptr);
}

} // namespace
