// SPDX-License-Identifier: Apache-2.0
#include "game/combat/damage.hpp"

#include <algorithm>

namespace coe::game {

float wieldableDamage(float baseDamage, float rarityMultiplier, float partDamageBonusSum) {
    return baseDamage * rarityMultiplier + partDamageBonusSum;
}

float wieldableDamage(float baseDamage, float rarityMultiplier, std::span<const float> partDamageBonuses) {
    float sum = 0.0f;
    for (float b : partDamageBonuses) sum += b;
    return wieldableDamage(baseDamage, rarityMultiplier, sum);
}

float clampResist(float r) { return std::clamp(r, 0.0f, kResistCap); }

DamageResult resolveHit(float damage, Element element, const DamageTarget& target, const ElementTable& elements) {
    DamageResult r;
    r.effectiveness = elements.effectiveness(element, target.affinity);
    r.resist = clampResist(target.resist[std::size_t(element)]);
    r.crit = target.weakPoint ? kWeakPointMultiplier : 1.0f;
    r.amount = std::max(0.0f, damage) * r.effectiveness * (1.0f - r.resist) * r.crit;
    return r;
}

} // namespace coe::game
