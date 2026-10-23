// SPDX-License-Identifier: Apache-2.0
// Gnawer AI, the melee rusher (BUILD_PLAN step 23, PLAN §7). Drives every live enemy whose
// EnemyDef has `ai = { kind = "rusher" }` (data/enemies/gnawer.toml):
//
//   Idle --(player within detect_range and in sight)--> Detect   (faces + stalks at walk_speed)
//   Detect --(within aggro_range)--> Chase                       (sprints straight at the player)
//   Chase --(within attack_range)--> Attack                      (stops, bites every attack_cooldown;
//                                                                 the first bite is immediate)
//   Attack --(beyond attack_range + 0.3 m)--> Chase
//   Detect / Chase --(beyond detect_range; Detect also on lost sight)--> Idle
//                                       (Chase not while hunting: 5 s after being hit)
//   any --(a hit dealing > knockback_threshold)--> Knockback (knockback_time) --> Chase / Attack
//   Idle / Detect --(any hit)--> Chase                           (being shot provokes it)
//   any --(Enemy::dead)--> Dead                                  (stops thinking for good)
//
// One hop per tick. Steering is a straight line on XZ (the greybox has no navmesh): the
// move is swept against Static geometry with a sphere and slides along walls (blocked
// head-on, it detours along the wall for 0.5 s past the last block), the feet
// follow the ground with a downward sweep (0.35 m step up, falls with gravity off ledges)
// and EnemySystem::place() moves the kinematic hitboxes. Bites are EnemyAttack events;
// until the player has health (step 24) the game only logs and totals them. A bite on an
// invulnerable player (dash i-frames) is dodged: the cooldown is spent, no damage.
//
// Magewar: enemy_base.gd declares these exports (the mutant rat overrides them) and its
// knockback, but has no AI loop at all; the brain is our reinterpretation of the intent.
// Knockback decays linearly from knockback_strength over knockback_time (2.5 m for the
// rat) instead of Magewar's never-applied constant force (would be 5 m).
#pragma once
#include "engine/physics/physics.hpp"
#include "game/ai/state_machine.hpp"
#include "game/combat/element.hpp"
#include "game/enemies/enemy.hpp"

#include <glm/glm.hpp>

#include <cstdint>
#include <optional>
#include <vector>

namespace coe::game {

enum class GnawerState : std::uint8_t { Idle, Detect, Chase, Attack, Knockback, Dead };
const char* gnawerStateName(GnawerState s);

// What a brain perceives this tick (built by GnawerAI from physics; tests fill it directly).
struct GnawerSenses {
    bool targetValid = true;      // false: no player (the brain idles)
    float distance = 1e9f;        // horizontal (XZ) centre distance to the player, metres
    bool lineOfSight = true;      // nothing Static between its eyes and the player's
    bool provoked = false;        // it was hit since the last tick
    bool hunting = false;         // hit within kGnawerHuntTime: Chase ignores the detect leash
    float knockbackLeft = 0.0f;   // seconds of knockback still to run
    bool dead = false;
};

inline constexpr float kGnawerAttackSlack = 0.3f;   // Attack holds until attack_range + this
inline constexpr float kGnawerHuntTime = 5.0f;      // s a hit keeps it chasing from any range
inline constexpr float kGnawerDetourTime = 0.5f;    // s it keeps skirting a wall after the last block

// The pure transition rule above; returns `s` when nothing changes.
GnawerState nextGnawerState(GnawerState s, const RusherDef& d, const GnawerSenses& in);

// The player as the brain sees it.
struct AITarget {
    glm::vec3 feet{0.0f};
    float eyeHeight = 1.5f;       // sight line goes to feet + this
    float radius = 0.3f;          // capsule radius
    bool invulnerable = false;    // dash i-frames: bites are dodged
    bool valid = true;
};

// One bite. `dodged` bites dealt nothing (the player was invulnerable).
struct EnemyAttack {
    std::uint32_t enemy = 0;
    const EnemyDef* def = nullptr;
    float damage = 0.0f;          // raw: step 24 runs it through resolveHit with the player's resistances
    Element element = Element::Arcane;   // the attacker's affinity
    glm::vec3 from{0.0f};         // the attacker's feet
    bool dodged = false;
};

struct GnawerTransition {
    std::uint32_t enemy = 0;
    GnawerState from = GnawerState::Idle;
    GnawerState to = GnawerState::Idle;
    float distance = 0.0f;
    std::uint64_t tick = 0;       // GnawerAI tick count when it happened (1-based)
};

struct GnawerAgent {
    std::uint32_t enemy = 0;
    StateMachine<GnawerState> fsm{GnawerState::Idle};
    float attackTimer = 0.0f;     // s until the next bite may land (Magewar _attack_timer)
    float knockbackLeft = 0.0f;
    glm::vec3 knockbackDir{0.0f}; // unit, horizontal
    float verticalSpeed = 0.0f;   // falling
    bool provoked = false;
    float huntLeft = 0.0f;        // s of kGnawerHuntTime left
    glm::vec3 detourDir{0.0f};    // unit, along the wall that blocked it
    float detourLeft = 0.0f;
    bool grounded = true;
    float distance = 0.0f;        // last sensed horizontal distance to the player
    float travelled = 0.0f;       // metres moved in total (XZ)
    std::uint32_t bites = 0;      // landed
    std::uint32_t dodged = 0;
    std::uint32_t knockbacks = 0;
};

class GnawerAI {
public:
    // Both must outlive the AI.
    GnawerAI(physics::PhysicsWorld& world, EnemySystem& enemies);

    // Starts driving every live enemy with an `ai` def not yet driven (call after spawns).
    std::size_t adoptAll();
    // Feeds a bolt hit (from EnemySystem::applyHit): provokes, and knocks back on > threshold.
    void onHit(const EnemyHit& hit);
    // One fixed step, before PhysicsWorld::step(dt) so the hitboxes arrive this step.
    void tick(float dt, const AITarget& target);

    std::vector<EnemyAttack> takeAttacks();
    std::vector<GnawerTransition> takeTransitions();
    const GnawerAgent* agent(std::uint32_t enemy) const;
    const std::vector<GnawerAgent>& agents() const { return agents_; }
    std::uint64_t ticks() const { return ticks_; }

    static constexpr float kStepUp = 0.35f;     // climbs ledges/ramps this high per step
    static constexpr float kStepDown = 0.3f;    // stays glued to ground this far below
    static constexpr float kGravity = 9.8f;     // = WorldSettings::gravity

private:
    glm::vec3 slide(const glm::vec3& feet, glm::vec3 delta, float radius, glm::vec3* blockNormal = nullptr) const;
    glm::vec3 steer(const glm::vec3& feet, const glm::vec3& dir, float len, float radius, GnawerAgent& a, float dt) const;
    glm::vec3 settle(const glm::vec3& feet, GnawerAgent& a, float dt) const;
    bool sees(const glm::vec3& eye, const glm::vec3& targetEye) const;

    physics::PhysicsWorld& world_;
    EnemySystem& enemies_;
    std::vector<GnawerAgent> agents_;
    std::vector<EnemyAttack> attacks_;
    std::vector<GnawerTransition> transitions_;
    std::uint64_t ticks_ = 0;
};

}  // namespace coe::game
