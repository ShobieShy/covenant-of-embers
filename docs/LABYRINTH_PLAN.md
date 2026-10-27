# The Labyrinth (plan only)

Status: PLAN, queued for after the 0.2.0 open-world release (OW11). Nothing here is built
until 0.2.0 ships and these defaults are approved. Requested 2026-10-27 ~01:18 CDT.

One main-game, multi-floor labyrinth dungeon replaces the Magewar Bible's "defeat all 5
dungeons, then the Demon Lord's lair" plan. It sits alongside the open world (OPEN_WORLD_PLAN.md):
the overworld stays the place for towns, quests and regions; the Labyrinth is where depth,
bosses and the endgame live. Future labyrinths could ship as DLC (own entrance, own floor
set, same systems); this plan covers only this one.

## 1. Source material (Magewar, read-only)

The Bible (`~/game/Magewar Bible.md`) names five dungeons but does not detail them: "Dungeon 1"
under Town 2 is a placeholder, and the ending is "Once the players defeat all 5 dungeons, the
Demon Lord teleports them to his lair, where he has them fight Crazy Joe, then himself."
The Storyline (`Magewar Storyline.md`) supplies the flavour the five should adapt from:

| Bible / Storyline hook | Becomes in the Labyrinth |
|---|---|
| Willowbrook goblin raids, "hidden dungeon entrance" | Act I theme: Goblin Warrens |
| Whispering Woods (murmuring trees, ambushes) | Act II: Overgrown Deep |
| Ironforge mines, trolls, rare ores | Act III: Drowned Forge / mines |
| Crimson Sea underwater ruins | Act IV: Sunken Ruins |
| Shattered Peaks aerial dungeons | Act V: Inverted Spire (floating, falling floors) |
| "Dungeon Fracture" / elder god in the core; Demon Lord's lair, Crazy Joe then Demon Lord | The Core: final floors and the two-stage finale |

The Fracture is the in-world reason the Labyrinth exists: the dungeons did not just open,
they collapsed into one another, and the Labyrinth is the fused shaft beneath Elyria.

## 2. Entrance in the open world

- The Breach crater (east of the Landfill, already built) is the entrance: Bob's lead ends
  there after the prologue, and the crater portals become the Labyrinth gate (floor 1).
  It reuses the Breach as the "first taste" and keeps the world map unchanged.
- Shortcut gates (sealed rifts) appear in the overworld near each Act's theme region
  (Willowbrook, Whispering Woods, Ironforge road, the coast, the Peaks foothills). Each
  opens only once its Act is cleared from below, as a return point, never as a skip.
- The entrance is an instanced interior (OPEN_WORLD_PLAN section 4): door trigger, loading
  screen, the overworld stays streamed.

## 3. Depth as progression

- About 25 floors in 5 Acts of 4 floors plus a boss floor each, then the Core (2-3 floors).
- Depth gates level and gear: each Act has a recommended level band (Act I 5-12 ... Core
  45+), and enemy tiers / brands scale by floor. The overworld regions unlock in step with
  the Acts (the quest log points to the matching region after each Act boss).
- Story beats sit on Act boss floors (Bob's research, Joe's past, the Demon Lord's voice);
  the main quest is "go deeper", which keeps the Bible's vague-main-quest feel.

## 4. Biomes per Act

Each Act has its own Terrain3D set or tile kit, lighting, fog and music, matching
the EmberArt pipeline (10 sets per region already exist; Acts add 5 more):

| Act | Biome | Hazard | Enemy families |
|---|---|---|---|
| I | Goblin Warrens: packed earth, timber, torchlight | traps, ambush rooms | goblins, gnawer packs |
| II | Overgrown Deep: roots, moss, glowing fungi | vines that grab, poison spores | treants, spore beasts |
| III | Drowned Forge: rails, lava channels, ore veins | heat zones, mine carts | trolls, constructs |
| IV | Sunken Ruins: flooded halls, coral, air pockets | rising water, breath (reuses the Breath meter) | sea horrors, cultists |
| V | Inverted Spire: floating platforms, wind | falls, wind push | harpies, storm elementals |
| Core | Fracture: crystal, void, fused bits of every Act | phase shifts | mixed elites |

## 5. Bosses

- One Act boss on every 5th floor (5 total), adapted from the five Bible dungeons:
  Goblin King (I), the Murmuring Elder (II), Forgemaw the troll smith (III), the Drowned
  Choir (IV), the Storm Warden (V). Each uses the existing boss framework (The Filth:
  arena trigger, phases, Boss Drop) and drops a named part + an Act key item.
- Mini-bosses: one elite room on each non-boss floor (a named variant with an affix).
- Core finale keeps the Bible's ending: Crazy Joe first (corrupted, using player-like
  spells), then the Demon Lord (multi-phase, uses every Act's mechanic once).

## 6. Procedural vs handmade

Hybrid (default):
- Boss floors, the entrance and the Core: handmade (TOML levels, like the current maps).
- Normal floors: generated from a handmade room kit per Act (rooms, corridors, set pieces)
  by a seeded graph generator (start, mini-boss, exit, 1-2 secrets, a rest room). The seed
  is fixed per save and floor, so a floor is the same when you come back; a "remix" option
  re-rolls cleared floors for farming.
- The generator runs offline-capable (python, like toml_to_scene.py) for tests and in-game
  on a worker thread behind the loading screen; navmesh tiles bake per room and cache by
  room id + rotation.

## 7. Checkpoints and returning

- Waystone on every boss floor (after the kill) and a rest room every floor (save, heal,
  craft station). Waystones link to the overworld network (OW6), so returning to town and
  going back down is one fast travel.
- Leaving mid-floor returns you to the floor's start (floor progress kept: opened chests
  and killed elites stay); dying respawns at the last rest room with the existing death
  rules.
- The Act shortcut gates in the overworld (section 2) open once that Act is cleared.

## 8. Co-op

- Host authority as in OPEN_WORLD_PLAN section 7: the host's floor seed and state decide;
  partners load the same floor through the loading screen.
- Party stays on one floor (no split floors); the stairs/exit need all players nearby or
  a 10 s vote. Boss arenas lock when the fight starts; late joiners spectate until the
  phase ends.
- Enemy health and loot rolls scale with party size (same scaling as the overworld camps).

## 9. Loot scaling

- Item level = floor depth band; part rarity weights rise per Act; each Act adds a brand
  pool (Act element) to the PartRoller tables.
- Boss drops are guaranteed named parts; first clear gives a fixed unique, repeat clears
  roll from the boss table.
- Secret rooms hold chests a tier above the floor. No pay-to-skip, no loot boxes.

## 10. Saves

- New `labyrinth` block in the save: deepest floor, cleared floors, per-floor seed and
  state (chests opened, elites dead, shortcuts open), bosses defeated, remix count.
- Versioned and migrated like the rest (old saves load with an empty block; the Breach
  progress maps onto floor 1). Fixtures in tests for each save version.

## 11. Performance

- Floors are instanced (not streamed with the overworld); one floor in memory, the next
  preloaded on a thread when the exit is in sight.
- Budget per floor: under 150 draw calls on Low / Steam Deck, room occlusion (rooms are
  natural portals), enemy sleep beyond 2 rooms, navmesh tiles cached per room.
- Load target: under 2 s per floor on Steam Deck, always behind the loading screen.

## 12. Fit after 0.2.0

0.2.0 (OW11) ships the open world with the Landfill and the Breach. The Labyrinth is the
next milestone, roughly:

| # | Step | Estimate |
|---|---|---|
| L1 | Floor/room kit format, seeded generator (python + GDScript), tests | 3 days |
| L2 | Labyrinth runtime: floor loader, stairs, rest rooms, waystones, saves + migration | 3 days |
| L3 | Act I kit + 4 floors + Goblin King | 4 days |
| L4 | Co-op floor sync, party scaling, loot tables per Act | 2 days |
| L5 | Perf pass and playtests (1x / 4x / co-op through Act I) -> 0.3.0 | 2 days |
| L6+ | Acts II-V and the Core, about 4-5 days each | 25 days |

Act I alone is a releasable slice (0.3.0); later Acts ship as 0.4.0+. DLC labyrinths would
reuse L1-L2 unchanged.

## 13. Open questions (recommended defaults)

1. Entrance: the Breach crater as floor 1? Default: yes.
2. Floor count: 5 Acts x 5 floors + a 2-3 floor Core? Default: yes (about 27 floors).
3. Hybrid generation (handmade boss/Core floors, generated normal floors)? Default: yes.
4. Fixed seed per save (floors persist) plus an optional remix for farming? Default: yes.
5. Act themes from the Storyline (Warrens, Deep, Forge, Ruins, Spire)? Default: yes.
6. Keep the Bible's finale (Crazy Joe, then the Demon Lord) in the Core? Default: yes.
7. Overworld shortcut gates per Act, opened from below only? Default: yes.
8. Death: respawn at the last rest room, keep floor progress? Default: yes.
9. Co-op: whole party on one floor, exit vote of 10 s? Default: yes.
10. Do the overworld regions unlock in step with the Acts? Default: yes, via quest hints only, no hard locks.
11. Act I as 0.3.0, later Acts in point releases? Default: yes.
12. DLC labyrinths: separate entrance and floor set, no change to the main one? Default: yes, plan later.
