// SPDX-License-Identifier: Apache-2.0
// Monotonic clock for the main loop (nanoseconds). Kept separate from SDL so
// engine/core stays SDL-free and unit-testable.
#pragma once
#include <chrono>
#include <cstdint>

namespace coe {
inline uint64_t monotonicNs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
} // namespace coe
