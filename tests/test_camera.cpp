// SPDX-License-Identifier: Apache-2.0
// Unit tests for engine/render/camera (BUILD_PLAN step 10): axis conventions,
// Vulkan clip space (Y down) and reverse-Z infinite-far depth. Plain checks; doctest in step 20.
#include "engine/render/camera.hpp"

#include <cmath>
#include <cstdio>
#include <glm/glm.hpp>

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

constexpr float kHalfPi = 1.5707963f;

bool near(float a, float b, float eps = 1e-5f) { return std::fabs(a - b) <= eps; }
bool near(glm::vec3 a, glm::vec3 b, float eps = 1e-5f) { return glm::length(a - b) <= eps; }

glm::vec3 toNdc(const coe::Camera& c, float aspect, glm::vec3 world) {
    const glm::vec4 clip = c.viewProjection(aspect) * glm::vec4(world, 1.0f);
    return glm::vec3(clip) / clip.w;
}

void defaults() {
    coe::Camera c;
    CHECK(c.fovYDeg == 75.0f);     // Magewar/Godot Camera3D default (vertical)
    CHECK(c.nearZ == 0.05f);
    CHECK(near(c.forward(), {0, 0, -1}));
}

void reverseZDepth() {
    coe::Camera c;
    const float aspect = 16.0f / 9.0f;
    CHECK(near(toNdc(c, aspect, {0, 0, -c.nearZ}).z, 1.0f));          // near plane -> 1
    CHECK(near(toNdc(c, aspect, {0, 0, -1.0f}).z, c.nearZ));          // depth = near / distance
    CHECK(toNdc(c, aspect, {0, 0, -1e6f}).z < 1e-6f);                 // infinity -> 0
    CHECK(toNdc(c, aspect, {0, 0, -1e6f}).z > 0.0f);
    // Strictly monotonic: nearer is larger (depth test GREATER).
    CHECK(toNdc(c, aspect, {0, 0, -2.0f}).z > toNdc(c, aspect, {0, 0, -3.0f}).z);
    // Behind the camera gives w < 0, so it is clipped.
    const glm::vec4 behind = c.viewProjection(aspect) * glm::vec4(0, 0, 1, 1);
    CHECK(behind.w < 0.0f);
}

void clipAxes() {
    coe::Camera c;
    const float aspect = 2.0f;
    const glm::vec3 centre = toNdc(c, aspect, {0, 0, -5});
    CHECK(near(centre.x, 0.0f) && near(centre.y, 0.0f));
    CHECK(toNdc(c, aspect, {0, 1, -5}).y < 0.0f);                     // world up -> Vulkan NDC up (negative y)
    CHECK(toNdc(c, aspect, {1, 0, -5}).x > 0.0f);                     // world right -> +x
    // Vertical FOV: a point on the top frustum edge lands at ndc y = -1 regardless of aspect.
    const float t = std::tan(glm::radians(c.fovYDeg) * 0.5f);
    CHECK(near(toNdc(c, aspect, {0, 5 * t, -5}).y, -1.0f));
    CHECK(near(toNdc(c, 1.0f, {0, 5 * t, -5}).y, -1.0f));
    // Horizontal extent scales with aspect (keep_height: wider screens see more).
    CHECK(near(toNdc(c, aspect, {5 * t * aspect, 0, -5}).x, 1.0f));
}

void yawPitch() {
    coe::Camera c;
    c.yaw = kHalfPi;                                                   // positive yaw turns left
    CHECK(near(c.forward(), {-1, 0, 0}));
    const glm::vec3 ahead = toNdc(c, 1.0f, {-5, 0, 0});
    CHECK(near(ahead.x, 0.0f) && near(ahead.y, 0.0f) && ahead.z > 0.0f);
    c.yaw = 0.0f; c.pitch = 0.5f;                                      // positive pitch looks up
    CHECK(c.forward().y > 0.0f);
    const glm::vec3 f = c.forward() * 4.0f;
    const glm::vec3 up = toNdc(c, 1.0f, f);
    CHECK(near(up.x, 0.0f) && near(up.y, 0.0f));
    CHECK(near(glm::length(c.forward()), 1.0f));
}

void translation() {
    coe::Camera c;
    c.position = {3, 1.7f, -2};
    const glm::vec3 ndc = toNdc(c, 1.0f, c.position + glm::vec3(0, 0, -1));
    CHECK(near(ndc.x, 0.0f) && near(ndc.y, 0.0f) && near(ndc.z, c.nearZ));
    // view() maps the eye to the origin.
    const glm::vec4 eye = c.view() * glm::vec4(c.position, 1.0f);
    CHECK(near(glm::vec3(eye), {0, 0, 0}));
}
} // namespace

int main() {
    defaults();
    reverseZDepth();
    clipAxes();
    yawPitch();
    translation();
    std::printf("camera tests: %s (%d failures)\n", g_failures ? "FAIL" : "PASS", g_failures);
    return g_failures ? 1 : 0;
}
