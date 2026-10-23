// SPDX-License-Identifier: Apache-2.0
// Mana (BUILD_PLAN step 18, PLAN §30.1): the only casting resource. No magazines, no
// reloads (the Reload action is left unbound to any gameplay for now).
//
// Follows Magewar's ManaAttribute (scripts/player/mana_attribute.gd +
// scenes/player/magewar_player_spawnable.tscn, read-only reference) directly:
//   * value_max 100, value_start 100;
//   * spend_mana(cost): refused (no change, regen delay NOT restarted) when
//     value < cost; otherwise subtract and restart the regen delay;
//   * regen (mana_regen_speed 3 + equipment_regen_bonus)/s once regen_delay 1.5 s has
//     passed since the last spend; never above the max;
//   * equipment (magewar_player.gd _apply_equipment_bonuses): mana_bonus raises the max
//     *and* the current value by the same amount (clamped), removing it lowers the max and
//     clamps; mana_regen_bonus adds to the regen rate (Novice Grimoire: +5 / +0.5);
//   * level-up (_level_up): max +5 and a full refill (step 38).
// Reinterpretation: Magewar counts the delay per rendered frame and regenerates the whole
// frame in which the timer runs out; here it runs per fixed tick and only the part of the
// tick past the delay regenerates (double time, like Breath), so the timing is exact to
// the sub-tick at 30/60/144 Hz.
#pragma once
#include <cstdint>

namespace coe::game {

struct ManaTuning {
    float max = 100.0f;          // ManaAttribute value_max (player scene)
    float regenPerSec = 3.0f;    // mana_regen_speed
    float regenDelay = 1.5f;     // regen_delay: seconds since the last cast
    bool autoRegenerate = true;  // auto_regenerate
};

class Mana {
public:
    explicit Mana(const ManaTuning& tuning = {});

    // One fixed tick of regen (if enabled and the delay has passed).
    void tick(float dt);
    // Magewar spend_mana: false (nothing changes) if value < amount; otherwise subtracts
    // and restarts the regen delay. Plugged into Caster::setManaSpender.
    bool spend(float amount);
    bool has(float amount) const { return value_ >= double(amount); }

    float value() const { return float(value_); }
    float max() const { return tuning_.max + maxBonus_; }
    float fraction() const { return max() > 0.0f ? value() / max() : 0.0f; }
    // Mana/s while regenerating: base + equipment bonus, never negative.
    float regenRate() const;
    double secondsSinceSpend() const { return sinceSpend_; }
    bool regenerating() const {
        return tuning_.autoRegenerate && sinceSpend_ >= double(tuning_.regenDelay) && value_ < double(max());
    }

    // Step 30 gear hook (Magewar equipment_regen_bonus): total bonus from all equipment.
    void setRegenBonus(float bonus) { regenBonus_ = bonus; }
    float regenBonus() const { return regenBonus_; }
    // Steps 30/38: total max bonus from gear + levels. Raising it adds the difference to
    // the current value too (Magewar equip), lowering it clamps.
    void setMaxBonus(float bonus);
    float maxBonus() const { return maxBonus_; }
    void refill() { value_ = double(max()); }   // level-up (Magewar _level_up)

    std::uint64_t spends() const { return spends_; }
    std::uint64_t refusals() const { return refusals_; }
    const ManaTuning& tuning() const { return tuning_; }

private:
    ManaTuning tuning_;
    float maxBonus_ = 0.0f, regenBonus_ = 0.0f;
    double value_;        // double: 3/s x 1/144 s steps don't drift over long sessions
    double sinceSpend_;   // seconds since the last successful spend
    std::uint64_t spends_ = 0, refusals_ = 0;
};

} // namespace coe::game
