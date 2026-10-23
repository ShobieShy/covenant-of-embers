// SPDX-License-Identifier: Apache-2.0
// First-person camera math (BUILD_PLAN step 10). World space is right-handed,
// +Y up, -Z forward at yaw 0 (same convention as glTF and Magewar's Godot scenes).
// Projection is Vulkan-native: clip-space Y points down and depth is reverse-Z
// with an infinite far plane (near plane -> 1, infinity -> 0), so the depth
// buffer is cleared to 0 and tested with GREATER. Reverse-Z on a float depth
// buffer keeps precision roughly constant with distance, which suits the tiny
// 5 cm near plane an FPS viewmodel needs.
#pragma once
#include <glm/glm.hpp>

namespace coe {

struct Camera {
    // Godot's Camera3D defaults, which Magewar keeps (no override in cogito_player.tscn):
    // 75 deg *vertical* FOV (keep_height, so wider screens see more), near 0.05 m.
    // Godot's far plane (4000 m) is not needed with an infinite reverse-Z projection.
    static constexpr float kDefaultFovYDeg = 75.0f;
    static constexpr float kDefaultNear = 0.05f;
    static constexpr float kMaxPitch = 1.5533430f;   // +-89 deg (no flip at the poles)
    // Step 19: the viewmodel (step 21) is drawn with its own fixed 75 deg vertical FOV so
    // focusing (ADS) zooms the world, not the staff (Magewar project.godot shader global
    // viewmodel_fov = 75).
    static constexpr float kViewmodelFovYDeg = 75.0f;

    glm::vec3 position{0.0f};
    float yaw = 0.0f;     // radians around +Y; positive turns left (counter-clockwise from above)
    float pitch = 0.0f;   // radians; positive looks up; keep within +-kMaxPitch
    float fovYDeg = kDefaultFovYDeg;
    float nearZ = kDefaultNear;

    glm::vec3 forward() const;                       // unit view direction
    glm::mat4 view() const;                          // world -> view (camera looks down -Z)
    glm::mat4 projection(float aspect) const;        // view -> Vulkan clip (reverse-Z, infinite far)
    glm::mat4 viewProjection(float aspect) const { return projection(aspect) * view(); }

    // Step 19: mouse-look scale at a zoomed FOV, tan(fov/2) / tan(hip/2), so a mouse count
    // moves the image under the crosshair by the same screen fraction at any zoom
    // (55 deg vs 75 deg: 0.6784). 1 at the hip FOV.
    static float lookScaleForFov(float fovYDeg, float hipFovYDeg = kDefaultFovYDeg);
};

} // namespace coe
