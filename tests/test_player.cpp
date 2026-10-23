// SPDX-License-Identifier: Apache-2.0
// Unit tests for engine/physics/character + game/player/player_controller (BUILD_PLAN
// steps 14-15).
// Done-check:
//  - 1 s of forward input from the Midden player start moves ~ walk speed x 1 s (4 m;
//    Magewar's direction easing at 10/s costs ~0.4 m of it) and ends at walk speed;
//  - standing on the Midden ground the eye is 1.5 m above it (ray-measured);
//  - walking into `ramp_west` climbs it onto `scrap_ledge` (1.5 m up);
//  - a 0.35 m step is climbed (Magewar STEP_HEIGHT) and a 0.5 m step blocks.
// Also: jump apex v^2/2g for 4.5 / 3.0 m/s (stand / crouch), crouch eye 0.6 m and
// speed 3 m/s, no standing up under a low ceiling, look clamp/wrap, and the inner body
// on Layers::Character is what a ray through the player hits.
// Step 15 (sprint/slide; the Breath pool's own timings are in test_breath.cpp):
//  - sprint reaches 7 m/s and drains Breath 20/s, needs a move key, never while crouched;
//    an empty pool drops back to walk until 20 Breath is back;
//  - a slide triggers only from sprint (walk + Crouch, crouch-then-sprint, standing
//    sprint + Crouch all don't), runs 1.5 s along the entry direction (look doesn't
//    steer it) at 7.5 -> 2.5 m/s (~7.5 m), ends on releasing Sprint, then crouch speed;
//  - a slide jump goes 4.5 x 1.3 m/s up, stands up in the air and keeps its speed;
//  - setSpeedMultiplier scales walk and sprint.
// Plain checks; doctest in step 20.
#include "engine/physics/character.hpp"
#include "engine/physics/physics.hpp"
#include "game/player/player_controller.hpp"
#include "game/world/level.hpp"
#include "game/world/level_physics.hpp"

#include <glm/glm.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using coe::game::Level;
using coe::game::PlayerController;
using coe::input::Action;
namespace ph = coe::physics;

constexpr float kDt = 1.0f / 60.0f;   // the game's fixed tick

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }

Level loadMidden() {
    Level l;
    const std::string err = coe::game::loadLevel(std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml", l);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    CHECK(err.empty());
    return l;
}

coe::input::TickInput hold(std::initializer_list<Action> held, std::initializer_list<Action> pressed = {}) {
    coe::input::TickInput in;
    for (Action a : held) in.held.set(size_t(a));
    for (Action a : pressed) { in.pressed.set(size_t(a)); in.held.set(size_t(a)); in.pressCount[size_t(a)] = 1; }
    return in;
}

// One game tick: controller first, then the world (as covenant does).
void tick(PlayerController& p, ph::PhysicsWorld& w, const coe::input::TickInput& in) {
    p.tick(in, kDt);
    CHECK(w.step(kDt));
}

void settle(PlayerController& p, ph::PhysicsWorld& w, int ticks = 30) {
    for (int i = 0; i < ticks; ++i) tick(p, w, {});
}

// --- done-check -------------------------------------------------------------------

void walkOneSecond(const Level& level) {
    ph::PhysicsWorld w;
    coe::game::buildLevelPhysics(level, w);
    PlayerController p(w, level.playerStart.position, glm::radians(level.playerStart.yawDeg));
    settle(p, w);
    CHECK(p.onGround());
    const glm::vec3 start = p.feet();
    for (int i = 0; i < 60; ++i) tick(p, w, hold({Action::MoveForward}));
    const glm::vec3 d = p.feet() - start;
    const float along = glm::dot(d, PlayerController::forwardFor(p.yaw()));
    std::printf("walk 1 s: %.3f m forward (walk speed %.1f m/s), sideways %.4f, dy %.4f, end speed %.3f m/s\n",
                double(along), double(p.tuning().walkSpeed), double(std::fabs(d.x)), double(d.y), double(p.horizontalSpeed()));
    CHECK(near(along, p.tuning().walkSpeed * 1.0f, 0.5f));      // ~ walk speed x 1 s
    CHECK(std::fabs(d.x) < 1e-3f && std::fabs(d.y) < 1e-3f);    // straight north, on the floor
    CHECK(near(p.horizontalSpeed(), p.tuning().walkSpeed, 0.05f));
    // Let go: Magewar's ground easing brings it to rest within ~1 s.
    for (int i = 0; i < 60; ++i) tick(p, w, {});
    CHECK(p.horizontalSpeed() < 0.05f);
    // Diagonals are not faster.
    for (int i = 0; i < 90; ++i) tick(p, w, hold({Action::MoveForward, Action::MoveRight}));
    CHECK(near(p.horizontalSpeed(), p.tuning().walkSpeed, 0.05f));
}

void eyeHeightOnGround(const Level& level) {
    ph::PhysicsWorld w;
    coe::game::buildLevelPhysics(level, w);
    PlayerController p(w, level.playerStart.position + glm::vec3(0, 0.2f, 0), 0.0f);   // drop from 20 cm
    settle(p, w, 60);
    CHECK(p.onGround());
    const glm::vec3 eye = p.eyePosition();
    // Ray from just in front of the eye straight down (misses the player's own capsule).
    const auto hit = w.castRay(eye + glm::vec3(0, 0, -0.5f), glm::vec3(0, -5, 0));
    CHECK(hit.has_value());
    if (!hit) return;
    const float above = eye.y - hit->point.y;
    std::printf("eye: %.4f m above the ground (feet y %.4f, ground y %.4f)\n", double(above), double(p.feet().y),
                double(hit->point.y));
    CHECK(near(above, 1.5f, 0.03f));
    CHECK(near(p.camera(1.0f).position.y - hit->point.y, 1.5f, 0.03f));
    CHECK(std::fabs(p.velocity().y) < 1e-3f);
}

void climbRamp(const Level& level) {
    ph::PhysicsWorld w;
    coe::game::buildLevelPhysics(level, w);
    // South of ramp_west (x -4.5; its slope rises from z -5 at y 0 to z -9 at y 1.5), facing north.
    PlayerController p(w, {-4.5f, 0.0f, -2.0f}, 0.0f);
    settle(p, w);
    float midY = -1.0f;
    bool groundedOnSlope = true;
    for (int i = 0; i < 150; ++i) {
        tick(p, w, hold({Action::MoveForward}));
        const glm::vec3 f = p.feet();
        if (f.z < -5.5f && f.z > -8.5f) groundedOnSlope = groundedOnSlope && p.onGround();
        if (midY < 0.0f && f.z <= -7.0f) midY = f.y;
    }
    const glm::vec3 f = p.feet();
    std::printf("ramp_west: at z -7 feet y %.3f (slope 0.75), end (%.2f, %.3f, %.2f) %s\n", double(midY), double(f.x),
                double(f.y), double(f.z), ph::groundStateName(p.character().groundState()));
    CHECK(near(midY, 0.75f, 0.1f));         // on the slope, not floating or sinking
    CHECK(groundedOnSlope);                 // walked up it (no hops)
    CHECK(f.z < -9.5f && near(f.y, 1.5f, 0.03f));   // up on scrap_ledge
    CHECK(p.onGround());
}

// A flat floor (top y 0) with a step of `height` whose south face is at z -3.
float walkIntoStep(float height, glm::vec3& endFeet) {
    ph::PhysicsWorld w;
    ph::BoxDesc floor;
    floor.center = {0, -0.5f, 0};
    floor.halfExtents = {20, 0.5f, 20};
    w.addStaticBox(floor);
    ph::BoxDesc step;
    step.center = {0, height * 0.5f, -6};
    step.halfExtents = {5, height * 0.5f, 3};
    w.addStaticBox(step);
    w.optimizeBroadPhase();
    PlayerController p(w, {0, 0, 0}, 0.0f);
    settle(p, w);
    for (int i = 0; i < 120; ++i) tick(p, w, hold({Action::MoveForward}));
    endFeet = p.feet();
    std::printf("step %.2f m: feet end (%.2f, %.3f, %.2f) %s\n", double(height), double(endFeet.x), double(endFeet.y),
                double(endFeet.z), ph::groundStateName(p.character().groundState()));
    return endFeet.y;
}

void steps() {
    glm::vec3 f;
    const float climbed = walkIntoStep(0.35f, f);
    CHECK(near(climbed, 0.35f, 0.03f) && f.z < -4.0f);   // on top and walking on
    const float blocked = walkIntoStep(0.5f, f);
    CHECK(near(blocked, 0.0f, 0.03f) && f.z > -3.0f && f.z < -2.5f);   // stopped against the face (radius 0.3)
}

// --- beyond the done-check -----------------------------------------------------------

struct Flat {
    ph::PhysicsWorld w;
    Flat() {
        ph::BoxDesc floor;
        floor.center = {0, -0.5f, 0};
        floor.halfExtents = {20, 0.5f, 20};
        w.addStaticBox(floor);
    }
};

float jumpApex(bool crouched) {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    const coe::input::TickInput stance = crouched ? hold({Action::Crouch}) : hold({});
    for (int i = 0; i < 30; ++i) tick(p, f.w, stance);
    tick(p, f.w, crouched ? hold({Action::Crouch}, {Action::Jump}) : hold({}, {Action::Jump}));
    float apex = 0.0f;
    bool stayedCrouched = true, landed = false;
    for (int i = 0; i < 120; ++i) {
        tick(p, f.w, {});   // crouch released mid-air: a crouch-jump stays crouched until landing
        apex = std::max(apex, p.feet().y);
        if (!p.onGround()) stayedCrouched = stayedCrouched && p.crouched() == crouched;
        if (p.onGround() && p.feet().y < 0.01f) landed = true;
    }
    CHECK(stayedCrouched && landed && p.jumps() == 1);
    // Held Jump (no new press edge) does not re-jump on landing.
    for (int i = 0; i < 30; ++i) tick(p, f.w, hold({Action::Jump}));
    CHECK(p.jumps() == 1 && p.feet().y < 0.01f);
    return apex;
}

void jumping() {
    const float stand = jumpApex(false), crouch = jumpApex(true);
    std::printf("jump apex: %.3f m standing (4.5^2/19.6 = 1.033), %.3f m crouched (3^2/19.6 = 0.459)\n", double(stand),
                double(crouch));
    CHECK(near(stand, 4.5f * 4.5f / 19.6f, 0.05f));
    CHECK(near(crouch, 3.0f * 3.0f / 19.6f, 0.05f));
    // No jumping in the air.
    Flat f;
    PlayerController p(f.w, {0, 3, 0}, 0.0f);
    tick(p, f.w, hold({}, {Action::Jump}));
    CHECK(p.jumps() == 0 && !p.onGround());
}

void crouching() {
    Flat f;
    // A 1 m-high ceiling slab north of z -3 (bottom at y 1.0).
    ph::BoxDesc slab;
    slab.center = {0, 1.25f, -6};
    slab.halfExtents = {5, 0.25f, 3};
    f.w.addStaticBox(slab);
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::Crouch}));
    CHECK(p.crouched() && near(p.eyeHeight(), 0.6f, 0.01f));
    CHECK(near(p.character().height(), 0.7f, 1e-6f));
    for (int i = 0; i < 120; ++i) tick(p, f.w, hold({Action::Crouch, Action::MoveForward}));
    std::printf("crouch: eye %.3f m, speed %.3f m/s, feet z %.2f (under the 1 m slab)\n", double(p.eyeHeight()),
                double(p.horizontalSpeed()), double(p.feet().z));
    CHECK(near(p.horizontalSpeed(), p.tuning().crouchSpeed, 0.05f));
    CHECK(p.feet().z < -4.0f);   // crouched under the slab
    // Releasing crouch under the slab keeps us crouched (Magewar's CrouchRayCast).
    for (int i = 0; i < 30; ++i) tick(p, f.w, {});
    CHECK(p.crouched());
    // Walk back out (south) and stand up.
    for (int i = 0; i < 120; ++i) tick(p, f.w, hold({Action::MoveBack}));
    for (int i = 0; i < 60; ++i) tick(p, f.w, {});
    CHECK(!p.crouched() && near(p.eyeHeight(), 1.5f, 0.01f) && p.feet().z > -2.5f);
}

void look() {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    p.addLook(360.0f, 0.0f);   // 360 counts x 0.25 deg = 90 deg right -> yaw -90 deg
    CHECK(near(p.yaw(), glm::radians(-90.0f), 1e-4f));
    CHECK(glm::length(PlayerController::forwardFor(p.yaw()) - glm::vec3(1, 0, 0)) < 1e-4f);   // facing +X (east)
    p.addLook(0.0f, -1000.0f);   // way up: clamped at +89 deg
    CHECK(near(p.pitch(), coe::Camera::kMaxPitch, 1e-6f));
    p.addLook(-360.0f * 7, 0.0f);   // 630 deg left -> wraps to -90 + 630 = 540 = 180
    CHECK(std::fabs(std::fabs(p.yaw()) - glm::radians(180.0f)) < 1e-3f);
    // The camera faces where the controller looks.
    const coe::Camera c = p.camera(1.0f);
    CHECK(c.yaw == p.yaw() && c.pitch == p.pitch());
    // Walking follows the look yaw: east.
    p.setLook(glm::radians(-90.0f), 0.0f);
    for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward}));
    CHECK(p.feet().x > 3.0f && std::fabs(p.feet().z) < 1e-3f);
}

void innerBody() {
    Flat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    tick(p, f.w, {});
    const ph::BodyHandle body = p.character().innerBody();
    CHECK(body.valid() && f.w.layer(body) == ph::Layers::Character);
    const auto hit = f.w.castRay({0, 1.0f, 5.0f}, {0, 0, -10.0f});   // chest height, from the south
    CHECK(hit && hit->body == body && near(hit->point.z, 0.3f, 0.02f));
    CHECK(std::string(ph::layerName(ph::Layers::Character)) == "character");
}

// --- step 15: sprint, Breath, slide ---------------------------------------------------

// A 400 m floor: long sprints stay on it.
struct BigFlat {
    ph::PhysicsWorld w;
    BigFlat() {
        ph::BoxDesc floor;
        floor.center = {0, -0.5f, 0};
        floor.halfExtents = {200, 0.5f, 200};
        w.addStaticBox(floor);
    }
};

void sprinting() {
    BigFlat f;
    PlayerController p(f.w, {0, 0, 150}, 0.0f);
    settle(p, f.w);
    // Sprint held, no move key: no sprint, no drain.
    for (int i = 0; i < 30; ++i) tick(p, f.w, hold({Action::Sprint}));
    CHECK(!p.sprinting() && p.breath().value() == 100.0f);
    const glm::vec3 start = p.feet();
    for (int i = 0; i < 120; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
    std::printf("sprint 2 s: speed %.3f m/s (7.0), %.2f m, Breath %.2f (100 - 40 = 60)\n", double(p.horizontalSpeed()),
                double(start.z - p.feet().z), double(p.breath().value()));
    CHECK(p.sprinting() && near(p.horizontalSpeed(), p.tuning().sprintSpeed, 0.05f));
    CHECK(near(p.breath().value(), 60.0f, 0.01f));
    // Run dry: Breath hits 0 after 5 s of sprint, speed eases back to walk.
    int dryTick = -1;
    for (int i = 0; i < 240 && dryTick < 0; ++i) {
        tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
        if (p.breath().empty()) dryTick = 120 + i + 1;
    }
    CHECK(std::abs(dryTick - 300) <= 1);
    // Still holding Sprint: walk until 20 Breath is back (1 s + 20/30 s = 100 ticks).
    int resumed = -1;
    for (int i = 1; i <= 200 && resumed < 0; ++i) {
        tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
        if (i == 60) CHECK(!p.sprinting() && near(p.horizontalSpeed(), p.tuning().walkSpeed, 0.05f));
        if (p.sprinting()) resumed = i;
    }
    std::printf("sprint: ran dry after %d ticks (300), sprinting again %d ticks later (~100)\n", dryTick, resumed);
    CHECK(resumed >= 99 && resumed <= 102);
    // Crouched: no sprint, crouch speed, no drain.
    BigFlat g;
    PlayerController c(g.w, {0, 0, 0}, 0.0f);
    settle(c, g.w);
    for (int i = 0; i < 120; ++i) tick(c, g.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
    CHECK(!c.sprinting() && !c.sliding() && c.slides() == 0 && c.crouched());
    CHECK(near(c.horizontalSpeed(), c.tuning().crouchSpeed, 0.05f) && c.breath().value() == 100.0f);
    // Speed multiplier (step 30 Shoes hook) scales walk and sprint.
    BigFlat h;
    PlayerController m(h.w, {0, 0, 0}, 0.0f);
    m.setSpeedMultiplier(1.1f);
    settle(m, h.w);
    for (int i = 0; i < 90; ++i) tick(m, h.w, hold({Action::MoveForward}));
    CHECK(near(m.horizontalSpeed(), 4.4f, 0.05f));
    for (int i = 0; i < 90; ++i) tick(m, h.w, hold({Action::MoveForward, Action::Sprint}));
    CHECK(near(m.horizontalSpeed(), 7.7f, 0.05f));
}

struct SlideRun {
    int slideTicks = 0;
    float distance = 0.0f, entrySpeed = 0.0f, endSpeedAfter = 0.0f, sideways = 0.0f;
    float breathStart = 0.0f, breathEnd = 0.0f;
    std::uint64_t slides = 0;
};

// Sprint north 1 s, then add Crouch for 3 s; turns the view 90 deg mid-slide.
SlideRun slideFromSprint() {
    BigFlat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    settle(p, f.w);
    for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
    CHECK(p.sprinting());
    SlideRun r;
    const glm::vec3 start = p.feet();
    r.breathStart = p.breath().value();
    bool counting = true;
    for (int i = 0; i < 180; ++i) {
        if (i == 30) p.setLook(glm::radians(90.0f), 0.0f);   // look west: the slide keeps going north
        tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
        if (i == 0) {
            r.entrySpeed = p.horizontalSpeed();
            CHECK(p.sliding() && p.crouched());
        }
        if (counting && p.sliding()) ++r.slideTicks;
        if (counting && !p.sliding()) {
            counting = false;
            r.distance = start.z - p.feet().z;
            r.sideways = std::fabs(p.feet().x - start.x);
            r.breathEnd = p.breath().value();
        }
    }
    r.endSpeedAfter = p.horizontalSpeed();
    r.slides = p.slides();
    CHECK(p.crouched() && !p.sprinting());
    return r;
}

void sliding() {
    const SlideRun r = slideFromSprint();
    std::printf("slide: %d ticks (90 = 1.5 s), %.3f m north (~7.5), sideways %.3f m, entry %.3f m/s (7.5), "
                "then crouch %.3f m/s, Breath %.2f -> %.2f\n", r.slideTicks, double(r.distance), double(r.sideways),
                double(r.entrySpeed), double(r.endSpeedAfter), double(r.breathStart), double(r.breathEnd));
    CHECK(r.slides == 1);   // one slide, no re-trigger while Sprint + Crouch stay held
    CHECK(std::abs(r.slideTicks - 90) <= 1);
    CHECK(near(r.entrySpeed, 7.5f, 0.05f));
    CHECK(near(r.distance, 7.5f, 0.3f));
    CHECK(r.sideways < 0.02f);                      // look turned west, slide kept north
    CHECK(near(r.endSpeedAfter, 3.0f, 0.05f));      // crouch speed once it ends
    CHECK(r.breathEnd >= r.breathStart - 0.01f);    // sliding doesn't drain

    // Only from sprint: walking + Crouch just crouches.
    {
        BigFlat f;
        PlayerController p(f.w, {0, 0, 0}, 0.0f);
        settle(p, f.w);
        for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward}));
        for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Crouch}));
        CHECK(p.slides() == 0 && p.crouched() && near(p.horizontalSpeed(), 3.0f, 0.05f));
        // Crouched first, then Sprint: still no slide.
        for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Crouch, Action::Sprint}));
        CHECK(p.slides() == 0);
    }
    // Sprint held while standing still + Crouch: no slide.
    {
        BigFlat f;
        PlayerController p(f.w, {0, 0, 0}, 0.0f);
        settle(p, f.w);
        for (int i = 0; i < 30; ++i) tick(p, f.w, hold({Action::Sprint}));
        for (int i = 0; i < 30; ++i) tick(p, f.w, hold({Action::Sprint, Action::Crouch}));
        CHECK(p.slides() == 0);
    }
    // Exhausted (no sprint) + Crouch: no slide.
    {
        BigFlat f;
        PlayerController p(f.w, {0, 0, 150}, 0.0f);
        settle(p, f.w);
        for (int i = 0; i < 310; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
        CHECK(!p.sprinting() && p.breath().exhausted());
        tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
        CHECK(p.slides() == 0 && !p.sliding());
    }
    // Releasing Sprint ends the slide early.
    {
        BigFlat f;
        PlayerController p(f.w, {0, 0, 0}, 0.0f);
        settle(p, f.w);
        for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
        for (int i = 0; i < 20; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
        CHECK(p.sliding());
        tick(p, f.w, hold({Action::MoveForward, Action::Crouch}));
        CHECK(!p.sliding() && p.crouched() && p.slides() == 1);
    }
}

void slideJump() {
    BigFlat f;
    PlayerController p(f.w, {0, 0, 0}, 0.0f);
    settle(p, f.w);
    for (int i = 0; i < 60; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint}));
    for (int i = 0; i < 10; ++i) tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
    CHECK(p.sliding());
    const float slideSpeed = p.horizontalSpeed();
    tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}, {Action::Jump}));
    CHECK(!p.sliding() && p.slideJumps() == 1 && p.jumps() == 1);
    float apex = 0.0f, minAirSpeed = 1e9f, maxAirSpeed = 0.0f;
    bool stoodUp = false;
    for (int i = 0; i < 120; ++i) {
        tick(p, f.w, hold({Action::MoveForward, Action::Sprint, Action::Crouch}));
        apex = std::max(apex, p.feet().y);
        if (!p.onGround()) {
            stoodUp = stoodUp || !p.crouched();
            minAirSpeed = std::min(minAirSpeed, p.horizontalSpeed());
            maxAirSpeed = std::max(maxAirSpeed, p.horizontalSpeed());
        }
    }
    const float v = 4.5f * 1.3f;
    std::printf("slide jump: apex %.3f m ((4.5x1.3)^2/19.6 = %.3f), air speed %.3f..%.3f m/s (slide %.3f)\n",
                double(apex), double(v * v / 19.6f), double(minAirSpeed), double(maxAirSpeed), double(slideSpeed));
    CHECK(near(apex, v * v / 19.6f, 0.06f));
    CHECK(stoodUp);
    CHECK(maxAirSpeed - minAirSpeed < 0.05f && maxAirSpeed > 6.0f);   // slide speed kept in the air
    CHECK(p.onGround() && p.slides() == 1);   // landing with Crouch held doesn't start a new slide
}
} // namespace

int main() {
    const Level midden = loadMidden();
    walkOneSecond(midden);
    eyeHeightOnGround(midden);
    climbRamp(midden);
    steps();
    jumping();
    crouching();
    look();
    innerBody();
    sprinting();
    sliding();
    slideJump();
    if (g_failures) { std::fprintf(stderr, "test_player: %d failure(s)\n", g_failures); return 1; }
    std::puts("test_player: all checks passed");
    return 0;
}
