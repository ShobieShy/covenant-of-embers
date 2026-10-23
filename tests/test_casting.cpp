// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/magic (BUILD_PLAN step 17): wieldables data, spell bolts, casting.
// Done-check:
//  - a cast at a target box registers a hit at the right distance and travel time
//    (within 1 tick), also for bolts far faster than the target is thick;
//  - the Swift Wind Wand's cooldown holds: at most 1 cast per 0.18 s however Fire is spammed;
//  - the caster's own capsule (Character::innerBody(), which the eye ray starts inside) is
//    never hit, in any direction, while another character's is.
// Also: data/magic/wieldables.toml holds Magewar's four bases exactly, bad files are
// rejected with file:line, bolts fizzle at their range, mana-refused casts cost no cooldown.
// doctest cases (step 20), run by coe_tests.
#include "engine/physics/physics.hpp"
#include "game/combat/element.hpp"
#include "game/magic/casting.hpp"
#include "game/magic/projectile.hpp"
#include "game/magic/wieldable.hpp"
#include "game/player/player_controller.hpp"

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

constexpr float kDt = 1.0f / 60.0f;

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }
bool contains(const std::string& s, const char* sub) { return s.find(sub) != std::string::npos; }

WieldableTable loadReal() {
    WieldableTable t;
    const std::string err = loadWieldables(std::string(COE_DATA_DIR) + "/magic/wieldables.toml", t);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    CHECK(err.empty());
    return t;
}

// --- Data ---------------------------------------------------------------------------

TEST_CASE("casting: wieldables.toml holds Magewar's four bases") {
    const WieldableTable t = loadReal();
    CHECK(t.defs.size() == 4);
    struct Want { const char* id; const char* name; WieldableType type; Rarity r; Element e;
                  float dmg, mana, cd, speed, range; };
    const Want want[] = {
        {"apprentice_fire_staff", "Apprentice Fire Staff", WieldableType::Staff, Rarity::Basic, Element::Fire, 10, 5, 0.4f, 30, 50},
        {"earthward_battlestaff", "Earthward Battlestaff", WieldableType::Staff, Rarity::Uncommon, Element::Earth, 14, 6, 0.55f, 22, 45},
        {"novice_arcane_wand", "Novice Arcane Wand", WieldableType::Wand, Rarity::Basic, Element::Arcane, 7, 3, 0.25f, 40, 35},
        {"swift_wind_wand", "Swift Wind Wand", WieldableType::Wand, Rarity::Uncommon, Element::Air, 6, 2.5f, 0.18f, 55, 40},
    };
    for (const Want& w : want) {
        const WieldableDef* d = t.find(w.id);
        CHECK(d != nullptr);
        if (!d) continue;
        CHECK((d->name == w.name && d->type == w.type && d->baseRarity == w.r && d->element == w.e));
        CHECK((d->damage == w.dmg && d->manaCost == w.mana && d->cooldown == w.cd));
        CHECK((d->projectileSpeed == w.speed && d->range == w.range));
    }
    // Final stats with no parts (Magewar get_final_damage / get_final_fire_rate).
    const WieldableInstance earth(*t.find("earthward_battlestaff")), wind(*t.find("swift_wind_wand"));
    CHECK((near(earth.damage(), 17.5f, 1e-5f) && near(wind.damage(), 7.5f, 1e-5f)));
    CHECK((earth.parts.empty() && wind.cooldown() == 0.18f && wind.element() == Element::Air));
    CHECK(std::string(elementName(Element::Arcane)) == "arcane");
    CHECK((rarityMultiplier(Rarity::Unique) == 3.0f && std::string(rarityName(Rarity::Mythic)) == "mythic"));
    CHECK((parseElement("air") == Element::Air && !parseElement("wind") && parseWieldableType("wand") == WieldableType::Wand));
    std::printf("wieldables: %zu bases loaded (Magewar's four)\n", t.defs.size());
}

constexpr const char* kOk = R"(
[[wieldable]]
id = "w"
name = "W"
type = "wand"
base_rarity = "basic"
element = "fire"
damage = 5
mana_cost = 1
cooldown = 0.2
projectile_speed = 40
range = 30
)";

std::string withLine(const std::string& from, const std::string& to) {
    std::string s = kOk;
    const size_t at = s.find(from);
    REQUIRE(at != std::string::npos);   // (a plain check here let replace() throw on a typo)
    return s.replace(at, from.size(), to);
}

TEST_CASE("casting: bad wieldables files are rejected with file:line") {
    WieldableTable t;
    CHECK((parseWieldables(kOk, "w.toml", t).empty() && t.defs.size() == 1));
    struct Bad { std::string text; const char* expect; };
    const Bad bad[] = {
        {withLine("range = 30", "range = 30\ncolour = 1"), "w.toml:13: wieldable #1: unknown key 'colour'"},
        {withLine("element = \"fire\"", "element = \"wind\""), "w.toml:7: wieldable 'w': unknown element 'wind'"},
        {withLine("type = \"wand\"", "type = \"sword\""), "w.toml:5: wieldable 'w': unknown type 'sword'"},
        {withLine("base_rarity = \"basic\"", "base_rarity = \"epic\""), "w.toml:6: wieldable 'w': unknown base_rarity"},
        {withLine("cooldown = 0.2", "cooldown = 0.05"), "w.toml:10: wieldable 'w' cooldown must be in [0.1, 10]"},
        {withLine("damage = 5", "damage = -1"), "w.toml:8: wieldable 'w' damage must be in"},
        {withLine("projectile_speed = 40", "projectile_speed = \"fast\""), "w.toml:11: wieldable 'w' projectile_speed must be a number"},
        {withLine("range = 30\n", ""), "wieldable 'w' range must be a number"},
        {withLine("id = \"w\"", "id = \"Bad Id\""), "w.toml:3: wieldable #1: id 'Bad Id' must be lower_snake_case"},
        {std::string(kOk) + kOk, "w.toml:14: duplicate wieldable id 'w'"},
        {"title = 1\n", "w.toml:1: top level: unknown key 'title'"},
        {"# nothing\n", "need at least one [[wieldable]]"},
        {withLine("damage = 5", "damage = = 5"), "w.toml:8: TOML: "},
    };
    for (const Bad& b : bad) {
        const std::string err = parseWieldables(b.text, "w.toml", t);
        if (!contains(err, b.expect)) std::fprintf(stderr, "  expected '%s', got '%s'\n", b.expect, err.c_str());
        CHECK(contains(err, b.expect));
        CHECK(t.defs.empty());
    }
    CHECK(contains(loadWieldables("/no/such/wieldables.toml", t), "cannot open wieldables file"));
}

// --- Bolts --------------------------------------------------------------------------

struct Range {
    ph::PhysicsWorld w;
    ph::BodyHandle target;
    Range(float targetFrontZ, float thickness) {
        ph::BoxDesc floor;
        floor.center = {0, -0.5f, 0};
        floor.halfExtents = {80, 0.5f, 80};
        w.addStaticBox(floor);
        ph::BoxDesc box;
        box.center = {0, 1.5f, targetFrontZ - thickness * 0.5f};
        box.halfExtents = {1.0f, 1.5f, thickness * 0.5f};
        target = w.addStaticBox(box);
        w.optimizeBroadPhase();
    }
};

// Casts `def` from a PlayerController at the origin facing -Z and runs ticks until the
// bolt lands; returns the hit (body invalid if none).
ProjectileHit castAtTarget(const WieldableDef& def, Range& r, int& ticksRun) {
    PlayerController p(r.w, {0, 0, 0}, 0.0f);
    const WieldableInstance inst(def);
    Caster caster(inst);
    ProjectileSystem bolts;
    std::vector<ProjectileHit> hits;
    ticksRun = 0;
    coe::input::TickInput none;
    bool fired = false;
    while (hits.empty() && ticksRun < 600) {
        p.tick(none, kDt);
        CHECK(r.w.step(kDt));
        if (!fired) { CHECK(caster.tick(true, true, kDt, playerAim(p), bolts)); fired = true; }
        else caster.tick(false, false, kDt, playerAim(p), bolts);
        bolts.tick(r.w, kDt, hits);
        ++ticksRun;
        if (bolts.live().empty() && hits.empty()) break;
    }
    CHECK(hits.size() == 1);
    return hits.empty() ? ProjectileHit{} : hits[0];
}

TEST_CASE("casting: a bolt hits at the right distance and time") {
    const WieldableTable t = loadReal();
    const float frontZ = -20.0f;
    for (const WieldableDef& def : t.defs) {
        Range r(frontZ, 1.0f);
        int ticks = 0;
        const ProjectileHit h = castAtTarget(def, r, ticks);
        const float eyeZ = 0.0f;
        const float d = eyeZ - frontZ;                       // 20 m from the eye to the face
        const float tExpect = d / def.projectileSpeed;
        const int tickExpect = int(std::ceil(d / (def.projectileSpeed * kDt) - 1e-4f));
        std::printf("bolt %-22s %4.0f m/s: hit at %.3f m after %.4f s (tick %d; expected %.3f m, %.4f s, tick %d)\n",
                    def.id.c_str(), double(def.projectileSpeed), double(h.distance), double(h.time), h.tick,
                    double(d), double(tExpect), tickExpect);
        CHECK(h.body == r.target);
        CHECK(near(h.distance, d, 0.01f));
        CHECK(near(h.time, tExpect, kDt));                   // done-check: within 1 tick
        CHECK(std::abs(h.tick - tickExpect) <= 1);
        CHECK((near(h.point.z, frontZ, 0.01f) && near(h.normal.z, 1.0f, 1e-3f)));
        CHECK((h.element == def.element && near(h.damage, WieldableInstance(def).damage(), 1e-5f)));
    }
    // A bolt much faster than the wall is thick (500 m/s = 8.3 m per tick vs 5 cm) still
    // stops on the near face: the sweep is a ray, not a per-tick position test.
    {
        WieldableDef fast = t.defs[0];
        fast.projectileSpeed = 500.0f;
        fast.range = 100.0f;
        Range r(-37.3f, 0.05f);
        int ticks = 0;
        const ProjectileHit h = castAtTarget(fast, r, ticks);
        CHECK((h.body == r.target && near(h.distance, 37.3f, 0.01f) && near(h.time, 37.3f / 500.0f, kDt)));
        std::printf("bolt 500 m/s vs 5 cm wall: hit at %.3f m after %.4f s (tick %d)\n", double(h.distance),
                    double(h.time), h.tick);
    }
}

TEST_CASE("casting: bolts fizzle at their range; tracers use element colours") {
    const WieldableTable t = loadReal();
    const WieldableInstance wand(*t.find("novice_arcane_wand"));   // 35 m at 40 m/s
    ph::PhysicsWorld w;   // empty: nothing to hit
    ProjectileSystem bolts;
    Caster c(wand);
    std::vector<ProjectileHit> hits;
    CHECK(c.tick(true, true, kDt, {{0, 1.5f, 0}, {0, 0, -1}, {}}, bolts));
    int ticks = 0;
    while (!bolts.live().empty() && ticks < 600) { bolts.tick(w, kDt, hits); ++ticks; }
    CHECK((hits.empty() && bolts.fizzled() == 1 && bolts.spawned() == 1));
    CHECK(ticks == int(std::ceil(35.0f / (40.0f * kDt))));   // 53 ticks
    std::printf("range: arcane wand bolt fizzled after %d ticks (35 m at 40 m/s)\n", ticks);
    // Debug tracer: coloured from elements.toml (step 20), never inside the first kSkipNear metres.
    ElementTable elements;
    const std::string err = loadElements(std::string(COE_DATA_DIR) + "/magic/elements.toml", elements);
    CHECK(err.empty());
    ProjectileSystem b2;
    b2.setElements(&elements);
    b2.spawn({{0, 1.5f, 0}, {0, 0, -1}, 40.0f, 35.0f, Element::Air, 1.0f, {}});
    std::vector<DebugLine> lines;
    b2.debugLines(0.5f, lines);
    CHECK(lines.empty());   // not moved yet
    for (int i = 0; i < 3; ++i) b2.tick(w, kDt, hits);   // 2 m out
    b2.debugLines(1.0f, lines);
    CHECK((lines.size() == 1 && lines[0].color == elements.color(Element::Air)));
    CHECK((!lines.empty() && lines[0].color == glm::vec3(0.8f, 0.95f, 1.0f)));   // Magewar AIR
    CHECK((!lines.empty() && near(lines[0].a.z, -ProjectileSystem::kSkipNear, 1e-4f) && near(lines[0].b.z, -2.0f, 1e-4f)));
    // Without an element table the tracer is white.
    b2.setElements(nullptr);
    lines.clear();
    b2.debugLines(1.0f, lines);
    CHECK((lines.size() == 1 && lines[0].color == glm::vec3(1.0f)));
}

// --- Cooldown -----------------------------------------------------------------------

std::vector<double> spam(const WieldableInstance& w, float dt, double seconds, int pressEvery, bool hold, bool repeat) {
    Caster c(w);
    c.setHoldToRepeat(repeat);
    ProjectileSystem bolts;
    std::vector<double> times;
    const int n = int(std::lround(seconds / dt));
    for (int i = 0; i < n; ++i)
        if (c.tick(i % pressEvery == 0, hold, dt, {{0, 1.5f, 0}, {0, 0, -1}, {}}, bolts)) times.push_back(i * double(dt));
    CHECK(c.casts() == times.size());
    return times;
}

TEST_CASE("casting: cooldown holds however Fire is spammed") {
    const WieldableTable t = loadReal();
    const WieldableInstance wind(*t.find("swift_wind_wand"));
    const double kWindow = 3.0;
    for (float hz : {60.0f, 144.0f, 30.0f}) {
        for (int every : {1, 2, 3, 7}) {
            const std::vector<double> times = spam(wind, 1.0f / hz, kWindow, every, true, false);
            double minGap = 1e9;
            for (size_t i = 1; i < times.size(); ++i) minGap = std::min(minGap, times[i] - times[i - 1]);
            CHECK(minGap >= 0.18 - 1e-6);                                    // done-check
            CHECK(times.size() <= size_t(std::floor(kWindow / 0.18)) + 1);
            // Any 0.18 s window holds at most one cast.
            for (size_t i = 1; i < times.size(); ++i) CHECK(times[i] - times[i - 1] >= 0.18 - 1e-6);
            if (hz == 60.0f && every == 1)
                std::printf("cooldown: swift wind wand spammed every tick at 60 Hz for 3 s -> %zu casts, min gap %.4f s (11 ticks)\n",
                            times.size(), minGap);
            if (hz == 60.0f && every == 1) CHECK((times.size() == 17 && near(float(minGap), 11.0f / 60.0f, 1e-5f)));
        }
    }
    // Semi-auto like Magewar: holding Fire after one press casts once.
    CHECK(spam(wind, kDt, 2.0, 100000, true, false).size() == 1);
    // holdToRepeat (options, step 44) re-casts while held, still on the cooldown.
    const std::vector<double> held = spam(wind, kDt, 2.0, 100000, true, true);
    CHECK(held.size() == 11);   // ticks 0, 11, ..., 110
    // Fire staff: 0.4 s = 24 ticks.
    const std::vector<double> staff = spam(WieldableInstance(*t.find("apprentice_fire_staff")), kDt, 1.0, 1, true, false);
    CHECK((staff.size() == 3 && near(float(staff[1] - staff[0]), 0.4f, 1e-5f)));
    // Mana refused (step 18 hook): no cast, no cooldown, so the next affordable press casts.
    Caster c(wind);
    ProjectileSystem bolts;
    bool affordable = false;
    c.setManaSpender([&](float cost) { CHECK(cost == 2.5f); return affordable; });
    CHECK((!c.tick(true, true, kDt, {}, bolts) && c.blocked() == 1 && c.cooldownRemaining() == 0.0f));
    affordable = true;
    CHECK((c.tick(true, true, kDt, {}, bolts) && near(c.cooldownRemaining(), 0.18f, 1e-6f)));
    CHECK((!c.tick(true, true, kDt, {}, bolts) && c.blocked() == 2));   // on cooldown
    // Empty hands never cast; swapping keeps the running cooldown.
    const WieldableInstance staffI(*t.find("apprentice_fire_staff"));
    c.equip(&staffI);
    CHECK(!c.tick(true, true, kDt, {}, bolts));
    c.equip(nullptr);
    for (int i = 0; i < 60; ++i) CHECK(!c.tick(true, true, kDt, {}, bolts));
}

// --- Own capsule --------------------------------------------------------------------

TEST_CASE("casting: the caster's own capsule is never hit") {
    const WieldableTable t = loadReal();
    ph::PhysicsWorld w;
    ph::BoxDesc floor;
    floor.center = {0, -0.5f, 0};
    floor.halfExtents = {80, 0.5f, 80};
    w.addStaticBox(floor);
    PlayerController me(w, {0, 0, 0}, 0.0f);
    PlayerController other(w, {0, 0, -6.0f}, 0.0f);
    w.optimizeBroadPhase();
    coe::input::TickInput none;
    for (int i = 0; i < 3; ++i) { me.tick(none, kDt); other.tick(none, kDt); CHECK(w.step(kDt)); }
    const ph::BodyHandle mine = me.character().innerBody(), theirs = other.character().innerBody();
    CHECK((mine.valid() && theirs.valid() && !(mine == theirs)));
    CHECK((w.layer(mine) == ph::Layers::Character && w.layer(theirs) == ph::Layers::Character));

    // Why the filter is needed: the eye is inside the caster's capsule, so an unfiltered
    // ray hits it immediately.
    const CastAim aim = playerAim(me);
    CHECK((aim.ignore == mine && near(aim.origin.y, 1.5f, 1e-3f) && near(aim.direction.z, -1.0f, 1e-5f)));
    const auto raw = w.castRay(aim.origin, {0, 0, 1.0f});
    CHECK((raw && raw->body == mine && raw->fraction == 0.0f));
    CHECK(!w.castRay(aim.origin, {0, 0, 1.0f}, mine));

    // Bolts in 26 directions (incl. straight down through the body and up) never hit the
    // caster; down lands on the floor 1.5 m below the eye, forward on the other player.
    const WieldableInstance wand(*t.find("swift_wind_wand"));
    int checked = 0, selfHits = 0, floorHits = 0;
    float forwardDist = -1.0f;
    for (int x = -1; x <= 1; ++x)
        for (int y = -1; y <= 1; ++y)
            for (int z = -1; z <= 1; ++z) {
                if (!x && !y && !z) continue;
                Caster c(wand);
                ProjectileSystem bolts;
                std::vector<ProjectileHit> hits;
                CastAim a = aim;
                a.direction = glm::normalize(glm::vec3(float(x), float(y), float(z)));
                CHECK(c.tick(true, true, kDt, a, bolts));
                for (int i = 0; i < 120 && !bolts.live().empty(); ++i) bolts.tick(w, kDt, hits);
                for (const ProjectileHit& h : hits) {
                    if (h.body == mine) ++selfHits;
                    if (x == 0 && y == -1 && z == 0) { CHECK(near(h.distance, 1.5f, 0.01f)); ++floorHits; }
                    if (x == 0 && y == 0 && z == -1) { CHECK(h.body == theirs); forwardDist = h.distance; }
                }
                ++checked;
            }
    CHECK((checked == 26 && selfHits == 0 && floorHits == 1));
    CHECK(near(forwardDist, 6.0f - 0.3f, 0.02f));   // the other capsule's surface (radius 0.3)
    // Crouched (smaller inner body) and moving: still never self-hit, cast every tick for 2 s.
    coe::input::TickInput crouchRun;
    crouchRun.held.set(size_t(coe::input::Action::Crouch));
    crouchRun.held.set(size_t(coe::input::Action::MoveLeft));
    Caster c(wand);
    c.setHoldToRepeat(true);
    ProjectileSystem bolts;
    std::vector<ProjectileHit> hits;
    for (int i = 0; i < 120; ++i) {
        me.setLook(float(i) * 0.3f, -1.2f + float(i % 7) * 0.4f);
        me.tick(crouchRun, kDt);
        CHECK(w.step(kDt));
        c.tick(false, true, kDt, playerAim(me), bolts);
        bolts.tick(w, kDt, hits);
    }
    for (const ProjectileHit& h : hits) CHECK(!(h.body == mine));
    CHECK((me.crouched() && c.casts() >= 10 && !hits.empty()));
    std::printf("own capsule: unfiltered eye ray hits it at fraction 0; 26 directions + %llu moving/crouched casts: "
                "0 self hits; other player hit at %.3f m\n", (unsigned long long)c.casts(), double(forwardDist));
}

} // namespace
