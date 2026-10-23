// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/player/stats (BUILD_PLAN step 15): the Breath pool.
// Done-check (drain/regen timings at the game's 60 Hz tick, and at 144 Hz):
//  - 100 base; sprinting drains 20/s: 1 s -> 80, empty after exactly 5 s (300 ticks);
//  - regen waits 1 s after the last drain (none on tick 60, +0.5 on tick 61), then
//    +30/s: 2 s after the last drain it has regained exactly 30;
//  - an emptied pool refills in 1 + 100/30 = 4.33 s; it stays exhausted (no sprint)
//    until 20 is back (1 + 20/30 = 1.667 s);
//  - a drain or spend restarts the delay; spend(25) refuses when short;
//  - setMaxBonus raises/lowers the max without refilling.
// Plain checks; doctest in step 20.
#include "game/player/stats.hpp"

#include <cmath>
#include <cstdio>

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using coe::game::Breath;
constexpr float kDt = 1.0f / 60.0f;

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }

void ticks(Breath& b, bool draining, int n, float dt = kDt) {
    for (int i = 0; i < n; ++i) b.tick(draining, dt);
}

void drain() {
    Breath b;
    CHECK(b.value() == 100.0f && b.max() == 100.0f && b.canSprint() && !b.exhausted());
    ticks(b, true, 60);
    std::printf("breath: after 1 s sprint %.4f (expect 80)\n", double(b.value()));
    CHECK(near(b.value(), 80.0f, 1e-3f));
    ticks(b, true, 239);   // 4.983 s total
    CHECK(b.value() > 0.0f && b.canSprint());
    ticks(b, true, 1);     // 300 ticks = 5 s
    std::printf("breath: after 300 ticks %.4f, exhausted %d\n", double(b.value()), int(b.exhausted()));
    CHECK(b.value() == 0.0f && b.empty() && b.exhausted() && !b.canSprint());
    ticks(b, true, 30);    // floored at 0
    CHECK(b.value() == 0.0f);
}

void regenTiming(float dt, int hz) {
    Breath b;
    ticks(b, true, 2 * hz, dt);   // 2 s of sprint -> 60
    const float base = b.value();
    CHECK(near(base, 60.0f, 1e-3f));
    ticks(b, false, hz - 1, dt);   // 1 s - 1 tick: still waiting
    CHECK(b.value() == base && !b.regenerating());
    ticks(b, false, 1, dt);        // exactly 1 s: regen starts now (at most a rounding sliver)
    CHECK(near(b.value(), base, 1e-3f));
    ticks(b, false, 1, dt);        // first regen tick: +30 x dt
    CHECK(near(b.value(), base + 30.0f * dt, 1e-3f));
    ticks(b, false, hz - 1, dt);   // 2 s after the last drain: +30
    std::printf("breath @%d Hz: %.4f after 1 s delay + 1 s regen (expect %.1f)\n", hz, double(b.value()),
                double(base + 30.0f));
    CHECK(near(b.value(), base + 30.0f, 1e-3f));
    ticks(b, false, 2 * hz, dt);   // capped at max
    CHECK(b.value() == b.max() && !b.regenerating());
}

void refillAndExhaustion() {
    Breath b;
    ticks(b, true, 300);
    CHECK(b.exhausted());
    int resumeTick = -1, fullTick = -1;
    for (int i = 1; i <= 400; ++i) {
        b.tick(false, kDt);
        if (resumeTick < 0 && b.canSprint()) resumeTick = i;
        if (fullTick < 0 && b.value() >= b.max()) fullTick = i;
    }
    std::printf("breath: empty -> sprint again after %d ticks (expect 100), full after %d ticks (expect 260)\n",
                resumeTick, fullTick);
    CHECK(std::abs(resumeTick - 100) <= 1);   // 1 s + 20/30 s
    CHECK(std::abs(fullTick - 260) <= 1);     // 1 s + 100/30 s
    // resumeAt 0 = Magewar's "sprint whenever > 0" behaviour.
    coe::game::BreathTuning t;
    t.resumeAt = 0.0f;
    Breath m(t);
    ticks(m, true, 300);
    CHECK(!m.canSprint());
    ticks(m, false, 61);
    CHECK(m.canSprint() && m.value() < 1.0f);
}

void interruptAndSpend() {
    Breath b;
    ticks(b, true, 60);              // 80
    ticks(b, false, 90);             // 1 s delay + 0.5 s regen -> 95
    CHECK(near(b.value(), 95.0f, 1e-3f));
    ticks(b, true, 1);               // a single sprint tick restarts the delay
    const float v = b.value();
    ticks(b, false, 60);
    CHECK(near(b.value(), v, 1e-3f));
    // Dash cost (step 16): 25, refused when short, restarts the delay too.
    Breath d;
    CHECK(d.spend(25.0f) && near(d.value(), 75.0f, 1e-6f));
    ticks(d, false, 59);
    CHECK(d.value() == 75.0f);
    CHECK(d.spend(25.0f) && d.spend(25.0f) && near(d.value(), 25.0f, 1e-5f));
    ticks(d, true, 60);              // 25 - 20 = 5
    CHECK(!d.spend(25.0f) && near(d.value(), 5.0f, 1e-3f));
}

void maxBonus() {
    Breath b;
    b.setMaxBonus(15.0f);            // e.g. a Belt (step 30)
    CHECK(b.max() == 115.0f && b.value() == 100.0f);   // no free refill
    ticks(b, false, 60);             // never drained: regen already allowed
    CHECK(near(b.value(), 115.0f, 1e-3f));
    b.setMaxBonus(0.0f);
    CHECK(b.value() == 100.0f && b.max() == 100.0f);   // clamped
    b.spend(50.0f);
    b.refill();
    CHECK(b.value() == 100.0f && !b.exhausted());
}
} // namespace

int main() {
    drain();
    regenTiming(1.0f / 60.0f, 60);
    regenTiming(1.0f / 144.0f, 144);
    refillAndExhaustion();
    interruptAndSpend();
    maxBonus();
    if (g_failures) { std::fprintf(stderr, "test_breath: %d failure(s)\n", g_failures); return 1; }
    std::puts("test_breath: all checks passed");
    return 0;
}
