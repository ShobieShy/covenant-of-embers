// SPDX-License-Identifier: Apache-2.0
// Unit tests for engine/core/fixed_timestep + the interpolated TumbleDemo state
// (BUILD_PLAN step 8). doctest cases (step 20), run by coe_tests.
#include "engine/core/fixed_timestep.hpp"
#include "game/core/tumble_demo.hpp"

#include <doctest/doctest.h>

#include <cmath>
#include <cstdint>
#include <vector>

namespace {

constexpr uint64_t kSec = coe::FixedTimestep::kNsPerSecond;

// Splits `total` ns into frames from a fixed pseudo-random sequence (1..40 ms).
std::vector<uint64_t> jitteredFrames(uint64_t total, uint32_t seed) {
    std::vector<uint64_t> out;
    uint64_t left = total;
    while (left) {
        seed = seed * 1664525u + 1013904223u;
        uint64_t f = 1'000'000ull + (seed >> 8) % 39'000'000ull;
        if (f > left) f = left;
        out.push_back(f);
        left -= f;
    }
    return out;
}

TEST_CASE("fixed_timestep: 3 s at any frame rate is 180 ticks") {
    // Steady 60/144/30 fps (frame times that don't divide evenly into ns) and jitter.
    for (uint64_t fps : {60ull, 144ull, 30ull, 240ull}) {
        coe::FixedTimestep step(60);
        uint64_t fed = 0, ticks = 0;
        for (uint64_t i = 1; i <= 3 * fps; ++i) {     // frame i ends at i*kSec/fps exactly
            uint64_t end = i * 3 * kSec / (3 * fps);
            ticks += step.advance(end - fed);
            fed = end;
        }
        CHECK(fed == 3 * kSec);
        CHECK(ticks == 180);
        CHECK(step.totalTicks() == 180);
        CHECK(step.alpha() == 0.0);
        CHECK(step.droppedNs() == 0);
    }
    for (uint32_t seed : {1u, 7u, 1234u}) {
        coe::FixedTimestep step(60);
        for (uint64_t f : jitteredFrames(3 * kSec, seed)) step.advance(f);
        CHECK(step.totalTicks() == 180);
    }
}

TEST_CASE("fixed_timestep: alpha is the fraction of a tick") {
    coe::FixedTimestep step(60);
    const uint64_t tickNs = kSec / 60;                 // 16'666'666 ns (1/3 ns short of a tick)
    CHECK(step.advance(tickNs / 2) == 0);
    CHECK(std::fabs(step.alpha() - 0.5) < 1e-6);
    CHECK(step.advance(tickNs / 2 + 1) == 1);          // completes the tick
    CHECK((step.alpha() >= 0.0 && step.alpha() < 1e-6));
    double prev = step.alpha();
    for (int i = 0; i < 10; ++i) {                     // grows monotonically until the next tick
        step.advance(1'000'000);
        CHECK((step.alpha() > prev && step.alpha() < 1.0));
        prev = step.alpha();
    }
    CHECK(step.advance(10'000'000) == 1);
    CHECK(step.alpha() < prev);
}

TEST_CASE("fixed_timestep: a hitch is clamped") {
    coe::FixedTimestep step(60, 250'000'000ull);
    CHECK(step.advance(2 * kSec) == 15);               // 0.25 s worth, not 120 ticks
    CHECK(step.droppedNs() == 2 * kSec - 250'000'000ull);
    CHECK(step.advance(0) == 0);
}

TEST_CASE("fixed_timestep: other tick rates") {
    coe::FixedTimestep step(120);
    for (uint64_t f : jitteredFrames(kSec, 99u)) step.advance(f);
    CHECK(step.totalTicks() == 120);
    CHECK(std::fabs(step.dtSeconds() - 1.0 / 120.0) < 1e-12);
}

TEST_CASE("fixed_timestep: tumble demo interpolates") {
    using coe::game::TumbleDemo;
    TumbleDemo s;
    const double dt = 1.0 / 60.0;
    s.tick(dt);
    s.tick(dt);
    const double a = TumbleDemo::kYawRadPerSecond * dt, b = TumbleDemo::kPitchRadPerSecond * dt;
    CHECK(std::fabs(s.renderYaw(0.0) - (TumbleDemo::kStartYaw + a)) < 1e-6);
    CHECK(std::fabs(s.renderYaw(0.5) - (TumbleDemo::kStartYaw + 1.5 * a)) < 1e-6);
    CHECK(std::fabs(s.renderYaw(1.0) - (TumbleDemo::kStartYaw + 2.0 * a)) < 1e-6);
    CHECK(std::fabs(s.renderPitch(0.5) - (TumbleDemo::kStartPitch + 1.5 * b)) < 1e-6);
    // Across the 2pi wrap the blended angle still moves forward (wrapped after lerp).
    TumbleDemo w;
    w.prevYaw = 6.28; w.currYaw = 6.29;
    CHECK(w.renderYaw(0.0) > 6.27f);
    CHECK(w.renderYaw(1.0) < 0.01f);
    CHECK(w.renderYaw(1.0) >= 0.0f);
    // The model matrix carries the interpolated pose: translation stays put, rotation is rigid.
    const glm::mat4 m = s.renderModel(0.5);
    CHECK(std::fabs(m[3][2] + TumbleDemo::kDistance) < 1e-6f);
    CHECK(std::fabs(glm::length(glm::vec3(m[0])) - 1.0f) < 1e-5f);
    CHECK(std::fabs(glm::dot(glm::vec3(m[0]), glm::vec3(m[1]))) < 1e-5f);
}
} // namespace
