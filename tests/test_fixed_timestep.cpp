// SPDX-License-Identifier: Apache-2.0
// Unit tests for engine/core/fixed_timestep + the interpolated CubeDemo state
// (BUILD_PLAN step 8). Plain checks; moves to doctest in step 20.
#include "engine/core/fixed_timestep.hpp"
#include "game/core/cube_demo.hpp"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

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

void threeSecondsIs180Ticks() {
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

void alphaIsFractionOfTick() {
    coe::FixedTimestep step(60);
    const uint64_t tickNs = kSec / 60;                 // 16'666'666 ns (1/3 ns short of a tick)
    CHECK(step.advance(tickNs / 2) == 0);
    CHECK(std::fabs(step.alpha() - 0.5) < 1e-6);
    CHECK(step.advance(tickNs / 2 + 1) == 1);          // completes the tick
    CHECK(step.alpha() >= 0.0 && step.alpha() < 1e-6);
    double prev = step.alpha();
    for (int i = 0; i < 10; ++i) {                     // grows monotonically until the next tick
        step.advance(1'000'000);
        CHECK(step.alpha() > prev && step.alpha() < 1.0);
        prev = step.alpha();
    }
    CHECK(step.advance(10'000'000) == 1);
    CHECK(step.alpha() < prev);
}

void hitchIsClamped() {
    coe::FixedTimestep step(60, 250'000'000ull);
    CHECK(step.advance(2 * kSec) == 15);               // 0.25 s worth, not 120 ticks
    CHECK(step.droppedNs() == 2 * kSec - 250'000'000ull);
    CHECK(step.advance(0) == 0);
}

void otherRates() {
    coe::FixedTimestep step(120);
    for (uint64_t f : jitteredFrames(kSec, 99u)) step.advance(f);
    CHECK(step.totalTicks() == 120);
    CHECK(std::fabs(step.dtSeconds() - 1.0 / 120.0) < 1e-12);
}

void cubeInterpolates() {
    using coe::game::CubeDemo;
    CubeDemo s;
    const double dt = 1.0 / 60.0;
    s.tick(dt);
    s.tick(dt);
    const double a = CubeDemo::kYawRadPerSecond * dt, b = CubeDemo::kPitchRadPerSecond * dt;
    CHECK(std::fabs(s.renderYaw(0.0) - (CubeDemo::kStartYaw + a)) < 1e-6);
    CHECK(std::fabs(s.renderYaw(0.5) - (CubeDemo::kStartYaw + 1.5 * a)) < 1e-6);
    CHECK(std::fabs(s.renderYaw(1.0) - (CubeDemo::kStartYaw + 2.0 * a)) < 1e-6);
    CHECK(std::fabs(s.renderPitch(0.5) - (CubeDemo::kStartPitch + 1.5 * b)) < 1e-6);
    // Across the 2pi wrap the blended angle still moves forward (wrapped after lerp).
    CubeDemo w;
    w.prevYaw = 6.28; w.currYaw = 6.29;
    CHECK(w.renderYaw(0.0) > 6.27f);
    CHECK(w.renderYaw(1.0) < 0.01f);
    CHECK(w.renderYaw(1.0) >= 0.0f);
    // The model matrix carries the interpolated pose: translation stays put, rotation is rigid.
    const glm::mat4 m = s.renderModel(0.5);
    CHECK(std::fabs(m[3][2] + CubeDemo::kDistance) < 1e-6f);
    CHECK(std::fabs(glm::length(glm::vec3(m[0])) - 1.0f) < 1e-5f);
    CHECK(std::fabs(glm::dot(glm::vec3(m[0]), glm::vec3(m[1]))) < 1e-5f);
}
} // namespace

int main() {
    threeSecondsIs180Ticks();
    alphaIsFractionOfTick();
    hitchIsClamped();
    otherRates();
    cubeInterpolates();
    std::printf("fixed_timestep tests: %s (%d failures)\n", g_failures ? "FAIL" : "PASS", g_failures);
    return g_failures ? 1 : 0;
}
