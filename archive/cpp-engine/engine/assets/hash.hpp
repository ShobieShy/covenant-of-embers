#pragma once
// Content hash shared by tools/asset_cooker (writes manifest.json) and the runtime
// manifest reader (verifies cooked files). FNV-1a 64: fast, dependency-free, and
// only used to detect stale/corrupt cooked files, not for security.

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>

namespace coe::assets {

inline std::uint64_t fnv1a64(const void* data, std::size_t size) {
    const auto* p = static_cast<const unsigned char*>(data);
    std::uint64_t h = 0xcbf29ce484222325ull;
    for (std::size_t i = 0; i < size; ++i) {
        h ^= p[i];
        h *= 0x100000001b3ull;
    }
    return h;
}

inline std::string fnv1a64Hex(const void* data, std::size_t size) {
    char buf[17];
    std::snprintf(buf, sizeof buf, "%016llx", static_cast<unsigned long long>(fnv1a64(data, size)));
    return buf;
}

}  // namespace coe::assets
