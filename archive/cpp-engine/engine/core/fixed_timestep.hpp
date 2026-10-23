// SPDX-License-Identifier: Apache-2.0
// Fixed-timestep accumulator ("fix your timestep"): gameplay/physics advance in
// whole ticks of 1/hz seconds, rendering runs at whatever rate the display allows
// and blends the last two simulation states with alpha().
//
// Time is kept in exact integer units (nanoseconds x hz), so N seconds of frame
// time always yields exactly N*hz ticks no matter how it is split into frames
// (no floating-point drift). A frame longer than maxFrameNs is clamped (the
// excess is counted in droppedNs()) so a hitch cannot trigger a "spiral of death".
#pragma once
#include <cstdint>

namespace coe {

class FixedTimestep {
public:
    static constexpr uint64_t kNsPerSecond = 1'000'000'000ull;

    explicit FixedTimestep(uint32_t hz = 60, uint64_t maxFrameNs = 250'000'000ull);

    // Feed one frame's real elapsed time; returns how many fixed ticks to run now.
    uint32_t advance(uint64_t frameNs);

    // Fraction of a tick left in the accumulator, in [0, 1): render state =
    // lerp(previous tick, current tick, alpha).
    double alpha() const { return double(acc_) / double(kNsPerSecond); }

    uint32_t hz() const { return hz_; }
    double dtSeconds() const { return 1.0 / double(hz_); }
    uint64_t totalTicks() const { return ticks_; }
    uint64_t droppedNs() const { return dropped_; }

private:
    uint32_t hz_;
    uint64_t maxFrameNs_;
    uint64_t acc_ = 0;       // pending time in ns*hz units; one tick = kNsPerSecond units
    uint64_t ticks_ = 0;
    uint64_t dropped_ = 0;
};

} // namespace coe
