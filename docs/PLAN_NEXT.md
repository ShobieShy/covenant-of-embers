# Version roadmap

Approved by ShobieShy on 5 Nov 2026.

Story outlines for Acts I–V are in [LABYRINTH_ACTS_STORY.md](LABYRINTH_ACTS_STORY.md). The Core is not outlined there. Approved Act II design notes stay in [ACT2_STORY.md](ACT2_STORY.md) and [PLAN_0.7.0_ACT2.md](PLAN_0.7.0_ACT2.md). The 11 Nov 2026 Act IV / post-game / DLC notes are in [design/BRAINSTORM_2026-11-11_ACT4_POSTGAME_DLC.md](design/BRAINSTORM_2026-11-11_ACT4_POSTGAME_DLC.md). Those notes do not replace the outlines on this page. The implementation plan for accessibility through 0.9.0 is [PLAN_IMPLEMENTATION_0.8.5-0.9.md](PLAN_IMPLEMENTATION_0.8.5-0.9.md). It is a plan, not a build.

0.6.0, the trust pass, already shipped. This file no longer plans that pass. 0.7.0 is Act II, The Blightcoil, and that act is on master. This roadmap does not bump a version or cut a release.

## Version scheme

ShobieShy locked this on 5 Nov 2026. The same rule is in [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md).

- **x.x.y** (patch): bugfixes, or a large addition that is not a new act and not a major feature upgrade.
- **x.y.0** (minor): major polish and finishing on a new act, or a big feature upgrade. A new act ships as a minor. Act III is 0.8.0, not a patch.
- The Breach Labyrinth campaign and all polish stay on **0.x** minors (0.8.0, 0.9.0, 0.10.0, and the 0.x minors after those).
- **1.0 is not a content milestone on this table.** It is a release cut, and only when ShobieShy explicitly tells Luna to make it.

## Versions

| Version | Content |
|---|---|
| 0.7.0 (shipping) | Act II, The Blightcoil |
| 0.8.0 | Act III — The Slagworks. A minor, not a patch. Plan: [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md). |
| 0.9.0 | Act IV — The Sunken Ruins |
| 0.10.0 | Act V — The Inverted Spire |
| Later 0.x | The Core, when ShobieShy opens it. Joe, then the Demon Lord, who escapes (main-campaign end, per the 31 Oct 2026 scope). Not 1.0. |
| Later 0.x | After that clear, the endless run **The Forgotten Abyss**. The name is settled. The mode stays deferred. Boundary: [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md) under Post-Core. Not 1.0. |

## Borderlands feel

Approved by ShobieShy as patches on top of the campaign, not as new acts and not as a version-string bump. Multiclassing stays the element skill trees. There are no classes. Vehicles stay out: the fight is the labyrinth.

0.8.3 is the ranged auto-pickup, crouch-jump, and enemy-AI work, on its own branch. These patches start at 0.8.4 so they do not edit that AI or the loot magnet.

| Version | Content |
|---|---|
| 0.8.4 | Second Wind, including solo (a kill while downed revives you; a co-op teammate can still revive you). A HUD compare card for the world item under the crosshair. Four wieldable carry slots (keys 3 and 4 draw the two new ones). Consecrations can roll on ordinary Rare+ drops, and the pool is larger. |
| 0.8.5 | Named uniques and legendaries with a special effect, flavor text, and a boss or rare-spawn drop you can farm. Named rare spawns. Elites that read as elites. Accessibility (ASAP, planned, not started): see below. |
| 0.8.6 | An action skill: one cooldown ability tied to the element spec you have spent, using verbs the game already has (summon, convert, stagger, chain). |
| 0.8.7 | Lootable shields (capacity, delay, an effect), a throwable or flask slot, a relic or amulet slot, and more wieldable bases and parts. |
| 0.8.8 | Vigil wired as a playable post-clear difficulty (UI, save, the run itself). Hub toys: a Breach-key chest, a vending cadence, a slot machine. A bounty board, a mantle, and combat barks. |

### Accessibility (ASAP, planned, not started)

Under 0.8.5. Added to issue #38 on 11 Nov 2026 by ShobieShy, priority ASAP. Planned only. Implementation waits for his go. These are settings-menu options, saved to the settings file, not the save game:

- Colorblind modes: protanopia, deuteranopia, and tritanopia filters, plus shape and icon cues so rarity, elements, and enemy or elite markers never rely on color alone.
- Subtitle and text options: subtitle size (small, medium, large, extra large), background opacity, speaker names, and a global UI text scale.
- Screen shake and camera bob toggles or sliders, and a flash and strobe reduction toggle.
- Separate volume sliders (master, music, SFX, voice) where any are missing.
- Full key and button rebinding, plus toggle versus hold for crouch, sprint, and aim.
- Crosshair size and color options.
- A high-contrast outline option for enemies and loot.

### Covenant Escalation (0.8.5 and beyond)

Covenant Escalation is the one post-game difficulty dial. It replaces the separate names Chaos mode and Mayhem tiers. Inspired by Tiny Tina's Wonderlands Chaos mode. Purely mechanical: same story beats, same dialogue, harder enemies, better loot. No narrative changes. Decided in the Act IV / post-game brainstorm, 2026-11-11.

### Endgame loop (2026-11-11)

After beating a labyrinth, you can replay the same labyrinth over and over. Once you beat it, its final level is no longer the final level; there is no final level. You keep descending with increasing difficulty, loot drops, and rewards until you can't go on. This is the endgame loop. It applies to the main Breach labyrinth and to each DLC labyrinth after its story is cleared. Story acts stay handmade. Post-clear floors are randomly generated with escalating stats (the endless-after-clear rule in [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md)). Covenant Escalation stays purely mechanical, same story.

The mode is called "the Abyss" while you are progressing through it (the finite version), and once you beat it, it becomes "Endless Descent" (the infinite post-clear version). Covenant Escalation is the dial that turns with depth in Endless Descent.

Gear earned going deep in Endless Descent, under Covenant Escalation, can appear as super rare drops in normal base-story labyrinth runs. The exact drop rate is unspecified for now, to be tuned later. It should be rare enough to be a genuine surprise and not break story balance. The deeper the Covenant Escalation tier the item came from, the crazier it is and the rarer it is as a base-game drop. Whether those drops are level-scaled down for story runs, and whether co-op shares the roll, is open.

In code the dial is still `scripts/loot/vigil.gd` (`Vigil`, tiers 1–10, unused as a playable run) and `scripts/labyrinth/labyrinth_state.gd` `remix()` (re-roll a cleared floor). The class is not renamed. Whether the player can also set the dial by hand, besides it turning with depth, is open. Whether "the Abyss" / "Endless Descent" clash with the name The Forgotten Abyss below, and whether "the Abyss" means each labyrinth's descent generally, is also open. Nothing here renames The Forgotten Abyss.

The Forgotten Abyss is not in 0.8.x. It stays the endless run after Act V and the Core, below.

## Defaults

- One act per minor (`x.y.0`). A patch (`x.x.y`) is for bugfixes or a large addition that is not a new act.
- Acts III–V are 5 floors, with the boss on floor 5, a waystone home, and the hub Breach gate unlocking the next descent. Act II stays the one cavern already built.
- Empty-shell hooks run in order: cocoon, slag cast, coral sarcophagus, lit path.
- Music stays on placeholders until it is composed.
- Act I outline polish folds into 0.8.0 prep, or an optional 0.7.1 patch.
- The Core stays closed until ShobieShy opens it. It ships as a later 0.x minor. 1.0 waits on his explicit release cut.

## After the Core

Not 0.8.0, not the 0.8.4–0.8.8 Borderlands-feel patches, and not 1.0. When the Core is cleared, the Breach Labyrinth becomes an endless run named **The Forgotten Abyss**, and each future DLC labyrinth does the same after its own story. The name is settled. The mode stays deferred. Both the Core and that run are later 0.x content, numbered when ShobieShy opens them. The boundary is in [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md) under Post-Core. This roadmap does not build that mode, and it does not cut 1.0.

## Out of scope

DLC towns, new music, drawn maps, mid-session join, and Core design.
