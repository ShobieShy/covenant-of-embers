// SPDX-License-Identifier: Apache-2.0
// Enemy tests (BUILD_PLAN step 22): enemy types from data/enemies/*.toml, health, death,
// bolt hits through the step-20 damage formula, weak points and the enemy sphere sweep.
// Done-check: casting the Apprentice Fire Staff (via Loadout::tick) at the Earth dummy
// lowers its health by the formula value, 10 x 1.5 = 15 (Fire > Earth); it dies at
// exactly 0 after four hits and later bolts fly through to the wall behind.
#include "engine/physics/physics.hpp"
#include "game/combat/damage.hpp"
#include "game/combat/element.hpp"
#include "game/enemies/enemy.hpp"
#include "game/magic/casting.hpp"
#include "game/magic/loadout.hpp"
#include "game/magic/projectile.hpp"
#include "game/magic/wieldable.hpp"
#include "game/world/level.hpp"

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
namespace ph = coe::physics;

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
EnemyTable enemiesReal() {
    return loadOrFail<EnemyTable>([](const std::string& p, EnemyTable& t) { return loadEnemies(p, t); },
                                  "/enemies/training_dummies.toml");
}
WieldableTable wieldablesReal() {
    return loadOrFail<WieldableTable>([](const std::string& p, WieldableTable& t) { return loadWieldables(p, t); },
                                      "/magic/wieldables.toml");
}

// A floor and a wall 10 m north of the origin; a dummy stands at z = -5.
struct Range {
    ph::PhysicsWorld world;
    ph::BodyHandle wall;
    Range() {
        ph::BoxDesc floor;
        floor.center = {0, -0.5f, 0};
        floor.halfExtents = {20, 0.5f, 20};
        world.addStaticBox(floor);
        ph::BoxDesc w;
        w.center = {0, 2, -10};
        w.halfExtents = {20, 2, 0.5f};
        wall = world.addStaticBox(w);
    }
};

// Ticks `bolts` until none is live; returns every hit, applying each to `enemies`.
std::vector<EnemyHit> settle(Range& r, ProjectileSystem& bolts, EnemySystem& enemies, std::vector<ProjectileHit>* raw = nullptr) {
    std::vector<EnemyHit> out;
    std::vector<ProjectileHit> hits;
    for (int i = 0; i < 600 && !bolts.live().empty(); ++i) {
        hits.clear();
        bolts.tick(r.world, kDt, hits);
        for (const ProjectileHit& h : hits) {
            if (raw) raw->push_back(h);
            if (auto eh = enemies.applyHit(h)) out.push_back(*eh);
        }
    }
    return out;
}

ProjectileSpawn bolt(const glm::vec3& origin, const glm::vec3& dir, Element e, float damage, float radius = 0.1f) {
    ProjectileSpawn s;
    s.origin = origin;
    s.direction = dir;
    s.element = e;
    s.damage = damage;
    s.radius = radius;
    return s;
}

} // namespace

TEST_CASE("enemy: the shipped training dummies load") {
    const EnemyTable t = enemiesReal();
    REQUIRE(t.defs.size() == 2);
    const EnemyDef* earth = t.find("earth_training_dummy");
    const EnemyDef* water = t.find("water_training_dummy");
    REQUIRE((earth && water));
    CHECK((earth->affinity == Element::Earth && earth->maxHealth == 60.0f && earth->weakPoint.has_value()));
    CHECK((water->affinity == Element::Water && water->resist[std::size_t(Element::Air)] == doctest::Approx(0.25f)));
    CHECK(earth->resist == Resistances{});
    CHECK(!t.find("nope"));
}

TEST_CASE("enemy: a Fire staff cast at the Earth dummy deals 10 x 1.5 = 15, it dies at exactly 0") {
    const ElementTable el = elementsReal();
    const EnemyTable types = enemiesReal();
    const WieldableTable wt = wieldablesReal();
    const WieldableInstance staff(*wt.find("apprentice_fire_staff"));
    REQUIRE((staff.element() == Element::Fire && staff.damage() == 10.0f));
    Range r;
    EnemySystem enemies(r.world, el);
    const std::uint32_t id = enemies.spawn(*types.find("earth_training_dummy"), {0, 0, -5});
    CHECK((enemies.alive() == 1 && enemies.find(id)->health == 60.0f));
    CHECK(r.world.layer(enemies.find(id)->body) == ph::Layers::Enemy);
    CHECK(enemies.byBody(enemies.find(id)->body) == enemies.find(id));
    CHECK(enemies.byBody(r.wall) == nullptr);

    Loadout l;
    REQUIRE(l.equip(Slot::Staff, &staff));
    ProjectileSystem bolts;
    const CastAim aim{{0, 0.8f, 0}, {0, 0, -1}, {}, {}};   // chest height, straight at it
    float health = 60.0f;
    for (int hit = 1; hit <= 4; ++hit) {
        CAPTURE(hit);
        bool cast = false;
        for (int i = 0; i < 120 && !cast; ++i) cast = l.tick(true, true, kDt, aim, bolts);
        REQUIRE(cast);
        const std::vector<EnemyHit> hits = settle(r, bolts, enemies);
        REQUIRE(hits.size() == 1);
        const EnemyHit& h = hits.front();
        CHECK((h.enemy == id && h.element == Element::Fire && !h.weakPoint));
        CHECK(h.result.amount == doctest::Approx(15.0f));
        CHECK((h.result.effectiveness == 1.5f && h.result.strong()));
        CHECK(h.healthBefore == doctest::Approx(health));
        health -= 15.0f;
        CHECK(h.healthAfter == doctest::Approx(health));
        CHECK(h.killed == (hit == 4));
        CHECK(h.point.z == doctest::Approx(-5.0f + 0.35f).epsilon(0.01));
    }
    const Enemy& e = *enemies.find(id);
    CHECK((e.dead && e.health == 0.0f && e.hits == 4 && e.damageTaken == doctest::Approx(60.0f)));
    CHECK((!e.body.valid() && !e.weakPoint.valid() && enemies.alive() == 0 && enemies.kills() == 1));
    const std::vector<EnemyDeath> deaths = enemies.takeDeaths();
    REQUIRE(deaths.size() == 1);
    CHECK((deaths[0].enemy == id && deaths[0].killingElement == Element::Fire));
    CHECK(enemies.takeDeaths().empty());

    // A fifth bolt flies through where the dummy stood and hits the wall.
    bool cast = false;
    for (int i = 0; i < 120 && !cast; ++i) cast = l.tick(true, true, kDt, aim, bolts);
    REQUIRE(cast);
    std::vector<ProjectileHit> raw;
    CHECK(settle(r, bolts, enemies, &raw).empty());
    REQUIRE(raw.size() == 1);
    CHECK(raw[0].body == r.wall);
}

TEST_CASE("enemy: health is clamped at 0 (overkill) and the formula follows the chart") {
    const ElementTable el = elementsReal();
    const EnemyTable types = enemiesReal();
    Range r;
    EnemySystem enemies(r.world, el);
    const std::uint32_t water = enemies.spawn(*types.find("water_training_dummy"), {0, 0, -5});
    ProjectileSystem bolts;
    // Fire vs Water: x0.5.
    bolts.spawn(bolt({0, 0.8f, 0}, {0, 0, -1}, Element::Fire, 10.0f));
    std::vector<EnemyHit> h = settle(r, bolts, enemies);
    REQUIRE(h.size() == 1);
    CHECK((h[0].result.amount == doctest::Approx(5.0f) && h[0].result.weak()));
    // Air vs Water: x1.5 (Air > Water) and its 25 % air resist: 10 x 1.5 x 0.75 = 11.25.
    bolts.spawn(bolt({0, 0.8f, 0}, {0, 0, -1}, Element::Air, 10.0f));
    h = settle(r, bolts, enemies);
    REQUIRE(h.size() == 1);
    CHECK(h[0].result.amount == doctest::Approx(11.25f));
    CHECK(h[0].result.resist == doctest::Approx(0.25f));
    CHECK(enemies.find(water)->health == doctest::Approx(60.0f - 5.0f - 11.25f));
    // A huge hit: amount is the formula value, health stops at 0.
    bolts.spawn(bolt({0, 0.8f, 0}, {0, 0, -1}, Element::Arcane, 1000.0f));
    h = settle(r, bolts, enemies);
    REQUIRE(h.size() == 1);
    CHECK((h[0].result.amount == doctest::Approx(1000.0f) && h[0].healthAfter == 0.0f && h[0].killed));
    CHECK(enemies.find(water)->damageTaken == doctest::Approx(60.0f));
}

TEST_CASE("enemy: the weak point takes x2") {
    const ElementTable el = elementsReal();
    const EnemyTable types = enemiesReal();
    Range r;
    EnemySystem enemies(r.world, el);
    const std::uint32_t id = enemies.spawn(*types.find("earth_training_dummy"), {0, 0, -5});
    const Enemy& e = *enemies.find(id);
    REQUIRE(e.weakPoint.valid());
    CHECK((r.world.layer(e.weakPoint) == ph::Layers::Enemy && enemies.byBody(e.weakPoint) == &e));
    ProjectileSystem bolts;
    bolts.spawn(bolt({0, 1.78f, 0}, {0, 0, -1}, Element::Fire, 10.0f));   // head height
    const std::vector<EnemyHit> h = settle(r, bolts, enemies);
    REQUIRE(h.size() == 1);
    CHECK((h[0].weakPoint && h[0].result.crit == kWeakPointMultiplier));
    CHECK(h[0].result.amount == doctest::Approx(10.0f * 1.5f * 2.0f));
}

TEST_CASE("enemy: bolts sweep a 0.1 m sphere against enemies, so a grazing shot counts") {
    const ElementTable el = elementsReal();
    const EnemyTable types = enemiesReal();
    Range r;
    EnemySystem enemies(r.world, el);
    enemies.spawn(*types.find("earth_training_dummy"), {0, 0, -5});   // body x in [-0.35, 0.35]
    ProjectileSystem bolts;
    // The ray passes 0.05 m beside the body: the ray misses, the sphere grazes it.
    bolts.spawn(bolt({0.4f, 0.8f, 0}, {0, 0, -1}, Element::Fire, 10.0f));
    std::vector<ProjectileHit> raw;
    std::vector<EnemyHit> h = settle(r, bolts, enemies, &raw);
    REQUIRE(h.size() == 1);
    REQUIRE(raw.size() == 1);
    CHECK(raw[0].grazed);
    CHECK(raw[0].point.x == doctest::Approx(0.35f).epsilon(0.02));
    // Radius 0 = ray only: the same shot misses and hits the wall.
    raw.clear();
    bolts.spawn(bolt({0.4f, 0.8f, 0}, {0, 0, -1}, Element::Fire, 10.0f, 0.0f));
    CHECK(settle(r, bolts, enemies, &raw).empty());
    REQUIRE(raw.size() == 1);
    CHECK((raw[0].body == r.wall && !raw[0].grazed));
    // 0.15 m beside: outside the radius too.
    raw.clear();
    bolts.spawn(bolt({0.5f, 0.8f, 0}, {0, 0, -1}, Element::Fire, 10.0f));
    CHECK(settle(r, bolts, enemies, &raw).empty());
    REQUIRE(raw.size() == 1);
    CHECK(raw[0].body == r.wall);
    // A direct hit is a ray hit (not grazed).
    raw.clear();
    bolts.spawn(bolt({0.0f, 0.8f, 0}, {0, 0, -1}, Element::Fire, 10.0f));
    CHECK(settle(r, bolts, enemies, &raw).size() == 1);
    REQUIRE(raw.size() == 1);
    CHECK(!raw[0].grazed);
}

TEST_CASE("physics: castSphere honours the layer mask and ignore body") {
    Range r;
    ph::BoxDesc d;
    d.center = {0, 1, -5};
    d.halfExtents = {0.3f, 1, 0.3f};
    d.layer = ph::Layers::Enemy;
    const ph::BodyHandle enemy = r.world.addKinematicBox(d);
    CHECK(r.world.layer(enemy) == ph::Layers::Enemy);
    CHECK(std::string(ph::layerName(ph::Layers::Enemy)) == "enemy");
    const auto any = r.world.castSphere({0, 1, 0}, {0, 0, -20}, 0.1f, {});
    REQUIRE(any);
    CHECK(any->body == enemy);
    CHECK(any->point.z == doctest::Approx(-4.7f).epsilon(0.01));
    CHECK(any->normal.z == doctest::Approx(1.0f).epsilon(0.01));
    const auto statics = r.world.castSphere({0, 1, 0}, {0, 0, -20}, 0.1f, {}, ph::Layers::bit(ph::Layers::Static));
    REQUIRE(statics);
    CHECK(statics->body == r.wall);
    const auto ignored = r.world.castSphere({0, 1, 0}, {0, 0, -20}, 0.1f, enemy, ph::Layers::bit(ph::Layers::Enemy));
    CHECK(!ignored);
    CHECK(!r.world.castSphere({0, 1, 0}, {0, 0, -20}, 0.0f, {}));   // radius 0: nothing
    // Kinematic enemies move (step 23's walkers).
    r.world.moveKinematic(enemy, {3, 1, -5}, glm::quat(1, 0, 0, 0), kDt);
    CHECK(r.world.step(kDt));
    const auto moved = r.world.castSphere({3, 1, 0}, {0, 0, -20}, 0.1f, {}, ph::Layers::bit(ph::Layers::Enemy));
    REQUIRE(moved);
    CHECK(moved->body == enemy);
}

TEST_CASE("enemy: dummies are placed on the Midden and its TOML is strict") {
    Level lv;
    REQUIRE(loadLevel(std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml", lv).empty());
    EnemyTable types;   // the game's default enemy files (step 23 added the Gnawer)
    REQUIRE(loadEnemyFiles({std::string(COE_DATA_DIR) + "/enemies/training_dummies.toml",
                            std::string(COE_DATA_DIR) + "/enemies/gnawer.toml"},
                           types)
                .empty());
    REQUIRE(lv.enemies.size() == 3);   // two dummies + the Gnawer in the north-west corner
    for (const LevelEnemy& e : lv.enemies) CHECK(types.find(e.enemy) != nullptr);

    EnemyTable t;
    const std::string ok = "[[enemy]]\nid = \"d\"\nname = \"D\"\naffinity = \"fire\"\nmax_health = 10\n"
                           "size = [1, 2, 1]\ncolor = [1, 1, 1]\n";
    CHECK(parseEnemies(ok, "e.toml", t).empty());
    CHECK(t.defs.size() == 1);
    const auto err = [&](const std::string& text) { return parseEnemies(text, "e.toml", t); };
    CHECK(err(ok + "colour = [1, 1, 1]\n").find("colour") != std::string::npos);
    CHECK(err("[[enemy]]\nid = \"d\"\nname = \"D\"\naffinity = \"lava\"\nmax_health = 10\nsize = [1, 2, 1]\ncolor = [1, 1, 1]\n")
              .find("unknown affinity 'lava'") != std::string::npos);
    CHECK(err(ok + ok).find("duplicate enemy id 'd'") != std::string::npos);
    CHECK(err(ok + "resist = { fire = 1.5 }\n").find("resist.fire") != std::string::npos);
    CHECK(err(ok + "resist = { lava = 0.5 }\n").find("unknown resist element 'lava'") != std::string::npos);
    CHECK(err(ok + "weak_point = { offset = [0, 1, 0] }\n").find("weak_point size") != std::string::npos);
    CHECK(err("[[enemy]]\nid = \"Bad Id\"\nname = \"D\"\n").find("lower_snake_case") != std::string::npos);
    CHECK(err("").find("enemy") != std::string::npos);
    CHECK(t.defs.empty());
    CHECK(err(ok).find(':') == std::string::npos);   // still parses after errors

    Level bad;
    std::string text;
    {
        std::FILE* f = std::fopen((std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml").c_str(), "rb");
        REQUIRE(f);
        char buf[4096];
        for (std::size_t n; (n = std::fread(buf, 1, sizeof buf, f)) > 0;) text.append(buf, n);
        std::fclose(f);
    }
    CHECK(parseLevel(text + "[[enemy]]\nenemy = \"x\"\nposition = [0, 3, 0]\n", "m.toml", bad).find("box surface") !=
          std::string::npos);
    CHECK(parseLevel(text + "[[enemy]]\nenemy = \"x\"\nposition = [0, 0, 10]\nhp = 3\n", "m.toml", bad).find("hp") !=
          std::string::npos);
    CHECK(parseLevel(text + "[[enemy]]\nenemy = \"x\"\nposition = [0, 0, 10]\n", "m.toml", bad).empty());
    CHECK(bad.enemies.size() == lv.enemies.size() + 1);
}
