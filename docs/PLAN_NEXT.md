---
title: 0.6.0 Trust the Closed Levels - Plan
type: fix
date: 2026-11-04
product_contract_source: ce-plan-bootstrap
origin: docs/LINEAR_LEVELS_PLAN.md
---

# 0.6.0 Trust the Closed Levels - Plan

ShobieShy approved this on 2026-11-04: 0.6.0 is the trust pass, with the defaults below.

Master at the time of the plan was `6901190` (PR #6). The campaign is closed levels.

## Goal Capsule

**Objective:** A co-op party can finish the existing closed-level slice, and `tools/run_tests.sh` can run its full list, without a known wrong vote, a dead player changing level, a Landfill travel list that is three stones, or a Warrens card that says The Landfill.

**Means:** 0.6.0 takes the five parked bugs and the full-tier exit leak (KTD1). R1 may stay open if the joiner abort cannot be symbolicated. Act II, a drawn map, and new art wait.

**Authority:** [LINEAR_LEVELS_PLAN.md](LINEAR_LEVELS_PLAN.md) is the campaign. This file only picks what is next. Story, art, and music stay ShobieShy's.

**Stop:** Do not start Act II, a drawn map, mid-session join, or a PR #3/#4 merge inside 0.6.0. Do not bring back world cells, world terrain, or `--open-world`.

**Finish:** The implementer opens a PR. ShobieShy merges.

## Recommendation

**0.6.0 is a trust pass, not a new act.**

The five parked bugs are already reproduced in [BUGTEST_0.4.0.md](BUGTEST_0.4.0.md). The full test script stops on the first Godot failure, so a green unit count can still hide the rest of the tier. Act II needs a story and an art pass that are not in the repo. Fix the slice we have, then build the next act on a suite that finishes.

[LINEAR_LEVELS_PLAN.md](LINEAR_LEVELS_PLAN.md) section 9 still says 0.4.x is Act II and 0.6–0.9 is Act V. 0.4.0 and 0.5.0 already shipped as closed levels and the open-world cut. This plan uses **0.6.0** for the trust pass and leaves Act II as the following content milestone (0.7.0 unless ShobieShy wants that number).

## Product Contract

### Problem Frame

Players can walk Old Oak → Town Square → Landfill → Breach → Act I. Co-op can log PASS and still abort the joiner. A gate vote can finish because a disconnected body was freed. A dead player can take a gate. The Warrens travel card says The Landfill, and the alias list shows three Landfill stones. The full-tier script can stop before smoke, solo, Labyrinth, and co-op.

### Requirements

- **R1.** The joiner process exits 0 after a Breach co-op slice that logged PASS. If it still aborts, the PR includes a symbolicated trace and leaves R1 open. The existing rc-134 warning is not widened, and it does not close R1. U2–U5 can ship while R1 stays open.
- **R2.** The player-facing travel list has one Landfill entry. Attuning `landfill` does not add `landfill_camp` and `landfill_overlook` as extra buttons. Old saves that stored those ids still count as attuned to `landfill`.
- **R3.** The Warrens hall card says The Warrens, not The Landfill.
- **R4.** Freeing a disconnected joiner's body does not complete the gate vote. A peer who is still on the roster with `reconnecting` set stays missing, avatar or not. When the roster drops them at the end of the window, a host who is at the gate may proceed on the next tick. A peer who returns is missing until they are in range.
- **R5.** `LevelGate.use` does nothing when the user is dead (`alive` false). A living player still travels.
- **R6.** A completed gate vote is not logged on the joiner as cancelled. A real cancel still is.
- **R7.** `tools/run_tests.sh` with no flags runs the unit suite, both smokes, the solo playtest, the Labyrinth playtest, the co-op playtest, and the lints, unless a real test or a non-classified error fails. A named headless exit leak does not abort that sequence.

### Success Criteria

- Fast tier stays green: `tools/run_tests.sh --fast`.
- Full tier reaches the lint lines or fails on a real check, not on a classified exit leak.
- The five behaviors in R1–R6 match the tests in the units below.
- No new act, map art, or join protocol.

### Scope Boundaries

In 0.6.0: R1–R7.

Deferred until ShobieShy asks: Act II and later, a drawn per-level map, mounting the minimap, mid-session join, merging PR #3 or PR #4.

Out of scope: open world, world cells, world terrain, `--open-world`, story rewrites, new music, balance numbers, save-format bumps beyond what R2 needs to keep old attunements.

### Assumptions

- The closed-level crystal list (`town_gate`, `breach`) from the 0.4.0 probe stays. R2 is the alias list, not a new set of destinations.
- Bug 1 in the bug test ("the Labyrinth needs the open world") was recorded at `e0d5840`, before the closed-level Labyrinth playtest commit. It is not one of the five parked bugs. If the full-tier Labyrinth run fails, that fails R7. It does not add an open-world fix to 0.6.0.
- Bugs 4 and 5 in that doc (`--open-world`, stale world cells) describe a flag and a cell set that 0.5.0 deleted.
- `tests/unit/test_coop.gd` now expects protocol 5. The "protocol 4" failure in the bug test is stale.
- Headless exit leaks were seen when a failing unit process quit, before the open-world cut. The fast tier on the linear branch did not trip `run_clean`. R7 starts by running the full script once and classifying whatever it still prints.
- Effort words in this plan mean change size, not calendar time. Small: one behavior, existing tests. Medium: a few files plus a co-op or full-tier run. Large: new act content, art, or a protocol.

## Options

### (a) Parked bugs

**Scope.** Five behaviors in [BUGTEST_0.4.0.md](BUGTEST_0.4.0.md) sections 2, 3, 7, 8, and 9. Files: `scripts/net/coop_world.gd`, `scripts/net/gate_vote.gd`, `scripts/world/level_gate.gd`, `scripts/world/fast_travel.gd`, `scripts/world/world_travel.gd`, `scripts/world/world_map.gd`, `scripts/ui/world_map_screen.gd`, `tools/coop_playtest.sh`.

**Risk.** rc 134 is intermittent (2 of 3 runs), after PASS, signal 11, official binary with no symbols. A wrong vote fix can travel without a reconnecting friend or wait forever. Collapsing Landfill aliases must not drop attunement on old saves.

**Effort.** Four bugs are small. rc 134 is medium and may stay parked under R1's second clause.

**Tests.** Extend `tests/unit/test_gate_vote.gd`, `tests/unit/test_world_map_screen.gd`, `tests/unit/test_flow.gd` or `tests/unit/test_linear_flow.gd`. Co-op: `tools/coop_playtest.sh` three times, joiner raw status recorded.

**Recommend.** Do this in 0.6.0.

### (b) Full-tier script stops on headless exit leaks

**Scope.** `tools/run_tests.sh` `run_clean` fails the process on any `ERROR:` line except the Terrain3D `res://` pair, and the script uses `set -e`, so the first Godot failure skips later legs. The bug test listed nine exit lines (dummy RID leaks, Jolt bodies, nav agents, "resources still in use") on a unit process that exited 1.

**Risk.** Filtering too wide hides a real error. Filtering nothing leaves the full tier unable to report Labyrinth and co-op.

**Effort.** Small once the lines are reproduced on current master. Medium if the leaks are nodes we fail to free.

**Tests.** One full `tools/run_tests.sh`. The log either has no unclassified `ERROR:` lines, or the classified lines are named in [TEST_TIERS.md](TEST_TIERS.md) and the later legs still run. A new `SCRIPT ERROR` still fails the run.

**Recommend.** Do this in 0.6.0, after one confirming run. Classify engine exit noise the way Terrain3D is classified. Free a leak only when it is one of our nodes.

### (c) Labyrinth Act II

**Scope.** Act I is `data/labyrinth/warrens.toml` plus `scripts/labyrinth/*`. Act II, Overgrown Deep, is a name in [LABYRINTH_PLAN.md](LABYRINTH_PLAN.md) only. A real act is a kit, floors 1–4, a boss floor, loot, a waystone back to Town Square, and the hub gate offering that act. No shortcut gate in another region.

**Risk.** Look, encounter text, and music are not specified. Building them here would invent story.

**Effort.** Large. New data, generation fixture, floor tests, and a playtest route.

**Tests.** A golden fixture next to `tests/fixtures/labyrinth/warrens_golden.txt`, floor and stairs tests in the labyrinth unit files, and `PLAYTEST_LABYRINTH=1 tools/playtest.sh` extended only after the kit exists.

**Recommend.** Not 0.6.0. Next content milestone after the trust pass, and only after ShobieShy locks the act.

### (d) Drawn per-level map

**Scope.** M on a closed level draws text from `WorldMap.level_lines` (`scripts/ui/world_map_screen.gd` `_draw_linear`). `world/map.png` is the old Elyria sheet and is not what M shows in play. A drawn map is a per-level image, pins, and the player arrow on that image.

**Risk.** Art direction. A placeholder atlas would ship a second unfinished map.

**Effort.** Medium for wiring once an image exists. The image is the large part, and it is art.

**Tests.** `tests/unit/test_world_map_screen.gd` and `tests/unit/test_linear_flow.gd` (the sheet lists the campaign and marks Here).

**Recommend.** Defer. The text sheet already tells the player where they are.

### (e) ZoneStreamer and the minimap

**Scope.** `ZoneStreamer` is on `Pois` in `scenes/levels/town_square.tscn`, `old_oak.tscn`, `midden.tscn`, `breach.tscn`, and `mage_association.tscn`. `QualityPresets` sets prop ranges through it. The Landfill is large enough that distant props detach. `tests/unit/test_zone_streamer.gd` covers that. `Minimap` (`scripts/ui/minimap.gd`) is not added by `scripts/core/main.gd`. The setting `minimap_north` remains.

**Risk.** Removing ZoneStreamer changes what the Landfill draws and what the quality presets do. Mounting the minimap without a per-level image puts the old Elyria texture on the HUD.

**Effort.** Keeping both is no work. Removing ZoneStreamer is medium (scenes, generator, presets, tests). Mounting the minimap is small and the wrong picture.

**Tests.** Leave `tests/unit/test_zone_streamer.gd` and `tests/unit/test_minimap.gd` as they are.

**Recommend.** Keep ZoneStreamer. Leave the minimap unmounted until a drawn per-level map exists.

### (f) Mid-session join

**Scope.** A new peer can join from the lobby. `scripts/net/net_session.gd` rejects a hello with "the game has already started" once the session is in game. A dropped peer has a reconnect window (`scripts/net/coop_flow.gd`). There is no "join this level now" for a new friend after the host has started.

**Risk.** Protocol bump, spawn-into-combat, and gate-vote membership. Easy to desync the floor.

**Effort.** Large.

**Tests.** Would need new cases in `tests/unit/test_coop.gd` and `tests/unit/test_coop_flow.gd`, plus a co-op playtest that joins after the host has left the lobby.

**Recommend.** Defer. Lobby join and reconnect stay as they are.

### (g) PR #3 and PR #4

Both are still open against `master` and were written for the open-world line.

**PR #3** ([0.3.4: playtime, Labyrinth prewarm, and S8 notes](https://github.com/ShobieShy/covenant-of-embers/pull/3), branch `cursor/covenant-0-3-4-13fa`). Playtime on save cards, a Labyrinth shader prewarm, S8 notes, and a latency check. The diff touches `scripts/world/shader_warmup.gd`, which 0.5.0 deleted, plus `main.gd`, save, net, and menu files that have moved. Merging it as a branch would resurrect the warmup file and fight later edits.

**PR #4** ([Align the Old Oak with the map](https://github.com/ShobieShy/covenant-of-embers/pull/4), branch `cursor/oak-map-intro-cast-cfe7`). It fixes open-world coordinates and edits `world/cells/0_0.tscn`, which is gone. The placement intent (Joe and the Summoned in the summoning, no second oak east of town) may still matter in level-local space. The cell and world-offset edits must not return.

**Risk.** A merge reintroduces deleted world data or a deleted script. Cherry-picking without a read copies open-world assumptions into closed levels.

**Effort.** Small to decide. Medium to port playtime, or the summoning placement, as their own changes later.

**Tests.** Do not use either PR's suite as the linear suite. A later port of playtime would extend `tests/unit/test_save.gd` and `tests/unit/test_menu_polish.gd`. A later placement check would extend `tests/unit/test_intro_association.gd`.

**Recommend.** Do not merge either. Close PR #4. Leave PR #3 closed or open only as a reading list: playtime and the S8 notes can be ported later if ShobieShy still wants them. The Labyrinth prewarm needs a new place to live; `ShaderWarmup` is gone.

## Planning Contract

### Key Technical Decisions

**KTD1. 0.6.0 is the trust pass.** Chosen over starting Act II, because the act has no kit and the full script cannot sign a new act off. Act II remains the campaign's next content, after this.

**KTD2. Classify exit leaks; do not silence every ERROR.** `run_clean` keeps failing on `SCRIPT ERROR` and on any `ERROR:` line not named in [TEST_TIERS.md](TEST_TIERS.md). Named headless-exit lines are the only addition, and only after a full run on current master shows they still print.

**KTD3. Keep ZoneStreamer. Do not mount the minimap.** The streamer is live level behavior. The minimap has no per-level image.

**KTD4. Do not merge PR #3 or PR #4.** Port playtime or summoning placement only as a later, separate change after ShobieShy asks.

### Sequencing

1. Confirm the full script on current master (U1).
2. Vote, gate, and travel-list fixes, which do not depend on the crash (U2–U5).
3. Joiner exit, which needs the co-op playtest and may end as "still parked" (U6).
4. Update [TEST_TIERS.md](TEST_TIERS.md) and [LINEAR_LEVELS_PLAN.md](LINEAR_LEVELS_PLAN.md) section 9 so 0.6.0 is this pass and Act II is next (U7).

### High-Level Technical Design

Directional only. The implementer chooses the exact messages.

Gate vote, three outcomes the joiner must be able to tell apart:

```
host starts vote → joiner shows the countdown
host: party ready → joiner logs ready, then the level changes
host: cancel, or someone walks away → joiner logs cancelled, level stays
```

A dropped peer is not "ready". They stay on the roster with `reconnecting` set until that window ends. Freeing their avatar does not clear `missing`.

Travel names:

```
attune landfill → one list row, "The Landfill"
card for warrens_hall → region "The Warrens"
old save with landfill_camp → still attuned to landfill
```

## Implementation Units

### U1. See why the full script stops

**Goal:** Know which lines, if any, still abort `tools/run_tests.sh` on master `6901190`.

**Requirements:** R7

**Files:** `tools/run_tests.sh`, `docs/TEST_TIERS.md`

**Approach:** Run the full script once. If it finishes, R7 is already true and U7 only records that. If it stops on exit leaks, list the exact lines and add only those to the filter, next to the Terrain3D pair. Do not filter a line that names a script error.

**Test scenarios:**

- Happy path: a full run prints `[run_tests] all green (full)` or fails on a test assertion.
- Edge: the Terrain3D `res://` pair still does not fail the run.
- Error: a planted `SCRIPT ERROR` line fails the run.

**Verification:** The log of that one full run is the evidence. Paste the exit code and the last `[run_tests]` line into the PR.

### U2. One Landfill row, Warrens region

**Goal:** R2 and R3.

**Requirements:** R2, R3

**Files:** `scripts/ui/world_map_screen.gd`, `scripts/world/world_map.gd`, `scripts/world/world_travel.gd`, `scripts/world/fast_travel.gd`, `tests/unit/test_world_map_screen.gd`

**Approach:** The list the player sees uses canonical point ids. `landfill_camp` and `landfill_overlook` share the landfill attunement and do not get their own buttons. `card_lines("warrens_hall")` reports The Warrens. `canon()` still maps the old ids so a migrated save stays attuned.

**Execution note:** `test_travel_card` currently expects three Landfill buttons and `Region: The Landfill` for `warrens_hall`. Change that test first and see it fail for the new expectation, then make it pass. Do not weaken it back to the bug.

**Test scenarios:**

- Happy path: after `attune("landfill")`, the travel list has one `landfill` button. `card_lines("warrens_hall")` line 2 is `Region: The Warrens`.
- Edge: `attune("landfill_overlook")` still allows travel to `landfill` and does not add a second button.
- Error: an unknown point still does not travel.
- Integration: the closed-level crystal destinations remain `town_gate` and `breach` for a fresh attune of those stones.

**Verification:** `TEST_ONLY=test_world_map_screen.gd,test_linear_flow.gd godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd`

### U3. A freed body does not pass the vote

**Goal:** R4.

**Requirements:** R4

**Files:** `scripts/net/gate_vote.gd`, `tests/unit/test_gate_vote.gd`

**Approach:** `missing` follows voters, not a node that happens to be gone. Today `scripts/net/net_session.gd` keeps a dropped peer on the roster with `reconnecting` set for `CoopFlow.RECONNECT_S` (30 s), and `scripts/net/coop_world.gd` frees the avatar when that roster entry is erased. `GateVote.missing` is "avatars farther than 8 m", so a freed avatar makes `missing` empty and `tick` decides at once. The fix: a roster member with `reconnecting` set stays missing after the avatar is freed. Erasing that member, the way the reconnect timeout does, lets a host who is at the gate proceed on the next tick. The existing 15 s vote timeout still decides. Walking away still cancels.

**Execution note:** Add the failing test before changing `tick`.

**Test scenarios:**

- Happy path: two voters, both at the gate, vote completes and the level is the one the host chose.
- Edge: joiner still on the roster with `reconnecting` set, avatar freed, one `tick` does not decide. After that roster entry is erased, one `tick` decides if the host is in range.
- Error: the joiner walks back out of range and the vote cancels, same as today. A full `VOTE_S` (15 s) with someone still missing still decides, as it does now.
- Integration: a peer who returns during the window is missing until they are within range. They are not treated as already at the gate.

**Verification:** `TEST_ONLY=test_gate_vote.gd godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd`

### U4. Dead players do not take gates

**Goal:** R5.

**Requirements:** R5

**Files:** `scripts/world/level_gate.gd`, `tests/unit/test_linear_flow.gd` or `tests/unit/test_flow.gd`

**Approach:** `use` returns without emitting when the overlapping player is dead. A living player still emits. The Breach crater portal is `GateLabyrinth`, also a `LevelGate`, so the same check covers it. Do not change the save rule that refills a health value at or below 0 on the next load.

**Execution note:** Test first. The bug test's observation is `gate.use while dead -> true`.

**Test scenarios:**

- Happy path: a living player uses the Town Square gate toward the Old Oak and travel is requested.
- Edge: health taken to 0, then `use`, returns false and does not request a level.
- Error: a dead player at the Labyrinth portal does not enter floor 1 on that press.
- Integration: after a normal death and respawn, the same gate works again.

**Verification:** the unit file chosen above, headless, fixed 60 fps.

### U5. Joiner vote log

**Goal:** R6.

**Requirements:** R6

**Files:** `scripts/net/gate_vote.gd`, `tests/unit/test_gate_vote.gd`

**Approach:** Ready and cancel are different messages. The joiner prints cancelled only for cancel. Today `t: -1` means both, and `_on_message` treats every negative `t` as cancel.

**Depends on:** U3, same file.

**Test scenarios:**

- Happy path: host completion delivers a ready message; the joiner's log line is the ready line, not "cancelled".
- Edge: a cancel still logs cancelled and does not load the next level.
- Error: an unknown vote message is ignored.

**Verification:** same command as U3.

### U6. Joiner exit after the Breach

**Goal:** R1.

**Requirements:** R1

**Files:** `scripts/net/coop_world.gd`, `scripts/core/playtest_bot.gd`, `tools/coop_playtest.sh`, `docs/TEST_TIERS.md`

**Approach:** Reproduce with three co-op runs and record raw joiner status before `tools/coop_playtest.sh` rewrites 134 to 0. If all three are 0, R1 is met. If 134 remains, trace `prepare_shutdown` and the quit order on a symbolicated Godot when one is available. Do not widen the warning. If the only binary on hand is the official one and the frames do not resolve, the PR says that, pastes the three raw statuses, and leaves R1 open. U2–U5 still ship.

**Test scenarios:**

- Happy path: three `tools/coop_playtest.sh` runs, private `XDG_DATA_HOME` each, host and joiner raw status 0, both logs contain `[playtest] PASS`.
- Edge: a short session (`COE_PLAYTEST_MAX_S`) still exits 0, as [TEST_TIERS.md](TEST_TIERS.md) already says.
- Error: a run that fails gameplay still fails the script. Rewriting 134 to 0 after PASS does not count as R1.

**Verification:** the three raw statuses in the PR. Fast tier does not need to repeat the long co-op slice.

### U7. Write the milestone down

**Goal:** The campaign doc matches 0.6.0.

**Requirements:** R7

**Files:** `docs/LINEAR_LEVELS_PLAN.md` section 9, `docs/TEST_TIERS.md` if U1 added a filter

**Approach:** Section 9 says 0.6.0 is this trust pass and the next content milestone is Act II. Delete the line that calls 0.6–0.9 Act V, or move Act V to the slots after Act II. Do not change save or combat numbers.

**Test expectation:** none. Doc only. U1's full run is the check that the test doc matches the script.

## Verification Contract

- Fast: `tools/run_tests.sh --fast` green.
- Targeted units: the `TEST_ONLY=...` commands on U2–U5.
- Full: `tools/run_tests.sh` once at the end. This is the R7 proof.
- Co-op raw statuses from U6, separate from the fast tier.

Known Terrain3D `res://` pair stays filtered. New classified exit lines, if U1 adds any, are listed in [TEST_TIERS.md](TEST_TIERS.md) by their exact text.

## Definition of Done

- R1 is three clean joiner exits, or it stays open in the PR with a symbolicated trace or a stated lack of symbols. It is not a quieter warning.
- R2–R6 have the tests above, and those tests fail if the behavior is reverted.
- R7: one full-tier log that reaches the end or fails on a real check.
- No Act II kit, no new map image, no PR #3 or #4 merge, no world-cell files.
- Abandoned debug changes are not in the diff.

## Decisions for ShobieShy

These are his. The defaults above are what this plan will follow if he says nothing else.

1. **Is 0.6.0 the trust pass, or is 0.6.0 Act II?** Default: trust pass. Act II has no kit, and story, look, and music are his.
2. **Act II brief, when he wants it.** Overgrown Deep's rooms, enemies, and any music. Not part of 0.6.0.
3. **A drawn per-level map.** Default: keep the text sheet. Art is his.
4. **ZoneStreamer and the minimap.** Default: keep the streamer, leave the minimap off the HUD.
5. **Mid-session join.** Default: not now. Friends join from the lobby; a dropped friend can reconnect.
6. **PR #3.** Default: do not merge. Say if playtime on the save card, or the S8 notes, should be ported later. The shader prewarm cannot land on the deleted `ShaderWarmup` script.
7. **PR #4.** Default: close it. Say if Joe and the Summoned are still standing in the wrong place in the closed-level summoning; that would be a small later port, without world cells.

## Sources

- [LINEAR_LEVELS_PLAN.md](LINEAR_LEVELS_PLAN.md) on master `6901190`
- [BUGTEST_0.4.0.md](BUGTEST_0.4.0.md), sections 2, 3, 7, 8, 9 for the parked bugs; sections 1, 4, 5, 6 treated as stale or obsolete as noted above
- [LABYRINTH_PLAN.md](LABYRINTH_PLAN.md) Act II name only; kit is `data/labyrinth/warrens.toml`
- [TEST_TIERS.md](TEST_TIERS.md), `tools/run_tests.sh`
- PR #3 and PR #4 file lists from GitHub, not merged
- No external research. The behaviors are local.
