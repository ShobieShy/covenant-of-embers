// SPDX-License-Identifier: Apache-2.0
// Spell projectiles (BUILD_PLAN step 17): fast bolts swept as Jolt rays once per fixed tick.
//
// Each tick a live bolt moves speed x dt along its direction (clipped to what is left of
// its range); the segment is one PhysicsWorld::castRay that skips the caster's own body
// (physics::Character::innerBody(), the Layers::Character proxy the eye ray starts
// inside). The closest hit ends the bolt and is reported with the exact distance and
// travel time (ticks flown before + fraction of this tick), so hits land at the right
// distance however fast the bolt is (no tunnelling, unlike a per-tick position test).
//
// Magewar reference (spell_projectile.tscn, read-only): a 0.1 m RigidBody3D sphere with
// continuous CD and gravity, 8 s lifespan, destroyed on impact. Reinterpreted: a straight
// ray (no drop, no radius) that fizzles at the wieldable's range (Magewar's wieldable_range
// was unused by the projectile). A sphere cast for the 0.1 m radius can come with step 22.
#pragma once
#include "engine/physics/physics.hpp"
#include "game/magic/wieldable.hpp"

#include <glm/glm.hpp>

#include <cstdint>
#include <vector>

namespace coe::game {

struct ProjectileSpawn {
    glm::vec3 origin{0.0f};          // ray start (the caster's eye: hits go where the crosshair points)
    glm::vec3 direction{0.0f, 0.0f, -1.0f};   // normalised by spawn()
    float speed = 30.0f;             // m/s
    float range = 50.0f;             // m
    Element element = Element::Arcane;
    float damage = 0.0f;             // carried to the hit (step 20/22 apply it)
    physics::BodyHandle ignore;      // never hit (the caster); invalid = none
};

struct Projectile {
    std::uint32_t id = 0;
    ProjectileSpawn spawn;
    glm::vec3 position{0.0f};        // after the last tick
    glm::vec3 previous{0.0f};        // before the last tick (render interpolation)
    float travelled = 0.0f;          // m
    int ticks = 0;                   // ticks flown
};

struct ProjectileHit {
    std::uint32_t projectile = 0;
    physics::BodyHandle body;
    glm::vec3 point{0.0f};
    glm::vec3 normal{0.0f};
    float distance = 0.0f;           // m from the spawn origin
    float time = 0.0f;               // s from spawn (ticks before + fraction of the hit tick)
    int tick = 0;                    // 1-based tick of flight in which it hit
    Element element = Element::Arcane;
    float damage = 0.0f;
};

// An element-coloured debug segment (drawn as a thin stretched cube by the game).
struct DebugLine {
    glm::vec3 a{0.0f}, b{0.0f};
    glm::vec3 color{1.0f};
};

class ProjectileSystem {
public:
    std::uint32_t spawn(const ProjectileSpawn& s);
    // One fixed tick: sweeps every live bolt, appends hits (closest first per bolt),
    // drops bolts that hit or ran out of range. Bolts spawned before this call move in it.
    void tick(const physics::PhysicsWorld& world, float dt, std::vector<ProjectileHit>& hits);

    const std::vector<Projectile>& live() const { return live_; }
    std::uint64_t spawned() const { return spawned_; }
    std::uint64_t hits() const { return hits_; }
    std::uint64_t fizzled() const { return fizzled_; }

    // Bolt tracers (a short tail behind each live bolt, interpolated by alpha) plus the
    // last stretch of recent impacts, fading out over kImpactLinger.
    void debugLines(float alpha, std::vector<DebugLine>& out) const;
    static constexpr float kTail = 2.5f;          // m of tracer behind the head
    static constexpr float kSkipNear = 0.6f;      // m in front of the eye not drawn (would fill the view)
    static constexpr float kImpactLinger = 0.2f;  // s

private:
    struct Impact { DebugLine line; float ttl; };
    std::vector<Projectile> live_;
    std::vector<Impact> impacts_;
    std::uint32_t nextId_ = 1;
    std::uint64_t spawned_ = 0, hits_ = 0, fizzled_ = 0;
};

} // namespace coe::game
