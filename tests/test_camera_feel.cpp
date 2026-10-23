// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/player/camera_feel + its PlayerController integration (step 16).
//  - head bob (Magewar wiggle): bobs only while grounded + moving; sprint bobs harder and
//    faster than walk; eases back to exactly 0 when standing;
//  - landing dip: none below 2 m/s, depth scales with impact up to 0.12 m at 8 m/s,
//    deepest around 0.1 s, gone by 0.3 s;
//  - reduced motion: offset exactly 0 for the same inputs, and camera() == the plain eye;
//  - in the controller: walking offsets the camera from eyePosition(), a jump landing
//    (~4.6 m/s) dips it, reduced motion keeps camera() on the eye.
// Plain checks; doctest in step 20.
#include "engine/physics/physics.hpp"
#include "game/player/camera_feel.hpp"
#include "game/player/player_controller.hpp"

#include <glm/glm.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using coe::game::CameraFeel;
using coe::game::CameraFeelInput;
using coe::game::Gait;
using coe::game::PlayerController;
using coe::input::Action;
namespace ph = coe::physics;

constexpr float kDt = 1.0f / 60.0f;

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }

struct Range { float maxY = 0, minY = 0, maxAbsX = 0; };

Range bobFor(CameraFeel& f, Gait g, int ticks) {
    Range r;
    CameraFeelInput in;
    in.bobbing = true;
    in.gait = g;
    for (int i = 0; i < ticks; ++i) {
        f.tick(in, kDt);
        if (i < 60) continue;   // past the ease-in
        r.maxY = std::max(r.maxY, f.offset().y);
        r.minY = std::min(r.minY, f.offset().y);
        r.maxAbsX = std::max(r.maxAbsX, std::fabs(f.offset().x));
    }
    return r;
}

void headBob() {
    CameraFeel walk, sprint;
    const Range w = bobFor(walk, Gait::Walk, 300);
    const Range s = bobFor(sprint, Gait::Sprint, 300);
    std::printf("bob walk: y %.4f..%.4f x %.4f | sprint: y %.4f..%.4f x %.4f\n", double(w.minY), double(w.maxY),
                double(w.maxAbsX), double(s.minY), double(s.maxY), double(s.maxAbsX));
    // Target amplitude y = I/2 (0.015 walk, 0.025 sprint), x = I; easing trims it.
    CHECK(w.maxY > 0.005f && w.maxY <= 0.015f && w.minY < -0.005f && w.minY >= -0.015f);
    CHECK(w.maxAbsX > 0.01f && w.maxAbsX <= 0.03f);
    CHECK(s.maxY > w.maxY && s.maxAbsX > w.maxAbsX);
    // Centred sway (Magewar's +0.5 bias dropped): x goes both ways.
    CameraFeel c;
    float minX = 0, maxX = 0;
    CameraFeelInput in;
    in.bobbing = true;
    for (int i = 0; i < 300; ++i) { c.tick(in, kDt); minX = std::min(minX, c.offset().x); maxX = std::max(maxX, c.offset().x); }
    CHECK(minX < -0.01f && maxX > 0.01f && near(minX, -maxX, 0.01f));
    // Stop: eases back to exactly zero.
    for (int i = 0; i < 120; ++i) c.tick({}, kDt);
    CHECK(c.offset() == glm::vec2(0.0f));
    // bobScale 0 = off.
    CameraFeel off;
    off.setBobScale(0.0f);
    CHECK(bobFor(off, Gait::Crouch, 120).maxAbsX == 0.0f);
}

void landingDip() {
    CameraFeelInput land;
    land.landed = true;
    land.landingSpeed = 1.9f;
    CameraFeel soft;
    soft.tick(land, kDt);
    CHECK(soft.dip() == 0.0f);   // below the 2 m/s threshold
    for (float speed : {5.0f, 8.0f, 12.0f}) {
        CameraFeel f;
        land.landingSpeed = speed;
        f.tick(land, kDt);
        float deepest = 0.0f;
        int deepestTick = 0, endTick = -1;
        for (int i = 1; i < 40; ++i) {
            if (f.dip() < deepest) { deepest = f.dip(); deepestTick = i; }
            if (endTick < 0 && i > 1 && f.dip() == 0.0f) endTick = i;
            f.tick({}, kDt);
        }
        const float expect = 0.12f * std::min(1.0f, (speed - 2.0f) / 6.0f);
        std::printf("landing dip at %.1f m/s: %.4f m (expected %.4f) at tick %d, back by tick %d\n", double(speed),
                    double(deepest), double(-expect), deepestTick, endTick);
        CHECK(near(-deepest, expect, 0.002f));
        CHECK(deepestTick >= 5 && deepestTick <= 7);   // ~0.1 s
        CHECK(endTick >= 17 && endTick <= 19);         // ~0.3 s
    }
}

void reducedMotionUnit() {
    CameraFeel f;
    f.setReducedMotion(true);
    CameraFeelInput in;
    in.bobbing = true;
    in.gait = Gait::Sprint;
    for (int i = 0; i < 200; ++i) {
        in.landed = i == 100;
        in.landingSpeed = 8.0f;
        f.tick(in, kDt);
        CHECK(f.offset() == glm::vec2(0.0f) && f.offset(0.5f) == glm::vec2(0.0f));
    }
    // Turning it on mid-bob snaps to zero.
    CameraFeel g;
    for (int i = 0; i < 30; ++i) g.tick(in, kDt);
    CHECK(g.offset() != glm::vec2(0.0f));
    g.setReducedMotion(true);
    CHECK(g.offset() == glm::vec2(0.0f) && g.offset(0.3f) == glm::vec2(0.0f));
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

coe::input::TickInput hold(std::initializer_list<Action> held, std::initializer_list<Action> pressed = {}) {
    coe::input::TickInput in;
    for (Action a : held) in.held.set(size_t(a));
    for (Action a : pressed) { in.pressed.set(size_t(a)); in.held.set(size_t(a)); in.pressCount[size_t(a)] = 1; }
    return in;
}

struct Seen { float maxOffset = 0.0f, minDipY = 0.0f, landingSpeed = 0.0f; };

Seen runController(bool reduced) {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    p.setReducedMotion(reduced);
    auto step = [&](const coe::input::TickInput& in, Seen& s, bool measureDip) {
        p.tick(in, kDt);
        CHECK(f.w.step(kDt));
        const glm::vec3 d = p.camera(1.0f).position - p.eyePosition();
        s.maxOffset = std::max(s.maxOffset, glm::length(d));
        if (measureDip) s.minDipY = std::min(s.minDipY, d.y);
        if (reduced) CHECK(d == glm::vec3(0.0f));   // camera exactly on the eye
    };
    Seen s;
    for (int i = 0; i < 30; ++i) step({}, s, false);
    for (int i = 0; i < 120; ++i) step(hold({Action::MoveForward}), s, false);   // walking: bob
    for (int i = 0; i < 60; ++i) step({}, s, false);
    step(hold({}, {Action::Jump}), s, false);
    for (int i = 0; i < 120; ++i) step({}, s, true);   // jump, land, dip
    s.landingSpeed = p.lastLandingSpeed();
    CHECK(p.landings() >= 1);
    return s;
}

void controller() {
    const Seen on = runController(false);
    const Seen off = runController(true);
    std::printf("controller: max camera offset %.4f m, landing at %.2f m/s dips %.4f m | reduced motion: %.4f / %.4f\n",
                double(on.maxOffset), double(on.landingSpeed), double(on.minDipY), double(off.maxOffset),
                double(off.minDipY));
    CHECK(on.maxOffset > 0.01f);
    CHECK(on.landingSpeed > 4.0f && on.landingSpeed < 5.2f);   // 4.5 m/s jump lands at ~4.6
    const float expect = 0.12f * (on.landingSpeed - 2.0f) / 6.0f;
    CHECK(near(-on.minDipY, expect, 0.005f));
    CHECK(off.maxOffset == 0.0f && off.minDipY == 0.0f);
}
} // namespace

int main() {
    headBob();
    landingDip();
    reducedMotionUnit();
    controller();
    if (g_failures) { std::fprintf(stderr, "test_camera_feel: %d failure(s)\n", g_failures); return 1; }
    std::puts("test_camera_feel: all checks passed");
    return 0;
}
