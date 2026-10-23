// SPDX-License-Identifier: Apache-2.0
// Damage number tests (BUILD_PLAN step 22): one floating label per hit, coloured by the
// bolt's element (ElementTable::color), rising and fading over a second, projected to
// pixels the same way as the viewmodel check (Vulkan clip, +y down); and the pixel
// check covenant --headless runs on the overlay frame.
#include "engine/render/camera.hpp"
#include "game/combat/damage.hpp"
#include "game/combat/element.hpp"
#include "game/ui/damage_numbers.hpp"

#include <doctest/doctest.h>
#include <glm/glm.hpp>

#include <cstdio>
#include <string>
#include <vector>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
using namespace coe::game;

ElementTable elementsReal() {
    ElementTable t;
    const std::string err = loadElements(std::string(COE_DATA_DIR) + "/magic/elements.toml", t);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    REQUIRE(err.empty());
    return t;
}

DamageResult result(float amount, float eff = 1.0f, float crit = 1.0f) {
    DamageResult r;
    r.amount = amount;
    r.effectiveness = eff;
    r.crit = crit;
    return r;
}

coe::HeadlessFrame frame(std::uint32_t w, std::uint32_t h, glm::u8vec3 c) {
    coe::HeadlessFrame f;
    f.width = w;
    f.height = h;
    f.rgba.resize(std::size_t(w) * h * 4);
    for (std::size_t i = 0; i < f.rgba.size(); i += 4) {
        f.rgba[i] = c.r;
        f.rgba[i + 1] = c.g;
        f.rgba[i + 2] = c.b;
        f.rgba[i + 3] = 255;
    }
    return f;
}
void paint(coe::HeadlessFrame& f, int x0, int y0, int n, glm::u8vec3 c) {
    for (int y = y0; y < y0 + n; ++y)
        for (int x = x0; x < x0 + n; ++x) {
            std::uint8_t* p = &f.rgba[(std::size_t(y) * f.width + std::size_t(x)) * 4];
            p[0] = c.r;
            p[1] = c.g;
            p[2] = c.b;
        }
}
} // namespace

TEST_CASE("damage numbers: formatting") {
    CHECK(DamageNumbers::format(15.0f) == "15");
    CHECK(DamageNumbers::format(11.25f) == "11.3");
    CHECK(DamageNumbers::format(7.5f) == "7.5");
    CHECK(DamageNumbers::format(4.999f) == "5");
    CHECK(DamageNumbers::format(0.0f) == "0");
    CHECK(DamageNumbers::format(-3.0f) == "0");
}

TEST_CASE("damage numbers: element colour, scale by hit kind, rise, fade and expiry") {
    const ElementTable el = elementsReal();
    DamageNumbers n;
    n.add({0, 1, -5}, result(15.0f, 1.5f), Element::Fire, el);
    n.add({0, 1, -5}, result(5.0f, 0.5f), Element::Water, el);
    n.add({0, 1, -5}, result(30.0f, 1.5f, 2.0f), Element::Earth, el);
    n.add({0, 1, -5}, result(10.0f), Element::Arcane, el);
    REQUIRE(n.numbers().size() == 4);
    CHECK(n.numbers()[0].color == el.color(Element::Fire));
    CHECK(n.numbers()[1].color == el.color(Element::Water));
    CHECK(n.numbers()[0].scale == DamageNumbers::kStrongScale);
    CHECK(n.numbers()[1].scale == DamageNumbers::kWeakScale);
    CHECK(n.numbers()[2].scale == DamageNumbers::kCritScale);
    CHECK(n.numbers()[3].scale == 1.0f);
    CHECK(n.numbers()[0].driftX != n.numbers()[1].driftX);

    const DamageNumber& first = n.numbers()[0];
    CHECK(DamageNumbers::position(first).y == doctest::Approx(1.0f));
    CHECK(DamageNumbers::alpha(first) == 1.0f);
    for (int i = 0; i < 30; ++i) n.tick(1.0f / 60.0f);   // 0.5 s
    CHECK(DamageNumbers::position(n.numbers()[0]).y > 1.0f + 0.5f * DamageNumbers::kRise);   // ease-out: past halfway
    CHECK(DamageNumbers::alpha(n.numbers()[0]) == 1.0f);
    for (int i = 0; i < 18; ++i) n.tick(1.0f / 60.0f);   // 0.8 s: fading
    const float a = DamageNumbers::alpha(n.numbers()[0]);
    CHECK((a > 0.0f && a < 1.0f));
    for (int i = 0; i < 13; ++i) n.tick(1.0f / 60.0f);   // past 1 s: gone
    CHECK(n.numbers().empty());
}

TEST_CASE("damage numbers: labels project to pixels; behind the camera is skipped; capped") {
    const ElementTable el = elementsReal();
    coe::Camera cam;   // at the origin looking down -Z
    const glm::vec2 vp{256, 256};
    const glm::mat4 m = cam.viewProjection(1.0f);
    DamageNumbers n;
    n.add({0, 0, -5}, result(15.0f, 1.5f), Element::Fire, el);   // straight ahead
    n.add({0, 0, 5}, result(15.0f), Element::Fire, el);          // behind
    std::vector<DamageLabel> out;
    n.labels(m, vp, out);
    REQUIRE(out.size() == 1);
    CHECK(out[0].screen.x == doctest::Approx(128.0f));
    CHECK(out[0].screen.y == doctest::Approx(128.0f));
    CHECK(out[0].text == "15");
    CHECK(out[0].color == el.color(Element::Fire));
    // A label above the centre has a smaller y (+y down).
    n.clear();
    n.add({0, 1, -5}, result(1.0f), Element::Fire, el);
    out.clear();
    n.labels(m, vp, out);
    REQUIRE(out.size() == 1);
    CHECK(out[0].screen.y < 128.0f);
    for (std::size_t i = 0; i < DamageNumbers::kMax + 5; ++i) n.add({0, 0, -5}, result(1.0f), Element::Fire, el);
    CHECK(n.numbers().size() == DamageNumbers::kMax);
}

TEST_CASE("damage numbers: the overlay pixel check finds element-coloured glyphs") {
    const glm::vec3 fire{1.0f, 0.3f, 0.1f};
    const coe::HeadlessFrame plain = frame(64, 64, {90, 80, 60});
    coe::HeadlessFrame with = plain;
    paint(with, 30, 30, 5, {255, 77, 26});   // 25 px of linear (1, 0.3, 0.1)
    std::string report;
    CHECK(checkLabelPixels(with, plain, {32, 32}, 10.0f, fire, 12, report));
    CHECK(report.find("25 in the element colour") != std::string::npos);
    // Wrong colour (Water blue) or too far from the label: fails.
    coe::HeadlessFrame blue = plain;
    paint(blue, 30, 30, 5, {26, 102, 255});
    CHECK(!checkLabelPixels(blue, plain, {32, 32}, 10.0f, fire, 12, report));
    CHECK(report.find("MISMATCH") != std::string::npos);
    CHECK(!checkLabelPixels(with, plain, {5, 5}, 4.0f, fire, 12, report));
    CHECK(!checkLabelPixels(with, plain, {32, 32}, 10.0f, fire, 30, report));   // not enough
    CHECK(!checkLabelPixels(with, frame(32, 32, {0, 0, 0}), {32, 32}, 10.0f, fire, 1, report));   // size mismatch
    // An sRGB capture is decoded first: linear 0.3 is sRGB ~149.
    coe::HeadlessFrame srgbPlain = plain, srgbWith = plain;
    srgbPlain.srgb = srgbWith.srgb = true;
    paint(srgbWith, 30, 30, 5, {255, 149, 89});
    CHECK(checkLabelPixels(srgbWith, srgbPlain, {32, 32}, 10.0f, fire, 12, report));
}
