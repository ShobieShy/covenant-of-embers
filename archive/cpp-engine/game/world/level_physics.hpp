// SPDX-License-Identifier: Apache-2.0
// Greybox level -> physics colliders (BUILD_PLAN step 13): one static Jolt box per
// LevelBox, half extents size/2, placed at `center` with the renderer's rotation
// (LevelBox::rotation(), Ry * Rx * Rz), so what you see is exactly what you collide with.
#pragma once
#include "engine/physics/physics.hpp"
#include "game/world/level.hpp"

#include <vector>

namespace coe::game {

// Object layer per box kind. Every greybox kind is level geometry for now (static);
// dynamic crates/heaps or a separate interactables layer would change it here.
physics::ObjectLayer objectLayerFor(BoxKind kind);
// Surface friction per box kind. All kinds use Jolt's default 0.2 for now (so a box
// slides off a 20.6 degree ramp). Magewar sets no PhysicsMaterial, i.e. Godot's
// friction 1.0 everywhere; see ADR-0001 / BUILD_PLAN for when that gets revisited.
float frictionFor(BoxKind kind);

struct LevelPhysics {
    std::vector<physics::BodyHandle> bodies;   // index i = level.boxes[i]
};

// Adds the level's boxes to `world` as static bodies and optimises the broad phase.
LevelPhysics buildLevelPhysics(const Level& level, physics::PhysicsWorld& world);

} // namespace coe::game
