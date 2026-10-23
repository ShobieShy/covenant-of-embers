// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/player/dash + its PlayerController integration (BUILD_PLAN step 16).
// Done-check:
//  - charges/recharge: 2 charges, a 3rd dash is refused, a charge comes back exactly
//    1.5 s (90 ticks at 60 Hz) after the first was spent and the 2nd 1.5 s later;
//  - distance: a dash covers 6 m +- 0.3 in 0.15 s (9 ticks at 60 Hz; also at 144 Hz).
// Also: a wall stops the dash (no tunnelling at 40 m/s), one air dash per jump (back on
// landing), Breath 25 per dash with refusal when short or exhausted (no charge spent),
// the 1 s regen delay restarting, a dash ending a slide (crouch kept while Crouch is
// held), direction = move keys or view forward, 0.1 s i-frames.
// Plain checks; doctest in step 20.
#include "engine/physics/physics.hpp"
#include "game/player/dash.hpp"
#include "game/player/player_controller.hpp"
#include "game/player/stats.hpp"

#include <glm/glm.hpp>

#include <cmath>
#include <cstdio>

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using coe::game::Breath;
using coe::game::Dash;
using coe::game::PlayerController;
using coe::input::Action;
namespace ph = coe::physics;

constexpr float kDt = 1.0f / 60.0f;

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }

coe::input::TickInput hold(std::initializer_list<Action> held, std::initializer_list<Action> pressed = {}) {
    coe::input::TickInput in;
    for (Action a : held) in.held.set(size_t(a));
    for (Action a : pressed) { in.pressed.set(size_t(a)); in.held.set(size_t(a)); in.pressCount[size_t(a)] = 1; }
    return in;
}

void tick(PlayerController& p, ph::PhysicsWorld& w, const coe::input::TickInput& in, float dt = kDt) {
    p.tick(in, dt);
    CHECK(w.step(dt));
}

struct Flat {
    ph::PhysicsWorld w;
    Flat() {
        ph::BoxDesc floor;
        floor.center = {0, -0.5f, 0};
        floor.halfExtents = {40, 0.5f, 40};
        w.addStaticBox(floor);
    }
};

// --- Dash on its own ------------------------------------------------------------------

void chargesAndRecharge() {
    Dash d;
    Breath b;
    const glm::vec3 fwd(0, 0, -1);
    CHECK(d.charges() == 2 && d.maxCharges() == 2 && !d.active());
    CHECK(d.tryStart(fwd, true, b));
    CHECK(!d.tryStart(fwd, true, b));   // already dashing
    int ticks = 0, dashTicks = 0;
    float covered = 0.0f;
    while (d.active()) { covered += d.advance(kDt); ++dashTicks; ++ticks; }
    CHECK(dashTicks == 9 && near(covered, 9.0f, 1e-4f));   // 0.15 s = 9 ticks
    CHECK(d.charges() == 1);
    CHECK(d.tryStart(fwd, true, b));
    while (d.active()) { d.advance(kDt); ++ticks; }
    CHECK(d.charges() == 0);
    CHECK(!d.tryStart(fwd, true, b));   // out of charges
    CHECK(near(b.value(), 50.0f, 1e-4f));   // 2 x 25, the refused one cost nothing
    int firstBack = -1, secondBack = -1;
    while (secondBack < 0 && ticks < 1000) {
        d.advance(kDt);
        ++ticks;
        if (firstBack < 0 && d.charges() == 1) firstBack = ticks;
        if (d.charges() == 2) secondBack = ticks;
    }
    std::printf("dash charges: 2 used (dash = %d ticks), back after %d and %d ticks (1.5 s each = 90/180)\n",
                dashTicks, firstBack, secondBack);
    CHECK(firstBack == 90 && secondBack == 180);   // counted from the first dash's tick
    CHECK(d.rechargeProgress() == 0.0f);
    // Bonus charge hook (PLAN §30.8 Sandals): a 3rd charge recharges like the others.
    d.setBonusCharges(1);
    CHECK(d.maxCharges() == 3 && d.charges() == 2);
    for (int i = 0; i < 90; ++i) d.advance(kDt);
    CHECK(d.charges() == 3);
    d.setBonusCharges(0);
    CHECK(d.charges() == 2);
}

void airDashUnit() {
    Dash d;
    Breath b;
    CHECK(d.tryStart({1, 0, 0}, false, b));   // one in the air
    while (d.active()) d.advance(kDt);
    CHECK(d.charges() == 1 && !d.airDashAvailable());
    CHECK(!d.tryStart({1, 0, 0}, false, b));  // second air dash refused, no cost
    CHECK(d.charges() == 1 && near(b.value(), 75.0f, 1e-4f));
    d.land();
    CHECK(d.tryStart({1, 0, 0}, false, b));
    CHECK(!d.tryStart({0, 0, 0}, true, b) && d.dashes() == 2);   // zero direction (and busy)
}

void breathRefusalUnit() {
    Dash d;
    Breath b;
    CHECK(b.spend(76.0f));   // 24 left
    CHECK(!d.tryStart({0, 0, -1}, true, b));
    CHECK(d.charges() == 2 && near(b.value(), 24.0f, 1e-4f) && d.dashes() == 0);
    for (int i = 0; i < 63; ++i) b.tick(false, kDt);   // 1 s delay, then +0.5 per tick past 25
    CHECK(b.value() >= 25.0f && d.tryStart({0, 0, -1}, true, b));
    CHECK(b.secondsSinceUse() == 0.0);   // spend restarted the 1 s regen delay
}

void iframes() {
    for (float hz : {60.0f, 144.0f}) {
        Dash d;
        Breath b;
        const float dt = 1.0f / hz;
        CHECK(d.tryStart({0, 0, -1}, true, b) && d.invulnerable());
        int n = 0;
        for (int i = 0; i < 100; ++i) {
            d.advance(dt);
            if (d.invulnerable()) ++n;
        }
        // Every tick starting within 0.1 s: 6 at 60 Hz, 15 at 144 Hz (14 x 1/144 = 0.0972).
        std::printf("i-frames at %.0f Hz: %d tick(s)\n", double(hz), n);
        CHECK(n == (hz == 60.0f ? 6 : 15));
    }
}

// --- PlayerController --------------------------------------------------------------------

float dashDistance(float hz) {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    const float dt = 1.0f / hz;
    for (int i = 0; i < int(hz / 2); ++i) tick(p, f.w, {}, dt);
    const glm::vec3 start = p.feet();
    tick(p, f.w, hold({}, {Action::Dash}), dt);   // no move key: along the view (north, -Z)
    int ticks = 1;
    CHECK(p.dashing() && near(p.breath().value(), 75.0f, 1e-3f));
    while (p.dashing() && ticks < 100) { tick(p, f.w, {}, dt); ++ticks; }
    const glm::vec3 d = p.feet() - start;
    std::printf("dash at %.0f Hz: %.3f m north in %d ticks, sideways %.4f, dy %.4f\n", double(hz), double(-d.z), ticks,
                double(d.x), double(d.y));
    CHECK(std::fabs(d.x) < 1e-3f && std::fabs(d.y) < 1e-2f && p.onGround());
    CHECK(ticks == int(std::ceil(0.15f * hz - 1e-3f)));
    // Standing still: the dash ends into rest, not a 40 m/s carry-over.
    for (int i = 0; i < 5; ++i) tick(p, f.w, {}, dt);
    CHECK(p.horizontalSpeed() < 0.5f);
    return -d.z;
}

void distance() {
    CHECK(near(dashDistance(60.0f), 6.0f, 0.3f));
    CHECK(near(dashDistance(144.0f), 6.0f, 0.3f));
    // With a move key: along the move direction (right = +X at yaw 0), even when walking.
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    for (int i = 0; i < 30; ++i) tick(p, f.w, hold({Action::MoveRight}));
    const glm::vec3 start = p.feet();
    tick(p, f.w, hold({Action::MoveRight}, {Action::Dash}));
    for (int i = 0; i < 8; ++i) tick(p, f.w, hold({Action::MoveRight}));
    const glm::vec3 d = p.feet() - start;
    std::printf("dash while walking right: %.3f m east in 9 ticks\n", double(d.x));
    CHECK(near(d.x, 6.0f, 0.3f) && std::fabs(d.z) < 1e-3f);
    CHECK(!p.dashing());
    tick(p, f.w, hold({Action::MoveRight}));
    CHECK(near(p.horizontalSpeed(), 4.0f, 0.1f));   // straight back to walking
}

void wallStops() {
    Flat f;
    ph::BoxDesc wall;   // south face at z -3, 3 m tall
    wall.center = {0, 1.5f, -3.5f};
    wall.halfExtents = {10, 1.5f, 0.5f};
    f.w.addStaticBox(wall);
    f.w.optimizeBroadPhase();
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    for (int i = 0; i < 30; ++i) tick(p, f.w, {});
    tick(p, f.w, hold({}, {Action::Dash}));
    for (int i = 0; i < 20; ++i) tick(p, f.w, {});
    const glm::vec3 e = p.feet();
    std::printf("dash into a wall at z -3: stopped at z %.3f (radius 0.3), y %.3f\n", double(e.z), double(e.y));
    CHECK(e.z > -3.0f && e.z < -2.6f);   // against the face, not through it
    CHECK(std::fabs(e.x) < 1e-3f && near(e.y, 0.0f, 0.03f));
}

void airDashOnce() {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    for (int i = 0; i < 30; ++i) tick(p, f.w, {});
    tick(p, f.w, hold({}, {Action::Jump}));
    for (int i = 0; i < 10; ++i) tick(p, f.w, {});
    CHECK(!p.onGround());
    const float yBefore = p.feet().y;
    tick(p, f.w, hold({}, {Action::Dash}));
    CHECK(p.dash().dashes() == 1);
    for (int i = 0; i < 9; ++i) tick(p, f.w, {});
    CHECK(!p.onGround() && !p.dashing());
    tick(p, f.w, hold({}, {Action::Dash}));   // second one in the same jump: refused
    const bool refused = p.dash().dashes() == 1 && p.dash().charges() == 1 && near(p.breath().value(), 75.0f, 0.5f);
    std::printf("air dash: from y %.3f, %llu dash(es), 2nd refused %s, Breath %.2f\n", double(yBefore),
                (unsigned long long)p.dash().dashes(), refused ? "yes" : "NO", double(p.breath().value()));
    CHECK(refused);
    for (int i = 0; i < 120 && !p.onGround(); ++i) tick(p, f.w, {});
    CHECK(p.onGround());
    tick(p, f.w, {});
    // Landed: a new jump has its air dash again (1 charge left).
    tick(p, f.w, hold({}, {Action::Jump}));
    for (int i = 0; i < 5; ++i) tick(p, f.w, {});
    tick(p, f.w, hold({}, {Action::Dash}));
    CHECK(p.dash().dashes() == 2);
    // A ground dash doesn't use the air dash.
    Dash d;
    Breath b;
    CHECK(d.tryStart({0, 0, -1}, true, b) && d.airDashAvailable());
}

void breathRefusal() {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    for (int i = 0; i < 30; ++i) tick(p, f.w, {});
    CHECK(p.breath().spend(80.0f));   // 20 left
    const glm::vec3 a = p.feet();
    tick(p, f.w, hold({}, {Action::Dash}));
    for (int i = 0; i < 9; ++i) tick(p, f.w, {});
    CHECK(p.dash().dashes() == 0 && p.dash().charges() == 2);
    CHECK(glm::length(p.feet() - a) < 1e-3f);
    // Exhausted pool (sprinted dry): refused too.
    Flat g;
    PlayerController q(g.w, {0, 0, 0}, 0.0f);
    for (int i = 0; i < 30; ++i) tick(q, g.w, {});
    int n = 0;
    while (!q.breath().exhausted() && n < 400) { tick(q, g.w, hold({Action::MoveForward, Action::Sprint})); ++n; }
    CHECK(q.breath().exhausted());
    tick(q, g.w, hold({Action::MoveForward}, {Action::Dash}));
    CHECK(q.dash().dashes() == 0);
    // Breath back to >= 25 (1 s delay + 25/30 s): dashing works and costs 25.
    for (int i = 0; i < 120; ++i) tick(q, g.w, {});
    const float before = q.breath().value();
    tick(q, g.w, hold({}, {Action::Dash}));
    std::printf("dash Breath: refused at 20 and exhausted, then %.2f -> %.2f\n", double(before), double(q.breath().value()));
    CHECK(q.dash().dashes() == 1 && near(q.breath().value(), before - 25.0f, 1e-3f));
    CHECK(!q.breath().regenerating());   // the 1 s delay restarted
}

void endsSlide() {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    for (int i = 0; i < 30; ++i) tick(p, f.w, {});
    for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
    tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
    for (int i = 0; i < 10; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
    CHECK(p.sliding());
    const glm::vec3 a = p.feet();
    tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}, {Action::Dash}));
    CHECK(!p.sliding() && p.slideTimeLeft() == 0.0f && p.dashing());
    CHECK(p.crouched());   // Crouch still held on the ground: crouch rules keep the crouch
    for (int i = 0; i < 8; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
    const float moved = a.z - p.feet().z;
    for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
    std::printf("dash out of a slide: %.3f m in 9 ticks, then %s at %.3f m/s, %llu slide(s)\n", double(moved),
                p.crouched() ? "crouched" : "standing", double(p.horizontalSpeed()), (unsigned long long)p.slides());
    CHECK(near(moved, 6.0f, 0.3f));
    CHECK(p.crouched() && !p.sliding() && p.slides() == 1);   // no new slide from the dash
    CHECK(near(p.horizontalSpeed(), 3.0f, 0.05f));            // crouch speed
}
} // namespace

int main() {
    chargesAndRecharge();
    airDashUnit();
    breathRefusalUnit();
    iframes();
    distance();
    wallStops();
    airDashOnce();
    breathRefusal();
    endsSlide();
    if (g_failures) { std::fprintf(stderr, "test_dash: %d failure(s)\n", g_failures); return 1; }
    std::puts("test_dash: all checks passed");
    return 0;
}
