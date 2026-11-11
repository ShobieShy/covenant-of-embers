# Act IV / post-game / DLC brainstorm

2026-11-11. ShobieShy's story and design decisions, recorded as stated. This is not a build plan and it does not change the outlines in [LABYRINTH_ACTS_STORY.md](../LABYRINTH_ACTS_STORY.md) or [PLAN_NEXT.md](../PLAN_NEXT.md).

## Act IV

Breach fallout. Uses a shared map spine with faction states (lever / spawn / room variants), not separate branches.

## Story / characters

- The Demon Lord caused the Breach.
- Crazy Joe is a useful-idiot proxy: he recklessly summoned the player to the Mages Association, got banished by the backlash, and joined the Demon Lord.
- Bob: lazy, nonchalant roommate in the Great Oak (an abandoned tree the Association assigned). Explains the lore after the Filth. His past failed summonings were the Demon Lord blocking him.
- Prism gag: the prism is half-cracked; mid-game seal-or-crack choice; late-game payoff.
- The Association head is terrified of the Demon Lord and won't commit resources.

## Structure

- Filth/junkyard = one tutorial zone, one boss (the Filth), soft fail.
- Main game = one town. The Breach = a half-level doorway. The labyrinth = Acts 1-5.
- DLC labyrinths each get their own town with their own Mages Association (adventurer-guild chapters): shops for trade, the association for quests/training/lore.

## Post-game

- Chaos mode is purely mechanical: harder enemies, better loot, same story and dialogue, no narrative changes.
- DLC has level minimums. Chaos requires beating the main game.
- Endgame loop, 2026-11-11: After beating a labyrinth, you can replay the same labyrinth over and over. Once you beat it, its final level is no longer the final level; there is no final level. You keep descending with increasing difficulty, loot drops, and rewards until you can't go on. This is the endgame loop. It pairs with the existing Mayhem-style tier system (already written in code but unused), which can be the dial that turns as you go deeper. This applies to the main Breach labyrinth and to each DLC labyrinth after its story is cleared (consistent with the earlier note that post-clear floors are randomly generated with escalating stats, while story acts stay handmade). Chaos mode stays purely mechanical, same story.
- The mode is called "the Abyss" while you are progressing through it (the finite version), and once you beat it, it becomes "Endless Descent" (the infinite post-clear version).

The Mayhem-style tiers are `scripts/loot/vigil.gd` (`Vigil`, tiers 1–10, separate difficulty and reward curves, seeded Omens). A cleared floor can be re-rolled by `scripts/labyrinth/labyrinth_state.gd` `remix()`. Neither is the playable descent loop. The earlier random-floor note is in `docs/PLAN_0.8.0_SLAGWORKS.md` (the endless-after-clear rule, Post-Core).

## Death

Borderlands-style. Respawn at the Association, keep loot and story flags, drop gold.

## Rewards

Gear + abilities + story unlocks, randomized and level-scaled (numbers to be tweaked later).

## Accessibility

Colorblind modes, subtitle size, and the rest of that list. ASAP, in the 0.8.5 plan alongside farmable loot. Already recorded in [issue #38](https://github.com/ShobieShy/covenant-of-embers/issues/38) and in `docs/PLAN_NEXT.md` on PR #47. Not started here.

## Open question for ShobieShy

Current outlines do not call the Landfill Act I. [LABYRINTH_ACTS_STORY.md](../LABYRINTH_ACTS_STORY.md) and [PLAN_NEXT.md](../PLAN_NEXT.md) put Acts I–V in the Labyrinth: Act I the Goblin Warrens, Act II the Blightcoil, Act III the Slagworks, Act IV the Sunken Ruins, Act V the Inverted Spire. The Landfill is already the tutorial zone with the Filth. "The labyrinth = Acts 1-5" matches that numbering. Nothing here was rewritten to force a match.

Act IV does not match. Those docs call Act IV The Sunken Ruins (0.9.0). This note calls Act IV Breach fallout, on a shared map spine with faction states. Both statements are left as written.

The tree name does not match. This note says Great Oak. The shipped level, quests, and docs say Old Oak (`old_oak`, [INTRO_PLAN.md](../INTRO_PLAN.md), [LINEAR_LEVELS_PLAN.md](../LINEAR_LEVELS_PLAN.md)). [EMBER_ART_REQUESTS.md](../EMBER_ART_REQUESTS.md) describes the Old Oak model as "the great oak" in the art request, not as the place name. No code or doc was renamed.

How Vigil tiers relate to Chaos mode is open. Whether depth auto-raises the tier, or the player picks it, is open.

"the Abyss" and "Endless Descent" may clash with the existing name The Forgotten Abyss (`docs/PLAN_NEXT.md`, `docs/PLAN_0.8.0_SLAGWORKS.md`: the deferred post-Core endless run). Whether "the Abyss" refers to each labyrinth's descent generally is also open. No name was renamed.
