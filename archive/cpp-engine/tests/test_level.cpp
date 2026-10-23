// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/world/level (BUILD_PLAN step 12): the Midden greybox data, TOML
// validation errors, box transforms (Y-X-Z Euler order, non-uniform scale + the
// inverse-transpose normal rule the vertex shader uses), the unit cube, and the
// headless level check rejecting an empty frame. Plain checks; doctest in step 20.
#include "game/world/headless_checks.hpp"
#include "game/world/level.hpp"

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include <cmath>
#include <cstdio>
#include <string>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using coe::game::BoxKind;
using coe::game::Level;

bool near(float a, float b, float eps = 1e-4f) { return std::fabs(a - b) <= eps; }
bool near(glm::vec3 a, glm::vec3 b, float eps = 1e-4f) { return glm::length(a - b) <= eps; }
glm::vec3 xform(const glm::mat4& m, glm::vec3 p) { return glm::vec3(m * glm::vec4(p, 1.0f)); }
bool contains(const std::string& s, const char* sub) { return s.find(sub) != std::string::npos; }

const coe::game::LevelBox* find(const Level& l, const char* name) {
    for (const auto& b : l.boxes) if (b.name == name) return &b;
    return nullptr;
}

void middenGreybox() {
    Level l;
    const std::string err = coe::game::loadLevel(std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml", l);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    CHECK(err.empty());
    CHECK(l.id == "midden_greybox");
    CHECK(l.boxes.size() >= 10);                 // step 12 done-check: >= 10 boxes
    CHECK(l.count(BoxKind::Ground) >= 1);
    CHECK(l.count(BoxKind::Wall) >= 4);
    CHECK(l.count(BoxKind::Ramp) >= 2);
    CHECK(l.count(BoxKind::Crate) >= 3);
    CHECK(near(glm::length(l.environment.toLight), 1.0f));
    // Ramps are data, not decoration: each top surface runs from the floor to the ledge top.
    const auto* ledge = find(l, "scrap_ledge");
    CHECK(ledge != nullptr);
    for (const char* name : {"ramp_west", "ramp_east"}) {
        const auto* r = find(l, name);
        CHECK(r != nullptr);
        if (!r || !ledge) continue;
        const glm::mat4 m = r->model();
        const glm::vec3 high = xform(m, {0, 0.5f, -0.5f}), low = xform(m, {0, 0.5f, 0.5f});
        CHECK(near(high.y, ledge->center.y + ledge->size.y * 0.5f, 0.01f));
        CHECK(near(high.z, ledge->center.z + ledge->size.z * 0.5f, 0.01f));   // meets the ledge's south edge
        CHECK(near(low.y, 0.0f, 0.01f));
    }
    // The player starts with its feet on the floor, facing north; the 1.5 m eye is clear of every box.
    const auto* ground = find(l, "ground");
    CHECK(near(l.playerStart.position.y, 0.0f, 0.01f));
    CHECK(l.boxAtSurface(l.playerStart.position, 0.05f) == int(ground - l.boxes.data()));
    CHECK(l.boxAtSurface(l.playerStart.position + glm::vec3(0, 1.5f, 0), 0.5f) < 0);
    CHECK(l.playerStart.yawDeg == 0.0f);
    // Surface lookup used by the headless check.
    CHECK(l.boxAtSurface({3.0f, 0.0f, 3.0f}, 0.01f) == int(ground - l.boxes.data()));
    const int north = l.boxAtSurface({0.0f, 3.0f, -14.0f}, 0.01f);
    CHECK(north >= 0 && l.boxes[size_t(north)].name == "wall_north");
    CHECK(l.boxAtSurface({0.0f, 10.0f, 0.0f}, 0.05f) == -1);
}

void transforms() {
    coe::game::LevelBox b;
    b.rotationDeg = {90.0f, 90.0f, 0.0f};
    // Godot order Y * X * Z: X first takes +Z to -Y, then Y leaves it. (X-then-Y order would give +X.)
    CHECK(near(b.rotation() * glm::vec3(0, 0, 1), {0, -1, 0}));
    b.rotationDeg = {0.0f, 90.0f, 0.0f};
    CHECK(near(b.rotation() * glm::vec3(0, 0, -1), {-1, 0, 0}));   // yaw +90 turns -Z (north) to -X, like Camera
    // model = translate * rotate * scale over the unit cube: corners land on center +- R * size/2.
    b.center = {1, 2, 3}; b.size = {4, 1, 2}; b.rotationDeg = {0, 30, 0};
    const glm::mat4 m = b.model();
    CHECK(near(xform(m, {0.5f, 0.5f, 0.5f}), b.center + b.rotation() * (b.size * 0.5f)));
    CHECK(near(b.surfaceDistance(xform(m, {0.5f, 0.1f, -0.2f})), 0.0f));     // on the +X face
    CHECK(b.surfaceDistance(b.center) < 0.0f);

    // Non-uniform scale + rotation: the inverse-transpose keeps normals perpendicular to
    // the transformed surface; plain mat3(model) does not. Cube faces are axis-aligned,
    // where both agree after normalising, so use a slanted plane x + y = 0 (as on glTF
    // meshes drawn with the same shader) with its in-plane direction (1, -1, 0).
    coe::game::LevelBox s;
    s.size = {4.0f, 1.0f, 1.0f}; s.rotationDeg = {10.0f, 25.0f, 30.0f};
    const glm::mat4 sm = s.model();
    const glm::vec3 edge = glm::normalize(glm::mat3(sm) * glm::vec3(1, -1, 0));
    const glm::vec3 n = glm::normalize(glm::vec3(1, 1, 0));
    const glm::vec3 nGood = glm::normalize(glm::transpose(glm::inverse(glm::mat3(sm))) * n);
    const glm::vec3 nNaive = glm::normalize(glm::mat3(sm) * n);
    CHECK(near(glm::dot(nGood, edge), 0.0f));
    CHECK(near(glm::dot(nGood, glm::normalize(glm::mat3(sm) * glm::vec3(0, 0, 1))), 0.0f));
    CHECK(std::fabs(glm::dot(nNaive, edge)) > 0.5f);          // mat3(model) tilts it badly
    // Axis-aligned cube faces: the normal is just the rotated face axis.
    const glm::vec3 nFace = glm::normalize(glm::transpose(glm::inverse(glm::mat3(sm))) * glm::vec3(0, 1, 0));
    CHECK(near(nFace, s.rotation() * glm::vec3(0, 1, 0)));
}

void unitCube() {
    const coe::assets::MeshData m = coe::game::makeUnitCube();
    CHECK(m.vertices.size() == 24);
    CHECK(m.indices.size() == 36);
    CHECK(m.submeshes.size() == 1 && m.submeshes[0].indexCount == 36 && !m.submeshes[0].doubleSided);
    CHECK(near(m.extent(), {1, 1, 1}) && near(m.center(), {0, 0, 0}));
    for (const auto& v : m.vertices) {
        CHECK(near(glm::length(v.normal), 1.0f));
        CHECK(near(glm::dot(v.position, v.normal), 0.5f));       // lies on its face plane
        CHECK(v.color == glm::vec4(1.0f));                       // tint comes per draw
    }
    for (size_t i = 0; i + 2 < m.indices.size(); i += 3) {
        const auto& p0 = m.vertices[m.indices[i]];
        const auto& p1 = m.vertices[m.indices[i + 1]];
        const auto& p2 = m.vertices[m.indices[i + 2]];
        // Counter-clockwise seen from outside: the winding normal agrees with the face normal.
        CHECK(glm::dot(glm::cross(p1.position - p0.position, p2.position - p0.position), p0.normal) > 0.0f);
        CHECK(p0.normal == p1.normal && p1.normal == p2.normal);
    }
}

constexpr const char* kHeader = R"(
[level]
id = "t"
name = "test"
[environment]
sky_color = [0.1, 0.1, 0.1]
ambient_color = [0.2, 0.2, 0.2]
[sun]
to_light = [0, 2, 0]
color = [1, 1, 1]
[player_start]
position = [0, 1, 0]
yaw_deg = 0
)";

std::string parse(const std::string& boxes, Level& l) { return coe::game::parseLevel(std::string(kHeader) + boxes, "t.toml", l); }

void validation() {
    Level l;
    const std::string box = "[[box]]\nname = \"a\"\nkind = \"crate\"\ncenter = [0, 0.5, 0]\nsize = [1, 1, 1]\ncolor = [1, 0, 0]\n";
    CHECK(parse(box, l).empty());
    CHECK(l.boxes.size() == 1 && l.boxes[0].kind == BoxKind::Crate && l.boxes[0].color == glm::vec4(1, 0, 0, 1));
    CHECK(near(l.environment.toLight, {0, 1, 0}));               // normalised on load
    CHECK(l.environment.fogDensity == 0.0f);                       // optional

    std::string e = coe::game::parseLevel("[level\nid = 1", "bad.toml", l);
    CHECK(contains(e, "bad.toml:1:") && contains(e, "TOML"));
    e = parse(box + "[[box]]\nname = \"b\"\nkind = \"barrel\"\ncenter = [0, 0, 0]\nsize = [1, 1, 1]\ncolor = [1, 1, 1]\n", l);
    CHECK(contains(e, "unknown kind 'barrel'") && contains(e, "t.toml:22:"));   // line of the kind key
    e = parse("[[box]]\nname = \"a\"\nkind = \"wall\"\ncenter = [0, 0, 0]\nsize = [1, 0, 1]\ncolor = [1, 1, 1]\n", l);
    CHECK(contains(e, "size must be > 0"));
    e = parse("[[box]]\nname = \"a\"\nkind = \"wall\"\ncenter = [0, 0, 0]\nsize = [1, 1, 1]\ncolour = [1, 1, 1]\n", l);
    CHECK(contains(e, "unknown key 'colour'"));
    e = parse("[[box]]\nname = \"a\"\nkind = \"wall\"\ncenter = [0, 0]\nsize = [1, 1, 1]\ncolor = [1, 1, 1]\n", l);
    CHECK(contains(e, "center must be an array of 3 numbers"));
    e = parse("[[box]]\nname = \"a\"\nkind = \"wall\"\ncenter = [0, 0, 0]\nsize = [1, 1, 1]\ncolor = [1, 2, 1]\n", l);
    CHECK(contains(e, "[0, 1]"));
    e = parse("[[box]]\nname = \"a\"\nkind = \"crate\"\ncenter = [5, 0.5, 0]\nsize = [1, 1, 1]\ncolor = [1, 0, 0]\n", l);
    CHECK(contains(e, "player_start position (feet) must lie on a box surface") && contains(e, "t.toml:12:"));
    e = coe::game::parseLevel(std::string(kHeader).replace(std::string(kHeader).find("yaw_deg"), 7, "pitch_deg") + box, "t.toml", l);
    CHECK(contains(e, "unknown key 'pitch_deg'"));
    e = parse(box + box, l);
    CHECK(contains(e, "duplicate box name 'a'"));
    e = parse("", l);
    CHECK(contains(e, "need at least one [[box]]"));
    e = coe::game::parseLevel("[level]\nid = \"x\"\nname = \"x\"\n", "m.toml", l);
    CHECK(contains(e, "missing [environment]"));
    e = coe::game::loadLevel("/no/such/level.toml", l);
    CHECK(contains(e, "cannot open"));
}

void headlessCheckRejectsEmptyFrame() {
    Level l;
    CHECK(coe::game::loadLevel(std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml", l).empty());
    coe::HeadlessFrame f;
    f.width = f.height = 64;
    f.rgba.assign(64 * 64 * 4, 0);
    f.depth.assign(64 * 64, 0.0f);   // nothing drawn
    coe::game::LevelViewStats st;
    std::string report;
    CHECK(!coe::game::checkLevelView(l, f, l.playerStart.position + glm::vec3(0, 1.5f, 0), {0, 0, 0}, st, report));
    CHECK(st.sky == st.samples && st.perKind[size_t(BoxKind::Ground)] == 0);
    CHECK(contains(report, "floor FAIL"));
}
} // namespace

int main() {
    middenGreybox();
    transforms();
    unitCube();
    validation();
    headlessCheckRejectsEmptyFrame();
    if (g_failures) { std::fprintf(stderr, "test_level: %d failure(s)\n", g_failures); return 1; }
    std::puts("test_level: all checks passed");
    return 0;
}
