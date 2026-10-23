// SPDX-License-Identifier: Apache-2.0
// Gnawer AI tests (BUILD_PLAN step 23): the rusher's state transitions at ranges (the pure
// rule and the driven system), straight-line steering on Jolt geometry (wall slide, ground
// follow, sight blocked by walls), bites on the cooldown, Magewar's knockback on hits over
// 10 damage, dead Gnawers that stop thinking, and a Gnawer chasing a real PlayerController
// across the Midden greybox. The window half of the done-check is ctest gnawer_window.
#include "engine/input/input.hpp"
#include "engine/physics/physics.hpp"
#include "game/ai/gnawer.hpp"
#include "game/ai/state_machine.hpp"
#include "game/combat/element.hpp"
#include "game/enemies/enemy.hpp"
#include "game/magic/projectile.hpp"
#include "game/player/player_controller.hpp"
#include "game/world/level.hpp"
#include "game/world/level_physics.hpp"

#include <doctest/doctest.h>
#include <glm/glm.hpp>

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {

using namespace coe::game;
namespace ph = coe::physics;
using GS = GnawerState;

constexpr float kDt = 1.0f / 60.0f;

template <class T, class F>
T loadOrFail(F load, const std::string& rel) {
    T t;
    const std::string err = load(std::string(COE_DATA_DIR) + rel, t);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    REQUIRE(err.empty());
    return t;
}
ElementTable elementsReal() {
    return loadOrFail<ElementTable>([](const std::string& p, ElementTable& t) { return loadElements(p, t); },
                                    "/magic/elements.toml");
}
EnemyTable gnawersReal() {
    return loadOrFail<EnemyTable>([](const std::string& p, EnemyTable& t) { return loadEnemies(p, t); },
                                  "/enemies/gnawer.toml");
}

float flatDist(const glm::vec3& a, const glm::vec3& b) { return glm::length(glm::vec2(a.x - b.x, a.z - b.z)); }

// A 40 x 40 m floor at y = 0 (top face), plus whatever walls a test adds.
struct Floor {
    ph::PhysicsWorld world;
    Floor() {
        ph::BoxDesc f;
        f.center = {0, -0.5f, 0};
        f.halfExtents = {20, 0.5f, 20};
        world.addStaticBox(f);
    }
    ph::BodyHandle wall(const glm::vec3& c, const glm::vec3& half) {
        ph::BoxDesc w;
        w.center = c;
        w.halfExtents = half;
        return world.addStaticBox(w);
    }
};

// One fixed tick the way covenant runs it: think, then the world steps.
void step(Floor& f, GnawerAI& ai, const AITarget& t) {
    ai.tick(kDt, t);
    REQUIRE(f.world.step(kDt));
}

AITarget at(const glm::vec3& feet) {
    AITarget t;
    t.feet = feet;
    return t;
}

// A hit as EnemySystem::applyHit reports it, for onHit.
EnemyHit hitOf(std::uint32_t enemy, float amount, const glm::vec3& dir) {
    EnemyHit h;
    h.enemy = enemy;
    h.result.amount = amount;
    h.direction = dir;
    return h;
}

} // namespace

TEST_CASE("gnawer: gnawer.toml is Magewar's mutant rat") {
    const EnemyTable t = gnawersReal();
    REQUIRE(t.defs.size() == 1);
    const EnemyDef* g = t.find("gnawer");
    REQUIRE((g && g->ai));
    CHECK((g->affinity == Element::Earth && g->maxHealth == 30.0f && g->weakPoint.has_value()));
    const RusherDef& d = *g->ai;
    // enemy_mutant_rat.gd: detection 8, aggro 6, walk 3, sprint 5.5, contact 3, cooldown 0.8.
    CHECK((d.detectRange == 8.0f && d.aggroRange == 6.0f && d.walkSpeed == 3.0f && d.sprintSpeed == 5.5f));
    CHECK((d.attackDamage == 3.0f && d.attackCooldown == doctest::Approx(0.8f) && d.attackRange == 1.0f));
    // enemy_base.gd knockback: strength 10 for 0.5 s on hits over 10.
    CHECK((d.knockbackStrength == 10.0f && d.knockbackTime == 0.5f && d.knockbackThreshold == 10.0f));
    // The dummies have no brain; both files merge into one table.
    EnemyTable all;
    CHECK(loadEnemyFiles({std::string(COE_DATA_DIR) + "/enemies/training_dummies.toml",
                          std::string(COE_DATA_DIR) + "/enemies/gnawer.toml"},
                         all)
              .empty());
    REQUIRE(all.defs.size() == 3);
    CHECK((!all.find("earth_training_dummy")->ai && all.find("gnawer")->ai));
    // ... but the same id from two files is an error.
    EnemyTable dup;
    const std::string err = loadEnemyFiles({std::string(COE_DATA_DIR) + "/enemies/gnawer.toml",
                                            std::string(COE_DATA_DIR) + "/enemies/gnawer.toml"},
                                           dup);
    CHECK(err.find("already defined") != std::string::npos);
    CHECK(dup.defs.empty());
}

TEST_CASE("gnawer: ai keys default to Magewar enemy_base and bad tables are rejected") {
    const std::string head = "[[enemy]]\nid = \"g\"\nname = \"G\"\naffinity = \"earth\"\nmax_health = 30\n"
                             "size = [0.5, 0.45, 0.8]\ncolor = [0.4, 0.4, 0.4]\n";
    EnemyTable t;
    REQUIRE(parseEnemies(head + "ai = { kind = \"rusher\" }\n", "g.toml", t).empty());
    const RusherDef& d = *t.defs.at(0).ai;
    CHECK((d.detectRange == 15.0f && d.aggroRange == 10.0f && d.walkSpeed == 2.0f && d.sprintSpeed == 4.0f));
    CHECK((d.attackDamage == 5.0f && d.attackCooldown == 1.5f && d.knockbackStrength == 10.0f && d.knockbackTime == 0.5f));
    const auto err = [&](const std::string& ai) {
        EnemyTable x;
        const std::string e = parseEnemies(head + ai + "\n", "g.toml", x);
        CHECK(x.defs.empty() == !e.empty());
        return e;
    };
    CHECK(err("ai = { kind = \"flier\" }").find("unknown ai kind") != std::string::npos);
    CHECK(err("ai = { detect_range = 8.0 }").find("kind") != std::string::npos);
    CHECK(err("ai = { kind = \"rusher\", detect_range = 5.0, aggro_range = 6.0 }").find("aggro_range") != std::string::npos);
    CHECK(err("ai = { kind = \"rusher\", attack_cooldown = -1.0 }").find("attack_cooldown") != std::string::npos);
    CHECK(err("ai = { kind = \"rusher\", sight = 3.0 }").find("sight") != std::string::npos);
    CHECK(err("ai = { kind = \"rusher\", attack_range = 0.5 }").find("attack_range") != std::string::npos);
    CHECK(err("ai = \"rusher\"").find("ai must be a table") != std::string::npos);
    CHECK(err("ai = { kind = \"rusher\" }").empty());
}

TEST_CASE("gnawer: state machine bookkeeping") {
    StateMachine<GS> m(GS::Idle);
    CHECK((m.state() == GS::Idle && m.changes() == 0 && m.timeInState() == 0.0f));
    m.tick(0.5f);
    CHECK(!m.set(GS::Idle));
    CHECK(m.timeInState() == 0.5f);
    CHECK(m.set(GS::Chase));
    CHECK((m.state() == GS::Chase && m.previous() == GS::Idle && m.changes() == 1 && m.timeInState() == 0.0f));
}

TEST_CASE("gnawer: transitions at ranges (the pure rule, rat ranges 8 / 6 / 1 m)") {
    const RusherDef d = *gnawersReal().find("gnawer")->ai;
    const auto next = [&](GS s, float dist, bool los = true) {
        GnawerSenses in;
        in.distance = dist;
        in.lineOfSight = los;
        return nextGnawerState(s, d, in);
    };
    // Idle: notices within detect range, only with sight.
    CHECK(next(GS::Idle, 8.5f) == GS::Idle);
    CHECK(next(GS::Idle, 8.0f) == GS::Detect);
    CHECK(next(GS::Idle, 7.9f, false) == GS::Idle);
    CHECK(next(GS::Idle, 3.0f) == GS::Detect);   // one hop per tick
    // Detect: aggro inside 6 m, loses it beyond 8 m or out of sight.
    CHECK(next(GS::Detect, 6.5f) == GS::Detect);
    CHECK(next(GS::Detect, 6.0f) == GS::Chase);
    CHECK(next(GS::Detect, 8.1f) == GS::Idle);
    CHECK(next(GS::Detect, 7.0f, false) == GS::Idle);
    // Chase: bites from 1 m; hysteresis keeps chasing out to 8 m (even without sight).
    CHECK(next(GS::Chase, 7.9f) == GS::Chase);
    CHECK(next(GS::Chase, 7.0f, false) == GS::Chase);
    CHECK(next(GS::Chase, 8.1f) == GS::Idle);
    CHECK(next(GS::Chase, 1.0f) == GS::Attack);
    CHECK(next(GS::Chase, 1.05f) == GS::Chase);
    // Attack: holds out to 1.3 m, then chases again.
    CHECK(next(GS::Attack, 1.25f) == GS::Attack);
    CHECK(next(GS::Attack, 1.35f) == GS::Chase);
    // No player: idle.
    GnawerSenses none;
    none.targetValid = false;
    none.distance = 0.5f;
    CHECK(nextGnawerState(GS::Attack, d, none) == GS::Idle);
    // Hunting (shot in the last 5 s): Chase ignores the detect leash.
    GnawerSenses hunt;
    hunt.distance = 20.0f;
    hunt.hunting = true;
    CHECK(nextGnawerState(GS::Chase, d, hunt) == GS::Chase);
    // Provoked (shot): Idle / Detect go straight to Chase, whatever the range.
    GnawerSenses shot;
    shot.distance = 30.0f;
    shot.lineOfSight = false;
    shot.provoked = true;
    CHECK(nextGnawerState(GS::Idle, d, shot) == GS::Chase);
    CHECK(nextGnawerState(GS::Detect, d, shot) == GS::Chase);
    // Knockback overrides everything but death and ends aggressive.
    GnawerSenses kb;
    kb.distance = 3.0f;
    kb.knockbackLeft = 0.2f;
    for (GS s : {GS::Idle, GS::Detect, GS::Chase, GS::Attack, GS::Knockback}) CHECK(nextGnawerState(s, d, kb) == GS::Knockback);
    CHECK(next(GS::Knockback, 3.0f) == GS::Chase);
    CHECK(next(GS::Knockback, 0.9f) == GS::Attack);
    CHECK(next(GS::Knockback, 20.0f) == GS::Chase);
    // Death is terminal.
    GnawerSenses dead;
    dead.dead = true;
    dead.distance = 0.5f;
    for (GS s : {GS::Idle, GS::Detect, GS::Chase, GS::Attack, GS::Knockback}) CHECK(nextGnawerState(s, d, dead) == GS::Dead);
    CHECK(next(GS::Dead, 0.5f) == GS::Dead);
}

TEST_CASE("gnawer: 7 m away it detects, stalks, chases, stops at the player and bites every 0.8 s") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    const EnemyDef& def = *types.find("gnawer");
    Floor f;
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t id = enemies.spawn(def, {0, 0, -7}, 180.0f);
    CHECK(ai.adoptAll() == 1);
    CHECK(ai.adoptAll() == 0);
    const AITarget player = at({0, 0, 0});
    std::vector<GnawerTransition> path;
    std::vector<std::uint64_t> biteTicks;
    std::vector<EnemyAttack> bites;
    float minDist = 1e9f;
    for (int i = 0; i < 300; ++i) {   // 5 s
        step(f, ai, player);
        for (const GnawerTransition& t : ai.takeTransitions()) path.push_back(t);
        for (const EnemyAttack& a : ai.takeAttacks()) {
            bites.push_back(a);
            biteTicks.push_back(ai.ticks());
        }
        minDist = std::min(minDist, flatDist(enemies.find(id)->feet, player.feet));
    }
    REQUIRE(path.size() == 3);
    CHECK((path[0].from == GS::Idle && path[0].to == GS::Detect && path[0].tick == 1));
    CHECK(path[0].distance == doctest::Approx(7.0f));
    CHECK((path[1].from == GS::Detect && path[1].to == GS::Chase && path[1].distance <= 6.0f));
    CHECK((path[2].from == GS::Chase && path[2].to == GS::Attack && path[2].distance <= 1.0f));
    // Stalking 1 m at walk speed 3 m/s takes 20 ticks; sprinting 6 -> 0.9 m at 5.5 m/s ~ 56.
    CHECK(path[1].tick == doctest::Approx(21.0).epsilon(0.1));
    CHECK(path[2].tick - path[1].tick == doctest::Approx(56.0).epsilon(0.1));
    // It stops short of the capsule (body half 0.4 + radius 0.3), at 90 % of the bite range.
    const Enemy& e = *enemies.find(id);
    CHECK(minDist >= 0.7f);
    CHECK(flatDist(e.feet, player.feet) == doctest::Approx(0.9f).epsilon(0.01));
    CHECK(e.feet.y == doctest::Approx(0.0f).epsilon(0.01));
    CHECK(std::abs(std::remainder(e.yawDeg - 180.0f, 360.0f)) < 1.0f);   // faces the player (+Z)
    // Bites: the first on entering Attack, then every 0.8 s = 48 ticks; 3 Earth each.
    REQUIRE(bites.size() >= 4);
    CHECK(biteTicks[0] == path[2].tick);
    for (std::size_t k = 1; k < biteTicks.size(); ++k) CHECK(biteTicks[k] - biteTicks[k - 1] == 48);
    for (const EnemyAttack& a : bites)
        CHECK((a.enemy == id && a.damage == 3.0f && a.element == Element::Earth && !a.dodged && a.def == &def));
    const GnawerAgent& g = *ai.agent(id);
    CHECK((g.fsm.state() == GS::Attack && g.bites == bites.size() && g.dodged == 0));
    CHECK(g.travelled == doctest::Approx(6.1f).epsilon(0.02));
    // The hitbox followed (moveKinematic): its centre is over the feet.
    const ph::BodyState bs = f.world.state(e.body);
    CHECK(flatDist(bs.position, e.feet) < 0.01f);
    CHECK(bs.position.y == doctest::Approx(def.size.y * 0.5f).epsilon(0.01));

    // The player backs off to 1.5 m: it chases again and closes back in.
    const AITarget away = at({0, 0, 0.6f});
    for (int i = 0; i < 30; ++i) step(f, ai, away);
    std::vector<GnawerTransition> t = ai.takeTransitions();
    REQUIRE(t.size() == 2);
    CHECK((t[0].to == GS::Chase && t[1].to == GS::Attack));
    // ... and out of detect range: it gives up.
    const AITarget gone = at({0, 0, 12.0f});
    step(f, ai, gone);
    t = ai.takeTransitions();
    REQUIRE(t.size() == 2 - 1);
    CHECK((t[0].from == GS::Attack && t[0].to == GS::Chase));
    step(f, ai, gone);
    t = ai.takeTransitions();
    REQUIRE(t.size() == 1);
    CHECK(t[0].to == GS::Idle);
}

TEST_CASE("gnawer: beyond detect range, or behind a wall, it stays idle and still") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Floor f;
    f.wall({0, 1.5f, -3}, {3, 1.5f, 0.2f});   // 3 m tall wall between it and the player
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t far = enemies.spawn(*types.find("gnawer"), {10, 0, 0});    // 10 m: beyond 8
    const std::uint32_t hidden = enemies.spawn(*types.find("gnawer"), {0, 0, -6});   // 6 m, wall between
    ai.adoptAll();
    for (int i = 0; i < 180; ++i) step(f, ai, at({0, 0, 0}));
    CHECK(ai.takeTransitions().empty());
    CHECK(ai.takeAttacks().empty());
    CHECK((ai.agent(far)->fsm.state() == GS::Idle && ai.agent(hidden)->fsm.state() == GS::Idle));
    CHECK((ai.agent(far)->travelled == 0.0f && ai.agent(hidden)->travelled == 0.0f));
    CHECK(enemies.find(far)->feet == glm::vec3(10, 0, 0));
}

TEST_CASE("gnawer: chasing into a wall it slides along it instead of passing through") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Floor f;
    // A 1 m tall, 4 m long wall at z = -2 (sight passes over it at 0.36 m? no: its eyes are at
    // 0.36 m), so provoke it with a hit; the player is straight behind the wall.
    f.wall({-1.0f, 0.5f, -2}, {2.0f, 0.5f, 0.1f});
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t id = enemies.spawn(*types.find("gnawer"), {0, 0, -5});
    ai.adoptAll();
    ai.onHit(hitOf(id, 5.0f, {0, 0, -1}));   // 5 damage: provokes, no knockback
    float zMin = 1e9f;
    bool reached = false;
    for (int i = 0; i < 300 && !reached; ++i) {
        step(f, ai, at({0, 0, 0}));
        const Enemy& e = *enemies.find(id);
        // While beside the wall it never gets inside it (centre stays >= 0.2 m from its face).
        if (e.feet.x > -3.0f && e.feet.x < 1.0f) CHECK((e.feet.z <= -2.1f - 0.2f || e.feet.z >= -1.9f + 0.2f));
        zMin = std::min(zMin, e.feet.z);
        reached = ai.agent(id)->fsm.state() == GS::Attack;
    }
    CHECK(ai.agent(id)->knockbacks == 0);
    CHECK(reached);   // skirted round an end of the wall and got to the player
    CHECK(zMin >= -5.01f);   // never backed away
}

TEST_CASE("gnawer: its feet follow the ground (falls onto the floor, climbs a low step)") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Floor f;
    f.wall({0, 0.1f, -3}, {2, 0.1f, 1});   // a 0.2 m high step plate it crosses
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t id = enemies.spawn(*types.find("gnawer"), {0, 1.0f, -6});   // 1 m in the air
    ai.adoptAll();
    float peakOnStep = 0.0f;
    for (int i = 0; i < 240; ++i) {
        step(f, ai, at({0, 0, 0}));
        const Enemy& e = *enemies.find(id);
        if (e.feet.z > -3.8f && e.feet.z < -2.2f) peakOnStep = std::max(peakOnStep, e.feet.y);
    }
    CHECK(peakOnStep == doctest::Approx(0.2f).epsilon(0.02));
    CHECK(enemies.find(id)->feet.y == doctest::Approx(0.0f).epsilon(0.01));
    CHECK(ai.agent(id)->grounded);
    CHECK(ai.agent(id)->fsm.state() == GS::Attack);
}

TEST_CASE("gnawer: hits over 10 damage knock it back for 0.5 s (Magewar), smaller hits only provoke") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Floor f;
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t id = enemies.spawn(*types.find("gnawer"), {0, 0, -15});   // 15 m: idle
    ai.adoptAll();
    const AITarget player = at({0, 0, 0});
    step(f, ai, player);
    REQUIRE(ai.agent(id)->fsm.state() == GS::Idle);

    // 10 is not over 10: provoked into a chase, no knockback.
    ai.onHit(hitOf(id, 10.0f, {0, 0, -1}));
    step(f, ai, player);
    CHECK(ai.agent(id)->fsm.state() == GS::Chase);
    CHECK(ai.agent(id)->knockbacks == 0);
    ai.takeTransitions();

    // A 15-damage Fire bolt flying -Z: shoved 2.5 m along -Z over 30 ticks (linear decay
    // from 10 m/s), then it chases again.
    const glm::vec3 before = enemies.find(id)->feet;
    ai.onHit(hitOf(id, 15.0f, glm::normalize(glm::vec3(0.0f, -0.2f, -1.0f))));
    int kbTicks = 0;
    for (int i = 0; i < 60; ++i) {
        step(f, ai, player);
        if (ai.agent(id)->fsm.state() == GS::Knockback) ++kbTicks;
        if (i == 29) {
            const glm::vec3 now = enemies.find(id)->feet;
            CHECK(before.z - now.z == doctest::Approx(10.0f * 0.5f * 0.5f).epsilon(0.01));
            CHECK(std::abs(now.x - before.x) < 1e-4f);
            CHECK(now.y == doctest::Approx(0.0f).epsilon(0.01));   // pushed flat, not into the floor
        }
    }
    CHECK(kbTicks == 30);
    CHECK(ai.agent(id)->knockbacks == 1);
    const std::vector<GnawerTransition> t = ai.takeTransitions();
    REQUIRE(t.size() == 2);
    CHECK((t[0].to == GS::Knockback && t[1].from == GS::Knockback && t[1].to == GS::Chase));
    CHECK(t[1].tick - t[0].tick == 30);
    // Shot from 15 m (beyond detect 8) it hunts for 5 s instead of giving up at once.
    CHECK(ai.agent(id)->fsm.state() == GS::Chase);
}

TEST_CASE("gnawer: a real bolt through EnemySystem knocks it back along its flight and hits its new pose") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Floor f;
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t id = enemies.spawn(*types.find("gnawer"), {0, 0, -5}, 180.0f);
    ai.adoptAll();
    const AITarget player = at({0, 0, 0});
    for (int i = 0; i < 40; ++i) step(f, ai, player);   // detecting, then sprinting in
    const glm::vec3 feet = enemies.find(id)->feet;
    REQUIRE(feet.z > -4.0f);   // it moved
    ProjectileSystem bolts;
    ProjectileSpawn s;
    s.origin = {0, 0.12f, 0};   // under the snout (weak point 0.2..0.4 m up): the body
    s.direction = {0, 0, -1};
    s.element = Element::Fire;
    s.damage = 10.0f;
    s.radius = 0.05f;
    bolts.spawn(s);
    std::vector<ProjectileHit> hits;
    std::optional<EnemyHit> eh;
    for (int i = 0; i < 60 && !eh; ++i) {
        step(f, ai, player);
        hits.clear();
        bolts.tick(f.world, kDt, hits);
        for (const ProjectileHit& h : hits) {
            CHECK(h.direction == glm::vec3(0, 0, -1));
            if (auto r = enemies.applyHit(h)) eh = r;
        }
    }
    REQUIRE(eh);
    CHECK(eh->result.amount == doctest::Approx(15.0f));   // Fire > Earth
    CHECK(eh->direction == glm::vec3(0, 0, -1));
    // The hit lands on the Gnawer's moved front (head end toward the player).
    CHECK(eh->point.z > feet.z);
    ai.onHit(*eh);
    const float z0 = enemies.find(id)->feet.z;
    for (int i = 0; i < 30; ++i) step(f, ai, player);
    CHECK(z0 - enemies.find(id)->feet.z == doctest::Approx(2.5f).epsilon(0.01));   // away from the player
    CHECK(enemies.find(id)->health == doctest::Approx(15.0f));
}

TEST_CASE("gnawer: bites on an invulnerable (dashing) player are dodged") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Floor f;
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t id = enemies.spawn(*types.find("gnawer"), {0, 0, -0.95f});
    ai.adoptAll();
    AITarget player = at({0, 0, 0});
    player.invulnerable = true;
    for (int i = 0; i < 6 && ai.agent(id)->fsm.state() != GS::Attack; ++i) step(f, ai, player);
    REQUIRE(ai.agent(id)->fsm.state() == GS::Attack);   // idle -> detect -> chase -> attack (tick 3)
    CHECK(ai.ticks() == 3);
    std::vector<EnemyAttack> a = ai.takeAttacks();
    REQUIRE(a.size() == 1);
    CHECK(a[0].dodged);
    CHECK((ai.agent(id)->dodged == 1 && ai.agent(id)->bites == 0));
    // The cooldown was spent: vulnerable again, the next bite lands 48 ticks after.
    player.invulnerable = false;
    int ticks = 0;
    while (a = ai.takeAttacks(), a.empty() && ticks < 100) {
        step(f, ai, player);
        ++ticks;
    }
    REQUIRE(a.size() == 1);
    CHECK((!a[0].dodged && ticks == 48));
}

TEST_CASE("gnawer: a dead Gnawer stops thinking") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Floor f;
    EnemySystem enemies(f.world, el);
    GnawerAI ai(f.world, enemies);
    const std::uint32_t id = enemies.spawn(*types.find("gnawer"), {0, 0, -3});
    ai.adoptAll();
    const AITarget player = at({0, 0, 0});
    for (int i = 0; i < 10; ++i) step(f, ai, player);
    REQUIRE(ai.agent(id)->fsm.state() == GS::Chase);
    ai.takeTransitions();
    ProjectileHit kill;   // a 1000-damage Arcane bolt on its body
    kill.body = enemies.find(id)->body;
    kill.damage = 1000.0f;
    kill.element = Element::Arcane;
    const std::optional<EnemyHit> dead = enemies.applyHit(kill);
    REQUIRE((dead && dead->killed));
    step(f, ai, player);
    std::vector<GnawerTransition> t = ai.takeTransitions();
    REQUIRE(t.size() == 1);
    CHECK((t[0].from == GS::Chase && t[0].to == GS::Dead));
    const glm::vec3 feet = enemies.find(id)->feet;
    const float travelled = ai.agent(id)->travelled;
    ai.onHit(hitOf(id, 50.0f, {0, 0, -1}));   // ignored
    for (int i = 0; i < 120; ++i) step(f, ai, player);
    CHECK(ai.takeTransitions().empty());
    CHECK(ai.takeAttacks().empty());
    CHECK((ai.agent(id)->fsm.state() == GS::Dead && ai.agent(id)->knockbacks == 0));
    CHECK((enemies.find(id)->feet == feet && ai.agent(id)->travelled == travelled));
    CHECK(!enemies.place(id, {1, 0, 1}, 0.0f, kDt));   // the dead can't be moved
    CHECK(ai.adoptAll() == 0);
}

TEST_CASE("gnawer: in the Midden it chases a standing PlayerController and bites it") {
    const ElementTable el = elementsReal();
    const EnemyTable types = gnawersReal();
    Level level;
    REQUIRE(loadLevel(std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml", level).empty());
    ph::PhysicsWorld world;
    buildLevelPhysics(level, world);
    PlayerController player(world, level.playerStart.position, glm::radians(level.playerStart.yawDeg));
    const glm::vec3 start = player.feet();
    const glm::vec3 fwd = PlayerController::forwardFor(glm::radians(level.playerStart.yawDeg));
    EnemySystem enemies(world, el);
    GnawerAI ai(world, enemies);
    const std::uint32_t id = enemies.spawn(*types.find("gnawer"), start + fwd * 7.0f, level.playerStart.yawDeg + 180.0f);
    ai.adoptAll();
    int bites = 0;
    float damage = 0.0f;
    for (int i = 0; i < 180; ++i) {   // 3 s
        player.tick(coe::input::TickInput{}, kDt);
        AITarget t;
        t.feet = player.feet();
        t.eyeHeight = player.eyeHeight();
        t.radius = player.character().settings().radius;
        t.invulnerable = player.invulnerable();
        ai.tick(kDt, t);
        REQUIRE(world.step(kDt));
        for (const EnemyAttack& a : ai.takeAttacks())
            if (!a.dodged) {
                ++bites;
                damage += a.damage;
            }
    }
    CHECK(bites >= 2);
    CHECK(damage == doctest::Approx(3.0f * float(bites)));
    CHECK(flatDist(enemies.find(id)->feet, player.feet()) < 1.3f);
    CHECK(flatDist(player.feet(), start) < 0.05f);   // the kinematic box never shoved the player
}
