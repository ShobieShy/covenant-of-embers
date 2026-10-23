// SPDX-License-Identifier: Apache-2.0
// Enemies (BUILD_PLAN step 22): data-defined enemy types (data/enemies/*.toml), health,
// element affinity + per-element resistance for the step-20 damage formula, a weak-point
// hitbox, and death.
//
// Each live enemy owns kinematic boxes on physics::Layers::Enemy: its body and, if the
// type has one, a weak point (e.g. a head). A ProjectileHit (step 17) on either is looked
// up by body handle; the enemy builds DamageTarget{affinity, resist, weakPoint} and calls
// resolveHit() with the bolt's wieldable damage and element, so Fire (x1.5) on an Earth
// dummy deals 15 from the Apprentice Fire Staff's 10. Health is clamped at 0; reaching 0
// kills the enemy: its hitboxes are removed (later bolts fly through) and an EnemyDeath
// is queued for the game (step 25's kill events, XP/loot later).
//
// Magewar reference (scripts/enemies/enemy_base.gd, read-only): an enemy has a name,
// element, level, xp/gold reward and a CogitoHealthAttribute whose death signal runs
// on_death; take_elemental_damage applies damage x effectiveness. Reinterpreted: plain
// health on the enemy, the full step-20 formula (resist cap 60 %, weak-point crit x2:
// Magewar has neither), no knockback yet (Magewar: > 10 damage knocks back for 0.5 s,
// with the AI in step 23), rewards/loot on death come with steps 25+.
#pragma once
#include "engine/physics/physics.hpp"
#include "engine/render/vk_renderer.hpp"
#include "game/combat/damage.hpp"
#include "game/magic/projectile.hpp"

#include <glm/glm.hpp>

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace coe::game {

struct WeakPointDef {
    glm::vec3 offset{0.0f};   // box centre relative to the feet (yaw-rotated with the enemy)
    glm::vec3 size{0.3f};     // full extents, metres
};

struct EnemyDef {
    std::string id;           // lower_snake_case
    std::string name;
    Element affinity = Element::Arcane;   // defender element (effectiveness chart)
    Resistances resist{};                 // per incoming element, 0..1 (resolveHit caps at 60 %)
    float maxHealth = 100.0f;
    glm::vec3 size{0.7f, 1.6f, 0.7f};     // body hitbox full extents; stands on its feet
    std::optional<WeakPointDef> weakPoint;
    glm::vec3 color{0.6f};                // greybox tint (body; the weak point draws brighter)
};

struct EnemyTable {
    std::vector<EnemyDef> defs;
    const EnemyDef* find(std::string_view id) const;
};

// Strict TOML: [[enemy]] tables with id, name, affinity, max_health, size, color and
// optional resist = { <element> = 0..1, ... } and weak_point = { offset, size }.
// "" on success, else "<source>:<line>: message" (table left empty).
std::string parseEnemies(std::string_view text, std::string_view sourceName, EnemyTable& out);
std::string loadEnemies(const std::filesystem::path& path, EnemyTable& out);

struct Enemy {
    std::uint32_t id = 0;
    const EnemyDef* def = nullptr;
    glm::vec3 feet{0.0f};
    float yawDeg = 0.0f;
    float health = 0.0f;
    bool dead = false;
    physics::BodyHandle body, weakPoint;   // invalid once dead
    std::uint32_t hits = 0;
    float damageTaken = 0.0f;              // applied (health lost; overkill not counted)
    float flash = 0.0f;                    // s of hit flash left (greybox feedback)
    glm::mat4 bodyModel() const;           // unit cube -> body box (world)
    glm::mat4 weakPointModel() const;      // unit cube -> weak-point box (def must have one)
};

// One bolt hit applied to an enemy.
struct EnemyHit {
    std::uint32_t enemy = 0;
    DamageResult result;          // amount = formula value (before the health clamp)
    float healthBefore = 0.0f, healthAfter = 0.0f;
    bool weakPoint = false;
    bool killed = false;          // this hit took health to 0
    glm::vec3 point{0.0f};
    Element element = Element::Arcane;
};

struct EnemyDeath {
    std::uint32_t enemy = 0;
    const EnemyDef* def = nullptr;
    glm::vec3 feet{0.0f};
    Element killingElement = Element::Arcane;
};

class EnemySystem {
public:
    // Both must outlive the system (element chart: data/magic/elements.toml).
    EnemySystem(physics::PhysicsWorld& world, const ElementTable& elements);
    ~EnemySystem();
    EnemySystem(const EnemySystem&) = delete;
    EnemySystem& operator=(const EnemySystem&) = delete;

    // Spawns at `feet` facing yawDeg (0 = -Z); `def` must outlive the system. Returns its id.
    std::uint32_t spawn(const EnemyDef& def, const glm::vec3& feet, float yawDeg = 0.0f);
    // If the bolt struck a live enemy's hitbox, applies the damage formula and returns
    // what happened; std::nullopt for anything else (walls, the dead, other bodies).
    std::optional<EnemyHit> applyHit(const ProjectileHit& hit);
    void tick(float dt);   // hit flashes

    const Enemy* find(std::uint32_t id) const;
    const Enemy* byBody(physics::BodyHandle body) const;   // body or weak point of a live enemy
    const std::vector<Enemy>& enemies() const { return enemies_; }   // the dead stay (dead = true)
    std::size_t alive() const;
    // Deaths since the last call (in order).
    std::vector<EnemyDeath> takeDeaths();
    std::uint64_t kills() const { return kills_; }

    // Greybox draws for the live enemies over the shared unit cube.
    void draws(MeshId cube, std::vector<DrawItem>& out) const;
    static constexpr float kFlashTime = 0.12f;

private:
    void kill(Enemy& e, Element element);
    physics::PhysicsWorld& world_;
    const ElementTable& elements_;
    std::vector<Enemy> enemies_;
    std::vector<EnemyDeath> deaths_;
    std::uint32_t nextId_ = 1;
    std::uint64_t kills_ = 0;
};

} // namespace coe::game
