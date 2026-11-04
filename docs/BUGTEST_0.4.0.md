# Bug test: 0.4.0 Closed Levels (PR #5)

Date: 2026-11-04. Branch `cursor/closed-levels-0-4-0-e02c` at `e0d5840`. Godot 4.7.2.stable headless (`ed1daf0bf`). Gameplay bugs were reproduced and left as they are. Nothing in this pass changes play, saves, or tests.

Recorded before the 0.5.0 cut. Probes that pass `--open-world` describe a flag that master no longer has. The parked gameplay bugs (joiner rc 134, the travel list's Landfill entries, a gate vote on a freed body, a dead player using a gate, the joiner vote log) are still open and are not part of the plan cleanup.

`--classic` is the same set as the full tier (`CLASSIC` in `tests/run_tests.gd` is empty). It was not run a second time.

## Counts

| Check | Result |
|---|---|
| Full-tier Python checks (scenes, import, labyrinth golden) | pass |
| Unit suite (`tools/run_tests.sh`, stopped at the Godot tests) | **692 passed, 3 failed**, exit 1 |
| Menu smoke `--seconds 2` | pass, exit 0 |
| Start smoke `--start --seconds 2` | pass, exit 0 |
| Solo playtest, 1x | **PASS**, exit 0 (444 s simulated, 0 deaths) |
| Solo Labyrinth playtest (`PLAYTEST_LABYRINTH=1`) | **FAIL**, exit 1 |
| Co-op playtest, 3 runs, gameplay | **3 PASS** |
| Co-op raw process status | host 0 / 0 / 0; joiner **134 / 0 / 134** |
| Co-op script exit after the rc-134 rewrite | 0 / 0 / 0 |
| Headless probe (migration, gates, M sheet, waystones, vote, intro, reload) | **49 passed, 0 failed** |
| `--open-world --start --seconds 3` | process exit 0; the loaded identity is mixed (bug 4) |
| Asset, credit, element-tree, world-map, and path lints | pass (run on their own; the full script never reached them) |
| `SCRIPT ERROR` lines | none in the unit log, the playtest log, the probe log, or the co-op logs |

The full script exits on the first Godot failure, so its built-in smokes, solo run, Labyrinth run, co-op run, and lints did not execute inside that process. Those legs were run afterwards, except `--classic`.

## Bugs

Parked for discussion. Severity is high when a 0.4.0 path cannot finish, medium when a dev path or a finished slice is wrong or crashes, low when a test or an edge case is stale and play still recovers.

### 1. High — the Labyrinth playtest stops because closed levels have no open world

The Breach slice completes. The bot then refuses the Labyrinth.

Repro:

```
PLAYTEST_LABYRINTH=1 tools/playtest.sh
```

Log (`LAB_EXIT=1`):

```
[playtest] FAIL the Labyrinth needs the open world kills 50, pickups 56, casts 107, crafted Basic Pyrowning Fire Staff + Uncommon Moss & Berg Earth Wand, saves 2, deaths 0, teleports 0, level 5, 448 s simulated
```

`PlaytestBot._lab_tick` finishes the run when `main` has no `OpenWorld` node. The closed-level crater portal itself still enters floor 1 (probe: `death during labyrinth enter: floor 1 busy false alive false frames 1`, with no script error).

### 2. Medium — joiner teardown crash, reported as rc 134, on 2 of 3 co-op runs

`tools/coop_playtest.sh`, three separate `XDG_DATA_HOME` directories. Raw status was printed before the script rewrites 134 to 0.

| Run | Host raw | Joiner raw | Gameplay | Script exit |
|---|---|---|---|---|
| 1 | 0 | 134 (shell: `Aborted`) | both PASS | 0, with the rc-134 warning |
| 2 | 0 | 0 | both PASS | 0 |
| 3 | 0 | 134 (shell: `Aborted`) | both PASS | 0, with the rc-134 warning |

Run 1 host: kills 53, deaths 0, 525 s simulated. Joiner: kills 26, level 2, 750 s simulated.
Run 2 host: kills 54, deaths 1, 502 s simulated. Joiner: kills 35, including `breach_warden`, 906 s simulated, clean exit.
Run 3 host: kills 54, deaths 1, 509 s simulated. Joiner: kills 27, level 2, 674 s simulated.

On both rc-134 runs the joiner log reaches PASS and a character save, then Godot's crash handler runs. The same stripped backtrace appears both times (load address `400000`; frames `libc+0x45330`, godot `0x2b511d8`, `0x5661f9`, `0x42c157`, `__libc_start_main`, godot `0x48a6da`). The official binary has no symbols, so the frames do not resolve. The shell reports `Aborted`, which is why the status is 134 (128+SIGABRT) even though the handler's first line is signal 11. These logs do not contain the glibc `corrupted size vs. prev_size` line the script comment describes.

```
[playtest] PASS kills 26, pickups 0, casts 144, crafted , saves 1, deaths 0, teleports 0, level 2, 750 s simulated
[playtest] coop totals { "hits_sent": 226, "hits_applied": 0, "snaps_seen": 4672, "poses_seen": 4672 }
[coop] session ended: host left
[save] character user://character_joinbot.json: OK
handle_crash: Program crashed with signal 11
Engine version: Godot Engine v4.7.2.stable.official (ed1daf0bf001b61586d9930840f2f1394092c079)
```

The slice itself finished on every run: both bots logged PASS through the Breach. The host process was 0 every time. `coop_playtest.sh` treats 134-after-PASS as a warning and exits 0, so a green script run can still hide this crash.

### 3. Medium — open-world travel card lists alias stones and calls the Warrens the Landfill

`tests/unit/test_world_map_screen.gd::test_travel_card` fails with `deep points; attuned points only`.

`WorldMapScreen.card_lines("warrens_hall")` returned:

```
["The Warrens - Goblin King's Hall", "Region: The Landfill", "Lv 5-12"]
```

The test expects `Region: The Warrens`. `FastTravel` maps `warrens_hall` to level `labyrinth`, and `WorldMap.LEVEL_REGION["labyrinth"]` is `landfill`, whose region name is The Landfill. The `"The Warrens"` fallback in `card_lines` never runs.

After `attune("landfill")`, the open-world travel list is three buttons: `landfill`, `landfill_camp`, `landfill_overlook`. `attuned()` goes through `canon()`, so the camp and overlook aliases share the landfill flag, and `WorldTravel.points()` lists every marker id. The test expects a single `landfill` button.

The closed-level crystal list stayed `town_gate,breach` in the probe, and an in-game crystal travel requested the Breach with `load_save` true. This failure is the dev map and any caller that treats alias ids as separate attunements.

### 4. Medium — world cells are one static node ahead of the town scene

`tests/unit/test_world_streamer.gd::test_cells_fresh`:

```
cells hold every static node (547 vs 546): rerun tools/build_cells.gd
```

The east-gate oak was removed from `scenes/levels/town_square.tscn`. `world/cells` was not rebuilt, so the cell set still has one extra static node. Closed levels do not load those cells. `--open-world` does.

### 5. Medium — `--open-world` boots, with the intro, the level id, and the player in different places

```
godot --headless --path . -- --open-world --start --seconds 3
```

Exit 0. The log then says all of the following in one boot:

```
[world] start inside mage_association
[flow] level old_oak, gate to breach
[enemies] 4 spawned (earth_training_dummy, water_training_dummy, gnawer, heap)
[nav] Level navmesh: 0 polygon(s), 0 bake(s)
[waves] 3 wave(s) (gnawer_pack, flank, the_filth), trigger r 4.0 m at (576.0, 0.0, -241.5)
[main] level old_oak, 0 boxes, player at (0.0, -1999.5, 10.5), eye (0.0, -1998.0, 10.5)
[intro] beat summoning in mage_association
```

The flag still builds a world. The fresh-intro session starts in the Association hall, `GameFlow` names the level `old_oak` and installs a Breach gate, the Filth wave set is the midden roster out in the world, and the player stands at the interior depth (y about -2000). A full-suite case, `test_fast_travel_from_start_interior_is_first_load`, logged `[intro] beat summoning in breach` after its own trip and still passed its assertions.

### 6. Low — co-op protocol test still expects protocol 4

`tests/unit/test_coop.gd::test_element_status_mods_reach_host`:

```
FAIL test_coop.gd::test_element_status_mods_reach_host: protocol 4 (0.3.2 level scaling); 0.3.1 builds can't join
```

`NetSession.PROTOCOL` is 5 and `version()` ends in `/p5`. That bump is the 0.4.0 co-op change. The test still checks `== 4` and `ends_with("/p4")`.

### 7. Low — a gate vote treats a disconnected body as the party

Probe, two voters, host at the gate, joiner ("Ada") 40 m away. The vote starts at 15.00 s and is still waiting at 1.00 s with missing `["Ada"]`. `GateVote.VOTE_S` is 15.

Dropping peer 2 from the roster while the avatar node stays in the tree:

```
OBS   after roster drop, avatar still far: party 1 left 0.80 missing ["Ada"] decided []
```

`party_size()` falls to 1. `missing()` still counts the puppet, so the vote keeps waiting. Freeing that avatar, then one `tick(0.2)`:

```
[gate] party ready for midden
OBS   after avatar freed: party 1 left -1.00 missing [] decided ["midden"]
```

`tick` completes when `missing()` is empty. It does not look at `party_size()` again after `begin`. A disconnect that frees the body ends the vote immediately. A disconnect that leaves the puppet waits out the timeout.

### 8. Low — a dead player can still change level

Probe, Town Square, health saved at 17. Reload stayed in Town Square at 17.0.

`health.take(100000)` and then the grove gate:

```
OBS   gate.use while dead -> true, requested level old_oak, alive false
```

`SaveGame.apply` replaces health at or below 0 with full health on the next load, so a corpse save is not stuck. The gate itself accepts the dead player.

The labyrinth portal plus a lethal hit entered floor 1 on the next frame (`busy false`, `alive false`). The respawn timer was not given time to run. No script error.

### 9. Low — the joiner logs a successful gate vote as cancelled

On every closed-level change in the co-op logs the host prints `party ready for <level>` and the joiner prints `the level-change vote was cancelled`. The party still changes level.

`GateVote.tick` sends `gate_vote` with `t: -1` both when the vote completes and when `cancel()` runs. The joiner treats every `t < 0` as a cancel (`gate_vote.gd` `_on_message`).

## What passed

Headless probe, 49 checks, 0 failures:

- A v2 world save migrates to linear v3. `user://slot1.pre_linear.json` is written once, has no `linear_v`, keeps the fog string, and its bytes still match after a second store. `world_pos` and the labyrinth floor are kept. `town_market` folds into `town_gate`, `landfill_overlook` into `landfill`. A character file is skipped. A Breach position without the story flags lands in `town_square`. `filth_defeated` keeps the Breach.
- The Old Oak road stays locked until `home_unlocked`. The grove has no stash and `can_respec()` is false. Town Square has the stash and respec. The landfill gate stays locked until `landfill_route_open`.
- M opens the campaign sheet on Town Square. Lines: `Eldoria, Town Square | Waystone: Eldoria | The Old Oak: Unseen | Eldoria, Town Square: Here | The Landfill: Unseen | The Breach: Unseen | The Breach Labyrinth: Unseen`. The sheet does not draw the Elyria atlas.
- Crystal destinations are `town_gate,breach`. In-game travel requests the Breach.
- A new game is `old_oak`. The summoning beat is authored there. Bob's lead beat is the Landfill (`midden`). The grove cast is Elder, Clerk, Summoned Nerd, Summoned Gal, Summoned Buff, Crazy Joe (3 Summoned).
- A mid-level save reloads in Town Square at the saved health.

Solo playtest PASS: kills 50, pickups 57, casts 111, crafted Basic Pyrowning Fire Staff + Basic Moss & Berg Earth Wand, saves 2, deaths 0, teleports 0, level 5, 444 s simulated.

Both smokes exited 0. The menu smoke quit after 2.00 s on the menu.

Lints, run because the full script stopped early: `check_assets.py`, `gen_credits.py --check`, `gen_element_trees.py --check`, `gen_world_map.py --check`, `check_paths.py --self-test`, and `check_paths.py` all exited 0.

## Warnings, errors, and leaks

No `SCRIPT ERROR` or parse error in the unit log (5046 lines), the playtest log, the probe log, or the three co-op logs.

Unit-suite `ERROR` lines, 191 total: 91 + 91 are the known Terrain3D pair (`Resource file not found: res://` and `Error loading resource: ''`), which `run_tests.sh` already filters. The other 9 are the exit leaks below. The same Terrain3D pair is in the smoke, solo, Labyrinth, open-world, probe, and co-op logs, once per terrain init.

Exit leaks, printed because the unit process exited 1. There is no master baseline in this run, and the renderer is the headless dummy, so these are recorded and not claimed as new:

```
ERROR: Pages in use exist at exit in PagedAllocator: N20RasterizerSceneDummy21GeometryInstanceDummyE
WARNING: Leaked instance dependency: Bug - did not call instance_notify_deleted when freeing.   (6 times)
ERROR: 2 RID allocations of type '10NavAgent3D' were leaked at exit.
ERROR: 4 RID allocations of type 'P11JoltShape3D' were leaked at exit.
ERROR: 2 RID allocations of type 'P10JoltBody3D' were leaked at exit.
ERROR: 10 RID allocations of type 'N13RendererDummy15MaterialStorage13DummyMaterialE' were leaked at exit.
ERROR: 2 RID allocations of type 'N13RendererDummy15MaterialStorage11DummyShaderE' were leaked at exit.
ERROR: 6 RID allocations of type 'N13RendererDummy9DummyMeshE' were leaked at exit.
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
WARNING: 128 ObjectDB instances were leaked at exit
ERROR: 28 resources still in use at exit
```

Other warnings in the unit log, all pre-existing noise as far as this pass can tell:

| Count | Warning |
|---|---|
| 112 | `border_size is ceiled to cell_size` during Breach nav rebakes |
| 25 | Navigation region synchronization edge errors (2–8 edges) |
| 5 | `LevelNavigation breach_slice: no fresh nav cache, baking 20 tiles` |
| 2 | `Nodes with non-equal opposite anchors will have their size overridden` (during `test_travel_card`) |
| 1 | `instance_reset_physics_interpolation() is deprecated` (`terrain_zone.gd` build) |
| 1 | `Jolt Physics job system exceeded the maximum number of jobs` |
| 1 | `inventory: dropped bad item code` |
| 2 | character-save refusals the tests expect (`user://save.json`, a test host world) |

The solo and Labyrinth playtests repeat the nav edge warnings, the Breach nav-cache bake, and the `border_size` warning. Co-op runs repeat the Terrain3D pair and the nav edge warning.
