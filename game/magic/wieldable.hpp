// SPDX-License-Identifier: Apache-2.0
// Magewar weapon model (BUILD_PLAN step 17, PLAN §30.1): staffs and wands.
//
// Follows Magewar's StaffWieldableItem (magewar/scripts/items/staff_wieldable_item.gd,
// read-only reference; design approved for direct use 2026-10-22):
//   * a WieldableDef is a *base* staff or wand and is the spell: type (Staff | Wand),
//     base rarity, primary element, base damage (wieldable_damage), mana cost per cast,
//     fire cooldown, projectile speed and range (wieldable_range);
//   * a WieldableInstance is a def + the parts attached at a Magic Assembly Station.
//     The part list is empty until step 28 (assembly rules), so the final stats below
//     are the def's: damage = base x RarityMult(base rarity) (+ part bonuses, step 28),
//     cooldown = base (x Exterior x Charm, step 28) clamped to >= 0.1 s, element =
//     Head element if set (step 28) else the def's.
// Bases are data (data/magic/wieldables.toml, loadWieldables()), not code.
//
// Element and Rarity tables live here until steps 20 (game/combat/element.*, colours in
// data/magic/elements.toml) and 26 (data/loot/rarities.toml) make them data; the values
// are Magewar's (magic_element.gd ELEMENT_COLORS, item_rarity.gd multipliers).
#pragma once
#include <glm/glm.hpp>

#include <cstddef>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace coe::game {

enum class WieldableType { Staff, Wand };
// Magewar MagicElement.Element; NONE is shown (and written in data) as "arcane".
enum class Element { Arcane, Fire, Water, Earth, Air, Light, Dark };
inline constexpr std::size_t kElementCount = 7;
// Magewar ItemRarity.Rarity.
enum class Rarity { Basic, Uncommon, Rare, Mythic, Primordial, Unique };
inline constexpr std::size_t kRarityCount = 6;

const char* wieldableTypeName(WieldableType t);             // "staff" / "wand"
std::optional<WieldableType> parseWieldableType(std::string_view s);
const char* elementName(Element e);                         // "arcane", "fire", ...
std::optional<Element> parseElement(std::string_view s);
glm::vec3 elementColor(Element e);                          // Magewar ELEMENT_COLORS (linear 0..1)
const char* rarityName(Rarity r);                           // "basic", ...
std::optional<Rarity> parseRarity(std::string_view s);
float rarityMultiplier(Rarity r);                           // x1.0 ... x3.0

// Minimum cooldown after part modifiers (Magewar get_final_fire_rate: max(0.1, rate)).
inline constexpr float kMinCooldown = 0.1f;

struct WieldableDef {
    std::string id;                    // stable key, e.g. "apprentice_fire_staff"
    std::string name;                  // display name, e.g. "Apprentice Fire Staff"
    WieldableType type = WieldableType::Staff;
    Rarity baseRarity = Rarity::Basic;
    Element element = Element::Arcane; // primary element
    float damage = 10.0f;              // base damage per hit (before rarity / parts)
    float manaCost = 5.0f;             // per cast (step 18 spends it)
    float cooldown = 0.4f;             // seconds between casts
    float projectileSpeed = 30.0f;     // m/s
    float range = 50.0f;               // m the bolt flies before it fizzles
};

// A part attached to an instance (Head / Exterior / Interior / Handle / Charm). Empty
// placeholder until steps 26-28 give parts their rolls and assembly rules.
struct WieldablePart {
    std::string id;
};

struct WieldableInstance {
    const WieldableDef* def = nullptr;   // must outlive the instance (owned by the loaded table)
    std::vector<WieldablePart> parts;    // empty until step 28

    explicit WieldableInstance(const WieldableDef& d) : def(&d) {}
    WieldableType type() const { return def->type; }
    Element element() const { return def->element; }
    float damage() const { return def->damage * rarityMultiplier(def->baseRarity); }
    float cooldown() const { return def->cooldown < kMinCooldown ? kMinCooldown : def->cooldown; }
    float manaCost() const { return def->manaCost; }
    float projectileSpeed() const { return def->projectileSpeed; }
    float range() const { return def->range; }
};

struct WieldableTable {
    std::vector<WieldableDef> defs;    // in file order
    const WieldableDef* find(std::string_view id) const;
};

// Parses data/magic/wieldables.toml-style text: [[wieldable]] tables with exactly the
// keys id, name, type, base_rarity, element, damage, mana_cost, cooldown,
// projectile_speed, range (all required). Unknown keys/values, out-of-range numbers and
// duplicate ids are rejected. Returns "" on success, else "<source>:<line>: message".
std::string parseWieldables(std::string_view text, std::string_view sourceName, WieldableTable& out);
std::string loadWieldables(const std::filesystem::path& path, WieldableTable& out);

} // namespace coe::game
