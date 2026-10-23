// SPDX-License-Identifier: Apache-2.0
#include "game/world/level_physics.hpp"

#include <glm/gtc/quaternion.hpp>

namespace coe::game {

physics::ObjectLayer objectLayerFor(BoxKind kind) {
    switch (kind) {
    case BoxKind::Ground:
    case BoxKind::Wall:
    case BoxKind::Ramp:
    case BoxKind::Crate:
    case BoxKind::Heap:
    case BoxKind::Platform:
        return physics::Layers::Static;
    }
    return physics::Layers::Static;
}

float frictionFor(BoxKind) { return 0.2f; }

LevelPhysics buildLevelPhysics(const Level& level, physics::PhysicsWorld& world) {
    LevelPhysics out;
    out.bodies.reserve(level.boxes.size());
    for (const LevelBox& b : level.boxes) {
        physics::BoxDesc d;
        d.center = b.center;
        d.halfExtents = b.size * 0.5f;
        d.rotation = glm::quat_cast(b.rotation());
        d.layer = objectLayerFor(b.kind);
        d.friction = frictionFor(b.kind);
        out.bodies.push_back(world.addStaticBox(d));
    }
    world.optimizeBroadPhase();
    return out;
}

} // namespace coe::game
