// SPDX-License-Identifier: Apache-2.0
// First-person player controller (BUILD_PLAN step 14): walk, jump, crouch, look.
//
// Reinterprets Magewar's cogito_player (CharacterBody3D, read-only reference) on our
// physics::Character (Jolt CharacterVirtual capsule, feet at its position):
//   * per fixed tick (tick()): the move direction is the input axes (moveForward /
//     moveRight) turned by the *current* look yaw, smoothed toward the wish direction
//     at LERP_SPEED 10/s on the ground and AIR_LERP_SPEED 6/s in the air (air control
//     only while a move key is held); speed eases toward walk 4 m/s / crouch 3 m/s at
//     10/s. Vertical: 0 while on the ground, gravity 9.8 m/s^2 otherwise; Jump (on the
//     press edge, ground only) sets 4.5 m/s standing / 3.0 m/s crouched.
//   * Crouch is held (Magewar TOGGLE_CROUCH = false; a toggle option is step 39): it
//     starts on the ground only, a crouch-jump keeps the crouch until landing, and
//     standing up waits until the 1.7 m capsule fits (Magewar's CrouchRayCast).
//   * The eye sits 1.5 m above the feet standing (body origin 0.8 + Neck 0.7) and
//     0.6 m crouched (Neck - CROUCHING_DEPTH 0.9), eased at 10/s like Magewar's head.
//   * Mouse look (addLook()) is applied per render frame: 0.25 deg/count, mouse right
//     = negative yaw (turn right), pitch clamped to +-89 deg (Camera::kMaxPitch).
// Sprint/slide (step 15), dash and head bob (step 16) build on this.
#pragma once
#include "engine/input/input.hpp"
#include "engine/physics/character.hpp"
#include "engine/physics/physics.hpp"
#include "engine/render/camera.hpp"

#include <glm/glm.hpp>

#include <cstdint>

namespace coe::game {

struct PlayerTuning {
    float walkSpeed = 4.0f;            // Magewar WALKING_SPEED (player scene override)
    float crouchSpeed = 3.0f;          // CROUCHING_SPEED
    float jumpVelocity = 4.5f;         // JUMP_VELOCITY
    float crouchJumpVelocity = 3.0f;   // CROUCH_JUMP_VELOCITY
    float gravity = 9.8f;              // project default gravity
    float lerpSpeed = 10.0f;           // LERP_SPEED: direction/speed/eye easing on the ground
    float airLerpSpeed = 6.0f;         // AIR_LERP_SPEED
    float standingEye = 1.5f;          // eye above the feet: body origin 0.8 + Neck 0.7
    float crouchingEye = 0.6f;         // + CROUCHING_DEPTH -0.9
    float lookRadPerCount = 0.25f * 3.14159265f / 180.0f;   // MOUSE_SENS 0.25 deg/count
};

class PlayerController {
public:
    // Spawns the character with its feet at `feet`, facing `yawRad` (pitch 0).
    PlayerController(physics::PhysicsWorld& world, const glm::vec3& feet, float yawRad,
                     const PlayerTuning& tuning = {}, const physics::CharacterSettings& body = {});

    // Per render frame: relative mouse motion in counts (dx right, dy down).
    void addLook(float dxCounts, float dyCounts);
    void setLook(float yawRad, float pitchRad);

    // Per fixed tick, before PhysicsWorld::step(): reads the latest look yaw.
    void tick(const input::TickInput& in, float dt);

    // Camera at the eye, interpolated between the last two ticks by alpha in [0, 1).
    Camera camera(float alpha) const;

    glm::vec3 feet() const { return feet_; }                 // after the last tick
    glm::vec3 eyePosition() const { return feet_ + glm::vec3(0.0f, eye_, 0.0f); }
    float eyeHeight() const { return eye_; }
    glm::vec3 velocity() const { return character_.velocity(); }
    float horizontalSpeed() const;
    bool onGround() const { return character_.onGround(); }
    bool crouched() const { return character_.crouched(); }
    float yaw() const { return yaw_; }
    float pitch() const { return pitch_; }
    std::uint64_t jumps() const { return jumps_; }
    const physics::Character& character() const { return character_; }
    const PlayerTuning& tuning() const { return tuning_; }

    // Unit vectors on the ground plane for a look yaw (yaw 0 faces -Z, +yaw turns left).
    static glm::vec3 forwardFor(float yawRad);
    static glm::vec3 rightFor(float yawRad);

private:
    PlayerTuning tuning_;
    physics::Character character_;
    float yaw_ = 0.0f, pitch_ = 0.0f;
    glm::vec3 direction_{0.0f};   // smoothed move direction (Magewar `direction`)
    float speed_;                 // Magewar `current_speed`
    bool crouchedJump_ = false;   // jumped while crouched: stay crouched until landing
    bool rising_ = false;         // jumped and still moving up
    float eye_, prevEye_;
    glm::vec3 feet_, prevFeet_;
    std::uint64_t jumps_ = 0;
};

} // namespace coe::game
