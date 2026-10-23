// SPDX-License-Identifier: Apache-2.0
// Data-defined greybox levels (BUILD_PLAN step 12): boxes + environment + player start
// parsed from TOML (toml++, data/levels/*.toml). CPU-only; the game turns boxes into
// one DrawItem each over a shared unit cube (makeUnitCube), physics colliders come
// from the same boxes in step 13.
#pragma once
#include "engine/assets/mesh_data.hpp"

#include <glm/glm.hpp>

#include <cstddef>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace coe::game {

enum class BoxKind { Ground, Wall, Ramp, Crate, Heap, Platform };
inline constexpr std::size_t kBoxKindCount = 6;
const char* boxKindName(BoxKind k);
std::optional<BoxKind> parseBoxKind(std::string_view s);

struct LevelBox {
    std::string name;
    BoxKind kind = BoxKind::Crate;
    glm::vec3 center{0.0f};
    glm::vec3 size{1.0f};          // full extents, metres (> 0)
    glm::vec3 rotationDeg{0.0f};   // Euler x, y, z applied in Y, X, Z order (Godot default)
    glm::vec4 color{1.0f};         // linear RGB tint, alpha 1

    glm::mat3 rotation() const;    // Ry * Rx * Rz
    glm::mat4 model() const;       // translate(center) * rotation * scale(size), over the unit cube
    // Signed distance-like measure of p to this box's surface in metres: max over
    // the box axes of |local| - half size (0 on the surface, < 0 inside).
    float surfaceDistance(const glm::vec3& p) const;
};

struct LevelEnvironment {
    glm::vec3 skyColor{0.02f, 0.02f, 0.05f};
    glm::vec3 ambientColor{0.2f};
    float fogDensity = 0.0f;
    glm::vec3 toLight{0.5934f, 0.5934f, 0.5439f};   // unit vector toward the sun
    glm::vec3 sunColor{0.8f};
};

// [player_start] (step 14; was step 12's [camera]): where the player's *feet* spawn and
// the facing (yaw only; the eye is 1.5 m above the feet, pitch starts level). Named
// player_start, not spawn, so step 25's [[spawn]] array of tables can share the file.
struct LevelPlayerStart {
    glm::vec3 position{0.0f};   // feet; must lie on a box surface (within 5 cm)
    float yawDeg = 0.0f;
};

struct Level {
    std::string id, name;
    LevelEnvironment environment;
    LevelPlayerStart playerStart;
    std::vector<LevelBox> boxes;

    std::size_t count(BoxKind k) const;
    // Index of the box whose surface is nearest to p, if within `tolerance` metres; -1 otherwise.
    int boxAtSurface(const glm::vec3& p, float tolerance) const;
};

// Parses TOML text; `sourceName` prefixes error messages ("file:line: ...").
// Returns "" on success, else an error (level left in an unspecified state).
std::string parseLevel(std::string_view text, std::string_view sourceName, Level& out);
std::string loadLevel(const std::filesystem::path& path, Level& out);

// Unit cube centred on the origin (-0.5..0.5): 24 vertices (4 per face, per-face
// normals), 36 indices, CCW from outside, white vertex colour (tint comes per draw).
assets::MeshData makeUnitCube();

} // namespace coe::game
