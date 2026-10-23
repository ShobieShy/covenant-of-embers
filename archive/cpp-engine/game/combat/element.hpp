// SPDX-License-Identifier: Apache-2.0
// Magewar elements (BUILD_PLAN step 20, PLAN §30.4): the seven spell elements, their
// display names and colours, and the effectiveness chart, loaded from
// data/magic/elements.toml (moved here from game/magic/wieldable.* in step 20).
//
// Follows Magewar's MagicElement (magewar/scripts/magic/magic_element.gd, read-only
// reference; the weapon system follows Magewar directly, approved 2026-10-22):
//   * Element NONE is "arcane" here (Magewar's display name for NONE is "Arcane");
//   * get_effectiveness(attacker, defender): same element or either side NONE = x1.0;
//     the cycle Fire > Earth > Air > Water > Fire gives x1.5 strong / x0.5 weak;
//     Light and Dark are x1.5 against each other (neither is weak); everything else x1.0;
//   * ELEMENT_COLORS (Godot Color components, used as 0..1 RGB tints).
// The chart is data (strong_against / weak_against lists per element plus the strong
// and weak multipliers) so the step 32 balance patches can tune it; the same/Arcane
// x1.0 rule is code, as in Magewar, and the loader refuses entries that would break it.
#pragma once
#include <glm/glm.hpp>

#include <array>
#include <cstddef>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace coe::game {

// Magewar MagicElement.Element order (NONE first).
enum class Element { Arcane, Fire, Water, Earth, Air, Light, Dark };
inline constexpr std::size_t kElementCount = 7;
inline constexpr std::array<Element, kElementCount> kAllElements = {
    Element::Arcane, Element::Fire, Element::Water, Element::Earth, Element::Air, Element::Light, Element::Dark};

const char* elementName(Element e);                        // data id: "arcane", "fire", ...
std::optional<Element> parseElement(std::string_view s);   // inverse of elementName

struct ElementInfo {
    std::string name;                  // display name ("Arcane", "Fire", ...)
    glm::vec3 color{1.0f};             // tracer / damage-number / UI tint, components 0..1
};

struct ElementTable {
    // Default-constructed: neutral chart (every pair x1.0), id-as-name, white. Load
    // data/magic/elements.toml for Magewar's values.
    ElementTable();

    float strong = 1.5f;               // multiplier for a strong_against pair
    float weak = 0.5f;                 // multiplier for a weak_against pair
    std::array<ElementInfo, kElementCount> info;
    // chart[attacker][defender]: +1 strong, -1 weak, 0 neutral.
    std::array<std::array<int, kElementCount>, kElementCount> chart{};

    const std::string& name(Element e) const { return info[std::size_t(e)].name; }
    glm::vec3 color(Element e) const { return info[std::size_t(e)].color; }
    // Magewar get_effectiveness: 1.0 for same / Arcane on either side, else strong/weak/1.0.
    float effectiveness(Element attacker, Element defender) const;
};

// Parses data/magic/elements.toml-style text: an [effectiveness] table {strong, weak}
// and exactly one [[element]] per Element with keys id, name, color, strong_against,
// weak_against (all required). Rejected: unknown keys/ids, missing or duplicate
// elements, strong <= 1 or weak outside [0, 1), colour components outside [0, 1], an
// element listing itself or arcane, arcane listing anything, a defender listed as both
// strong and weak. Returns "" on success, else "<source>:<line>: message".
std::string parseElements(std::string_view text, std::string_view sourceName, ElementTable& out);
std::string loadElements(const std::filesystem::path& path, ElementTable& out);

} // namespace coe::game
