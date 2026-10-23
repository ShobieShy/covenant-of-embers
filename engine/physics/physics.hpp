// SPDX-License-Identifier: Apache-2.0
// Rigid-body physics world (BUILD_PLAN step 13) on Jolt Physics (ADR-0001).
//
// Jolt stays private to engine/physics (pimpl): callers see glm types and opaque
// BodyHandles only, so game code never includes Jolt headers and the engine owns
// the one-time Jolt globals (allocator hook, factory, type registry). The world is
// stepped once per fixed 60 Hz tick (engine/core/fixed_timestep) with a constant dt,
// so the simulation is deterministic for a given sequence of calls.
//
// Conventions match the renderer: metres, right-handed, +Y up, gravity -Y.
// Gravity defaults to 9.8 m/s^2, Godot's default that Magewar keeps (project.godot has
// no physics/3d/default_gravity override; Jolt itself defaults to 9.81).
//
// Object layers reinterpret Magewar's two named 3D physics layers (layer_1
// "Environment", layer_2 "Interactables"): Static = the level (never moves, never
// collides with itself), Moving = everything simulated. Character (step 14) holds the
// kinematic inner bodies of CharacterVirtual players (character.hpp) so rays and moving
// bodies see them; it collides with Static + Moving (+ other characters). More layers
// (enemies, pickups/interactables, projectiles) arrive with the steps that need them.
#pragma once
#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>

namespace coe::physics {

using ObjectLayer = std::uint16_t;
namespace Layers {
inline constexpr ObjectLayer Static = 0;   // level geometry (Magewar "Environment")
inline constexpr ObjectLayer Moving = 1;   // dynamic bodies (props, debris; later actors)
inline constexpr ObjectLayer Character = 2;   // player characters' inner bodies (step 14)
inline constexpr ObjectLayer Count = 3;
} // namespace Layers
const char* layerName(ObjectLayer layer);

// Opaque body reference (Jolt BodyID index + sequence). Default = invalid.
struct BodyHandle {
    std::uint32_t id = 0xffffffffu;
    bool valid() const { return id != 0xffffffffu; }
    friend bool operator==(BodyHandle, BodyHandle) = default;
};

struct WorldSettings {
    glm::vec3 gravity{0.0f, -9.8f, 0.0f};
    std::uint32_t maxBodies = 4096;
    std::uint32_t maxBodyPairs = 4096;
    std::uint32_t maxContactConstraints = 4096;
    // 0 = run Jolt's jobs on the calling thread (deterministic, no threads; plenty
    // for the greybox), N > 0 = a JobSystemThreadPool with N worker threads.
    int workerThreads = 0;
};

struct BoxDesc {
    glm::vec3 center{0.0f};
    glm::vec3 halfExtents{0.5f};          // > 0
    glm::quat rotation{1, 0, 0, 0};       // world orientation (w, x, y, z)
    ObjectLayer layer = Layers::Static;
    float friction = 0.2f;                // Jolt default; combined as sqrt(f1 * f2)
    float restitution = 0.0f;
    float density = 1000.0f;              // kg/m^3, dynamic bodies only
};

struct RayHit {
    BodyHandle body;
    float fraction = 0.0f;                // along the cast segment, [0, 1]
    glm::vec3 point{0.0f};
    glm::vec3 normal{0.0f};               // world-space surface normal at the hit
};

struct BodyState {
    glm::vec3 position{0.0f};
    glm::quat rotation{1, 0, 0, 0};
    glm::vec3 linearVelocity{0.0f};
    glm::vec3 angularVelocity{0.0f};
    bool active = false;                  // false once Jolt put the body to sleep (or static)
};

class PhysicsWorld {
public:
    explicit PhysicsWorld(const WorldSettings& settings = {});
    ~PhysicsWorld();
    PhysicsWorld(const PhysicsWorld&) = delete;
    PhysicsWorld& operator=(const PhysicsWorld&) = delete;

    // Static boxes are the level; call optimizeBroadPhase() once after adding them.
    BodyHandle addStaticBox(const BoxDesc& desc);
    BodyHandle addDynamicBox(const BoxDesc& desc);   // layer forced to Moving
    void removeBody(BodyHandle body);
    void optimizeBroadPhase();

    // One fixed tick: advances the simulation by dt seconds (one collision step).
    // Returns false if Jolt reported an error (e.g. out of contact constraints).
    bool step(float dt);

    std::size_t bodyCount() const;
    std::size_t activeBodyCount() const;
    std::uint64_t steps() const;
    BodyState state(BodyHandle body) const;
    ObjectLayer layer(BodyHandle body) const;
    glm::vec3 halfExtents(BodyHandle body) const;     // of a box body, 0 otherwise
    void setLinearVelocity(BodyHandle body, const glm::vec3& v);

    // Closest hit along origin -> origin + delta, any layer.
    std::optional<RayHit> castRay(const glm::vec3& origin, const glm::vec3& delta) const;

private:
    friend class Character;   // character.cpp drives Jolt's CharacterVirtual on this world
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace coe::physics
