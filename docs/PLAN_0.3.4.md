# 0.3.4 leftovers

Three items ShobieShy approved on top of 0.3.2 and 0.3.3. Act II, the intro, and music
are out of scope. This branch is not the release cut: `project.godot` stays
`0.3.3-prealpha`. Set `0.3.4-prealpha` when this ships as the release line.

## 1. Save-slot playtime

Save-slot cards now show cumulative playtime (`1h 23m`). `SaveGame.VERSION` stays 1.
`playtime_s` is an optional top-level number; `read()` already returns the whole JSON
object and only checks `version`, so old saves load as 0 seconds.

`Main.play_seconds` starts from that field and advances while the game scene is
unpaused. `save_game()` and level travel write it back. Under a minute (or a missing
field) the card omits the line, so an old slot still shows character, place, and save
time. Formatting is `0m`, `23m`, or `1h 23m` (`SaveGame.format_playtime`).

## 2. First Labyrinth floor hitch

The first floor compiled warrens and goblin shaders on the frame they appeared (about
60 ms in the 0.3.1 notes). `Interiors._enter_floor` now calls
`ShaderWarmup.warm_labyrinth` after the loading screen is up and before the floor is
parented. That draws each warrens glb, each Act I goblin, a plain material, an emissive
material, and one torch light for a few frames, the same idea as the open-world warmup.

Headless Godot uses the dummy renderer, so this environment cannot time the hitch.
`tests/unit/test_warrens_kit.gd` checks the mesh list and that the headless call returns
0. A GPU capture is `tools/perf_cold.sh` (see `docs/TEST_TIERS.md`).

## 3. S8 balance and the latency conditioner

Curves stay locked: HP `1.09` cap x60, damage `1.07` cap x25. The fixture is
`tests/unit/test_level_scale.gd` (`test_s8_hits_and_time_to_die`). Spell is an
Apprentice Fire Staff bolt (10, chart and resist applied). Burst time-to-die spends
naked health 100 + shield 50 with no shield regen. Solo zone floors apply, and bosses
keep +2.

`today_hits` is scaling off. `same_*` is the player at the enemy's authored level.

| Enemy | L0 | today hits | same-level hits | same bite | L1 hits / bite / TTD | L25 hits / bite / TTD | L50 hits / bite / TTD |
|---|---:|---:|---:|---:|---|---|---|
| Gnawer | 1 | 2.00 | 2.00 | 3.00 | 2.00 / 3.00 / 40.00 s | 2.27 / 15.22 / 7.89 s | 2.65 / 75.00 / 1.60 s |
| Heap | 3 | 10.00 | 8.42 | 8.00 | 10.00 / 8.00 / 37.50 s | 9.46 / 35.44 / 8.46 s | 12.51 / 192.37 / 1.56 s |
| Breach Warden | 5 (+2) | 40.00 | 34.01 | 13.74 | 40.00 / 12.00 / 25.00 s | 37.83 / 53.16 / 5.64 s | 41.57 / 252.03 / 1.19 s |
| Goblin grunt | 5 | 5.33 | 3.78 | 8.00 | 5.33 / 8.00 / 20.62 s | 4.20 / 30.96 / 5.33 s | 5.54 / 168.02 / 0.98 s |
| Goblin King | 12 (+2) | 120.00 | 55.81 | 20.61 | 120.00 / 18.00 / 18.33 s | 59.73 / 49.66 / 6.64 s | 65.28 / 235.43 / 1.40 s |

Gnawer hits stay near two bolts from level 1 to 50. The small rise is resist
(+0.5 % per level, 24.5 % at a 49-level gap), not the HP curve. At a gnawer's own
level, hits match an unscaled fight. Higher authored levels die in fewer hits than
today once the player has gained levels, because spell damage grows from level 1
(`1.09^(level-1)`) while an on-level enemy's pool stays at L0.

Time-to-die shrinks because player health does not grow (`HEALTH_PER_LEVEL` is 0) and
enemy damage still follows 1.07, up to the x25 cap (a level-50 gnawer bite is 75).
That is the locked curve against flat health, not a sign the rates are mistyped.
Setting damage growth to 1.0 would freeze every bite at its authored value and drop
the 0.3.2 default. A player-health curve is a separate decision. Caps stay x60 / x25.

Latency: `test_walk_stays_smooth_at_150ms_5pct` pushes a 6 m/s, 20 Hz walk through
`LinkConditioner` at 150 ms and 5 % loss into `NetInterp`. Result: 466 steps, 0 snaps,
0 jumps over 1 m, 3 poses dropped. Remote players and puppets print
`[net] player interp` / `[net] puppet interp` (steps, snaps, big) when a session ends.
The live co-op hook is `COOP_LAG=150 COOP_LOSS=0.05 tools/coop_playtest.sh`.
