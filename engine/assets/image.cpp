// SPDX-License-Identifier: Apache-2.0
#include "engine/assets/image.hpp"

#include <climits>
#include <cstring>

// The one stb_image implementation in the project (PNG + JPEG only, memory only).
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_MAX_DIMENSIONS 8192
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#pragma GCC diagnostic ignored "-Wsign-compare"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#endif
#include <stb_image.h>
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

namespace coe::assets {

std::string decodeImage(std::span<const std::byte> bytes, const std::string& name, ImageData& out) {
    if (bytes.empty()) return "image " + name + ": no data";
    if (bytes.size() > std::size_t(INT_MAX)) return "image " + name + ": too large";
    int w = 0, h = 0, channels = 0;
    stbi_uc* px = stbi_load_from_memory(reinterpret_cast<const stbi_uc*>(bytes.data()), int(bytes.size()), &w, &h,
                                        &channels, 4);
    if (!px) return "image " + name + ": decode failed (" + std::string(stbi_failure_reason()) + ")";
    if (w <= 0 || h <= 0 || std::uint32_t(w) > kMaxImageDim || std::uint32_t(h) > kMaxImageDim) {
        stbi_image_free(px);
        return "image " + name + ": bad size " + std::to_string(w) + "x" + std::to_string(h);
    }
    out.width = std::uint32_t(w);
    out.height = std::uint32_t(h);
    out.rgba.assign(px, px + std::size_t(w) * std::size_t(h) * 4);
    out.name = name;
    stbi_image_free(px);
    return {};
}

} // namespace coe::assets
