// SPDX-License-Identifier: Apache-2.0
// Unit tests for engine/physics + game/world/level_physics (BUILD_PLAN step 13):
//  - done-check: a dynamic box dropped on the Midden `ground` (top y = 0) comes to rest
//    at its half height (+-0.05 m) and sleeps; one dropped over `ramp_west` slides off
//    it (downhill = +Z) and ends on the ground south of the ramp;
//  - every collider has its LevelBox's centre, half size and Ry*Rx*Rz rotation, on the
//    kind's object layer;
//  - down-rays over the arena hit level box surfaces (the boxes the renderer draws),
//    and the ramp is hit on its analytic 20.56 degree plane;
//  - determinism: identical runs give bit-identical poses, with or without workers.
// Plain checks; doctest in step 20.
#include "engine/physics/physics.hpp"
#include "game/world/level.hpp"
#include "game/world/level_physics.hpp"

#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>

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

using coe::game::BoxKind;
using coe::game::Level;
namespace ph = coe::physics;

constexpr float kDt = 1.0f / 60.0f;   // the game's fixed tick (kTickHz = 60)
constexpr int kMaxTicks = 600;        // 10 s of simulated time per drop

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }
bool near(glm::vec3 a, glm::vec3 b, float eps) { return glm::length(a - b) <= eps; }

const coe::game::LevelBox* find(const Level& l, const char* name) {
    for (const auto& b : l.boxes) if (b.name == name) return &b;
    return nullptr;
}

Level loadMidden() {
    Level l;
    const std::string err = coe::game::loadLevel(std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml", l);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    CHECK(err.empty());
    return l;
}

struct DropResult {
    ph::BodyState rest;
    int ticksToSleep = -1;     // first tick the body was asleep, -1 = never
    float maxVzOnRamp = 0.0f;  // fastest +Z (downhill) speed while above y 0.5
    bool stepsOk = true;
};

// Drops a cube of edge `edge` at `start` (rotated by `rot`) into the level and steps
// until it sleeps (plus a few ticks to confirm) or kMaxTicks.
DropResult drop(const Level& level, glm::vec3 start, float edge, glm::quat rot = {1, 0, 0, 0}, int workers = 0) {
    ph::WorldSettings ws;
    ws.workerThreads = workers;
    ph::PhysicsWorld world(ws);
    const auto lp = coe::game::buildLevelPhysics(level, world);
    CHECK(lp.bodies.size() == level.boxes.size());
    ph::BoxDesc d;
    d.center = start;
    d.halfExtents = glm::vec3(edge * 0.5f);
    d.rotation = rot;
    const ph::BodyHandle box = world.addDynamicBox(d);
    CHECK(box.valid());
    CHECK(world.layer(box) == ph::Layers::Moving);
    DropResult r;
    for (int t = 1; t <= kMaxTicks; ++t) {
        r.stepsOk = world.step(kDt) && r.stepsOk;
        const ph::BodyState s = world.state(box);
        if (s.position.y > 0.5f) r.maxVzOnRamp = std::fmax(r.maxVzOnRamp, s.linearVelocity.z);
        if (!s.active && r.ticksToSleep < 0) r.ticksToSleep = t;
        if (r.ticksToSleep >= 0 && t >= r.ticksToSleep + 10) break;
    }
    r.rest = world.state(box);
    CHECK(world.steps() > 0);
    return r;
}

void collidersMatchBoxes(const Level& level) {
    ph::PhysicsWorld world;
    const auto lp = coe::game::buildLevelPhysics(level, world);
    CHECK(lp.bodies.size() == level.boxes.size());
    CHECK(world.bodyCount() == level.boxes.size());
    CHECK(world.activeBodyCount() == 0);   // static bodies never simulate
    for (size_t i = 0; i < level.boxes.size() && i < lp.bodies.size(); ++i) {
        const auto& b = level.boxes[i];
        const ph::BodyState s = world.state(lp.bodies[i]);
        CHECK(near(s.position, b.center, 1e-5f));
        CHECK(near(world.halfExtents(lp.bodies[i]), b.size * 0.5f, 1e-5f));
        CHECK(world.layer(lp.bodies[i]) == coe::game::objectLayerFor(b.kind));
        CHECK(world.layer(lp.bodies[i]) == ph::Layers::Static);
        CHECK(!s.active);
        // Same orientation as the renderer's model matrix (compare matrices: q and -q are equal).
        const glm::mat3 r = glm::mat3_cast(s.rotation), want = b.rotation();
        for (int c = 0; c < 3; ++c) CHECK(near(r[c], want[c], 1e-5f));
    }
    CHECK(std::string(ph::layerName(ph::Layers::Static)) == "static");
}

void raysHitLevelSurfaces(const Level& level) {
    ph::PhysicsWorld world;
    const auto lp = coe::game::buildLevelPhysics(level, world);
    int hits = 0, onGround = 0, onOthers = 0;
    const int groundIdx = int(find(level, "ground") - level.boxes.data());
    // Grid offset off the half-metre lattice so no ray grazes a box edge exactly
    // (an edge hit legitimately reports the side face's normal).
    for (float x = -18.87f; x <= 19.0f; x += 0.5f) {
        for (float z = -18.91f; z <= 19.0f; z += 0.5f) {
            const auto hit = world.castRay({x, 10.0f, z}, {0.0f, -20.0f, 0.0f});
            CHECK(hit.has_value());   // the 40 x 40 m ground is under everything
            if (!hit) continue;
            ++hits;
            int idx = -1;
            for (size_t i = 0; i < lp.bodies.size(); ++i) if (lp.bodies[i] == hit->body) idx = int(i);
            CHECK(idx >= 0);
            if (idx < 0) continue;
            const float dist = level.boxes[size_t(idx)].surfaceDistance(hit->point);
            if (!near(dist, 0.0f, 0.01f))
                std::fprintf(stderr, "ray (%.1f, %.1f) hit %s at y %.3f, %.4f m off its surface\n", double(x), double(z),
                             level.boxes[size_t(idx)].name.c_str(), double(hit->point.y), double(dist));
            CHECK(near(dist, 0.0f, 0.01f));
            CHECK(level.boxAtSurface(hit->point, 0.01f) >= 0);
            if (!(hit->normal.y > 0.0f))
                std::fprintf(stderr, "ray (%.1f, %.1f) hit %s at (%.3f %.3f %.3f) normal (%.3f %.3f %.3f)\n", double(x), double(z),
                             level.boxes[size_t(idx)].name.c_str(), double(hit->point.x), double(hit->point.y), double(hit->point.z),
                             double(hit->normal.x), double(hit->normal.y), double(hit->normal.z));
            CHECK(hit->normal.y > 0.0f);   // down-rays hit up-facing faces
            (idx == groundIdx ? onGround : onOthers)++;
            if (idx == groundIdx) CHECK(near(hit->point.y, 0.0f, 1e-4f));
        }
    }
    std::printf("[physics] rays: %d hits, %d on ground, %d on other boxes\n", hits, onGround, onOthers);
    CHECK(onGround > 0 && onOthers > 0);

    // ramp_west top surface: y = 1.5 * (-5 - z) / 4 for z in [-9, -5], normal tilted toward +Z.
    for (float z : {-5.5f, -7.0f, -8.5f}) {
        const auto hit = world.castRay({-4.5f, 5.0f, z}, {0.0f, -10.0f, 0.0f});
        CHECK(hit.has_value());
        if (!hit) continue;
        CHECK(near(hit->point.y, 1.5f * (-5.0f - z) / 4.0f, 0.01f));
        const float slope = std::acos(hit->normal.y) * 180.0f / 3.14159265f;
        CHECK(near(slope, 20.556f, 0.05f));
        CHECK(hit->normal.z > 0.0f);
    }
    // A horizontal ray toward the north wall stops at its south face (z = -14).
    const auto wall = world.castRay({-10.0f, 2.0f, 0.0f}, {0.0f, 0.0f, -30.0f});
    CHECK(wall && near(wall->point.z, -14.0f, 1e-3f) && near(wall->normal, {0, 0, 1}, 1e-3f));
    // Nothing above the arena.
    CHECK(!world.castRay({0.0f, 10.0f, 0.0f}, {0.0f, 10.0f, 0.0f}).has_value());
}

void dropOnGround(const Level& level) {
    const auto* ground = find(level, "ground");
    CHECK(ground && near(ground->center.y + ground->size.y * 0.5f, 0.0f, 1e-6f));   // top at y = 0
    // Open floor south of the mound, clear of crates/heaps: (0, *, 8).
    const DropResult r = drop(level, {0.0f, 2.0f, 8.0f}, 0.5f);
    std::printf("[physics] ground drop: rest (%.4f, %.4f, %.4f), asleep after %d ticks\n", double(r.rest.position.x),
                double(r.rest.position.y), double(r.rest.position.z), r.ticksToSleep);
    CHECK(r.stepsOk);
    CHECK(near(r.rest.position.y, 0.25f, 0.05f));            // done-check: rests on the ground top
    CHECK(near(r.rest.position.x, 0.0f, 0.05f) && near(r.rest.position.z, 8.0f, 0.05f));   // straight down
    CHECK(r.ticksToSleep > 0 && r.ticksToSleep < kMaxTicks);   // settles and sleeps
    CHECK(!r.rest.active && glm::length(r.rest.linearVelocity) < 1e-3f);

    // Tumbled drop: lands on a face, same rest height.
    const glm::quat tilt = glm::angleAxis(0.6f, glm::normalize(glm::vec3(1.0f, 0.3f, 0.7f)));
    const DropResult t = drop(level, {0.0f, 3.0f, 8.0f}, 0.5f, tilt);
    std::printf("[physics] tumbled drop: rest y %.4f, asleep after %d ticks\n", double(t.rest.position.y), t.ticksToSleep);
    CHECK(near(t.rest.position.y, 0.25f, 0.05f));
    CHECK(t.ticksToSleep > 0);

    // Determinism: same inputs -> bit-identical result; worker threads don't change it.
    const DropResult t2 = drop(level, {0.0f, 3.0f, 8.0f}, 0.5f, tilt);
    CHECK(t2.rest.position == t.rest.position && t2.ticksToSleep == t.ticksToSleep);
    const DropResult tp = drop(level, {0.0f, 3.0f, 8.0f}, 0.5f, tilt, 3);
    CHECK(tp.rest.position == t.rest.position && tp.ticksToSleep == t.ticksToSleep);
}

void dropOnRamp(const Level& level) {
    // ramp_west: 3 m wide at x = -4.5, top from (z -9, y 1.5) down to (z -5, y 0).
    // Surface at z = -7.5 is y ~0.94; the box starts 1 m above it and slides south.
    const DropResult r = drop(level, {-4.5f, 2.0f, -7.5f}, 0.5f);
    std::printf("[physics] ramp drop: rest (%.4f, %.4f, %.4f), max downhill speed on ramp %.2f m/s, asleep after %d ticks\n",
                double(r.rest.position.x), double(r.rest.position.y), double(r.rest.position.z),
                double(r.maxVzOnRamp), r.ticksToSleep);
    CHECK(r.stepsOk);
    CHECK(r.maxVzOnRamp > 0.5f);                    // it slid downhill while on the ramp
    CHECK(r.rest.position.z > -5.0f + 0.25f);       // off the ramp's low edge, fully on the ground
    CHECK(near(r.rest.position.y, 0.25f, 0.05f));   // resting on the ground, not the ramp
    CHECK(near(r.rest.position.x, -4.5f, 0.5f));    // went straight down the slope
    CHECK(r.ticksToSleep > 0);
}

} // namespace

int main() {
    const Level level = loadMidden();
    if (g_failures == 0) {
        collidersMatchBoxes(level);
        raysHitLevelSurfaces(level);
        dropOnGround(level);
        dropOnRamp(level);
    }
    if (g_failures) { std::fprintf(stderr, "%d check(s) failed\n", g_failures); return 1; }
    std::puts("test_physics: all checks passed");
    return 0;
}
