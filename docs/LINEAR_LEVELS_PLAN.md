# Linear Levels Plan (closed levels replace the open world)

Status: APPROVED 2026-11-04. ShobieShy approved every default in section 11.
0.4.0 (LL1-LL5) and the 0.5.0 open-world cut are in this branch. Section 10 still
leaves new Labyrinth Acts, art, and balance out of this plan. PR #3 and PR #4
were not touched. Requested
the same day: the game should no longer be open world; it should be linear with closed
levels. This document is the build source for milestone 0.4.0 "Closed Levels" (LL1-LL5).
Supersedes OPEN_WORLD_PLAN.md (OW1-OW11) as the default flow; LABYRINTH_PLAN.md stays
approved, but its overworld hooks (section 2, shortcut gates in theme regions) are
rewritten here.

## 1. Where the code is today (master 14dbe84, 0.3.3-prealpha)

| Area | Today | Files |
|---|---|---|
| Default flow | `GameFlow.open_world := true` (OW11c-3). `Main.open_world_on()` returns false only for `--classic-levels`. `_use_world_level()` swaps the level for `WorldZones.merged(here)` | scripts/core/game_flow.gd, scripts/core/main.gd |
| Open world | `WorldZones.ZONES = [town_square, old_oak, midden]` merged into one level, plus strips; `WorldStreamer` / `ZoneStreamer`, `TerrainZone`, `world/cells`, `world/terrain`, `world/nav`, `world/markers.json`, `WorldFog`, `WorldMap` / map screen / minimap / pins, `CampLeash`, `EnemySleep` | scripts/world/*, scenes/world/open_world.tscn |
| Classic levels | `GameFlow.LEVELS`: midden, breach, town_square, mage_association, old_oak, each with a scene and `data/levels/*.toml`; `LevelGate` exits, scene reload with autosave between levels | scenes/levels/*, scripts/world/level_gate.gd, level_toml.gd |
| Travel | `FastTravel.POINTS` (old_oak, town_gate, town_market, landfill, landfill_camp, landfill_overlook, breach) + `DEEP_POINTS` (warrens_hall, floor 5); `WorldTravel` streams to a spot; `Waystone` attunes | scripts/world/fast_travel.gd, world_travel.gd, waystone.gd |
| Interiors | Mage Association + the Labyrinth are instanced interiors entered from the world (`Interiors`, `InteriorDoor`) | scripts/world/interiors.gd |
| Labyrinth | Act I Warrens: `data/labyrinth/warrens.toml` floors 1-4 generated (`FloorGen`, golden fixture), floor 5 handmade Goblin King; `LabyrinthState` in `progress["labyrinth"]`; `LabyrinthStairs`, `RestShrine`, `LabyrinthSync` | scripts/labyrinth/*, scripts/net/labyrinth_sync.gd |
| Saves | `SaveGame.VERSION` (file), `progress.level_id` always kept; `SaveMigration.WORLD_V = 2` adds `world_pos`, `region`, `fog` (additive, so classic builds still read migrated files) | scripts/core/save_game.gd, save_migration.gd |
| Co-op | Host authority; `CoopWorld` interest radius 150 m, `CoopLeash` / camp leash for spread-out parties; joiner spawns at host's waystone via `GameFlow.spawn_anchor`; `IntroSync`, `LabyrinthSync` | scripts/net/* |
| Tests | `run_tests.gd` sets `GameFlow.open_world = false` for unit tests unless they opt in; the CLASSIC group (test_level, test_flow, test_hub, test_town::test_all_exits_link, test_vault::test_chest_opens_after_boss) only runs with `--classic` (release tier) | tests/run_tests.gd, docs/TEST_TIERS.md |

The classic flow is a working base, but it predates 0.2.0-0.3.3: quests, intro (Old Oak,
back door, Association), the Breach fight, waystones and the Labyrinth entrance were all
tuned on the open world since then. Expect a re-wiring pass, not a flag flip.

## 2. Proposed level sequence (1.0)

Closed levels, one scene each, joined by exit gates with a loading screen. Forward
progress is gated by story flags; going back is allowed only to the hub.

1. **Prologue: The Old Oak** (old_oak). Intro, summoning, Crazy Joe and the Summoned.
2. **Eldoria, Town Square** (town_square) = **the hub**. Vendors, stash, stations, quests;
   Mage Association stays an interior of the hub.
3. **The Landfill** (midden). Joe's camp, Bob's lead.
4. **The Breach** (breach). Crater fight; the crater portal is the Labyrinth gate.
5. **The Breach Labyrinth** (the 1.0 campaign): Act I Warrens (floors 1-4 + Goblin King 5),
   Act II Overgrown Deep, Act III Drowned Forge, Act IV Sunken Ruins, Act V Inverted Spire
   (5 floors each, floor 5 the Act boss), then **the Core**: Crazy Joe, then the Demon Lord,
   who escapes (1.0 ending, DLC hook).

Each Act boss floor has a waystone; it returns the party to the hub and the hub's Breach
gate offers "descend to Act N". No overworld shortcut gates (LABYRINTH_PLAN section 2 cut).
DLC = new towns and dungeons as new closed level sets with their own hub entrance.

## 3. Reuse / rework / cut

Reuse as is: all combat, loot, magic, enemies, UI (except map), story/quest/dialogue,
`LabyrinthState`, `FloorGen`, warrens kit, rest shrines, stairs, `SaveGame`, `ItemCodes`,
level scenes + `data/levels/*.toml`, `LevelGate`, `Interiors` (for Association + Labyrinth),
`EnemySpawner`, `ArenaLock`, `ZoneChests`, `VaultChest`, `QualityPresets`, `ShaderWarmup`.

Rework:
- `GameFlow`/`Main`: classic flow becomes the only flow; `open_world` flag and
  `--classic-levels` / `--open-world` args removed (keep `--open-world` as a dev flag until
  0.5, decision 3).
- `FastTravel` / `WorldTravel`: waystones become per-level points (hub + Labyrinth boss
  floors); travel = load the target level, not stream a spot. `POINTS` trimmed to the hub,
  `breach`, and `DEEP_POINTS`.
- Level gates re-tuned to current intro / quest flags (Old Oak finale -> town, Bob's lead ->
  Landfill -> Breach).
- Map: `WorldMap` / map screen become a per-level map (layout image + pins + fog per level);
  minimap stays.
- Level content that only exists in the merged world (strips, markers.json placements,
  PR #4 fixes) ported back into the level scenes / toml.

Cut (deleted in 0.5 after one release behind a flag): `WorldZones.merged`, strips,
`WorldStreamer`, `ZoneStreamer`, `world/cells`, `world/terrain` large data set (keep per-level
Terrain3D only), `world/nav` world bake, `tools/build_cells.gd`, `bake_world_nav.gd`,
`bake_world_markers.gd`, `save_world_terrain.gd`, `export_zone_heights.gd`, `EnemySleep`
(distance sleep; closed levels are small), `CampLeash`, `CoopLeash` world leash, locked-region
border gates. Docs OPEN_WORLD_PLAN.md / WORLD_LAYOUT.md / ZONE_BALANCE.md marked superseded.

## 4. Save migration (SaveMigration LINEAR_V = 3)

- `progress.level_id` is still written by every build, so most saves already know their level.
- New `progress.flow = "linear"`, `progress.linear_v = 3`. Migration from a world save:
  `region` / `world_pos` -> nearest level (`WorldMap.LEVEL_REGION` inverse); spawn at that
  level's PlayerStart, or the hub if the level is past story gates the save has not met.
- In the Labyrinth: keep the floor (LabyrinthState already per floor).
- Waystone attunements map to the new points (landfill_* -> landfill, town_market ->
  town_gate); fog dropped (or per-level fog seeded from "visited").
- Additive: keep `world_pos`/`region` untouched so a rollback to 0.3.x still loads.
- Back up the slot (`slotN.pre_linear.json`) before the first write.

## 5. Co-op

- Party is always in one level: level changes are host-driven, with a ready vote at gates
  (`VoteBanner` exists) and a load barrier like the Labyrinth's. Removes leash and interest
  logic; snapshots go back to level-local.
- Joining mid-game: joiner loads the host's current level (and Labyrinth floor) and spawns
  at its PlayerStart or the host's last waystone (`spawn_anchor` reused, now level + point).
- Character files unchanged (no progress block, migration skips them).
- Compat: bump `Compat` protocol; a 0.3.x peer cannot join a linear host.
- Known joiner rc 134 at teardown after the Breach is unrelated but should be re-checked
  without the world streamer (it may go away).

## 6. Tests

- Classic group moves out of the release-only tier into Full (and the core list gets
  test_flow + test_level).
- `run_tests.gd`: remove the `GameFlow.open_world = false` override once the flag is gone.
- Retire or rewrite open-world tests: test_world_streamer, test_zone_streamer, test_world_zones,
  test_world_terrain, test_world_nav, test_world_travel, test_world_session, test_map_anchors,
  test_coop_leash, test_enemy_sleep, test_world_save_migration (kept for old saves), test_minimap /
  test_world_map(_screen) rewritten for per-level maps, test_fast_travel rewritten.
- New: test_linear_migration (world save -> level, labyrinth floor kept, rollback-safe),
  test_linear_flow (Old Oak -> town -> Landfill -> Breach -> Labyrinth gate -> back to hub),
  co-op gate vote + join-into-level, playtest bot route rewritten for gates.
- Playtests: solo slice, Labyrinth playtest, co-op playtest all on the linear flow.

## 7. Open PRs

- **#3 (0.3.4 leftovers: playtime, Labyrinth prewarm, S8 notes)**: mostly independent.
  Playtime and the Labyrinth shader prewarm stay useful. Recommend merging it first as the
  last open-world release (0.3.4), then branching linear work from it.
- **#4 (Old Oak map alignment, Joe + the Summoned placement, intro fixes in the open-world
  map)**: its fixes target world-space coordinates in the merged level and markers.json.
  The intro/cast placement intent still applies, but in level-local space in old_oak.tscn /
  old_oak.toml. Recommend closing it without merge and porting the intent in LL2, or merging
  it only if a 0.3.4 open-world build ships to playtesters.

## 8. Milestones

- **0.3.4**: merge #3; last open-world build.
- **0.4.0 "Closed Levels"** (LL1-LL5): LL1 flow flip (classic default, `--open-world` dev
  flag), LL2 port level content + #4 intent + intro/quest gates, LL3 level-based waystones +
  per-level map, LL4 save migration v3, LL5 co-op gate vote / join-into-level + tests + tiers.
- **0.4.x**: Labyrinth Act II on the linear flow.
- **0.5.0**: delete open-world code/data (section 3 "Cut"), Acts III-IV.
- **0.6-0.9**: Act V, the Core, Crazy Joe + Demon Lord finale, balance.
- **1.0**: town + Breach + full Labyrinth + main story; Demon Lord escapes.

## 9. Risks

- Classic flow has bit-rotted against 0.2-0.3 intro/quest work; LL2 may be larger than it looks.
- Level-local vs world coordinates: content placed in world space must be re-placed per level.
- Save migration edge cases (saves standing in strips / border areas); mitigated by hub fallback and backups.
- Co-op: forcing everyone through gates can annoy; the vote needs a timeout.
- Loading time between levels on Steam Deck (shader warmup per level).
- Map / minimap and quest markers assume world coordinates.
- Repo size: deleting world terrain/cells is large; do it in one commit in 0.5 for easy revert.

## 10. Out of scope

DLC towns/dungeons, new Labyrinth Acts' content, art, balance numbers.

## 11. Default decisions to approve

1. Level order: Old Oak -> Eldoria Town Square (hub) -> Landfill -> Breach -> Labyrinth (5 Acts x 5 floors + Core).
2. Town Square is the only hub; backtracking only to the hub, via Act-boss waystones and the Breach gate.
3. Open world stays behind a dev-only `--open-world` flag in 0.4.x, deleted in 0.5.0.
4. No overworld Labyrinth shortcut gates; Act boss waystones replace them.
5. Waystones become per-level points (hub, Breach, Act boss floors); the Landfill/market sub-points merge.
6. Full-screen map becomes a per-level map; minimap kept.
7. Save migration v3 is additive and backs up the slot; unknown positions land in the hub.
8. Co-op: host-driven level changes with a ready vote (15 s timeout), joiners load into the host's level.
9. Leash, enemy sleep, zone/world streaming are cut.
10. Classic level-flow tests move into the Full tier; open-world tests retired as listed.
11. Merge PR #3 as 0.3.4 (last open-world build); close PR #4 and port its placements to old_oak level-local in LL2.
12. Target 0.4.0 "Closed Levels" for the switch; 1.0 content milestones as in section 8.
