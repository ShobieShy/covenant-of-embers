# Linear levels plan

Status: current plan. ShobieShy approved the closed-level campaign on 2026-11-04, and the Acts I–V outlines plus the version roadmap on 2026-11-05.
0.4.0 (closed levels), the 0.5.0 open-world cut, and the 0.6.0 trust pass are on master.
0.7.0 is Act II, The Blightcoil, on master. Versions after that are [PLAN_NEXT.md](PLAN_NEXT.md).
The 11 Nov 2026 Act IV / post-game / DLC notes are in [design/BRAINSTORM_2026-11-11_ACT4_POSTGAME_DLC.md](design/BRAINSTORM_2026-11-11_ACT4_POSTGAME_DLC.md).
The game is a linear campaign of closed levels. There is no open world, no
`--open-world` flag, and no seamless cell stream.

This document is the only current campaign plan. The seamless-world plans are in
[archive/](archive/README.md). [LABYRINTH_PLAN.md](LABYRINTH_PLAN.md) is the dungeon
content plan and follows this level order. [PLAN.md](PLAN.md) still holds mechanics;
its open-region map is not the world we are building.

## 1. Where the game is (Act II on master)

| Area | Now | Files |
|---|---|---|
| Flow | One scene per level. `LevelFlow.ORDER` is Old Oak, Town Square, Landfill, Breach, Labyrinth. Forward gates use story flags. The road back to Town Square stays open. | scripts/world/level_flow.gd, scripts/core/main.gd, scripts/core/game_flow.gd |
| Levels | `old_oak`, `town_square`, `midden`, `breach`, `mage_association` (interior of the hub). Each has a scene and `data/levels/*.toml`. Per-level Terrain3D stays. | scenes/levels/*, data/levels/* |
| Travel | Waystones are per-level points. Travel loads the target level. Deep points (`warrens_hall`, floor 5) enter the Labyrinth floor. | scripts/world/fast_travel.gd, waystone.gd, world_travel.gd |
| Map | M opens a campaign sheet for the current level (`WorldMapScreen.linear_level`). | scripts/ui/world_map_screen.gd, scripts/world/world_map.gd |
| Labyrinth | Act I Warrens: floors 1-4 generated, floor 5 the Goblin King. Act II The Blightcoil: one cavern. Entered from the Breach crater portal. | scripts/labyrinth/*, data/labyrinth/warrens.toml, data/labyrinth/blightcoil.toml |
| Saves | `SaveMigration` still reads 0.1.x level saves and 0.2/0.3 world saves (`WORLD_V`) and writes the linear save (`LINEAR_V`). `world_pos` and `region` stay in the file so an older build can still open it. | scripts/core/save_migration.gd, scripts/world/world_session.gd |
| Co-op | The party shares one level. The host changes level after a gate vote. A joiner loads the host's level and Labyrinth floor. | scripts/net/*, scripts/world/level_gate.gd |
| Tests | Closed-level flow tests run in the full tier. The fast tier's core list includes `test_flow`, `test_level`, `test_linear_flow`, `test_linear_migration`, and `test_gate_vote`. | docs/TEST_TIERS.md, tests/run_tests.gd |

## 2. Campaign (through the Core)

Closed levels, one scene each, joined by exit gates and a loading screen. Forward
progress is gated by story flags. Going back is allowed to the hub.

1. **Prologue: The Old Oak** (`old_oak`). Intro, summoning, Crazy Joe and the Summoned.
2. **Eldoria, Town Square** (`town_square`) is the hub. Vendors, stash, stations, quests. The Mage Association stays an interior of the hub.
3. **The Landfill** (`midden`). Joe's camp, Bob's lead.
4. **The Breach** (`breach`). Crater fight. The crater portal is the Labyrinth gate.
5. **The Breach Labyrinth**, the campaign on 0.x minors: Act I Warrens (floors 1-4 and the Goblin King on 5, in the game), Act II The Blightcoil (one cavern, not five generated floors — see [PLAN_0.7.0_ACT2.md](PLAN_0.7.0_ACT2.md)), Act III The Slagworks (five floors, checkpoints 9–13 — see [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md)), Act IV Sunken Ruins, Act V Inverted Spire, then **the Core**: Crazy Joe, then the Demon Lord, who escapes (main-campaign end, DLC hook). The Core is a later 0.x when ShobieShy opens it. 1.0 is a release cut he orders, not that milestone. Acts III–V are five floors each, boss on floor 5. Act II is not. Outlines: [LABYRINTH_ACTS_STORY.md](LABYRINTH_ACTS_STORY.md). Versions: [PLAN_NEXT.md](PLAN_NEXT.md).

Each Act boss floor has a waystone. It returns the party to the hub, and the hub's Breach gate offers "descend to Act N". There are no overworld shortcut gates. DLC is new towns and dungeons as new closed level sets with their own hub entrance.

Level counts for the levels that exist today are in [ZONE_BALANCE.md](ZONE_BALANCE.md).

## 3. What 0.5.0 already removed

Deleted with the cut: `OpenWorld`, `WorldZones.merged`, `WorldStreamer`, world cells, world terrain, world nav, `CampLeash`, `CoopLeash`, `EnemySleep`, `--open-world`, `--classic-levels`, and the tools that baked that world (`build_cells.gd`, `bake_world_nav.gd`, `bake_world_markers.gd`, `save_world_terrain.gd`, `export_zone_heights.gd`).

A later sweep removed the leftovers that nothing calls: `ShaderWarmup` (it only walked `world/cells`), `tools/build_world.py`, `tools/build_world.sh`, `tools/gen_world_map.py`, `WorldTravel`'s no-op cell stream, and `Interiors`' unused streamer hold. Old-save migration was not changed.

## 4. Still in the tree (not the open world)

These are easy to mistake for a second world plan. They stay.

- **`ZoneStreamer` on generated levels.** `town_square`, `old_oak`, `midden`, `breach`, and `mage_association` still put props under a `Pois` node with this script. `QualityPresets` sets prop visibility ranges through it. The Landfill is large enough that distant props detach. Removing it would change those levels. `tests/unit/test_zone_streamer.gd` covers it.
- **`WorldTravel`.** Waystones from `world/markers.json`, deep Labyrinth travel, the map screen's non-linear fallback, and the interior fade's arrival signal. The cell-stream field and the empty `_stream` are gone. Travel moves the party.
- **`WorldSession`.** `start_spot` and `nearest_level` are how a world save picks a closed level. Required for old saves.
- **`world/map.png`, `world/map.json`, `world/markers.json`.** Fog grid, map tests, and waystone positions. The generator that painted the seamless map is gone.
- **`Minimap`.** The class, the `minimap_north` setting, and its tests remain. The closed-level HUD does not mount the widget. The campaign plan keeps a minimap; mounting it is later work, not a world stream.
- **`IntroDirector._world_way`.** Used when a beat has no level gate. It returns that level's entrance. It is not a cell stream.
- **`CoopWorld.world_enemies`.** The host sets it false. The "share every enemy in the world" branch does not run. Left in place so co-op enemy ownership stays as it is.
- **`Interiors`.** Association, Breach rooms, and the Labyrinth are still instanced interiors of a closed level. `level_local` keeps door landings in that level's coordinates.

## 5. Saves

`progress.level_id` is still written. Linear saves add `progress.flow = "linear"` and `progress.linear_v`. A world save maps `region` / `world_pos` to the nearest level, or to the hub when story gates have not opened that level. A Labyrinth floor is kept. Waystone attunements map onto the linear points. Fog is not required to load. The first write backs up `slotN.pre_linear.json`. `world_pos` and `region` are left in the file.

Do not drop `WORLD_V` or `WorldSession` while those saves still load.

## 6. Co-op

The party is in one level. Level changes are host-driven, with a ready vote at gates and a load barrier. A joiner loads the host's level and Labyrinth floor and spawns at that level's start or the host's last waystone. Character files have no progress block. Protocol compat rejects a 0.3.x peer.

## 7. Tests

Fast tier: `tools/run_tests.sh --fast` (core list, one smoke, the 4x solo playtest).
Full tier: `tools/run_tests.sh` (every unit test, smokes, solo, Labyrinth, co-op).

`test_linear_migration` and `test_linear_flow` are the closed-level proofs. `test_world_save_migration` stays so old world saves still migrate.

## 8. Explicitly not this plan

- **PR #3 and PR #4** were not merged and are not edited from this plan.
- The 0.6.0 trust pass already shipped. The bugs in [BUGTEST_0.4.0.md](BUGTEST_0.4.0.md) are not the remaining milestone list.
- DLC towns, new music, drawn maps, mid-session join, and Core design. See [PLAN_NEXT.md](PLAN_NEXT.md). Later acts are campaign work, not a return to an open world.

## 9. Remaining milestones

- **0.4.0** shipped: closed levels.
- **0.5.0** shipped: the open-world cut.
- **0.6.0** shipped: the trust pass. ZoneStreamer stays. The minimap stays off the HUD. The map stays the text sheet. No mid-session join.
- **0.7.0** (shipping): Labyrinth Act II, The Blightcoil, one walkable cavern (Sump, Canopy Ring, Crown) around the Rotheart. See [PLAN_0.7.0_ACT2.md](PLAN_0.7.0_ACT2.md). The Murmuring Elder name is retired.
- **0.8.0**: Act III, The Slagworks, five floors at checkpoints 9–13. See [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md). Act I outline polish can fold into this prep, or an optional 0.7.1. Story: [LABYRINTH_ACTS_STORY.md](LABYRINTH_ACTS_STORY.md) and [PLAN_NEXT.md](PLAN_NEXT.md).
- **0.9.0**: Act IV, The Sunken Ruins.
- **0.10.0**: Act V, The Inverted Spire.
- **Later 0.x**: The Core, when ShobieShy opens it. Joe, then the Demon Lord, who escapes. Main-campaign end. An endless run after that clear is Post-Core in [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md). Neither is 1.0. 1.0 waits on his explicit release cut. See [PLAN_NEXT.md](PLAN_NEXT.md).

## 10. Decisions that still hold

1. Level order: Old Oak, Eldoria Town Square (hub), Landfill, Breach, Labyrinth (five Acts, then the Core). Act II is one cavern. Acts III–V are five floors each.
2. Town Square is the only hub. Backtracking is to the hub, through Act-boss waystones and the Breach gate.
3. The open world is gone. It is not a dev flag.
4. No overworld Labyrinth shortcut gates.
5. Waystones are per-level points (hub, Breach, Act boss floors). Act II's three pads are waystones as well.
6. The full-screen map is the campaign sheet for the current level. A minimap is still wanted; the widget is not mounted yet.
7. Save migration stays additive and keeps a backup. Unknown positions land in the hub.
8. Co-op level changes are host-driven with a ready vote. Joiners load the host's level.
9. Leash, enemy distance-sleep, and world streaming stay cut.
10. Closed-level flow tests live in the full tier and in the fast core list.
