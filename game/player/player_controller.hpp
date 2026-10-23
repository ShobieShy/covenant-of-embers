// SPDX-License-Identifier: Apache-2.0
// First-person player controller (BUILD_PLAN steps 14-15): walk, jump, crouch, look,
// sprint, Breath and slide.
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
//   * Sprint (step 15, held): 7 m/s (Magewar SPRINTING_SPEED scene override), eased at
//     LERP_SPEED like walk/crouch; starts on the ground only with a move key held, not
//     while crouched and not while Breath (game/player/stats.hpp) is exhausted; drains
//     Breath 20/s while active, keeps going in the air while held.
//   * Slide (Magewar SlidingTimer 1.5 s, SLIDING_SPEED 5): pressing/holding Crouch on the
//     ground while sprinting (sprinting on the previous tick, move key held) crouches into
//     a slide along the entry direction (mouse look does not steer it: Magewar free-looks
//     while sliding) at (timeLeft / 1.5 + 0.5) x 5 m/s, i.e. 7.5 -> 2.5 m/s, ~7.5 m in
//     total. It ends on timeout, on releasing Crouch or Sprint, or on leaving the ground.
//     Jump during a slide = slide jump: 4.5 x SLIDE_JUMP_MOD 1.3 (scene override) m/s
//     upward, stands up and keeps the slide speed until landing. A slide doesn't drain.
//   * setSpeedMultiplier(): equipment hook (Magewar Shoes speed_modifier, step 30) that
//     scales walk/sprint/crouch speed but not the slide (Magewar leaves SLIDING_SPEED).
// Dash and head bob (step 16) build on this.
#pragma once
#include "engine/input/input.hpp"
#include "engine/physics/character.hpp"
#include "engine/physics/physics.hpp"
#include "engine/render/camera.hpp"
#include "game/player/stats.hpp"

#include <glm/glm.hpp>

#include <cstdint>

namespace coe::game {

struct PlayerTuning {
    float walkSpeed = 4.0f;            // Magewar WALKING_SPEED (player scene override)
    float crouchSpeed = 3.0f;          // CROUCHING_SPEED
    float sprintSpeed = 7.0f;          // SPRINTING_SPEED (scene override; script default 8)
    float slideSpeed = 5.0f;           // SLIDING_SPEED: slide runs (timeLeft/duration + 0.5) x this
    float slideDuration = 1.5f;        // SlidingTimer wait_time
    float slideJumpMod = 1.3f;         // SLIDE_JUMP_MOD (scene override; script default 1.5)
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
                     const PlayerTuning& tuning = {}, const physics::CharacterSettings& body = {},
                     const BreathTuning& breath = {});

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
    bool sprinting() const { return sprinting_; }          // sprint was active on the last tick
    bool sliding() const { return slideLeft_ > 0.0f; }
    float slideTimeLeft() const { return slideLeft_; }
    glm::vec3 slideDirection() const { return slideDir_; }
    std::uint64_t slides() const { return slides_; }
    std::uint64_t slideJumps() const { return slideJumps_; }
    float currentSpeed() const { return speed_; }          // Magewar current_speed (eased target)
    const Breath& breath() const { return breath_; }
    Breath& breath() { return breath_; }
    void setSpeedMultiplier(float m) { speedMul_ = m; }
    float speedMultiplier() const { return speedMul_; }
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
    Breath breath_;
    float speedMul_ = 1.0f;
    bool sprinting_ = false;
    float slideLeft_ = 0.0f;        // Magewar sliding_timer.time_left (0 = not sliding)
    glm::vec3 slideDir_{0.0f};      // world direction captured when the slide started
    bool jumpedFromSlide_ = false;  // slide-jumped: keep the slide speed until landing
    std::uint64_t slides_ = 0, slideJumps_ = 0;
};

} // namespace coe::game
