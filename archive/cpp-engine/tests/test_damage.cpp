// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/combat (BUILD_PLAN step 20): Magewar elements + the damage formula.
// Done-check (>= 10 doctest cases): the full 7x7 effectiveness table, rarity multipliers
// x1.0 ... x3.0, the part bonus sum, the 60 % resist cap and the weak-point crit.
// Also: data/magic/elements.toml holds Magewar's names/colours/chart, bad element files
// are rejected with file:line, and a worked example through every factor.
#include "game/combat/damage.hpp"
#include "game/combat/element.hpp"
#include "game/magic/wieldable.hpp"

#include <doctest/doctest.h>
#include <glm/glm.hpp>

#include <cmath>
#include <string>
#include <vector>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
using namespace coe::game;
using E = Element;

bool contains(const std::string& s, const char* sub) { return s.find(sub) != std::string::npos; }

ElementTable loadReal() {
    ElementTable t;
    const std::string err = loadElements(std::string(COE_DATA_DIR) + "/magic/elements.toml", t);
    INFO(err);
    CHECK(err.empty());
    return t;
}

// Magewar MagicElement.get_effectiveness, transcribed independently of the data file.
float magewarEffectiveness(E a, E d) {
    if (a == d || a == E::Arcane || d == E::Arcane) return 1.0f;
    switch (a) {
        case E::Fire: return d == E::Earth ? 1.5f : d == E::Water ? 0.5f : 1.0f;
        case E::Water: return d == E::Fire ? 1.5f : d == E::Air ? 0.5f : 1.0f;
        case E::Earth: return d == E::Air ? 1.5f : d == E::Fire ? 0.5f : 1.0f;
        case E::Air: return d == E::Water ? 1.5f : d == E::Earth ? 0.5f : 1.0f;
        case E::Light: return d == E::Dark ? 1.5f : 1.0f;
        case E::Dark: return d == E::Light ? 1.5f : 1.0f;
        default: return 1.0f;
    }
}

// --- Elements -----------------------------------------------------------------------

TEST_CASE("damage: full 7x7 effectiveness table matches Magewar") {
    const ElementTable t = loadReal();
    int strong = 0, weak = 0;
    for (E a : kAllElements)
        for (E d : kAllElements) {
            CAPTURE(elementName(a));
            CAPTURE(elementName(d));
            const float got = t.effectiveness(a, d);
            CHECK(got == magewarEffectiveness(a, d));
            strong += got > 1.0f;
            weak += got < 1.0f;
        }
    CHECK(strong == 6);   // the 4-cycle + Light/Dark both ways
    CHECK(weak == 4);     // the 4-cycle backwards; Light/Dark are never weak
    // Spot checks in the plan's words: Fire > Earth > Air > Water > Fire.
    CHECK(t.effectiveness(E::Fire, E::Earth) == 1.5f);
    CHECK(t.effectiveness(E::Earth, E::Air) == 1.5f);
    CHECK(t.effectiveness(E::Air, E::Water) == 1.5f);
    CHECK(t.effectiveness(E::Water, E::Fire) == 1.5f);
    CHECK(t.effectiveness(E::Fire, E::Water) == 0.5f);
    CHECK(t.effectiveness(E::Light, E::Dark) == 1.5f);
    CHECK(t.effectiveness(E::Dark, E::Light) == 1.5f);
    CHECK(t.effectiveness(E::Fire, E::Light) == 1.0f);
}

TEST_CASE("damage: same element and arcane are always x1.0") {
    const ElementTable t = loadReal();
    for (E e : kAllElements) {
        CAPTURE(elementName(e));
        CHECK(t.effectiveness(e, e) == 1.0f);
        CHECK(t.effectiveness(E::Arcane, e) == 1.0f);
        CHECK(t.effectiveness(e, E::Arcane) == 1.0f);
    }
    // The default table (no data loaded) is neutral everywhere.
    const ElementTable neutral;
    for (E a : kAllElements)
        for (E d : kAllElements) CHECK(neutral.effectiveness(a, d) == 1.0f);
}

TEST_CASE("damage: elements.toml names and colours are Magewar's") {
    const ElementTable t = loadReal();
    struct Want { E e; const char* id; const char* name; glm::vec3 color; };
    const Want want[] = {
        {E::Arcane, "arcane", "Arcane", {0.7f, 0.7f, 0.7f}}, {E::Fire, "fire", "Fire", {1.0f, 0.3f, 0.1f}},
        {E::Water, "water", "Water", {0.1f, 0.4f, 1.0f}},    {E::Earth, "earth", "Earth", {0.5f, 0.35f, 0.1f}},
        {E::Air, "air", "Air", {0.8f, 0.95f, 1.0f}},         {E::Light, "light", "Light", {1.0f, 0.95f, 0.7f}},
        {E::Dark, "dark", "Dark", {0.3f, 0.0f, 0.5f}},
    };
    for (const Want& w : want) {
        CAPTURE(w.id);
        CHECK(std::string(elementName(w.e)) == w.id);
        CHECK(parseElement(w.id) == w.e);
        CHECK(t.name(w.e) == w.name);
        CHECK(t.color(w.e) == w.color);
    }
    CHECK(!parseElement("wind"));
    CHECK(!parseElement("none"));
    CHECK((t.strong == 1.5f && t.weak == 0.5f));
}

constexpr const char* kElementsOk = R"([effectiveness]
strong = 1.5
weak = 0.5
[[element]]
id = "arcane"
name = "Arcane"
color = [0.7, 0.7, 0.7]
strong_against = []
weak_against = []
[[element]]
id = "fire"
name = "Fire"
color = [1, 0.3, 0.1]
strong_against = ["earth"]
weak_against = ["water"]
[[element]]
id = "water"
name = "Water"
color = [0.1, 0.4, 1]
strong_against = ["fire"]
weak_against = []
[[element]]
id = "earth"
name = "Earth"
color = [0.5, 0.35, 0.1]
strong_against = []
weak_against = []
[[element]]
id = "air"
name = "Air"
color = [0.8, 0.95, 1]
strong_against = []
weak_against = []
[[element]]
id = "light"
name = "Light"
color = [1, 0.95, 0.7]
strong_against = []
weak_against = []
[[element]]
id = "dark"
name = "Dark"
color = [0.3, 0, 0.5]
strong_against = []
weak_against = []
)";

std::string withLine(const std::string& from, const std::string& to) {
    std::string s = kElementsOk;
    const size_t at = s.find(from);
    REQUIRE(at != std::string::npos);
    return s.replace(at, from.size(), to);
}

TEST_CASE("damage: bad elements files are rejected with file:line") {
    ElementTable t;
    CHECK(parseElements(kElementsOk, "e.toml", t).empty());
    CHECK(t.effectiveness(E::Fire, E::Earth) == 1.5f);
    CHECK(t.effectiveness(E::Earth, E::Air) == 1.0f);   // chart is data: only what's listed
    struct Bad { std::string text; const char* expect; };
    const Bad bad[] = {
        {withLine("weak = 0.5", "weak = 0.5\nmid = 1"), "e.toml:4: [effectiveness]: unknown key 'mid'"},
        {withLine("strong = 1.5", "strong = 0.9"), "e.toml:2: [effectiveness] strong must be in"},
        {withLine("strong = 1.5", "strong = 1.0"), "e.toml:2: [effectiveness] strong must be > 1"},
        {withLine("weak = 0.5", "weak = 1.0"), "e.toml:3: [effectiveness] weak must be < 1"},
        {withLine("id = \"fire\"", "id = \"plasma\""), "e.toml:11: element #2: unknown element 'plasma'"},
        {withLine("id = \"fire\"", "id = \"arcane\""), "duplicate element 'arcane'"},
        {withLine("strong_against = [\"earth\"]", "strong_against = [\"wood\"]"),
         "e.toml:14: element 'fire': unknown element 'wood' in strong_against"},
        {withLine("strong_against = [\"earth\"]", "strong_against = [\"fire\"]"), "e.toml:14: element 'fire': strong_against can't list itself"},
        {withLine("strong_against = [\"earth\"]", "strong_against = [\"arcane\"]"), "element 'fire': strong_against can't list arcane"},
        {withLine("strong_against = [\"earth\"]", "strong_against = [\"water\"]"),
         "element 'fire': 'water' is in both strong_against and weak_against"},
        {withLine("strong_against = [\"earth\"]", "strong_against = [\"earth\", \"earth\"]"), "'earth' listed twice in strong_against"},
        {withLine("strong_against = [\"earth\"]", "strong_against = \"earth\""), "e.toml:14: element 'fire' strong_against must be an array"},
        {withLine("strong_against = [\"earth\"]", "strong_against = [3]"), "strong_against entries must be element ids"},
        {withLine("strong_against = []\nweak_against = []\n[[element]]\nid = \"fire\"",
                  "strong_against = [\"fire\"]\nweak_against = []\n[[element]]\nid = \"fire\""),
         "e.toml:8: element 'arcane': arcane is neutral"},
        {withLine("color = [1, 0.3, 0.1]", "color = [2, 0.3, 0.1]"), "e.toml:13: element 'fire' color"},
        {withLine("name = \"Fire\"\n", ""), "element 'fire' name must be a string"},
        {withLine("color = [0.3, 0, 0.5]\nstrong_against = []\nweak_against = []\n",
                  "color = [0.3, 0, 0.5]\nstrong_against = []\nweak_against = []\nglow = 1\n"),
         "unknown key 'glow'"},
        {std::string(kElementsOk).substr(0, std::string(kElementsOk).find("[[element]]\nid = \"dark\"")),
         "missing [[element]] 'dark'"},
        {"[effectiveness]\nstrong = 1.5\nweak = 0.5\n", "need at least one [[element]]"},
        {"[[element]]\nid = \"fire\"\n", "[effectiveness]"},
        {withLine("weak = 0.5", "weak = = 0.5"), "e.toml:3: TOML: "},
    };
    for (const Bad& b : bad) {
        const std::string err = parseElements(b.text, "e.toml", t);
        INFO("expected '", b.expect, "', got '", err, "'");
        CHECK(contains(err, b.expect));
        CHECK(t.effectiveness(E::Fire, E::Earth) == 1.0f);   // output reset on failure
    }
    CHECK(contains(loadElements("/no/such/elements.toml", t), "cannot open elements file"));
}

// --- Damage formula -----------------------------------------------------------------

TEST_CASE("damage: rarity multipliers x1.0 ... x3.0 (Magewar item_rarity.gd)") {
    const float want[kRarityCount] = {1.0f, 1.25f, 1.5f, 2.0f, 2.75f, 3.0f};
    for (std::size_t i = 0; i < kRarityCount; ++i) {
        const Rarity r = Rarity(i);
        CAPTURE(rarityName(r));
        CHECK(rarityMultiplier(r) == want[i]);
        WieldableDef d;
        d.damage = 10.0f;
        d.baseRarity = r;
        CHECK(WieldableInstance(d).damage() == doctest::Approx(10.0f * want[i]));
        CHECK(wieldableDamage(10.0f, rarityMultiplier(r)) == doctest::Approx(10.0f * want[i]));
    }
    CHECK(rarityMultiplier(Rarity::Basic) == 1.0f);
    CHECK(rarityMultiplier(Rarity::Unique) == 3.0f);
}

TEST_CASE("damage: part damage bonuses add after the rarity scaling") {
    // Magewar get_final_damage: wieldable_damage x rarity + head + exterior + interior + handle + charm.
    const std::vector<float> bonuses = {2.0f, 1.5f, 0.5f, 1.0f, 3.0f};
    CHECK(wieldableDamage(14.0f, 1.25f, bonuses) == doctest::Approx(14.0f * 1.25f + 8.0f));
    CHECK(wieldableDamage(14.0f, 1.25f, std::vector<float>{}) == doctest::Approx(17.5f));
    CHECK(wieldableDamage(10.0f, 3.0f, 8.0f) == doctest::Approx(38.0f));   // bonus not x3

    WieldableDef d;
    d.damage = 14.0f;
    d.baseRarity = Rarity::Uncommon;
    WieldableInstance inst(d);
    CHECK(inst.damage() == doctest::Approx(17.5f));
    const PartType types[] = {PartType::Head, PartType::Exterior, PartType::Interior, PartType::Handle, PartType::Charm};
    float expect = 17.5f;
    for (std::size_t i = 0; i < 5; ++i) {   // every part type's damage_bonus counts
        inst.parts.push_back({"p" + std::to_string(i), types[i], 0.0f, bonuses[i]});
        expect += bonuses[i];
        CHECK(inst.damage() == doctest::Approx(expect));
    }
    CHECK(inst.damage() == doctest::Approx(25.5f));
}

TEST_CASE("damage: resistance is capped at 60 %") {
    const ElementTable t = loadReal();
    CHECK(kResistCap == 0.6f);
    CHECK(clampResist(0.25f) == 0.25f);
    CHECK(clampResist(0.6f) == 0.6f);
    CHECK(clampResist(0.8f) == 0.6f);   // over the cap (Magewar would allow 0.8)
    CHECK(clampResist(5.0f) == 0.6f);
    CHECK(clampResist(-0.3f) == 0.0f);  // negative resist never amplifies
    DamageTarget target;
    target.resist[std::size_t(E::Fire)] = 0.25f;
    DamageResult r = resolveHit(100.0f, E::Fire, target, t);
    CHECK(r.resist == 0.25f);
    CHECK(r.amount == doctest::Approx(75.0f));
    target.resist[std::size_t(E::Fire)] = 0.9f;
    r = resolveHit(100.0f, E::Fire, target, t);
    CHECK(r.resist == 0.6f);
    CHECK(r.amount == doctest::Approx(40.0f));
    // Resistance is per incoming element: fire resist doesn't stop water.
    r = resolveHit(100.0f, E::Water, target, t);
    CHECK(r.resist == 0.0f);
    CHECK(r.amount == doctest::Approx(100.0f));
}

TEST_CASE("damage: a weak-point hit is a x2 crit") {
    const ElementTable t = loadReal();
    CHECK(kWeakPointMultiplier == 2.0f);
    DamageTarget body, seam;
    seam.weakPoint = true;
    const DamageResult a = resolveHit(12.0f, E::Arcane, body, t), b = resolveHit(12.0f, E::Arcane, seam, t);
    CHECK(a.crit == 1.0f);
    CHECK(b.crit == 2.0f);
    CHECK(a.amount == doctest::Approx(12.0f));
    CHECK(b.amount == doctest::Approx(24.0f));
}

TEST_CASE("damage: effectiveness applies per hit against the target's affinity") {
    const ElementTable t = loadReal();
    DamageTarget earth;
    earth.affinity = E::Earth;
    const DamageResult strong = resolveHit(10.0f, E::Fire, earth, t);
    CHECK(strong.effectiveness == 1.5f);
    CHECK(strong.strong());
    CHECK(!strong.weak());
    CHECK(strong.amount == doctest::Approx(15.0f));
    const DamageResult weak = resolveHit(10.0f, E::Air, earth, t);
    CHECK(weak.weak());
    CHECK(weak.amount == doctest::Approx(5.0f));
    const DamageResult neutral = resolveHit(10.0f, E::Earth, earth, t);
    CHECK((!neutral.strong() && !neutral.weak()));
    CHECK(neutral.amount == doctest::Approx(10.0f));
    CHECK(resolveHit(-5.0f, E::Fire, earth, t).amount == 0.0f);   // negative damage never heals
}

TEST_CASE("damage: worked example through every factor") {
    // Apprentice Fire Staff (basic x1.0, base 10) + a Head with damage_bonus 2 = 12 per bolt,
    // into an Earth-affinity target (x1.5 strong) with 30 % fire resist, on its weak point (x2).
    const ElementTable t = loadReal();
    WieldableDef staff;
    staff.damage = 10.0f;
    staff.baseRarity = Rarity::Basic;
    staff.element = E::Fire;
    WieldableInstance inst(staff);
    inst.parts.push_back({"ember_head", PartType::Head, 0.0f, 2.0f});
    CHECK(inst.damage() == doctest::Approx(12.0f));
    DamageTarget heap;
    heap.affinity = E::Earth;
    heap.resist[std::size_t(E::Fire)] = 0.3f;
    heap.weakPoint = true;
    const DamageResult r = resolveHit(inst.damage(), inst.element(), heap, t);
    CHECK(r.amount == doctest::Approx(12.0f * 1.5f * 0.7f * 2.0f));   // 25.2
    CHECK(r.amount == doctest::Approx(25.2f));
    // Same hit, resist over the cap and off the seam: 12 x 1.5 x 0.4 = 7.2.
    heap.resist[std::size_t(E::Fire)] = 0.75f;
    heap.weakPoint = false;
    CHECK(resolveHit(inst.damage(), inst.element(), heap, t).amount == doctest::Approx(7.2f));
}

TEST_CASE("damage: the real wieldables' final damage (no parts)") {
    WieldableTable w;
    const std::string err = loadWieldables(std::string(COE_DATA_DIR) + "/magic/wieldables.toml", w);
    INFO(err);
    REQUIRE(err.empty());
    struct Want { const char* id; float dmg; };
    const Want want[] = {{"apprentice_fire_staff", 10.0f}, {"earthward_battlestaff", 17.5f},
                         {"novice_arcane_wand", 7.0f}, {"swift_wind_wand", 7.5f}};
    for (const Want& x : want) {
        CAPTURE(x.id);
        const WieldableDef* d = w.find(x.id);
        REQUIRE(d != nullptr);
        CHECK(WieldableInstance(*d).damage() == doctest::Approx(x.dmg));
    }
}

} // namespace
