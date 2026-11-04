# Linear levels plan

Status: current plan. ShobieShy approved the closed-level campaign on 2026-11-04.
0.4.0 (closed levels) and the 0.5.0 open-world cut are on master (`6901190`).
0.6.0 is the trust pass in [PLAN_NEXT.md](PLAN_NEXT.md).
The game is a linear campaign of closed levels. There is no open world, no
`--open-world` flag, and no seamless cell stream.

This document is the only current campaign plan. The seamless-world plans are in
[archive/](archive/README.md). [LABYRINTH_PLAN.md](LABYRINTH_PLAN.md) is the dungeon
content plan and follows this level order. [PLAN.md](PLAN.md) still holds mechanics;
its open-region map is not the world we are building.

## 1. Where the game is (master 6901190)

| Area | Now | Files |
|---|---|---|
| Flow | One scene per level. `LevelFlow.ORDER` is Old Oak, Town Square, Landfill, Breach, Labyrinth. Forward gates use story flags. The road back to Town Square stays open. | scripts/world/level_flow.gd, scripts/core/main.gd, scripts/core/game_flow.gd |
| Levels | `old_oak`, `town_square`, `midden`, `breach`, `mage_association` (interior of the hub). Each has a scene and `data/levels/*.toml`. Per-level Terrain3D stays. | scenes/levels/*, data/levels/* |
| Travel | Waystones are per-level points. Travel loads the target level. Deep points (`warrens_hall`, floor 5) enter the Labyrinth floor. | scripts/world/fast_travel.gd, waystone.gd, world_travel.gd |
| Map | M opens a campaign sheet for the current level (`WorldMapScreen.linear_level`). | scripts/ui/world_map_screen.gd, scripts/world/world_map.gd |
| Labyrinth | Act I Warrens: floors 1-4 generated, floor 5 the Goblin King. Entered from the Breach crater portal. | scripts/labyrinth/*, data/labyrinth/warrens.toml |
| Saves | `SaveMigration` still reads 0.1.x level saves and 0.2/0.3 world saves (`WORLD_V`) and writes the linear save (`LINEAR_V`). `world_pos` and `region` stay in the file so an older build can still open it. | scripts/core/save_migration.gd, scripts/world/world_session.gd |
| Co-op | The party shares one level. The host changes level after a gate vote. A joiner loads the host's level and Labyrinth floor. | scripts/net/*, scripts/world/level_gate.gd |
| Tests | Closed-level flow tests run in the full tier. The fast tier's core list includes `test_flow`, `test_level`, `test_linear_flow`, `test_linear_migration`, and `test_gate_vote`. | docs/TEST_TIERS.md, tests/run_tests.gd |

## 2. Campaign (through 1.0)

Closed levels, one scene each, joined by exit gates and a loading screen. Forward
progress is gated by story flags. Going back is allowed to the hub.

1. **Prologue: The Old Oak** (`old_oak`). Intro, summoning, Crazy Joe and the Summoned.
2. **Eldoria, Town Square** (`town_square`) is the hub. Vendors, stash, stations, quests. The Mage Association stays an interior of the hub.
3. **The Landfill** (`midden`). Joe's camp, Bob's lead.
4. **The Breach** (`breach`). Crater fight. The crater portal is the Labyrinth gate.
5. **The Breach Labyrinth**, the 1.0 campaign: Act I Warrens (floors 1-4 and the Goblin King on 5, in the game), Act II Overgrown Deep, Act III Drowned Forge, Act IV Sunken Ruins, Act V Inverted Spire (5 floors each, floor 5 the Act boss), then **the Core**: Crazy Joe, then the Demon Lord, who escapes (1.0 ending, DLC hook).

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
- **Parked gameplay bugs**, left as they are: joiner exit rc 134 after a Breach slice, the travel list showing Landfill alias stones, a gate vote on a freed body, a dead player using a gate, the joiner vote log. See [BUGTEST_0.4.0.md](BUGTEST_0.4.0.md).
- New Labyrinth Act content, art, and balance numbers. Act II and later are the campaign work below, not a return to an open world.

## 9. Remaining milestones

- **0.4.0** shipped: closed levels.
- **0.5.0** shipped: the open-world cut. Acts III and IV did not ship with it.
- **0.6.0** is the trust pass ([PLAN_NEXT.md](PLAN_NEXT.md)): the parked co-op and travel bugs, and a full test run that gets past classified headless exit leaks. ZoneStreamer stays. The minimap stays off the HUD. The map stays the text sheet. No mid-session join.
- **0.7.0**: Labyrinth Act II, after the story, look, and music are set.
- **Later**: Acts III–V, the Core, Crazy Joe and the Demon Lord, balance.
- **1.0**: town, Breach, full Labyrinth, main story. The Demon Lord escapes.

## 10. Decisions that still hold

1. Level order: Old Oak, Eldoria Town Square (hub), Landfill, Breach, Labyrinth (5 Acts of 5 floors, then the Core).
2. Town Square is the only hub. Backtracking is to the hub, through Act-boss waystones and the Breach gate.
3. The open world is gone. It is not a dev flag.
4. No overworld Labyrinth shortcut gates.
5. Waystones are per-level points (hub, Breach, Act boss floors).
6. The full-screen map is the campaign sheet for the current level. A minimap is still wanted; the widget is not mounted yet.
7. Save migration stays additive and keeps a backup. Unknown positions land in the hub.
8. Co-op level changes are host-driven with a ready vote. Joiners load the host's level.
9. Leash, enemy distance-sleep, and world streaming stay cut.
10. Closed-level flow tests live in the full tier and in the fast core list.
