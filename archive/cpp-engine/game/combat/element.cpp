// SPDX-License-Identifier: Apache-2.0
#include "game/combat/element.hpp"

#include "game/data/toml_read.hpp"

namespace coe::game {
namespace {
constexpr std::array<const char*, kElementCount> kElementIds = {"arcane", "fire", "water", "earth", "air", "light", "dark"};

using data::Ctx;

std::string idChoices() {
    std::string out;
    for (const char* n : kElementIds) out += std::string(out.empty() ? "" : ", ") + n;
    return out;
}

// strong_against / weak_against: an array of element ids (may be empty).
bool readElementList(Ctx& c, const toml::table& t, const char* key, const std::string& w, Element self,
                     int mark, std::array<int, kElementCount>& row) {
    const toml::node* n = t.get(key);
    const toml::array* a = n ? n->as_array() : nullptr;
    if (!a) return c.fail(n ? n : &t, w + " " + key + " must be an array of element ids");
    for (const toml::node& item : *a) {
        if (!item.is_string()) return c.fail(&item, w + " " + key + " entries must be element ids");
        const std::string s = item.as_string()->get();
        const auto e = parseElement(s);
        if (!e) return c.fail(&item, w + ": unknown element '" + s + "' in " + key + " (expected " + idChoices() + ")");
        if (self == Element::Arcane)
            return c.fail(&item, w + ": arcane is neutral (Magewar NONE), its " + key + " must be empty");
        if (*e == Element::Arcane) return c.fail(&item, w + ": " + key + " can't list arcane (always x1.0)");
        if (*e == self) return c.fail(&item, w + ": " + key + " can't list itself (same element is x1.0)");
        int& cell = row[std::size_t(*e)];
        if (cell == mark) return c.fail(&item, w + ": '" + s + "' listed twice in " + key);
        if (cell != 0) return c.fail(&item, w + ": '" + s + "' is in both strong_against and weak_against");
        cell = mark;
    }
    return true;
}
} // namespace

const char* elementName(Element e) { return kElementIds[std::size_t(e)]; }

std::optional<Element> parseElement(std::string_view s) {
    for (std::size_t i = 0; i < kElementCount; ++i)
        if (s == kElementIds[i]) return Element(i);
    return std::nullopt;
}

ElementTable::ElementTable() {
    for (std::size_t i = 0; i < kElementCount; ++i) info[i].name = kElementIds[i];
}

float ElementTable::effectiveness(Element attacker, Element defender) const {
    if (attacker == defender || attacker == Element::Arcane || defender == Element::Arcane) return 1.0f;
    switch (chart[std::size_t(attacker)][std::size_t(defender)]) {
        case 1: return strong;
        case -1: return weak;
        default: return 1.0f;
    }
}

std::string parseElements(std::string_view text, std::string_view sourceName, ElementTable& out) {
    out = {};
    ElementTable t;
    Ctx c{sourceName, {}};
    toml::table root;
    if (!data::parseToml(c, text, root)) return c.err;
    if (!data::onlyKeys(c, root, {"effectiveness", "element"}, "top level")) return c.err;
    const toml::table* eff = data::needTable(c, root, "effectiveness");
    if (!eff) return c.err;
    if (!data::onlyKeys(c, *eff, {"strong", "weak"}, "[effectiveness]") ||
        !data::readFloatIn(c, eff->get("strong"), "[effectiveness] strong", 1.0f, 10.0f, t.strong) ||
        !data::readFloatIn(c, eff->get("weak"), "[effectiveness] weak", 0.0f, 1.0f, t.weak))
        return c.err;
    if (t.strong == 1.0f) { c.fail(eff->get("strong"), "[effectiveness] strong must be > 1"); return c.err; }
    if (t.weak == 1.0f) { c.fail(eff->get("weak"), "[effectiveness] weak must be < 1"); return c.err; }

    const toml::array* list = data::needTableArray(c, root, "element");
    if (!list) return c.err;
    std::array<bool, kElementCount> seen{};
    for (std::size_t i = 0; i < list->size(); ++i) {
        const toml::table& et = *list->get(i)->as_table();
        const std::string where = "element #" + std::to_string(i + 1);
        if (!data::onlyKeys(c, et, {"id", "name", "color", "strong_against", "weak_against"}, where)) return c.err;
        std::string id;
        if (!data::readString(c, et.get("id"), where + " id", id)) return c.err;
        const auto e = parseElement(id);
        if (!e) { c.fail(et.get("id"), where + ": unknown element '" + id + "' (expected " + idChoices() + ")"); return c.err; }
        if (seen[std::size_t(*e)]) { c.fail(list->get(i), "duplicate element '" + id + "'"); return c.err; }
        seen[std::size_t(*e)] = true;
        const std::string w = "element '" + id + "'";
        ElementInfo& info = t.info[std::size_t(*e)];
        auto& row = t.chart[std::size_t(*e)];
        if (!data::readString(c, et.get("name"), w + " name", info.name) ||
            !data::readColor(c, et.get("color"), w + " color", info.color) ||
            !readElementList(c, et, "strong_against", w, *e, 1, row) ||
            !readElementList(c, et, "weak_against", w, *e, -1, row))
            return c.err;
    }
    for (std::size_t i = 0; i < kElementCount; ++i)
        if (!seen[i]) { c.fail(&root, std::string("missing [[element]] '") + kElementIds[i] + "'"); return c.err; }
    out = std::move(t);
    return {};
}

std::string loadElements(const std::filesystem::path& path, ElementTable& out) {
    out = {};
    std::string text;
    if (std::string err = data::readTextFile(path, "elements file", text); !err.empty()) return err;
    return parseElements(text, path.filename().string(), out);
}

} // namespace coe::game
