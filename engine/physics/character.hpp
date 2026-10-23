// SPDX-License-Identifier: Apache-2.0
// Kinematic player character (BUILD_PLAN step 14) on Jolt's CharacterVirtual.
//
// Like PhysicsWorld, Jolt stays private (pimpl, character.cpp): callers see glm types.
// The character is a capsule whose *feet* are at position(): radius 0.3 m, 1.7 m tall
// standing / 0.7 m crouched (reinterpreting Magewar's cogito_player 0.6 x 1.7 x 0.6 m
// and 0.6 x 0.7 x 0.6 m box colliders; a capsule slides along edges instead of
// snagging on them). It is not simulated by PhysicsWorld::step(): the game sets its
// velocity and calls update() once per fixed tick (before stepping the world), which
// sweeps the shape through the world, slides along walls, climbs steps up to
// stepHeight, sticks to the floor going down slopes/steps and pushes dynamic bodies.
// A kinematic inner body on Layers::Character follows it so rays (step 17 hitscan)
// and moving bodies see the player. A Character must not outlive its PhysicsWorld.
#pragma once
#include "engine/physics/physics.hpp"

#include <glm/glm.hpp>

#include <memory>

namespace coe::physics {

struct CharacterSettings {
    float radius = 0.3f;              // capsule radius (Magewar collider 0.6 m wide)
    float standingHeight = 1.7f;      // feet to top of head (Magewar 1.7 m)
    float crouchingHeight = 0.7f;     // Magewar's crouch collider is 0.7 m tall
    float stepHeight = 0.35f;         // Magewar STEP_HEIGHT_DEFAULT (0, 0.35, 0)
    float stickToFloor = 0.5f;        // max snap down when walking off steps / down slopes
    float maxSlopeDeg = 45.0f;        // Godot CharacterBody3D floor_max_angle default (Magewar keeps it)
    float mass = 70.0f;               // kg, pushes on what it stands on
    float maxStrength = 100.0f;       // N, max push on dynamic bodies
    bool innerBody = true;            // kinematic body on Layers::Character (visible to rays)
};

enum class GroundState { OnGround, OnSteepGround, NotSupported, InAir };
const char* groundStateName(GroundState s);

class Character {
public:
    // Spawns standing with its feet at `feet`. Contacts are refreshed immediately, so a
    // character placed on the floor reports OnGround before its first update.
    Character(PhysicsWorld& world, const CharacterSettings& settings, const glm::vec3& feet);
    ~Character();
    Character(const Character&) = delete;
    Character& operator=(const Character&) = delete;

    // One fixed tick: moves by velocity() * dt with collision response, stair stepping
    // and floor sticking (only while supported), then refreshes the ground state.
    // velocity() afterwards is the velocity actually achieved (e.g. 0 into a wall,
    // vertical velocity cut by a ceiling).
    void update(float dt);

    glm::vec3 position() const;                // feet
    void setPosition(const glm::vec3& feet);   // teleport (no sweep)
    glm::vec3 velocity() const;
    void setVelocity(const glm::vec3& v);

    GroundState groundState() const;
    bool onGround() const { return groundState() == GroundState::OnGround; }
    glm::vec3 groundNormal() const;            // valid unless InAir
    glm::vec3 groundVelocity() const;          // velocity of what we stand on

    // Switches the collision shape. Crouching always succeeds; standing up fails
    // (and the character stays crouched) if the taller capsule would hit something.
    bool setCrouched(bool crouched);
    bool crouched() const;
    float height() const;                      // current capsule height
    const CharacterSettings& settings() const;
    BodyHandle innerBody() const;              // invalid if settings.innerBody is false

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace coe::physics
