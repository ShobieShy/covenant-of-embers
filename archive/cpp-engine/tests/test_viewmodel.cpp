// SPDX-License-Identifier: Apache-2.0
// Viewmodel tests (BUILD_PLAN step 21): staff / wand poses, focus and swap offsets, the
// CastPoint, view-to-world mapping across the two FOVs, the head-colour Done-check on
// synthetic frames, and the tracer starting at the CastPoint (ProjectileSpawn::visualOffset).
#include "engine/physics/physics.hpp"
#include "engine/render/camera.hpp"
#include "game/combat/element.hpp"
#include "game/magic/loadout.hpp"
#include "game/magic/projectile.hpp"
#include "game/render/viewmodel.hpp"

#include <doctest/doctest.h>
#include <glm/glm.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {

using namespace coe;
using namespace coe::game;

constexpr float kDt = 1.0f / 60.0f;
constexpr std::uint32_t kW = 1280, kH = 720;

bool near(float a, float b, float eps = 1e-4f) { return std::fabs(a - b) <= eps; }
bool near(const glm::vec3& a, const glm::vec3& b, float eps = 1e-4f) { return glm::length(a - b) <= eps; }

TEST_CASE("viewmodel: rest poses sit lower right with the head on screen") {
    for (const WieldableType t : {WieldableType::Staff, WieldableType::Wand}) {
        CAPTURE(int(t));
        const ViewmodelPose& p = viewmodelPose(t);
        const glm::mat4 m = viewmodelTransform(t, 0.0f, 0.0f);
        CHECK(near(glm::vec3(m[3]), p.hand));
        const glm::vec3 tip = glm::normalize(glm::vec3(m * glm::vec4(0, 0, -1, 0)));
        CHECK((tip.z < -0.8f && tip.y > 0.0f && tip.x < 0.0f));   // forward, tipped up, toward the centre
        const glm::vec3 cp = viewmodelCastPoint(t, m);
        CHECK(near(glm::length(cp - p.hand), p.castDistance));
        glm::vec2 px;
        REQUIRE(viewmodelPixel(cp, kW, kH, px));
        CHECK((px.x > kW * 0.5f && px.y > kH * 0.5f));   // lower right
        std::printf("viewmodel: %s head at (%.0f, %.0f) of %ux%u\n", t == WieldableType::Staff ? "staff" : "wand",
                    double(px.x), double(px.y), kW, kH);
    }
    const ViewmodelPose &s = viewmodelPose(WieldableType::Staff), &w = viewmodelPose(WieldableType::Wand);
    CHECK((s.castDistance > w.castDistance && s.headRadius > w.headRadius && s.shaftRadius > w.shaftRadius));
}

TEST_CASE("viewmodel: focus slides toward the centre, a swap lowers out of view") {
    const ViewmodelTuning tune;
    for (const WieldableType t : {WieldableType::Staff, WieldableType::Wand}) {
        const ViewmodelPose& p = viewmodelPose(t);
        const glm::mat4 ads = viewmodelTransform(t, 1.0f, 0.0f);
        CHECK(near(ads[3].x, p.hand.x * (1.0f - tune.adsCentre)));
        CHECK(near(ads[3].y, p.hand.y + tune.adsRaise));
        CHECK(near(glm::vec3(viewmodelTransform(t, 0.5f, 0.0f)[3]).x, p.hand.x * (1.0f - 0.5f * tune.adsCentre)));
        glm::vec2 hip, foc;
        REQUIRE(viewmodelPixel(viewmodelCastPoint(t, viewmodelTransform(t, 0, 0)), kW, kH, hip));
        REQUIRE(viewmodelPixel(viewmodelCastPoint(t, ads), kW, kH, foc));
        const glm::vec2 c(kW * 0.5f, kH * 0.5f);
        CHECK(glm::length(foc - c) < glm::length(hip - c) * 0.75f);

        const glm::mat4 low = viewmodelTransform(t, 0.0f, 1.0f);
        CHECK(near(low[3].y, p.hand.y - tune.lowerDrop));
        glm::vec2 lp;
        const bool shown = viewmodelPixel(viewmodelCastPoint(t, low), kW, kH, lp);
        CHECK((!shown || lp.y > kH * 0.95f));   // fully lowered: the head is out of view
        // Clamped inputs.
        CHECK(near(glm::vec3(viewmodelTransform(t, 2.0f, -1.0f)[3]), glm::vec3(ads[3])));
    }
}

TEST_CASE("viewmodel: a swap shows the old weapon lowering, then the new one raising") {
    WieldableTable table;
    REQUIRE(loadWieldables(std::string(COE_DATA_DIR) + "/magic/wieldables.toml", table).empty());
    const WieldableInstance staff(*table.find("apprentice_fire_staff")), wand(*table.find("novice_arcane_wand"));
    Loadout l;
    l.equip(Slot::Staff, &staff);
    l.equip(Slot::Wand, &wand);
    ProjectileSystem bolts;
    const CastAim aim{};
    auto shownAfter = [&](int ticks) {
        for (int i = 0; i < ticks; ++i) l.tick(false, false, kDt, aim, bolts);
        return viewmodelShown(l);
    };
    ViewmodelShown s = viewmodelShown(l);
    CHECK((s.wieldable == &staff && s.lowered == 0.0f));
    l.select(Slot::Wand);
    s = viewmodelShown(l);
    CHECK((s.wieldable == &staff && near(s.lowered, 0.0f)));
    s = shownAfter(6);    // 25 %: staff half down
    CHECK((s.wieldable == &staff && near(s.lowered, 0.5f, 1e-3f)));
    s = shownAfter(5);    // 11 ticks: staff nearly out
    CHECK((s.wieldable == &staff && s.lowered > 0.9f));
    s = shownAfter(2);    // 13 ticks: wand coming up from the bottom
    CHECK((s.wieldable == &wand && s.lowered > 0.9f));
    s = shownAfter(5);    // 75 %: wand half up
    CHECK((s.wieldable == &wand && near(s.lowered, 0.5f, 1e-3f)));
    s = shownAfter(6);    // done
    CHECK((l.ready() && s.wieldable == &wand && s.lowered == 0.0f));
}

TEST_CASE("viewmodel: a view-space point maps to the world point drawn on the same pixel") {
    Camera cam;
    cam.position = {3.0f, 1.6f, -2.0f};
    cam.yaw = 0.7f;
    cam.pitch = -0.2f;
    const glm::vec3 cp = viewmodelCastPoint(WieldableType::Staff, viewmodelTransform(WieldableType::Staff, 0, 0));
    for (const float fov : {75.0f, 55.0f}) {   // hip (== viewmodel FOV) and focused
        CAPTURE(fov);
        cam.fovYDeg = fov;
        const glm::vec3 w = viewmodelToWorld(cp, cam);
        if (fov == 75.0f) CHECK(near(glm::vec3(cam.view() * glm::vec4(w, 1.0f)), cp));
        const glm::vec4 clip = cam.viewProjection(float(kW) / float(kH)) * glm::vec4(w, 1.0f);
        const glm::vec2 worldPx((clip.x / clip.w * 0.5f + 0.5f) * kW, (clip.y / clip.w * 0.5f + 0.5f) * kH);
        glm::vec2 vmPx;
        REQUIRE(viewmodelPixel(cp, kW, kH, vmPx));
        CHECK(glm::length(worldPx - vmPx) < 0.05f);
    }
    glm::vec2 px;
    CHECK(!viewmodelPixel({0, 0, 1}, kW, kH, px));      // behind
    CHECK(!viewmodelPixel({5, 0, -1}, kW, kH, px));     // off to the right
    CHECK(!viewmodelPixel({0, 0, -1}, 0, kH, px));
}

TEST_CASE("viewmodel: greybox meshes are closed and face outward") {
    for (const assets::MeshData& m : {makeViewmodelShaft(), makeViewmodelHead()}) {
        REQUIRE(m.triangleCount() > 0);
        glm::vec3 centre(0.0f);
        for (const auto& v : m.vertices) centre += v.position;
        centre /= float(m.vertices.size());
        for (size_t i = 0; i + 2 < m.indices.size(); i += 3) {
            const glm::vec3 a = m.vertices[m.indices[i]].position, b = m.vertices[m.indices[i + 1]].position,
                            c = m.vertices[m.indices[i + 2]].position;
            const glm::vec3 n = glm::cross(b - a, c - a);
            CHECK(glm::dot(n, (a + b + c) / 3.0f - centre) > 0.0f);   // CCW seen from outside
        }
        for (const auto& v : m.vertices) CHECK(v.color == glm::vec4(1.0f));   // tinted per draw
    }
}

HeadlessFrame frame(glm::vec3 bg, bool srgb) {
    HeadlessFrame f;
    f.width = f.height = 32;
    f.srgb = srgb;
    f.rgba.resize(32 * 32 * 4);
    for (size_t i = 0; i < f.rgba.size(); i += 4)
        for (int c = 0; c < 4; ++c) f.rgba[i + c] = c == 3 ? 255 : std::uint8_t(std::lround(bg[c] * 255.0f));
    return f;
}
void paint(HeadlessFrame& f, glm::vec2 at, glm::vec3 linear) {
    const auto enc = [&](float x) {
        if (f.srgb) x = x <= 0.0031308f ? x * 12.92f : 1.055f * std::pow(x, 1.0f / 2.4f) - 0.055f;
        return std::uint8_t(std::lround(std::clamp(x, 0.0f, 1.0f) * 255.0f));
    };
    for (int y = int(at.y) - 4; y <= int(at.y) + 4; ++y)
        for (int x = int(at.x) - 4; x <= int(at.x) + 4; ++x)
            for (int c = 0; c < 3; ++c) f.rgba[(size_t(y) * f.width + size_t(x)) * 4 + size_t(c)] = enc(linear[c]);
}

TEST_CASE("viewmodel: the head check wants the element colour, visible, over the scene") {
    ElementTable el;
    REQUIRE(loadElements(std::string(COE_DATA_DIR) + "/magic/elements.toml", el).empty());
    const glm::vec3 fire = el.color(Element::Fire), arcane = el.color(Element::Arcane), bg(0.3f, 0.32f, 0.35f);
    const glm::vec2 at(16, 16);
    std::string report;
    for (const bool srgb : {false, true}) {
        CAPTURE(srgb);
        const HeadlessFrame without = frame(bg, srgb);
        HeadlessFrame f = without;
        paint(f, at, fire * 0.7f);   // shaded but the same hue
        CHECK(checkViewmodelHead(f, &without, at, fire, report));
        CHECK(checkViewmodelHead(f, nullptr, at, fire, report));
        CHECK(!checkViewmodelHead(f, &without, at, arcane, report));   // wrong element colour
        CHECK(!checkViewmodelHead(without, &without, at, bg, report)); // nothing drawn there
        CHECK(!checkViewmodelHead(f, &without, {40, 5}, fire, report)); // off the frame
        HeadlessFrame dark = without;
        paint(dark, at, fire * 0.02f);
        CHECK(!checkViewmodelHead(dark, &without, at, fire, report));
    }
    std::printf("viewmodel: %s\n", report.c_str());
}

TEST_CASE("viewmodel: the tracer starts at the cast point and converges onto the eye ray") {
    physics::PhysicsWorld w;   // empty
    std::vector<ProjectileHit> hits;
    ProjectileSystem bolts;
    const glm::vec3 eye(0, 1.5f, 0), off(0.3f, -0.2f, -0.5f);
    ProjectileSpawn s{eye, {0, 0, -1}, 30.0f, 50.0f, Element::Fire, 10.0f, {}};
    s.visualOffset = off;
    bolts.spawn(s);
    bolts.tick(w, kDt, hits);   // 0.5 m out
    std::vector<DebugLine> lines;
    bolts.debugLines(1.0f, lines);
    REQUIRE(lines.size() == 1);
    CHECK(near(lines[0].a, eye + off));   // from the cast point, not kSkipNear ahead of the eye
    CHECK(near(lines[0].b, eye + glm::vec3(0, 0, -0.5f) + off * (1.0f - 0.5f / ProjectileSystem::kConverge)));
    for (int i = 0; i < 19; ++i) bolts.tick(w, kDt, hits);   // 10 m out
    lines.clear();
    bolts.debugLines(1.0f, lines);
    REQUIRE(lines.size() == 1);
    CHECK(near(lines[0].b, eye + glm::vec3(0, 0, -10.0f)));   // on the ray past kConverge
    CHECK(near(lines[0].a, eye + glm::vec3(0, 0, -7.5f) + off * (1.0f - 7.5f / ProjectileSystem::kConverge)));
    CHECK(hits.empty());
}

} // namespace
