// SPDX-License-Identifier: Apache-2.0
#pragma once
// PNG / JPEG decoding to RGBA8 (BUILD_PLAN step 21) via stb_image, for glTF
// base-colour textures. Plain data, no Vulkan.

#include "engine/assets/mesh_data.hpp"

#include <cstddef>
#include <span>
#include <string>

namespace coe::assets {

// Largest accepted width or height; bigger images are rejected, not downscaled.
inline constexpr std::uint32_t kMaxImageDim = 8192;

// Decodes a PNG or JPEG held in memory into `out` (RGBA8, row 0 = top). Returns an
// empty string on success, else a message naming `name`.
std::string decodeImage(std::span<const std::byte> bytes, const std::string& name, ImageData& out);

} // namespace coe::assets
