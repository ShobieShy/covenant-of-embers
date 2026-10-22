// SPDX-License-Identifier: Apache-2.0
#include "engine/core/fixed_timestep.hpp"

namespace coe {

FixedTimestep::FixedTimestep(uint32_t hz, uint64_t maxFrameNs)
    : hz_(hz ? hz : 60), maxFrameNs_(maxFrameNs ? maxFrameNs : 250'000'000ull) {}

uint32_t FixedTimestep::advance(uint64_t frameNs) {
    if (frameNs > maxFrameNs_) {
        dropped_ += frameNs - maxFrameNs_;
        frameNs = maxFrameNs_;
    }
    acc_ += frameNs * hz_;                        // <= 0.25 s * hz: far from overflow
    const uint64_t n = acc_ / kNsPerSecond;
    acc_ -= n * kNsPerSecond;
    ticks_ += n;
    return static_cast<uint32_t>(n);
}

} // namespace coe
