// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/player/mana (BUILD_PLAN step 18): Magewar's ManaAttribute numbers
// (100 max, regen 3/s after 1.5 s since the last cast, equipment regen bonus) and the
// Caster::setManaSpender hook. Done-check:
//  - 20 casts of the 5-mana Apprentice Fire Staff empty 100 mana and the 21st is refused
//    (no bolt, no cooldown; it casts on the first tick the pool is back at 5);
//  - spend refuses when value < cost (equal is fine) and a refusal doesn't restart the delay;
//  - regen starts exactly 1.5 s after the last cast and refills at 3/s, at 30/60/144 Hz;
//    a cast inside the delay restarts it; empty -> full in 1.5 + 100/3 s;
//  - the equipment regen bonus adds (Novice Grimoire +0.5 -> 3.5/s); max bonus follows
//    Magewar's equip (raise max and current, removal clamps); refill; auto_regenerate off;
//  - the PlayerController regenerates its pool once per tick().
// Plain checks; doctest in step 20.
#include "engine/physics/physics.hpp"
#include "game/magic/casting.hpp"
#include "game/magic/projectile.hpp"
#include "game/magic/wieldable.hpp"
#include "game/player/mana.hpp"
#include "game/player/player_controller.hpp"

#include <cmath>
#include <cstdio>
#include <string>
#include <tuple>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using namespace coe::game;
constexpr float kDt = 1.0f / 60.0f;

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }
void ticks(Mana& m, int n, float dt = kDt) { for (int i = 0; i < n; ++i) m.tick(dt); }

WieldableTable loadReal() {
    WieldableTable t;
    const std::string err = loadWieldables(std::string(COE_DATA_DIR) + "/magic/wieldables.toml", t);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    CHECK(err.empty());
    return t;
}

void basics() {
    Mana m;
    CHECK(m.value() == 100.0f && m.max() == 100.0f && m.fraction() == 1.0f);
    CHECK(m.tuning().regenPerSec == 3.0f && m.tuning().regenDelay == 1.5f && m.regenRate() == 3.0f);
    CHECK(!m.regenerating());   // full
    for (int i = 0; i < 20; ++i) CHECK(m.spend(5.0f));
    CHECK(m.value() == 0.0f && m.spends() == 20);
    CHECK(!m.spend(5.0f) && m.value() == 0.0f && m.refusals() == 1);
    // Refused when short; exactly enough is fine (Magewar: value_current < amount).
    Mana s;
    CHECK(s.spend(96.0f) && s.value() == 4.0f);
    CHECK(!s.spend(5.0f) && s.value() == 4.0f && s.has(4.0f) && !s.has(4.5f));
    CHECK(s.spend(4.0f) && s.value() == 0.0f);
    // Magewar's other bases: Swift Wind 2.5 -> 40 casts, Earthward 6 -> 16 casts (4 left).
    const WieldableTable t = loadReal();
    for (const auto& [id, n, left] : {std::tuple{"swift_wind_wand", 40, 0.0f}, std::tuple{"earthward_battlestaff", 16, 4.0f},
                                      std::tuple{"novice_arcane_wand", 33, 1.0f}}) {
        const WieldableDef* d = t.find(id);
        CHECK(d != nullptr);
        if (!d) continue;
        Mana w;
        int casts = 0;
        while (w.spend(d->manaCost)) ++casts;
        std::printf("mana: %s (%.1f/cast) -> %d casts, %.2f left\n", id, double(d->manaCost), casts, double(w.value()));
        CHECK(casts == n && near(w.value(), left, 1e-5f));
    }
}

// 20 casts of the Apprentice Fire Staff through the real Caster hook, Fire pressed every
// tick at 60 Hz: one cast per 0.4 s cooldown (24 ticks), no regen in between (< 1.5 s).
void twentyCasts() {
    const WieldableTable t = loadReal();
    const WieldableDef* staffDef = t.find("apprentice_fire_staff");
    CHECK(staffDef && staffDef->manaCost == 5.0f);
    if (!staffDef) return;
    const WieldableInstance staff(*staffDef);
    Mana m;
    Caster c(staff);
    c.setManaSpender([&](float cost) { return m.spend(cost); });
    ProjectileSystem bolts;
    int lastCastTick = -1, firstRefusedTick = -1;
    for (int tick = 0; tick < 480; ++tick) {
        m.tick(kDt);
        if (c.tick(true, true, kDt, {}, bolts)) lastCastTick = tick;
    }
    std::printf("mana: 20 fire-staff casts by tick %d, mana %.4f, %zu bolts\n", lastCastTick, double(m.value()),
                bolts.live().size());
    CHECK(c.casts() == 20 && lastCastTick == 19 * 24 && m.value() == 0.0f && bolts.live().size() == 20);
    CHECK(c.manaRefused() == 0);
    // 21st: refused for mana -> no bolt, no cooldown, presses keep being refused (and
    // don't restart the delay) until regen brings back 5 mana: 1.5 s + 5/3 s after the
    // last cast = tick 456 + 90 + 100.
    int nextCast = -1;
    for (int tick = 480; tick < 1200 && nextCast < 0; ++tick) {
        m.tick(kDt);
        const bool cast = c.tick(true, true, kDt, {}, bolts);
        if (!cast && firstRefusedTick < 0) firstRefusedTick = tick;
        if (cast) nextCast = tick;
        if (tick == 480) CHECK(!cast && c.cooldownRemaining() == 0.0f && bolts.live().size() == 20);
    }
    std::printf("mana: 21st cast refused at tick %d (%llu refusals), next cast at tick %d (expect %d +-1)\n",
                firstRefusedTick, (unsigned long long)c.manaRefused(), nextCast, 456 + 90 + 100);
    CHECK(firstRefusedTick == 480 && c.casts() == 21 && bolts.live().size() == 21);
    CHECK(nextCast >= 645 && nextCast <= 647);
    CHECK(c.manaRefused() == unsigned(nextCast - 480));
    CHECK(near(m.value(), 0.0f, 0.06f));   // spent the 5 it just regained
    CHECK(m.spends() == 21);
}

void regenTiming(int hz) {
    const float dt = 1.0f / float(hz);
    const int delayTicks = hz * 3 / 2;   // 1.5 s (integral at 30/60/144 Hz)
    Mana m;
    CHECK(m.spend(50.0f));
    ticks(m, delayTicks - 1, dt);
    CHECK(m.value() == 50.0f && !m.regenerating());
    ticks(m, 1, dt);                    // exactly 1.5 s: at most a rounding sliver
    CHECK(near(m.value(), 50.0f, 1e-4f) && m.regenerating());
    ticks(m, 1, dt);                    // first regen tick: +3 dt
    CHECK(near(m.value(), 50.0f + 3.0f * dt, 1e-4f));
    ticks(m, hz - 1, dt);               // 2.5 s after the cast: +3
    std::printf("mana @%d Hz: %.5f after 1.5 s delay + 1 s regen (expect 53)\n", hz, double(m.value()));
    CHECK(near(m.value(), 53.0f, 1e-4f));
    ticks(m, 10 * hz, dt);              // 10 s more: +30
    CHECK(near(m.value(), 83.0f, 1e-3f));

    // A cast inside the delay restarts it: cast at 0 and at 1.4 s, regen only from 2.9 s.
    Mana r;
    CHECK(r.spend(10.0f));
    ticks(r, int(1.4 * hz + 0.5), dt);
    CHECK(r.value() == 90.0f && r.spend(10.0f) && r.value() == 80.0f);
    ticks(r, delayTicks, dt);
    CHECK(near(r.value(), 80.0f, 1e-4f));
    ticks(r, hz, dt);
    CHECK(near(r.value(), 83.0f, 1e-4f));

    // A refused cast doesn't restart it (Magewar returns before resetting the timer).
    Mana q;
    CHECK(q.spend(99.0f));
    ticks(q, hz, dt);                   // 1 s
    CHECK(!q.spend(5.0f) && q.value() == 1.0f);
    ticks(q, delayTicks / 3 + hz, dt);  // 1.5 s + 1 s after the successful cast
    CHECK(near(q.value(), 4.0f, 1e-4f));

    // Empty -> full in 1.5 + 100/3 s = 34.833 s.
    Mana e;
    CHECK(e.spend(100.0f));
    int n = 0;
    while (e.value() < e.max() && n < 100 * hz) { e.tick(dt); ++n; }
    const int expect = int(std::ceil((1.5 + 100.0 / 3.0) * hz - 1e-6));
    std::printf("mana @%d Hz: empty -> full in %d ticks = %.4f s (expect %d = 34.833 s)\n", hz, n,
                double(n) / hz, expect);
    CHECK(std::abs(n - expect) <= 1 && e.value() == 100.0f);
    ticks(e, hz, dt);
    CHECK(e.value() == 100.0f && !e.regenerating());   // never above the max
}

void bonuses() {
    // Equipment regen (step 30 hook): Novice Grimoire mana_regen_bonus 0.5 -> 3.5/s.
    Mana m;
    m.setRegenBonus(0.5f);
    CHECK(m.regenRate() == 3.5f && m.regenBonus() == 0.5f);
    CHECK(m.spend(50.0f));
    ticks(m, 90 + 60);
    std::printf("mana: regen bonus +0.5 -> %.4f after 1.5 s + 1 s (expect 53.5)\n", double(m.value()));
    CHECK(near(m.value(), 53.5f, 1e-4f));
    m.setRegenBonus(2.0f);   // e.g. Grimoire 0.5..2 at a higher rarity: rate 5/s
    ticks(m, 60);
    CHECK(near(m.value(), 58.5f, 1e-4f));
    m.setRegenBonus(-10.0f); // never drains
    CHECK(m.regenRate() == 0.0f);
    ticks(m, 60);
    CHECK(near(m.value(), 58.5f, 1e-4f));

    // Max bonus (Magewar equip: max and current both +bonus; removal clamps).
    Mana x;
    CHECK(x.spend(20.0f));
    x.setMaxBonus(5.0f);   // Novice Grimoire mana_bonus 5
    CHECK(x.max() == 105.0f && x.value() == 85.0f);
    x.setMaxBonus(0.0f);
    CHECK(x.max() == 100.0f && x.value() == 85.0f);
    Mana f;
    f.setMaxBonus(25.0f);
    CHECK(f.max() == 125.0f && f.value() == 125.0f);
    f.setMaxBonus(0.0f);
    CHECK(f.max() == 100.0f && f.value() == 100.0f);
    // Level-up (step 38): +5 max and a full refill.
    CHECK(f.spend(60.0f));
    f.setMaxBonus(5.0f);
    f.refill();
    CHECK(f.max() == 105.0f && f.value() == 105.0f);

    // auto_regenerate off: never regenerates.
    ManaTuning off;
    off.autoRegenerate = false;
    Mana o(off);
    CHECK(o.spend(10.0f));
    ticks(o, 600);
    CHECK(o.value() == 90.0f && !o.regenerating());
}

void controller() {
    namespace ph = coe::physics;
    ph::PhysicsWorld w;
    ph::BoxDesc floor;
    floor.center = {0, -0.5f, 0};
    floor.halfExtents = {20, 0.5f, 20};
    w.addStaticBox(floor);
    PlayerController p(w, {0, 0, 0}, 0.0f);
    CHECK(p.mana().value() == 100.0f);
    CHECK(p.mana().spend(10.0f));
    const coe::input::TickInput idle{};
    for (int i = 0; i < 90 + 60; ++i) { p.tick(idle, kDt); w.step(kDt); }
    std::printf("mana: PlayerController 1.5 s + 1 s after spending 10 -> %.4f (expect 93)\n", double(p.mana().value()));
    CHECK(near(p.mana().value(), 93.0f, 1e-4f));
}
} // namespace

int main() {
    basics();
    twentyCasts();
    for (int hz : {30, 60, 144}) regenTiming(hz);
    bonuses();
    controller();
    if (g_failures) { std::fprintf(stderr, "test_mana: %d failure(s)\n", g_failures); return 1; }
    std::puts("test_mana: all checks passed");
    return 0;
}
