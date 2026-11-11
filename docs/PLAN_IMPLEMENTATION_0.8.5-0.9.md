# Implementation plan: accessibility through 0.9.0

Planning only. Written against master `cde6e10` (#50). No code in this change.

Build string stays `0.8.2-prealpha`. Save version stays 1. New save fields are optional and defaulted. Multiclassing stays the element skill trees. No classes. No vehicles. The Forgotten Abyss name is not changed. The Vigil class in `scripts/loot/vigil.gd` is not renamed.

Six releases, in this order. Each is one pull request branched off master after the previous one has merged. None of them is stacked.

| Order | Release | Issue | PR base |
|---|---|---|---|
| 1 | Accessibility | #38 | master after `cde6e10` |
| 2 | 0.8.6 action skill | #39 | master after 1 merges |
| 3 | 0.8.7 gear | #40 | master after 2 merges |
| 4 | 0.8.8 post-clear play | #41 | master after 3 merges |
| 5 | The Abyss, then Endless Descent | endgame notes on master | master after 4 merges |
| 6 | 0.9.0 Act IV | roadmap | master after 5 merges, and only after the Act IV call below |

## Defaults (change if you want)

Answer these in one pass. Each line is what the build will do if you do not say otherwise.

1. **Colorblind scope.** Gameplay tints and shape marks only. No full-screen filter that recolors terrain. Palettes already in `scripts/core/accessibility.gd` stay. **Default (change if you want).**
2. **Voice slider.** Add a Voice bus and a settings slider. No new voice lines. The slider is silent until voice-over exists. **Default (change if you want).**
3. **Aim toggle.** The existing `action_secondary` latch (`focus_toggle`). **Default (change if you want).**
4. **Action-skill key.** New action `action_skill`, default key Q. **Default (change if you want).**
5. **Action-skill cooldown.** 30 seconds, one constant. **Default (change if you want).**
6. **Downed.** The action skill does not fire while downed. Cast still follows Second Wind. **Default (change if you want).**
7. **Which verb.** Highest spent element wins. Ties break in element order: Arcane, Fire, Water, Earth, Air, Light, Dark. Light summons, Dark converts, Fire and Earth stagger, Air, Water, and Arcane chain. **Default (change if you want).**
8. **Dropped shield.** Replaces the numbers on `Health.shield` (capacity, delay, effect). Not a second bar. **Default (change if you want).**
9. **Flask.** One charge, separate from the health and mana potion. Refills at a rest or at the Association. **Default (change if you want).**
10. **Relic.** A small effect list in the consecration style. Not a new combat system. **Default (change if you want).**
11. **What counts as a clear for 0.8.8.** Forgemaw, the current end of the shipped campaign. Later acts raise that gate when they ship. **Default (change if you want).**
12. **Bounties.** Repeatable. They pay gold. **Default (change if you want).**
13. **Mantle.** Cosmetic only. **Default (change if you want).**
14. **Covenant Escalation control.** Endless Descent raises the tier cap with depth. In the hub you can set any tier from 0 up to that cap, not above it. **Default (change if you want).**
15. **Names versus The Forgotten Abyss.** "the Abyss" and "Endless Descent" do not replace The Forgotten Abyss. That name stays the post-Core run. **Default (change if you want).**
16. **What "the Abyss" means.** Each labyrinth's finite replay after that labyrinth's story boss, not one global mode. **Default (change if you want).**
17. **Story-run deep drops.** Level-scaled to the story floor. The effect stays. **Default (change if you want).**
18. **Co-op and that roll.** Each player rolls on their own instanced loot stream. Not one shared world drop. **Default (change if you want).**
19. **Drop rate.** One constant. No number is chosen here. Tests inject the chance. Tune the constant later. **Default (change if you want).**
20. **Act IV.** The build plan below is Breach fallout (shared map spine, faction states). **Blocked** until you choose that over The Sunken Ruins. Old Oak stays Old Oak. **Default (change if you want).**

## 1. Accessibility (#38)

**Size.** Settings, HUD, dialogue, and a few presentation hooks. No new content.

**Depends on.** Nothing. First PR.

**Acceptance.** Every option in the 0.8.5 accessibility list in `docs/PLAN_NEXT.md` is in the settings menu and in `user://keybinds.cfg`. The save game version stays 1. Colorblind mode plus a shape still tells rarity, element, elite, and named unique apart. `docs/PLAN_NEXT.md` says accessibility is done.

**Steps.**

1. Extend `scripts/core/settings.gd` and `scripts/ui/settings_ui.gd`: subtitle preset (small, medium, large, extra large), subtitle background opacity, speaker names, UI text scale, shake slider, flash reduction, voice volume, sprint toggle, crosshair size, crosshair swatch, high contrast. Old cfg keys stay defaulted. `tests/unit/test_settings.gd` currently expects 19 options; update that count.
2. Push them through `Settings.apply_to` into `scripts/core/accessibility.gd`.
3. Shape marks on rarity and elements in `scripts/ui/compare_card.gd`, loot describe text, and elite name tags in `scripts/enemies/elite_presence.gd`. Named uniques in `scripts/loot/named_uniques.gd` keep the pearlescent tint when colorblind mode is off, and a distinct palette color plus the named mark when a mode is on.
4. Dialogue in `scripts/ui/dialogue_ui.gd`: preset size, background opacity, speaker name on or off.
5. `scripts/player/camera_feel.gd`: shake scale. Reduced motion still zeros bob and shake. Flash reduction skips the white hit flash in `scripts/enemies/enemy.gd` and `scripts/player/viewmodel.gd` `flash_muzzle` without stopping the flash timer tests already assert.
6. Voice bus in `default_bus_layout.tres` and `scripts/audio/game_audio.gd`. No new clips.
7. Sprint latch beside the crouch and aim latches in `scripts/player/player.gd`.
8. Crosshair size and color, and high-contrast outlines, in `scripts/ui/hud.gd` and on elite and loot meshes.
9. Mark accessibility done in `docs/PLAN_NEXT.md`.

**Tests.** `tests/unit/test_settings.gd` for round-trip, defaults, and `apply_to`. Existing palette test stays distinct. One dialogue case for speaker name and preset size. Fast tier (`tools/run_tests.sh --fast`), then full tier plus Act II, Act III, and co-op, because settings apply on player spawn.

## 2. 0.8.6 action skill (#39)

**Size.** One player ability, one HUD widget, co-op replication of one cast.

**Depends on.** Accessibility merged, so the new action is on the rebind list. Branched off that master.

**Acceptance.** One cooldown. The verb follows points spent on an element tree. It uses summon, convert, stagger, or chain. Solo and co-op. No class select. No new story. Issue #39.

**Steps.**

1. Add action `action_skill` to the input map and `scripts/player/player_input.gd`. Default key Q.
2. In `scripts/player/player.gd`, a 30 second cooldown. Refuse it while downed.
3. Pick the verb in `scripts/player/skill_tree.gd` from `data/skills/` using the default map above.
4. Call the existing verb: `scripts/magic/light_summon.gd` for summon, dark conversion for convert, the existing stagger for stagger, the existing chain proc for chain.
5. Cooldown readout on `scripts/ui/hud.gd`.
6. Replicate the cast in the co-op combat path so the joiner sees it. The host does not roll a private result the joiner misses.

**Tests.** New unit test: highest tree wins, tie break, cooldown blocks a second press, each verb calls the existing effect, downed refuses it. Fast tier. One co-op smoke. Act II and Act III only if a verb moves enemies. Summon and convert must not add a separation shove. That shove broke the Act II climb before.

## 3. 0.8.7 gear (#40)

**Size.** Largest of the 0.8.x patches: three equip paths, drop tables, item codes. Still not a new act.

**Depends on.** 0.8.6 merged. Branched off that master.

**Acceptance.** Shields drop with capacity, delay, and an effect and replace the fixed shield numbers. Flask slot is not the potion slot. Relic slot has its own small effects. More bases and parts enter the existing roller in the current art. No vehicles. No story. Old EM1 codes still decode. Save version stays 1.

**Steps.**

1. Shield item in `scripts/player/equipment.gd` that writes capacity, delay, and effect onto `scripts/player/health.gd`. Unequip restores the old numbers.
2. Flask slot, one charge, refill on rest and at the Association. It must not call the potion quick-slot.
3. Relic slot. Effects are a short id list applied and removed with the item, same pattern as consecrations.
4. New bases and parts through `scripts/loot/equipment_roller.gd` and the part roller. Placeholder art only.
5. Drops in `scripts/loot/drop_roller.gd` on a side stream, not extra draws on the kill rng. `test_pools` replays that rng.
6. Item codes: append-only table version if new handmade ids do not fit version 2. Do not widen version 1 indexes.

**Tests.** Shield on and off. Flask does not consume a potion. Relic effect clears when removed. New code round-trips. A golden EM1 string is unchanged. Fast tier. Full tier if any kill drop changes.

## 4. 0.8.8 post-clear play (#41)

**Size.** A difficulty switch plus several small hub features. No new level geometry.

**Depends on.** 0.8.7 merged if the mantle is another equip slot. Branched off that master. Vigil's math already exists.

**Acceptance.** After Forgemaw, a UI sets the Vigil tier, the tier is saved, and `scripts/loot/vigil.gd` weights apply. Hub toys spend keys or gold that already exist: Breach-key chest, vending cadence, slot machine. A bounty board gives combat tasks in shipped levels. A mantle is visible. Enemies bark on aggro, hurt, and death. No vehicles. The Forgotten Abyss is not built.

**Steps.**

1. Wire `scripts/loot/vigil.gd` from a hub control. Save the tier as an optional field with default 0.
2. Call `scripts/labyrinth/labyrinth_state.gd` `remix()` only for a floor the player has already cleared, when they ask for a new roll. Do not remix the Act II climb on a story run.
3. Hub props in Town Square and Old Oak, using vendor gold and existing keys.
4. Bounty rows that point at existing enemy ids. Repeatable. Gold reward. No new dialogue scenes.
5. Mantle mesh on the character model. No stat.
6. Bark strings on existing enemies at aggro, hurt, and death. Presentation only. Do not edit 0.8.3 attack scripts.

**Tests.** Tier N matches the health, damage, and rarity curves in `vigil.gd`. `remix()` still returns false on an uncleared floor. Toys debit the existing currency. Fast tier. No Act II playtest change while the tier is 0.

## 5. The Abyss, then Endless Descent

**Size.** A mode flag, floor generation after the story boss, and a rare story-run drop. Not a new act.

**Depends on.** 0.8.8 merged, so Vigil is playable. Branched off that master.

**Acceptance.** After that labyrinth's story boss, you can run it again. The finite replay is called the Abyss. After you beat that replay, there is no final floor: Endless Descent, random floors, escalating stats. Covenant Escalation turns with depth there, and you can set any tier up to that cap. Same story and dialogue. Deep gear can appear in a base-story labyrinth run. Deeper source tier is crazier and rarer. The rate is one constant, unset in this plan, tuned later. The Forgotten Abyss name stays on the post-Core run.

**Steps.**

1. Per labyrinth, a cleared-story flag. The Abyss is a replay of that labyrinth. Endless Descent starts only after the Abyss is beaten.
2. Story floors stay the handmade kits. Endless Descent floors use `remix()` and `scripts/labyrinth/floor_gen.gd` with stats from `scripts/loot/vigil.gd`. Depth raises the tier cap.
3. Hub control: pick tier 0 through the cap.
4. In `scripts/labyrinth/act_loot.gd`, a side-stream roll for a deep-gear drop during a story run. Constant has no tuned value yet. Tests pass an explicit chance. Scale the item to the story floor and keep the effect.
5. Each co-op player rolls on their own instanced stream.

**Tests.** Story boss clear unlocks the Abyss. Beating the Abyss unlocks Endless Descent. `remix()` changes the floor seed. A higher tier raises the documented weights. Tier 0 leaves Act II and Act III endings where they are. A forced story-run drop does not change kill-rng order. Fast tier, then one extra-floor playtest and the full tier.

## 6. Act IV / 0.9.0

**Blocked.** Do not start until you choose Breach fallout or The Sunken Ruins. The tasks below are Breach fallout. If you choose The Sunken Ruins, this section is replaced by that outline in `docs/LABYRINTH_ACTS_STORY.md` (flooded halls, Breath as the leash, the Drowned Choir, the coral sarcophagus). Old Oak is not renamed.

**Size.** The largest release in this plan: a variant layer on the Breach, a boss, and a loot band. One pull request after the call, off master, not stacked.

**Depends on.** Release 5 merged, and the Act IV call.

**Acceptance, if Breach fallout is confirmed.** One shared map spine. Faction state changes levers, spawns, and rooms. Not separate level branches. Five floors, boss on floor 5, waystone home, version 0.9.0. No Great Oak rename. Landfill stays the tutorial. Act I stays the Goblin Warrens.

**Steps, only after the call.**

1. One Breach interior with state flags for lever, spawn, and room variants.
2. Five floors on that spine, boss on floor 5, waystone home.
3. An Act IV loot band. Empty-shell hook stays the coral sarcophagus only if you keep that outline beat. Breach fallout does not add it unless you say so.
4. Story facts from the brainstorm (Demon Lord caused the Breach, Joe as proxy, Bob, the prism, the Association head) stay out of dialogue until you ask for a writing pass.

**Tests.** A floor or variant unit test. A solo playtest down the act and home. A co-op smoke. Full tier. Landfill, Act II, and Act III still finish.

## What this plan does not build

DLC towns, new music, the Core, and The Forgotten Abyss. Those stay out of scope in `docs/PLAN_NEXT.md` until you open them.
