// SPDX-License-Identifier: Apache-2.0
#include "game/magic/wieldable.hpp"

#include "game/data/toml_read.hpp"

#include <algorithm>
#include <array>

namespace coe::game {
namespace {
constexpr std::array<const char*, 2> kTypeNames = {"staff", "wand"};
constexpr std::array<const char*, kElementCount> kElementNames = {"arcane", "fire", "water", "earth", "air", "light", "dark"};
// Magewar magic_element.gd ELEMENT_COLORS (NONE/Arcane is the grey 0.7).
constexpr std::array<glm::vec3, kElementCount> kElementColors = {
    glm::vec3(0.7f, 0.7f, 0.7f), glm::vec3(1.0f, 0.3f, 0.1f), glm::vec3(0.1f, 0.4f, 1.0f), glm::vec3(0.5f, 0.35f, 0.1f),
    glm::vec3(0.8f, 0.95f, 1.0f), glm::vec3(1.0f, 0.95f, 0.7f), glm::vec3(0.3f, 0.0f, 0.5f)};
constexpr std::array<const char*, kRarityCount> kRarityNames = {"basic", "uncommon", "rare", "mythic", "primordial", "unique"};
constexpr std::array<float, kRarityCount> kRarityMult = {1.0f, 1.25f, 1.5f, 2.0f, 2.75f, 3.0f};   // item_rarity.gd

template <typename E, std::size_t N>
std::optional<E> parseName(const std::array<const char*, N>& names, std::string_view s) {
    for (std::size_t i = 0; i < N; ++i)
        if (s == names[i]) return E(i);
    return std::nullopt;
}

template <std::size_t N>
std::string choices(const std::array<const char*, N>& names) {
    std::string out;
    for (const char* n : names) out += std::string(out.empty() ? "" : ", ") + n;
    return out;
}

using data::Ctx;

template <typename E, std::size_t N>
bool readEnum(Ctx& c, const toml::table& t, const char* key, const std::string& w,
              const std::array<const char*, N>& names, E& out) {
    std::string s;
    if (!data::readString(c, t.get(key), w + " " + key, s)) return false;
    const auto v = parseName<E>(names, s);
    if (!v) return c.fail(t.get(key), w + ": unknown " + key + " '" + s + "' (expected " + choices(names) + ")");
    out = *v;
    return true;
}

bool parseDef(Ctx& c, const toml::table& t, std::size_t index, WieldableDef& d) {
    const std::string where = "wieldable #" + std::to_string(index + 1);
    if (!data::onlyKeys(c, t, {"id", "name", "type", "base_rarity", "element", "damage", "mana_cost", "cooldown",
                               "projectile_speed", "range"}, where))
        return false;
    if (!data::readString(c, t.get("id"), where + " id", d.id)) return false;
    for (char ch : d.id)
        if (!((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_'))
            return c.fail(t.get("id"), where + ": id '" + d.id + "' must be lower_snake_case [a-z0-9_]");
    const std::string w = "wieldable '" + d.id + "'";
    // Ranges: generous sanity bounds around Magewar's bases (damage 6-14, mana 2.5-6,
    // cooldown 0.18-0.55 s, speed 22-55 m/s, range 35-50 m); cooldown >= Magewar's 0.1 s floor.
    return data::readString(c, t.get("name"), w + " name", d.name) &&
           readEnum(c, t, "type", w, kTypeNames, d.type) &&
           readEnum(c, t, "base_rarity", w, kRarityNames, d.baseRarity) &&
           readEnum(c, t, "element", w, kElementNames, d.element) &&
           data::readFloatIn(c, t.get("damage"), w + " damage", 0.1f, 1000.0f, d.damage) &&
           data::readFloatIn(c, t.get("mana_cost"), w + " mana_cost", 0.0f, 100.0f, d.manaCost) &&
           data::readFloatIn(c, t.get("cooldown"), w + " cooldown", kMinCooldown, 10.0f, d.cooldown) &&
           data::readFloatIn(c, t.get("projectile_speed"), w + " projectile_speed", 1.0f, 500.0f, d.projectileSpeed) &&
           data::readFloatIn(c, t.get("range"), w + " range", 1.0f, 1000.0f, d.range);
}
} // namespace

const char* wieldableTypeName(WieldableType t) { return kTypeNames[std::size_t(t)]; }
std::optional<WieldableType> parseWieldableType(std::string_view s) { return parseName<WieldableType>(kTypeNames, s); }
const char* elementName(Element e) { return kElementNames[std::size_t(e)]; }
std::optional<Element> parseElement(std::string_view s) { return parseName<Element>(kElementNames, s); }
glm::vec3 elementColor(Element e) { return kElementColors[std::size_t(e)]; }
const char* rarityName(Rarity r) { return kRarityNames[std::size_t(r)]; }
std::optional<Rarity> parseRarity(std::string_view s) { return parseName<Rarity>(kRarityNames, s); }
float rarityMultiplier(Rarity r) { return kRarityMult[std::size_t(r)]; }

const WieldableDef* WieldableTable::find(std::string_view id) const {
    for (const WieldableDef& d : defs)
        if (d.id == id) return &d;
    return nullptr;
}

std::string parseWieldables(std::string_view text, std::string_view sourceName, WieldableTable& out) {
    out = {};
    Ctx c{sourceName, {}};
    toml::table root;
    if (!data::parseToml(c, text, root)) return c.err;
    if (!data::onlyKeys(c, root, {"wieldable"}, "top level")) return c.err;
    const toml::array* list = data::needTableArray(c, root, "wieldable");
    if (!list) return c.err;
    for (std::size_t i = 0; i < list->size(); ++i) {
        WieldableDef d;
        if (!parseDef(c, *list->get(i)->as_table(), i, d)) { out = {}; return c.err; }
        if (out.find(d.id)) { c.fail(list->get(i), "duplicate wieldable id '" + d.id + "'"); out = {}; return c.err; }
        out.defs.push_back(std::move(d));
    }
    return {};
}

std::string loadWieldables(const std::filesystem::path& path, WieldableTable& out) {
    out = {};
    std::string text;
    if (std::string err = data::readTextFile(path, "wieldables file", text); !err.empty()) return err;
    return parseWieldables(text, path.filename().string(), out);
}

float WieldableInstance::accuracy() const {
    float acc = kBaseAccuracy;
    for (const WieldablePart& p : parts)
        if (p.type == PartType::Head || p.type == PartType::Handle || p.type == PartType::Charm)
            acc += p.accuracyBonus;
    return std::clamp(acc, 0.0f, 100.0f);
}

} // namespace coe::game
