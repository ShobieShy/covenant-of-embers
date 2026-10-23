// SPDX-License-Identifier: Apache-2.0
#include "game/player/player_controller.hpp"

#include <algorithm>
#include <cmath>

namespace coe::game {

using input::Action;

PlayerController::PlayerController(physics::PhysicsWorld& world, const glm::vec3& feet, float yawRad,
                                   const PlayerTuning& tuning, const physics::CharacterSettings& body,
                                   const BreathTuning& breath, const DashTuning& dash,
                                   const CameraFeelTuning& feel)
    : tuning_(tuning), character_(world, body, feet), yaw_(yawRad), speed_(tuning.walkSpeed),
      eye_(tuning.standingEye), prevEye_(tuning.standingEye), feet_(character_.position()), prevFeet_(feet_),
      breath_(breath), dash_(dash), feel_(feel) {}

glm::vec3 PlayerController::forwardFor(float yawRad) { return {-std::sin(yawRad), 0.0f, -std::cos(yawRad)}; }
glm::vec3 PlayerController::rightFor(float yawRad) { return {std::cos(yawRad), 0.0f, -std::sin(yawRad)}; }

void PlayerController::addLook(float dxCounts, float dyCounts) {
    setLook(yaw_ - dxCounts * tuning_.lookRadPerCount, pitch_ - dyCounts * tuning_.lookRadPerCount);
}

void PlayerController::setLook(float yawRad, float pitchRad) {
    yaw_ = float(std::remainder(double(yawRad), 2.0 * 3.141592653589793));   // keep in (-pi, pi]
    pitch_ = std::clamp(pitchRad, -Camera::kMaxPitch, Camera::kMaxPitch);
}

float PlayerController::horizontalSpeed() const {
    const glm::vec3 v = character_.velocity();
    return std::sqrt(v.x * v.x + v.z * v.z);
}

void PlayerController::tick(const input::TickInput& in, float dt) {
    prevFeet_ = feet_;
    prevEye_ = eye_;
    // Still rising from a jump: the ground probe (Jolt's predictive contacts) can report
    // OnGround for a tick or two after take-off, which must not cancel the jump.
    if (rising_ && character_.velocity().y <= 0.0f) rising_ = false;
    const bool grounded = character_.onGround() && !rising_;
    const bool landed = grounded && airborne_;
    if (landed) {
        ++landings_;
        lastLandingSpeed_ = std::max(0.0f, -airVy_);
    }
    if (grounded) {   // landed
        crouchedJump_ = false;
        jumpedFromSlide_ = false;
        dash_.land();
    }

    glm::vec3 wish = forwardFor(yaw_) * in.moveForward() + rightFor(yaw_) * in.moveRight();
    const float wishLen = glm::length(wish);
    const bool moving = wishLen > 1e-6f;
    if (moving) wish /= wishLen;   // diagonals are not faster

    // Slide (Magewar): Crouch on the ground while sprinting with a move key held starts
    // the 1.5 s slide along the current wish direction; leaving the ground, letting go of
    // Crouch or Sprint stops it (the timeout is handled after the move below).
    const bool crouchHeld = in.down(Action::Crouch);
    if (sliding() && (!grounded || !crouchHeld || !in.down(Action::Sprint))) slideLeft_ = 0.0f;

    // Dash (press edge): along the wish direction, or the view's forward with no move key.
    // A dash ends an active slide; the crouch rules below still apply (Crouch held on the
    // ground keeps the crouch). Refusals (no charge, air dash used, Breath < 25) cost nothing.
    if (in.wasPressed(Action::Dash) && dash_.tryStart(moving ? wish : forwardFor(yaw_), grounded, breath_))
        slideLeft_ = 0.0f;

    if (!sliding() && !dash_.active() && grounded && crouchHeld && sprinting_ && moving) {
        slideLeft_ = tuning_.slideDuration;
        slideDir_ = wish;
        ++slides_;
    }

    // Crouch (held): only starts on the ground; a crouch-jump stays crouched in the air;
    // standing up needs head room (setCrouched(false) fails under a low ceiling).
    const bool wantCrouch = crouchedJump_ || (grounded && crouchHeld);
    if (wantCrouch) character_.setCrouched(true);
    else if (character_.crouched()) character_.setCrouched(false);
    const bool crouched = character_.crouched();

    // Sprint (held): starts on the ground, carries on in the air while held; never while
    // crouched or with Breath exhausted; needs a move key (standing still doesn't drain).
    sprinting_ = in.down(Action::Sprint) && !crouched && moving && breath_.canSprint() && (grounded || sprinting_);
    breath_.tick(sprinting_, dt);

    // Horizontal: smoothed direction x eased speed (Magewar's direction/current_speed lerps).
    const float lerpSpeed = tuning_.lerpSpeed;
    if (sliding()) {
        direction_ = slideDir_;
        speed_ = (slideLeft_ / tuning_.slideDuration + 0.5f) * tuning_.slideSpeed;
    } else {
        if (!jumpedFromSlide_) {   // a slide jump keeps its speed until landing
            const float base = crouched ? tuning_.crouchSpeed : sprinting_ ? tuning_.sprintSpeed : tuning_.walkSpeed;
            speed_ = std::lerp(speed_, base * speedMul_, std::min(1.0f, dt * lerpSpeed));
        }
        if (grounded)
            direction_ = glm::mix(direction_, wish, std::min(1.0f, dt * lerpSpeed));
        else if (moving)
            direction_ = glm::mix(direction_, wish, std::min(1.0f, dt * tuning_.airLerpSpeed));
        if (glm::length(direction_) < 1e-3f) direction_ = glm::vec3(0.0f);
    }

    // Vertical: rest on the ground, fall otherwise; jump on the press edge from the ground.
    glm::vec3 v = direction_ * speed_;
    v.y = grounded ? 0.0f : character_.velocity().y - tuning_.gravity * dt;
    if (grounded && in.wasPressed(Action::Jump)) {
        if (sliding()) {   // slide jump: standard jump x SLIDE_JUMP_MOD, stand up in the air
            v.y = tuning_.jumpVelocity * tuning_.slideJumpMod;
            jumpedFromSlide_ = true;
            crouchedJump_ = false;
            slideLeft_ = 0.0f;
            ++slideJumps_;
        } else {
            v.y = crouched ? tuning_.crouchJumpVelocity : tuning_.jumpVelocity;
            crouchedJump_ = crouched;
        }
        rising_ = true;
        ++jumps_;
    }
    // Dash: replaces the horizontal velocity for the part of this tick it covers.
    const float dashCover = dash_.advance(dt);
    if (dashCover > 0.0f) {
        const glm::vec3 d = dash_.direction() * dash_.speed();
        v.x = d.x * dashCover + v.x * (1.0f - dashCover);
        v.z = d.z * dashCover + v.z * (1.0f - dashCover);
    }
    if (grounded) v += character_.groundVelocity();
    character_.setVelocity(v);
    character_.update(dt);
    feet_ = character_.position();
    if (sliding()) slideLeft_ = std::max(0.0f, slideLeft_ - dt);   // SlidingTimer counts down

    // Eye height eases toward the stance's (Magewar lerps the head the same way).
    const float targetEye = character_.crouched() ? tuning_.crouchingEye : tuning_.standingEye;
    eye_ = std::lerp(eye_, targetEye, std::min(1.0f, dt * lerpSpeed));
    if (std::fabs(eye_ - targetEye) < 1e-4f) eye_ = targetEye;

    // Landing detection for the next tick + camera feel (bob / dip).
    // (Tick-start ground state, like `grounded`: the tick that touches down still moved
    // with its airborne velocity, which is the impact speed.)
    airborne_ = !grounded;
    if (airborne_) airVy_ = v.y;
    CameraFeelInput feel;
    feel.bobbing = grounded && moving && !sliding() && dashCover <= 0.0f;
    feel.gait = crouched ? Gait::Crouch : sprinting_ ? Gait::Sprint : Gait::Walk;
    feel.landed = landed;
    feel.landingSpeed = lastLandingSpeed_;
    feel_.tick(feel, dt);
}

Camera PlayerController::camera(float alpha) const {
    Camera c;
    const glm::vec3 feet = glm::mix(prevFeet_, feet_, alpha);
    const glm::vec2 o = feel_.offset(alpha);   // head bob (x right, y up) + landing dip
    c.position = feet + glm::vec3(0.0f, std::lerp(prevEye_, eye_, alpha) + o.y, 0.0f) + rightFor(yaw_) * o.x;
    c.yaw = yaw_;
    c.pitch = pitch_;
    return c;
}

} // namespace coe::game
