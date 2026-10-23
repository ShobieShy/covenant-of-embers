// SPDX-License-Identifier: Apache-2.0
// Checks on a resolved headless frame (VkRenderer::renderHeadless), run by
// `covenant --headless` and unit-tested on synthetic frames (tests/test_level.cpp).
#pragma once
#include "engine/render/vk_renderer.hpp"
#include "game/world/level.hpp"

#include <glm/glm.hpp>

#include <cstddef>
#include <string>

namespace coe::game {

struct LevelViewStats {
    std::size_t samples = 0;                 // grid samples taken
    std::size_t perKind[kBoxKindCount] = {};
    std::size_t sky = 0, skyWrongColor = 0;  // depth 0; colour not the clear colour
    std::size_t unexplained = 0;             // geometry not on any level box surface
    std::size_t msaaEdgePixels = 0;          // silhouette pixels blending sky + geometry (MSAA resolve)
    double groundMeanY = 0, skyMeanY = 0;    // in pixels, 0 = top
    int groundLumaMin = 255, groundLumaMax = 0, wallLumaMin = 255, wallLumaMax = 0;
    double groundSkyDiff = 0, wallSkyDiff = 0;   // mean |rgb - clear| (0..765)
};

// Unprojects a grid of depth samples through inverse(viewProj) and attributes each
// to the level box whose surface it lies on. Passes when floor (ground) and walls are
// both clearly visible, lit (not the clear colour), in the right half of the image,
// every drawn sample lies on some box (so transforms match the data), sky shows the
// clear colour, and (with MSAA) resolved edges exist. `report` gets a one-line summary.
bool checkLevelView(const Level& level, const HeadlessFrame& f, const glm::vec3& cameraPos,
                    const glm::vec3& clearColor, LevelViewStats& stats, std::string& report);

// Step 11's single-model check: corner shows the clear colour, the centre is lit and
// nearer than model0's origin (a back face winning would be behind it), shading varies.
bool checkModelView(const HeadlessFrame& f, const glm::mat4& model0, const glm::vec3& clearColor, std::string& report);

bool writePpm(const std::string& path, const HeadlessFrame& f);

} // namespace coe::game
