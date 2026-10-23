// SPDX-License-Identifier: Apache-2.0
// Damage formula (BUILD_PLAN step 20, PLAN §30.1/§30.4):
//
//   wieldable damage = base x RarityMult(base rarity) + sum of part damage_bonus
//   hit damage       = wieldable damage x ElementEffectiveness(spell, target affinity)
//                      x (1 - resist[spell element], clamped to 0..60 %)
//                      x crit (weak point x2)
//
// The first line is Magewar's StaffWieldableItem.get_final_damage (staff_wieldable_item.gd,
// followed directly); the effectiveness is MagicElement.get_effectiveness, applied to the
// bolt's damage on impact like Magewar's spell_projectile.gd / enemy_base.gd. Resistance is
// per element like Magewar's magewar_player.get_elemental_resistance (sum of equipment
// elemental_resistance whose affinity matches the hit's element) but capped at PLAN's
// 60 % (Magewar caps at 90 %; see kResistCap). Weak points (Heap seam, step 24) are plan
// design: Magewar has no crits.
// ProjectileHit carries the wieldable damage + element; enemies (step 22) and the player
// (step 24) call resolveHit() with their own DamageTarget.
#pragma once
#include "game/combat/element.hpp"

#include <array>
#include <span>

namespace coe::game {

// PLAN §30.4 hard cap on any one element's resistance. Deliberate deviation from Magewar's
// clamp(resistance, 0, 0.9), kept from PLAN §30.4 (revisit with gear resist in step 30).
inline constexpr float kResistCap = 0.6f;
// PLAN §30.1 critical hit: a hit on a weak point does double damage.
inline constexpr float kWeakPointMultiplier = 2.0f;

// Magewar get_final_damage: base x rarity multiplier + the parts' damage bonuses (flat,
// added after the rarity scaling, so part bonuses aren't multiplied by the base rarity).
float wieldableDamage(float baseDamage, float rarityMultiplier, std::span<const float> partDamageBonuses);
float wieldableDamage(float baseDamage, float rarityMultiplier, float partDamageBonusSum = 0.0f);

// Resistance per incoming element as a 0..1 fraction (index = Element), uncapped as
// summed from gear; resolveHit() clamps it to [0, kResistCap].
using Resistances = std::array<float, kElementCount>;
float clampResist(float r);

struct DamageTarget {
    Element affinity = Element::Arcane;   // defender element for the effectiveness chart
    Resistances resist{};                 // per incoming element
    bool weakPoint = false;               // the hit struck a weak-point hitbox
};

struct DamageResult {
    float amount = 0.0f;          // final damage dealt
    float effectiveness = 1.0f;   // 0.5 / 1.0 / 1.5 (from the chart)
    float resist = 0.0f;          // applied (clamped) resistance
    float crit = 1.0f;            // kWeakPointMultiplier on a weak point, else 1
    bool strong() const { return effectiveness > 1.0f; }   // Magewar "Super Effective!"
    bool weak() const { return effectiveness < 1.0f; }     // Magewar "Not Very Effective..."
};

// One hit of `damage` (wieldable damage, >= 0) of `element` against `target`.
DamageResult resolveHit(float damage, Element element, const DamageTarget& target, const ElementTable& elements);

} // namespace coe::game
