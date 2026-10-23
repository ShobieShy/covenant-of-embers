// SPDX-License-Identifier: Apache-2.0
// Jolt CharacterVirtual behind physics::Character (see character.hpp).
#include "engine/physics/character.hpp"
#include "engine/physics/physics_impl.hpp"

#include <Jolt/Physics/Character/CharacterVirtual.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>

#include <algorithm>
#include <cfloat>

namespace coe::physics {
namespace {

// Capsule standing on the character's position (feet): total height h, radius r.
JPH::RefConst<JPH::Shape> capsule(float h, float r) {
    const float halfCylinder = std::max(0.5f * h - r, 0.01f);
    const JPH::Ref<JPH::CapsuleShape> cap = new JPH::CapsuleShape(halfCylinder, r);
    return JPH::RotatedTranslatedShapeSettings(JPH::Vec3(0.0f, halfCylinder + r, 0.0f), JPH::Quat::sIdentity(), cap)
        .Create().Get();
}

} // namespace

const char* groundStateName(GroundState s) {
    switch (s) {
    case GroundState::OnGround: return "on-ground";
    case GroundState::OnSteepGround: return "on-steep-ground";
    case GroundState::NotSupported: return "not-supported";
    case GroundState::InAir: return "in-air";
    }
    return "?";
}

struct Character::Impl {
    Impl(PhysicsWorld::Impl& w, const CharacterSettings& s, const glm::vec3& feet) : world(w), settings(s) {
        standing = capsule(s.standingHeight, s.radius);
        crouching = capsule(s.crouchingHeight, s.radius);
        JPH::Ref<JPH::CharacterVirtualSettings> cs = new JPH::CharacterVirtualSettings();
        cs->mShape = standing;
        cs->mMaxSlopeAngle = JPH::DegreesToRadians(s.maxSlopeDeg);
        cs->mMass = s.mass;
        cs->mMaxStrength = s.maxStrength;
        // Contacts below the lower hemisphere's centre support the character.
        cs->mSupportingVolume = JPH::Plane(JPH::Vec3::sAxisY(), -s.radius);
        if (s.innerBody) {
            cs->mInnerBodyShape = standing;
            cs->mInnerBodyLayer = Layers::Character;
        }
        character = new JPH::CharacterVirtual(cs, JPH::RVec3(feet.x, feet.y, feet.z), JPH::Quat::sIdentity(), 0,
                                              world.system.get());
        refresh();
    }

    void refresh() {
        character->RefreshContacts(bp, layers, bodies, shapes, *world.temp);
    }

    PhysicsWorld::Impl& world;
    CharacterSettings settings;
    JPH::RefConst<JPH::Shape> standing, crouching;
    JPH::Ref<JPH::CharacterVirtual> character;
    // The character queries the world as a Layers::Character object (Static + Moving +
    // other characters; its own inner body is skipped by Jolt).
    JPH::DefaultBroadPhaseLayerFilter bp{world.objVsBp, Layers::Character};
    JPH::DefaultObjectLayerFilter layers{world.pairs, Layers::Character};
    JPH::BodyFilter bodies;
    JPH::ShapeFilter shapes;
    bool isCrouched = false;
};

Character::Character(PhysicsWorld& world, const CharacterSettings& settings, const glm::vec3& feet)
    : impl_(std::make_unique<Impl>(*world.impl_, settings, feet)) {}

Character::~Character() = default;

void Character::update(float dt) {
    Impl& m = *impl_;
    JPH::CharacterVirtual::ExtendedUpdateSettings ext;
    ext.mWalkStairsStepUp = JPH::Vec3(0.0f, m.settings.stepHeight, 0.0f);
    ext.mStickToFloorStepDown = JPH::Vec3(0.0f, -m.settings.stickToFloor, 0.0f);
    m.character->ExtendedUpdate(dt, m.world.system->GetGravity(), ext, m.bp, m.layers, m.bodies, m.shapes, *m.world.temp);
    m.character->UpdateGroundVelocity();
}

glm::vec3 Character::position() const {
    const JPH::RVec3 p = impl_->character->GetPosition();
    return {float(p.GetX()), float(p.GetY()), float(p.GetZ())};
}

void Character::setPosition(const glm::vec3& feet) {
    impl_->character->SetPosition(JPH::RVec3(feet.x, feet.y, feet.z));
    impl_->refresh();
}

glm::vec3 Character::velocity() const { return toG(impl_->character->GetLinearVelocity()); }
void Character::setVelocity(const glm::vec3& v) { impl_->character->SetLinearVelocity(toJ(v)); }

GroundState Character::groundState() const {
    switch (impl_->character->GetGroundState()) {
    case JPH::CharacterBase::EGroundState::OnGround: return GroundState::OnGround;
    case JPH::CharacterBase::EGroundState::OnSteepGround: return GroundState::OnSteepGround;
    case JPH::CharacterBase::EGroundState::NotSupported: return GroundState::NotSupported;
    case JPH::CharacterBase::EGroundState::InAir: return GroundState::InAir;
    }
    return GroundState::InAir;
}

glm::vec3 Character::groundNormal() const { return toG(impl_->character->GetGroundNormal()); }
glm::vec3 Character::groundVelocity() const { return toG(impl_->character->GetGroundVelocity()); }

bool Character::setCrouched(bool crouched) {
    Impl& m = *impl_;
    if (crouched == m.isCrouched) return true;
    const JPH::Shape* shape = crouched ? m.crouching.GetPtr() : m.standing.GetPtr();
    // Growing back to standing height must not push into geometry (FLT_MAX would force it).
    const float maxPenetration = crouched ? FLT_MAX : 1.5f * m.character->GetCharacterPadding();
    if (!m.character->SetShape(shape, maxPenetration, m.bp, m.layers, m.bodies, m.shapes, *m.world.temp)) return false;
    if (m.settings.innerBody) m.character->SetInnerBodyShape(shape);
    m.isCrouched = crouched;
    return true;
}

bool Character::crouched() const { return impl_->isCrouched; }
float Character::height() const { return impl_->isCrouched ? impl_->settings.crouchingHeight : impl_->settings.standingHeight; }
const CharacterSettings& Character::settings() const { return impl_->settings; }
BodyHandle Character::innerBody() const { return toH(impl_->character->GetInnerBodyID()); }

} // namespace coe::physics
