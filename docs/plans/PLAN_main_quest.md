# Main quest chain, Acts I–V

Planning only. Written against master `af73cae` (v0.11.4-prealpha). No gameplay code in this change.

The ask is one working main-quest trail: each objective completes when the player actually does it, and a waypoint marks the next place until that objective is done, from the tutorial through Act V.

Standing rules stay in force. The Core stays closed. Music stays silent. The Drowned Choir stays one body. Save version stays 1. No new character, place, or item names. Names below are already in `data/story/quests.toml`, `docs/LABYRINTH_ACTS_STORY.md`, or `docs/COVENANT_OF_EMBERS_STORYLINE.md`.

The live version table is [PLAN_VISUAL_AUDIT.md](../PLAN_VISUAL_AUDIT.md). 0.12.0 is the Town remake. This work does not take that number and does not open the Core.

## Proposed version

**0.11.5-prealpha.** Four pull requests, version string bumped only on the last one.

| PR | What lands | Done when |
|---|---|---|
| 1 | Quest table and tracker order | Act I has a row. The Breach no longer ends on the Matriarch. The HUD follows the earliest open main step |
| 2 | Waypoint resolver | Every open main step resolves to a point in the current level, or to the exit that leads there. The mark hides when the step completes |
| 3 | Save repair and a debug jump | An old save still on version 1 repairs its step. A debug jump can stand the log at any main quest |
| 4 | Headless chain test, then the 0.11.5 bump | One test walks permit through the Storm Warden and checks the waypoint at each hop |

## What is on master today

### Data

`data/story/quests.toml` is the only quest table. `scripts/story/quest_log.gd` (`QuestLog`) loads it. It is not an autoload. `scripts/core/main.gd` builds one log, stores it on the game node, and saves it under `progress["quests"]`.

Objective kinds are `kill`, `collect`, `talk`, and `reach`. A step may set `count` (default 1) and `optional`. Steps run in order. `notify(kind, target)` advances only the current required step of each active quest. Optional steps are recorded and skipped so they never block completion. There is no parallel step and no multi-target step. A collect of three marks is one target id counted three times, not three places.

A quest's `kind` is `main` or `side`. Rows tagged `kind = "main"` stay main. Anything else is main unless the id is `joes_marks` or `joes_seals` (`quest_log.gd` `load_text`). Those two are the only side quests.

Auto-start: `auto_start_when` is a list of story flags. `check_auto_start` starts the quest when every flag is set. Two extra rules are not in the toml:

- `the_sunken_ruins` starts when `known_bosses` contains `forgemaw`.
- `the_inverted_spire` starts when `known_bosses` contains `drowned_choir`.

`known_bosses` is copied from the labyrinth save in `main.gd` and `main_labyrinth.gd`. Starting a boss quest whose boss is already in that list completes it immediately (`_seed_act2`, `_seed_act3`, `_seed_sunken`, `_seed_spire`). Marks and seals do the same from `mark:*` and `seal:*` flags.

Rewards are XP, dust, gold, flags, and one clue, applied inside `_complete`. There is no turn-in and no reward choice.

### Who feeds the log

`scripts/story/quest_driver.gd` sits on the game scene.

| Kind | Event | Target string |
|---|---|---|
| kill | `EventBus.enemy_killed` | the enemy def id (`gnawer`, `the_filth`, `goblin_king`, `blightmaw_matriarch`, `forgemaw`, `drowned_choir`, `storm_warden`, `breach_warden`) |
| collect | `EventBus.quest_item_collected` | item id (`joes_discards`, `joe_mark`, `slag_seal`) |
| reach | level enter, once per level visit | `FastTravel.LEVEL_POINT`, else the raw level id. `midden` becomes `landfill`. `bobs_lab` stays `bobs_lab` |
| talk | dialogue with that speaker ends (`main.gd` `_on_npc_talked`) | speaker name (`Bob`, `Verdant Mother`, `Scrap-spirit`) |

The intro is a second list. `IntroDirector.objective()` and `target_point()` place a gold `v` named `ObjectiveMarker`. The playtest bot walks to it. It is not a `QuestLog` step. `QuestMarker` hides itself while that intro mark is up.

### Waypoints, compass, minimap

There is no compass.

`scripts/story/quest_marker.gd` is one world `v` for `QuestLog.tracked`. `scripts/ui/minimap.gd` draws that same point as `quest_at`. `scripts/ui/world_map_screen.gd` has waystones and travel. It has no quest pin.

Resolution today (`QuestMarker._resolve`):

- `collect` returns nothing. The mark hides. Joe's Trash, the marks, and the seals never get a point.
- `talk` searches the current scene for an `Npc` with that speaker. Bob in the oak does not show while you are in the landfill.
- `kill` replaces the enemy id with a level id from `KILL_LEVEL` (Filth and Gnawer to `midden`; every labyrinth boss to `labyrinth`) and then looks for a door.
- `reach` looks for a `LevelGate` in the current scene whose `target` equals the objective target. If none exists, it uses the first `Waystone` in the scene.

That last fallback is why a kill step inside the Labyrinth marks the waystone home. The scene has no gate whose target is `labyrinth`, because you are already there. The marker never looks at `BossSpawn`, a stair, or the next floor. It never asks which exit leaves this level toward a level you are not in. `RouteGraph` builds a walk for the playtest bot inside one level. The marker does not use it.

The mark updates when the tracked id or step index changes. Completing the step hides that point because the step index moves. Completing the quest clears `tracked` when no other main quest is active. A finished step does not leave a ghost mark. A step the resolver cannot see leaves no mark at all, which reads the same as "done" while the objective is still open.

`!` and `?` glyphs are placed once, in `_ready`, on NPCs whose `giver` matches an available quest. No current row sets `giver`, so the glyphs do not appear. `docs/release/CHANGELOG_0.9.2.md` already says that.

### Save and load

`SaveGame.VERSION` is 1. `QuestLog.to_dict` writes `active` (step, count, optional counts), `done`, `clues`, `tracked`, and a copy of the flags. `from_dict` drops unknown quest ids, keeps flags that are missing on the live flag set, and if `tracked` is empty or no longer active calls `_follow_main`, which picks the first active main quest in file order.

Loading does not re-check auto-start against bosses defeated while the quest row did not exist yet. A new row added later stays available until something calls `check_auto_start`. Level load does call it, via the flag signal and the labyrinth boss copy.

### Act transitions

These are the handoffs that exist. They are flags and boss ids, not a quest graph.

| Handoff | Where it is set | What starts |
|---|---|---|
| `permit_given` | intro grant, `intro_director.gd` | `a_new_home` |
| `starter_gear_given` | `mentor_arrival.gd` | `the_landfill` |
| `filth_defeated` | reward of `the_landfill` | `report_to_bob` and `the_breach` in the same pass |
| `verdant_met` | dialogue `verdant_intro`, speaker Verdant Mother | `the_overgrown_deep` and `joes_marks` |
| `scrap_met` | dialogue `scrap_intro`, speaker Scrap-spirit | `the_slagworks` and `joes_seals` |
| `forgemaw` in `known_bosses` | labyrinth save | `the_sunken_ruins` |
| `drowned_choir` in `known_bosses` | labyrinth save | `the_inverted_spire` |

`start` sets `tracked` to every new main quest. The Filth completion therefore starts Report to Bob, tracks it, then starts The Breach and tracks that instead. Report to Bob stays active and leaves the HUD. `tests/unit/test_quest_chain.gd` locks this: after the Filth, the tracked Breach step is `breach`, and talking to Bob does not change it.

`tests/unit/test_quest_chain.gd` loads the Association, the Town, the Old Oak room, the Landfill, and the Breach, then drives the log with `notify` only as far as "the Breach quest's current target is `blightmaw_matriarch`". It never kills the Goblin King, Forgemaw, the Choir, or the Storm Warden, and it never reads a waypoint.

## The chain

Status words: **works** means the row exists, the completion event fires, and a test covers that event. **Broken** means the row or the event exists and the player-facing trail does not follow it. **Missing** means the story asks for it and the quest table has no step.

### Before Act I

| Quest | Objectives | Completion | Waypoint | Status | Files |
|---|---|---|---|---|---|
| A New Home | Reach `old_oak` | Entering the level `old_oak` notifies `reach` / `old_oak` | Gate whose target is `old_oak` | Broken after 0.11.4 for the door players see. The east-lobe door opens `bobs_lab`. Entering the lab notifies `bobs_lab`, which is not the objective. The ring exit `to_old_oak` still targets `old_oak` and still completes the step | `quests.toml` `a_new_home`; `data/levels/town_square.toml` exit `to_old_oak`; `scripts/world/old_oak_landmark.gd` lab door; `fast_travel.gd` `LEVEL_POINT` |
| Trash Talk | Reach `landfill`; kill 3 `gnawer`; kill `the_filth`; collect `joes_discards` | Reach maps `midden` to `landfill`. Kills use the enemy id. The Filth drops `joes_discards` | Reach and kill look for a gate to `midden`. The collect step has no mark, including the trash on the ground | Works as a log. Waypoint missing on the collect step | `quests.toml` `the_landfill`; `quest_driver.gd`; `filth.gd` `DROP_ID`; `test_tutorial.gd` |
| Report to Bob | Talk `Bob` | Dialogue end with speaker Bob | NPC named Bob in the current scene only | Broken on the HUD. The Breach steals `tracked` in the same flag pass, so the marker leaves Bob | `quests.toml` `report_to_bob`; `quest_log.gd` `start`; `test_quest_chain.gd` |
| The Breach | Reach `breach`; reach `labyrinth`; kill `blightmaw_matriarch` | Level enter, then a Matriarch kill | Gate to `breach`, then a gate to `labyrinth`, then the labyrinth-wide kill fallback | Broken as an Act I handoff. The third step is the Act II boss. The Breach Warden is a fight in the crater and is not a step | `quests.toml` `the_breach`; `test_quest_chain.gd` last checks; `LABYRINTH_ACTS_STORY.md` Act I opening |

### Act I — The Goblin Warrens

Story: after the crater, the Labyrinth gate opens. Floor 5 is the Goblin King's throne hall. His death lights a waystone home. The Fracture stays open.

| Piece | Status | Files |
|---|---|---|
| Floors and the Goblin King fight | Works as a level. Out of scope for this plan except as a waypoint target (`BossSpawn` on floor 5) | `scripts/labyrinth/labyrinth_floor.gd`; `tests/unit/test_goblin_king.gd` |
| Main quest | Missing. No row. `goblin_king` is a kill id the driver would accept. Nothing listens | `quests.toml` has no Act I id; `quest_driver.gd` `_on_killed` |
| Waypoint | Missing with the quest | `quest_marker.gd` `KILL_LEVEL` has no `goblin_king` entry |
| "Return home or go deeper" | Missing as objectives. The waystone and the downward gate exist as level machinery | `docs/COVENANT_OF_EMBERS_STORYLINE.md` Act I |

### Act II — The Blightcoil

Story: the Verdant Mother asks you to burn out the infection. Three of Joe's marks, then the Blightmaw Matriarch at the Crown. An empty cocoon. A door toward the Slagworks.

| Quest | Objectives | Completion | Waypoint | Status | Files |
|---|---|---|---|---|---|
| The Overgrown Deep | Kill `blightmaw_matriarch` | Kill event, or instant complete if she is already in `known_bosses` when the quest starts | `KILL_LEVEL` sends every labyrinth boss to a gate targeted `labyrinth`, else the first waystone | Broken waypoint. The log works only after `verdant_met`. Killing her before the talk does not start this row; The Breach's third step is the one that was already open | `quests.toml` `the_overgrown_deep`; `dialogue.toml` `verdant_intro`; `quest_log.gd` `_seed_act2`; `test_blight_story.gd` |
| Joe's Marks (side) | Collect 3 `joe_mark` | Pickup plus `mark:<id>` flags. Seeded if the flags already exist | Collect resolves to nothing | Works as a count. Waypoint missing. Not on the HUD unless Track is pressed | `blight_mark.gd`; `quests.toml` `joes_marks`; `test_quest_rules.gd` |

### Act III — The Slagworks

Story: the Scrap-spirit names Forgemaw. Three slag seals. Forgemaw's crucible. Empty slag cast. Waystone home.

| Quest | Objectives | Completion | Waypoint | Status | Files |
|---|---|---|---|---|---|
| The Slagworks | Kill `forgemaw` | Kill event, or instant complete if he is already known when the quest starts | Same labyrinth-gate fallback | Broken the same way as Act II. The row does not auto-start from his death. `forgemaw` in `known_bosses` starts Act IV, not this row | `quests.toml` `the_slagworks`; `dialogue.toml` `scrap_intro`; `quest_log.gd` `check_auto_start`; `test_slag_story.gd` |
| Joe's Seals (side) | Collect 3 `slag_seal` | Pickup plus `seal:<id>` flags | No mark | Works as a count. Waypoint missing | `slag_seal.gd`; `quests.toml` `joes_seals` |

### Act IV — The Sunken Ruins

Story in the outline also has hymn-shards and the dry prophet. Those lines are marked Open and unwritten in `COVENANT_OF_EMBERS_STORYLINE.md`. This plan does not add them.

The quest section of that storyline still says nothing asks you to face the Choir. That sentence is stale. The row shipped in 0.9.2.

| Quest | Objectives | Completion | Waypoint | Status | Files |
|---|---|---|---|---|---|
| The Sunken Ruins | Kill `drowned_choir` | Starts when Forgemaw is in `known_bosses`. Kill event, or instant complete if the Choir is already known | Labyrinth-gate fallback, not the Nave | Log works. Waypoint broken. One body, matching the standing rule | `quests.toml` `the_sunken_ruins`; `quest_log.gd` `_seed_sunken`; `test_quest_rules.gd` `test_sunken_starts_when_forgemaw_is_known` |

### Act V — The Inverted Spire

`COVENANT_OF_EMBERS_STORYLINE.md` still says Act V is not in the game. The act shipped in 0.11.0 (`docs/release/CHANGELOG_0.11.0.md`). The quest row is the same shape as Act IV.

| Quest | Objectives | Completion | Waypoint | Status | Files |
|---|---|---|---|---|---|
| The Inverted Spire | Kill `storm_warden` | Starts when the Choir is in `known_bosses`. Kill event, or instant complete if the Warden is already known | Labyrinth-gate fallback, not the Warden's platforms | Log works. Waypoint broken | `quests.toml` `the_inverted_spire`; `quest_log.gd` `_seed_spire` |

No Core quest. The Core stays closed. No Demon Lord step.

## What to build

### 1. Quest table

Edit `data/story/quests.toml` and the seed rules. No new ids that are not already creature or level ids.

- The Breach ends at `reach` / `labyrinth`. Drop the Matriarch step from that row. The Matriarch stays on The Overgrown Deep.
- Add one main quest for Act I, started when the player reaches `labyrinth`, with one objective: kill `goblin_king`. Title from the act name already in the story docs: The Goblin Warrens. The kill id `goblin_king` already exists.
- Keep Acts II–V on the rows they have. Act II and Act III still start from the Verdant Mother and the Scrap-spirit. If the boss is already dead when the talk happens, the seed complete stays.
- Also start `the_overgrown_deep` when `goblin_king` is in `known_bosses`, the same way Act IV starts from Forgemaw. Otherwise a player who never talks to the Verdant Mother has no Act II row after the King. The talk can remain the moment the side quest Joe's Marks starts.
- Same for `the_slagworks` when `blightmaw_matriarch` is known, so Act III does not depend on finding the Scrap-spirit before the objective exists. Joe's Seals still start at `scrap_met`.
- `start` stops overwriting `tracked` when an earlier main quest is still active. File order becomes the trail: A New Home, Trash Talk, Report to Bob, The Breach, The Goblin Warrens, The Overgrown Deep, The Slagworks, The Sunken Ruins, The Inverted Spire. `_follow_main` already walks that order. `start` should call it instead of assigning `tracked = id`.
- A New Home's reach target accepts `bobs_lab` as well as `old_oak`, so the east-lobe door counts. That is a second reach step or a `notify` alias inside `QuestDriver.reach_id`, not a new place name. `bobs_lab` is already the level id.

The Breach Warden stays off the table unless the open question below says otherwise. The crater already gates the Labyrinth on his death. Adding him is a `kill` / `breach_warden` step on The Breach, between the crater and the Labyrinth. The id exists. No new art.

### 2. Waypoints

One resolver used by `QuestMarker` and the minimap. Input is the tracked objective plus the current level. Output is a world position in this level, or nothing when the step is done.

Search order:

1. If the target is a speaker, an item pickup, or a `BossSpawn` for this objective and it is in the loaded level, use that position.
2. If the objective's level is the loaded level and the boss or pickup is not spawned yet, use the stair or exit that leads toward that floor. Labyrinth floors already have downward exits. The marker points at the next floor's door, not at the waystone home.
3. If the objective's level is a different level, use the `LevelGate` in this scene that is the next hop toward it. The hop table is the exits that already exist: Town to Landfill (`midden`), Landfill to Breach, Breach to Labyrinth, and the labyrinth stairs between acts. Do not invent links.
4. If nothing in this scene leads there, hide the mark. Do not fall back to "the first waystone".

`collect` uses the same resolver. A live `QuestPickup` with that item id is the point. Three marks are one objective with count 3. The mark moves to the next uncollected pickup of that id and hides when the count is full. That is the multi-target behavior this chain needs. It does not need a new objective kind.

Cross-level means the hop above, not a pointer into an unloaded scene. The minimap pin is the same position. The world map stays a travel map. A screen-edge compass would be new UI art and waits for 0.15.1.

The gold `v` stays. No new mesh, no new icon. The art gate does not trip if no new art is added. Hymn-shards, a cult name, and a Core quest need writing first and new art second. They are out.

The intro mark still wins while the intro is running. When the intro ends, the quest mark takes the same job.

### 3. Save and the debug jump

Save version stays 1. `from_dict` gains a repair, not a version bump:

- A saved step index past the end of a shortened row (The Breach losing its third step) clamps to the last open step or completes the row if that step's target was already satisfied.
- After load, `check_auto_start` runs so a save that already has `goblin_king` in `known_bosses` picks up The Goblin Warrens without a new game.
- Unknown ids are still dropped.

Debug jump, debug builds and tests only, not the release menu: an environment variable `QUEST_AT` naming a quest id. On boot the log sets the flags and `known_bosses` that start that quest, marks earlier main quests done, and leaves the named quest active on its first step. Tests and a local playthrough can stand at Act IV without replaying the tutorial. No new command name that sounds like a character or a place.

### 4. Tests

Extend the headless path. Do not add another 15-minute co-op playtest as the proof.

`tests/unit/test_quest_chain.gd` already builds the early levels and then `notify`s the log. Grow it so one test, still headless:

1. Starts from `permit_given` and walks every main objective through `storm_warden` with `notify` and `known_bosses`.
2. After each `notify`, asserts the tracked quest and the current target.
3. Asks the resolver, with a stand-in for "which gates exist in this level", for a point. The point is the next hop or the boss spawn. It is never the waystone when a stair or a gate toward the objective exists.
4. Asserts a completed step and a completed quest produce no point.
5. Loads one real scene per act far enough to find `BossSpawn` or the downward exit and checks the resolver against that node. Acts that are closed greybox scenes still have those nodes. This is not a screenshot test and does not need new art.

Existing tests that lock the old Breach-to-Matriarch handoff (`test_quest_chain.gd` final checks) change with the table. `test_quest_rules.gd` stays the tracker and Choir test and gains the "earlier main quest keeps the tracker" case.

## Out of scope

- The Town, Landfill, Association, Breach, and act remakes (0.12.0 through 0.13.4).
- Boss and enemy meshes (0.14.0, 0.14.1).
- The parchment UI and any new compass art (0.15.1).
- Hymn-shards, the dry prophet, the prism, the Core, the Demon Lord, DLC towns.
- New names. New music. A save version bump.

## Open questions

1. The Breach Warden. Leave him as the crater's gate, with no quest step, or add `kill` / `breach_warden` on The Breach before `reach` / `labyrinth`? The plan defaults to no new step. His death already opens the Labyrinth.
2. Report to Bob versus The Breach. Both open after the Filth. The plan keeps the marker on Report to Bob until the talk completes, then moves to The Breach. Say if the crater should win instead.
3. Act II and Act III auto-start from the previous boss, with the Verdant Mother and the Scrap-spirit still starting the side quests. Say if those talks should remain the only way the main rows start.
4. Joe's Marks and Joe's Seals. The plan gives them a pickup waypoint and leaves them off the HUD unless Track is pressed. Say if the main trail should ignore side pickups entirely.
5. The east-lobe door. The plan treats entering Bob's lab as completing A New Home, and still accepts the old `old_oak` room. Say if A New Home should keep pointing at the grove exit only.
