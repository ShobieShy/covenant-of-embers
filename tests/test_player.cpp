// SPDX-License-Identifier: Apache-2.0
// Unit tests for engine/physics/character + game/player/player_controller (BUILD_PLAN step 14).
// Done-check:
//  - 1 s of forward input from the Midden player start moves ~ walk speed x 1 s (4 m;
//    Magewar's direction easing at 10/s costs ~0.4 m of it) and ends at walk speed;
//  - standing on the Midden ground the eye is 1.5 m above it (ray-measured);
//  - walking into `ramp_west` climbs it onto `scrap_ledge` (1.5 m up);
//  - a 0.35 m step is climbed (Magewar STEP_HEIGHT) and a 0.5 m step blocks.
// Also: jump apex v^2/2g for 4.5 / 3.0 m/s (stand / crouch), crouch eye 0.6 m and
// speed 3 m/s, no standing up under a low ceiling, look clamp/wrap, and the inner body
// on Layers::Character is what a ray through the player hits.
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
    if (g_failures) { std::fprintf(stderr, "test_player: %d failure(s)\n", g_failures); return 1; }
    std::puts("test_player: all checks passed");
    return 0;
}
