// SPDX-License-Identifier: Apache-2.0
#include "game/world/level.hpp"

#define TOML_EXCEPTIONS 0
#include <toml++/toml.hpp>

#include <glm/gtc/matrix_transform.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <limits>
#include <sstream>

namespace coe::game {
namespace {
constexpr std::array<const char*, kBoxKindCount> kKindNames = {"ground", "wall", "ramp", "crate", "heap", "platform"};

struct Ctx {
    std::string_view source;
    std::string err;
    bool fail(const toml::node* at, const std::string& msg) {
        if (!err.empty()) return false;
        std::ostringstream o;
        o << source;
        if (at && at->source().begin) o << ':' << at->source().begin.line;
        o << ": " << msg;
        err = o.str();
        return false;
    }
};

bool readFloat(Ctx& c, const toml::node* n, const std::string& what, float& out) {
    if (!n || !(n->is_floating_point() || n->is_integer())) return c.fail(n, what + " must be a number");
    const double v = n->is_integer() ? double(n->as_integer()->get()) : n->as_floating_point()->get();
    if (!std::isfinite(v)) return c.fail(n, what + " must be finite");
    out = float(v);
    return true;
}

bool readVec3(Ctx& c, const toml::node* n, const std::string& what, glm::vec3& out) {
    const toml::array* a = n ? n->as_array() : nullptr;
    if (!a || a->size() != 3) return c.fail(n, what + " must be an array of 3 numbers");
    for (int i = 0; i < 3; ++i)
        if (!readFloat(c, a->get(size_t(i)), what, out[i])) return false;
    return true;
}

bool readColor(Ctx& c, const toml::node* n, const std::string& what, glm::vec3& out) {
    if (!readVec3(c, n, what, out)) return false;
    for (int i = 0; i < 3; ++i)
        if (out[i] < 0.0f || out[i] > 1.0f) return c.fail(n, what + " components must be in [0, 1]");
    return true;
}

bool readString(Ctx& c, const toml::node* n, const std::string& what, std::string& out) {
    if (!n || !n->is_string()) return c.fail(n, what + " must be a string");
    out = n->as_string()->get();
    if (out.empty()) return c.fail(n, what + " must not be empty");
    return true;
}

// Rejects keys outside `allowed` so typos ("colour") fail instead of being ignored.
bool onlyKeys(Ctx& c, const toml::table& t, std::initializer_list<std::string_view> allowed, const std::string& where) {
    for (auto&& [k, v] : t)
        if (std::find(allowed.begin(), allowed.end(), k.str()) == allowed.end())
            return c.fail(&v, where + ": unknown key '" + std::string(k.str()) + "'");
    return true;
}

const toml::table* needTable(Ctx& c, const toml::table& root, std::string_view key) {
    const toml::node* n = root.get(key);
    if (!n || !n->is_table()) { c.fail(n ? n : &root, "missing [" + std::string(key) + "] table"); return nullptr; }
    return n->as_table();
}

bool parseBox(Ctx& c, const toml::table& t, size_t index, LevelBox& b) {
    const std::string where = "box #" + std::to_string(index + 1);
    if (!onlyKeys(c, t, {"name", "kind", "center", "size", "rotation_deg", "color"}, where)) return false;
    if (!readString(c, t.get("name"), where + " name", b.name)) return false;
    const std::string w = "box '" + b.name + "'";
    std::string kind;
    if (!readString(c, t.get("kind"), w + " kind", kind)) return false;
    const auto k = parseBoxKind(kind);
    if (!k) return c.fail(t.get("kind"), w + ": unknown kind '" + kind + "'");
    b.kind = *k;
    if (!readVec3(c, t.get("center"), w + " center", b.center)) return false;
    if (!readVec3(c, t.get("size"), w + " size", b.size)) return false;
    if (b.size.x <= 0.0f || b.size.y <= 0.0f || b.size.z <= 0.0f) return c.fail(t.get("size"), w + ": size must be > 0");
    if (t.get("rotation_deg") && !readVec3(c, t.get("rotation_deg"), w + " rotation_deg", b.rotationDeg)) return false;
    glm::vec3 rgb;
    if (!readColor(c, t.get("color"), w + " color", rgb)) return false;
    b.color = glm::vec4(rgb, 1.0f);
    return true;
}
} // namespace

const char* boxKindName(BoxKind k) { return kKindNames[size_t(k)]; }

std::optional<BoxKind> parseBoxKind(std::string_view s) {
    for (size_t i = 0; i < kKindNames.size(); ++i)
        if (s == kKindNames[i]) return BoxKind(i);
    return std::nullopt;
}

glm::mat3 LevelBox::rotation() const {
    const glm::mat4 ry = glm::rotate(glm::mat4(1.0f), glm::radians(rotationDeg.y), glm::vec3(0, 1, 0));
    const glm::mat4 rx = glm::rotate(glm::mat4(1.0f), glm::radians(rotationDeg.x), glm::vec3(1, 0, 0));
    const glm::mat4 rz = glm::rotate(glm::mat4(1.0f), glm::radians(rotationDeg.z), glm::vec3(0, 0, 1));
    return glm::mat3(ry * rx * rz);
}

glm::mat4 LevelBox::model() const {
    glm::mat4 m = glm::mat4(rotation());
    m[3] = glm::vec4(center, 1.0f);
    return glm::scale(m, size);
}

float LevelBox::surfaceDistance(const glm::vec3& p) const {
    const glm::vec3 local = glm::transpose(rotation()) * (p - center);   // rotation is orthonormal
    const glm::vec3 d = glm::abs(local) - size * 0.5f;
    return std::max({d.x, d.y, d.z});
}

size_t Level::count(BoxKind k) const {
    return size_t(std::count_if(boxes.begin(), boxes.end(), [k](const LevelBox& b) { return b.kind == k; }));
}

int Level::boxAtSurface(const glm::vec3& p, float tolerance) const {
    int best = -1;
    float bestDist = std::numeric_limits<float>::max();
    for (size_t i = 0; i < boxes.size(); ++i) {
        const float d = std::abs(boxes[i].surfaceDistance(p));
        if (d <= tolerance && d < bestDist) { bestDist = d; best = int(i); }
    }
    return best;
}

std::string parseLevel(std::string_view text, std::string_view sourceName, Level& out) {
    out = {};
    Ctx c{sourceName, {}};
    toml::parse_result parsed = toml::parse(text, sourceName);
    if (!parsed) {
        std::ostringstream o;
        o << sourceName << ':' << parsed.error().source().begin.line << ": TOML: " << parsed.error().description();
        return o.str();
    }
    const toml::table& root = parsed.table();
    if (!onlyKeys(c, root, {"level", "environment", "sun", "player_start", "box"}, "top level")) return c.err;

    const toml::table* level = needTable(c, root, "level");
    if (!level || !onlyKeys(c, *level, {"id", "name"}, "[level]") ||
        !readString(c, level->get("id"), "level id", out.id) || !readString(c, level->get("name"), "level name", out.name))
        return c.err;

    LevelEnvironment& env = out.environment;
    const toml::table* e = needTable(c, root, "environment");
    if (!e || !onlyKeys(c, *e, {"sky_color", "ambient_color", "fog_density"}, "[environment]") ||
        !readColor(c, e->get("sky_color"), "sky_color", env.skyColor) ||
        !readColor(c, e->get("ambient_color"), "ambient_color", env.ambientColor))
        return c.err;
    if (e->get("fog_density")) {
        if (!readFloat(c, e->get("fog_density"), "fog_density", env.fogDensity)) return c.err;
        if (env.fogDensity < 0.0f || env.fogDensity > 1.0f) { c.fail(e->get("fog_density"), "fog_density must be in [0, 1]"); return c.err; }
    }
    const toml::table* sun = needTable(c, root, "sun");
    if (!sun || !onlyKeys(c, *sun, {"to_light", "color"}, "[sun]") ||
        !readVec3(c, sun->get("to_light"), "sun to_light", env.toLight) ||
        !readColor(c, sun->get("color"), "sun color", env.sunColor))
        return c.err;
    const float len = glm::length(env.toLight);
    if (len < 1e-4f) { c.fail(sun->get("to_light"), "sun to_light must not be zero"); return c.err; }
    env.toLight /= len;

    const toml::table* start = needTable(c, root, "player_start");
    if (!start || !onlyKeys(c, *start, {"position", "yaw_deg"}, "[player_start]") ||
        !readVec3(c, start->get("position"), "player_start position", out.playerStart.position) ||
        !readFloat(c, start->get("yaw_deg"), "player_start yaw_deg", out.playerStart.yawDeg))
        return c.err;

    const toml::node* boxesNode = root.get("box");
    const toml::array* boxes = boxesNode ? boxesNode->as_array() : nullptr;
    if (!boxes || boxes->empty() || !boxes->is_array_of_tables()) {
        c.fail(boxesNode ? boxesNode : &root, "need at least one [[box]]");
        return c.err;
    }
    for (size_t i = 0; i < boxes->size(); ++i) {
        LevelBox b;
        if (!parseBox(c, *boxes->get(i)->as_table(), i, b)) return c.err;
        for (const LevelBox& o : out.boxes)
            if (o.name == b.name) { c.fail(boxes->get(i), "duplicate box name '" + b.name + "'"); return c.err; }
        out.boxes.push_back(std::move(b));
    }
    // The player's feet must rest on something (a typo'd start would fall forever).
    if (out.boxAtSurface(out.playerStart.position, 0.05f) < 0) {
        c.fail(start->get("position"), "player_start position (feet) must lie on a box surface (within 5 cm)");
        return c.err;
    }
    return {};
}

std::string loadLevel(const std::filesystem::path& path, Level& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return path.string() + ": cannot open level file";
    std::ostringstream ss;
    ss << f.rdbuf();
    return parseLevel(ss.str(), path.filename().string(), out);
}

assets::MeshData makeUnitCube() {
    assets::MeshData m;
    // Per face: outward normal n and two in-plane axes u, v with u x v = n, so the
    // corners (-u-v, +u-v, +u+v, -u+v) run counter-clockwise seen from outside.
    struct Face { glm::vec3 n, u, v; };
    constexpr Face faces[6] = {
        {{1, 0, 0}, {0, 0, -1}, {0, 1, 0}}, {{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
        {{0, 1, 0}, {1, 0, 0}, {0, 0, -1}}, {{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
        {{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},  {{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}},
    };
    constexpr float su[4] = {-1, 1, 1, -1}, sv[4] = {-1, -1, 1, 1};
    for (const Face& f : faces) {
        const auto base = static_cast<uint32_t>(m.vertices.size());
        for (int i = 0; i < 4; ++i) {
            assets::Vertex vx;
            vx.position = 0.5f * (f.n + su[i] * f.u + sv[i] * f.v);
            vx.normal = f.n;
            vx.uv = glm::vec2(su[i] * 0.5f + 0.5f, 0.5f - sv[i] * 0.5f);
            vx.color = glm::vec4(1.0f);
            m.vertices.push_back(vx);
        }
        for (uint32_t i : {0u, 1u, 2u, 0u, 2u, 3u}) m.indices.push_back(base + i);
    }
    m.submeshes.push_back({0, uint32_t(m.indices.size()), -1, false});
    m.boundsMin = glm::vec3(-0.5f);
    m.boundsMax = glm::vec3(0.5f);
    return m;
}

} // namespace coe::game
