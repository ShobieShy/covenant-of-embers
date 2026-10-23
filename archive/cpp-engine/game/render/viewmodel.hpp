// SPDX-License-Identifier: Apache-2.0
// First-person viewmodel (BUILD_PLAN step 21): the held staff or wand as a greybox
// (a wooden shaft + a gem head tinted by the wieldable's element colour from
// elements.toml), posed in view space and drawn by the renderer's viewmodel pass
// (FrameParams::viewmodelDraws: own 75 deg FOV, depth cleared, so it never clips walls
// and focusing zooms only the world).
//
// Magewar reference (read-only; Player.tscn's wieldable holder + staff/wand scenes and
// their `CastPoint` Marker3D): the wieldable hangs at the lower right of the view and
// bolts leave from its CastPoint. Reinterpreted here:
//  - The tip points along view -Z in every pose; Magewar's staff scenes point the model
//    along +Z and the wand along -Y with the CastPoint rotated to match (inconsistent
//    axes; logged as a mismatch, nothing to port).
//  - Focus slides the weapon toward the centre by Focus::amount() (Magewar animates an
//    ADS pose; same intent, no animation data yet - real meshes/anims are step 44+).
//  - A swap lowers the old weapon for the first half of the equip time and raises the
//    new one for the second half (Magewar: unequip then equip animation).
//  - Bolts still fly along the eye ray (hits go where the crosshair is); only the
//    tracer starts at the cast point and converges onto the ray (ProjectileSpawn::visualOffset).
#pragma once
#include "engine/assets/mesh_data.hpp"
#include "engine/render/camera.hpp"
#include "engine/render/vk_renderer.hpp"
#include "game/magic/loadout.hpp"
#include "game/magic/wieldable.hpp"

#include <glm/glm.hpp>

#include <string>
#include <vector>

namespace coe::game {

struct ViewmodelPose {
    glm::vec3 hand{0.0f};        // view space (m): where the grip sits at rest
    float pitchDeg = 0.0f;       // tip tilted up
    float yawDeg = 0.0f;         // tip turned toward the centre
    float castDistance = 0.0f;   // m from the hand along the tip axis: the CastPoint / head centre
    float shaftBack = 0.0f;      // m of shaft behind the hand
    float shaftRadius = 0.0f, headRadius = 0.0f;
    glm::vec3 shaftColor{0.0f};  // linear
};
const ViewmodelPose& viewmodelPose(WieldableType t);

struct ViewmodelTuning {
    float adsCentre = 0.6f;      // fully focused: hand.x moves this fraction toward 0
    float adsRaise = 0.04f;      // m up when fully focused
    float lowerDrop = 0.35f;     // m down when fully lowered (swap)
    float lowerPitchDeg = 35.0f; // tip turned down when fully lowered
};

// View-space transform of the wieldable's grip: tip along local -Z. focus 0..1
// (Focus::amount()), lowered 0 (held) .. 1 (out of view, mid-swap).
glm::mat4 viewmodelTransform(WieldableType t, float focus, float lowered, const ViewmodelTuning& tune = {});
// The head centre / CastPoint in view space.
glm::vec3 viewmodelCastPoint(WieldableType t, const glm::mat4& transform);

// What the loadout shows this frame: the previous slot's wieldable lowering in the first
// half of a swap, then the active one raising.
struct ViewmodelShown {
    const WieldableInstance* wieldable = nullptr;
    float lowered = 0.0f;
};
ViewmodelShown viewmodelShown(const Loadout& l);

// The world-space point that appears where a view-space viewmodel point does: the
// viewmodel is projected with vmFovYDeg and the world with camera.fovYDeg, so x and y
// scale by tan(world/2) / tan(vm/2) (same aspect), then the camera transform applies.
glm::vec3 viewmodelToWorld(const glm::vec3& viewPoint, const Camera& camera, float vmFovYDeg = Camera::kViewmodelFovYDeg);

// Greybox meshes, white vertices (colour comes from the draw tint).
assets::MeshData makeViewmodelShaft();   // cylinder r = 1 from z = 0 to z = -1
assets::MeshData makeViewmodelHead();    // gem (octahedron, long axis z) r = 1

struct ViewmodelMeshes { MeshId shaft = kInvalidMesh, head = kInvalidMesh; };
// Appends the shaft + head draws (view space) for a wieldable of type t posed at
// `transform`, the head tinted `headColor` (the element colour).
void appendViewmodelDraws(const ViewmodelMeshes& m, WieldableType t, const glm::mat4& transform,
                          const glm::vec3& headColor, std::vector<DrawItem>& out);

// Pixel position of a view-space point under the viewmodel projection (pixels from the
// top-left), false if behind the camera or off-screen.
bool viewmodelPixel(const glm::vec3& viewPoint, std::uint32_t width, std::uint32_t height, glm::vec2& outPx,
                    float vmFovYDeg = Camera::kViewmodelFovYDeg, float vmNear = 0.01f);

// Done-check: the head is visible in `f` at headPx and tinted by `elementColor` (the
// mean of a 5x5 block, decoded to linear when f.srgb, points the same way in RGB as the
// element colour: cosine >= 0.97, and is not dark). With `without` (the same frame drawn
// with no viewmodel) the block must also differ from it. `report` gets one line.
bool checkViewmodelHead(const HeadlessFrame& f, const HeadlessFrame* without, const glm::vec2& headPx,
                        const glm::vec3& elementColor, std::string& report);

} // namespace coe::game
