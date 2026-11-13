# Quests and the Auto-Scribe™ (0.9.x)

Planning only. Written against master `38b3ec5` (v0.9.0-prealpha). No code in this change.

The ask is two things that share one screen. A Borderlands-style mission list, and one tabbed pause menu for every in-game panel, with animated tabs and a reduced-motion path. The title screen stays a title screen.

## What is on master today

### Quest data

`data/story/quests.toml` is the only quest table. `scripts/story/quest_log.gd` (`QuestLog`) loads it.

Eight quests, all auto-started by story flags. None is marked main or side. None has a giver, a turn-in, a recommended level, gold, or an item reward.

| Id | Starts when | Steps | Reward |
|---|---|---|---|
| `a_new_home` | `permit_given` | Reach Old Oak | 20 XP, flag `old_oak_unlocked`, clue |
| `the_landfill` | `starter_gear_given` | Reach landfill, kill 3 gnawers, kill the Filth, collect Joe's Trash | 100 XP, 50 dust, flag `filth_defeated`, clue |
| `report_to_bob` | `filth_defeated` | Talk to Bob | 50 XP, flags `tutorial_done` and `fast_travel_crystal`, clue |
| `the_breach` | `filth_defeated` | Reach Breach, reach Labyrinth, kill the Matriarch | 40 XP |
| `the_overgrown_deep` | `verdant_met` | Kill the Matriarch | 80 XP |
| `joes_marks` | `verdant_met` | Collect 3 `joe_mark` | 40 XP, clue |
| `the_slagworks` | `scrap_met` | Kill Forgemaw | 90 XP |
| `joes_seals` | `scrap_met` | Collect 3 `slag_seal` | 40 XP, clue |

Objective kinds are only `kill`, `collect`, `talk`, and `reach`. Steps run in order. The log advances only the current step (`notify`). There is no optional step and no parallel step.

A quest completes itself when the last step fills. Rewards are applied in `_complete`: XP and dust if a player is bound, then flags, then a clue. There is no turn-in NPC and no reward choice. Act II and Act III can also complete early if the boss is already in `known_bosses`, or if the marks or seals are already on the flags (`_seed_act2`, `_seed_act3`).

Act IV has no row. The Abyss and Endless Descent are not quests. The bounty board is not in this file.

Save: `QuestLog.to_dict()` writes `active` (step and count), `done`, `clues`, and a copy of the story flags. `main.gd` stores that under `progress["quests"]`. `SaveGame.VERSION` is still 1. Missing quest keys load as empty. Unknown quest ids are dropped on load.

### Who feeds the log

`scripts/story/quest_driver.gd` is one node on the game scene.

- Kill: `EventBus.enemy_killed`, the enemy's def id.
- Collect: `EventBus.quest_item_collected`.
- Reach: the level id, mapped through `FastTravel.LEVEL_POINT` (`midden` becomes `landfill`). It also raises a level-name banner on the HUD.
- Talk: `talked(speaker)` when a dialogue with that speaker ends.

The intro has a second, older list. `IntroDirector.objective()` and `OBJECTIVES` are beat strings ("Speak to the Clerk"). `target_point()` places a world `Label3D` named `ObjectiveMarker` (the letter v, gold, bobbing). The playtest bot walks to that marker. It is not a `QuestLog` objective, and it is removed when the intro ends.

### Bounties

`scripts/world/bounties.gd` is a class and a unit test. Nothing in the game scene creates it. Three rows: 3 gnawers for 12 gold, 2 heaps for 18, 2 spore husks for 18. Repeatable. Counts are not saved. There is no board, no marker, and no HUD line.

### Quest UI, and where it overlaps

| Surface | File | What the player sees | How it opens |
|---|---|---|---|
| Quest tracker | `scripts/ui/quest_tracker_ui.gd` | Top-right label of every active quest and its current step, with a count when the count is above 1 | Always on, under the HUD layer |
| Clue log | same file | A centered "Clue Log" panel | `toggle_clue_log()`. No key calls it. Only `tests/unit/test_quests.gd` opens it |
| Intro marker | `scripts/story/intro_director.gd` | A gold v in the world | While an intro beat has a target |
| HUD hit marker | `scripts/ui/hud.gd` | A white, yellow, or red x at screen center | On a bolt hit. Not a quest marker |
| Level banner | `Hud.show_banner` | Full-width banner | Quest reach, waves, intro beats |
| Hint line | `Hud` | Short line under the crosshair | Interaction and combat hints |
| Inventory quest items | `scripts/ui/inventory_ui.gd` `quest_box` | Buttons for `player.quest_items` (Joe's Trash and similar). Not the quest log | Tab |
| Minimap | `scripts/ui/minimap.gd` | Top-right 160 px map: fog, waystones, exits, party | Always on |

The tracker and the minimap both sit in the top right. The tracker does not pick one quest. It prints every active quest, so Trash Talk, Report to Bob, and The Breach can all be on screen after the Filth.

There is no compass, no quest waypoint on the minimap, and no `!` or `?` on an NPC. Map pins are waystones, exits, and party members (`WorldMapScreen`, `MapPins`).

### Every other in-game menu

These are separate screens. Each sets `player.ui_open`, shows the mouse, and (except the pause menu) does not pause the tree. The pause menu does pause the tree. `UiAnim` already fades and slides a panel 8 px over 0.15 s, and skips that when `UiAnim.reduced_motion` is set or the game is headless.

| Screen | File | Key | Notes |
|---|---|---|---|
| Pause | `scripts/ui/pause_menu.gd` | Esc (`menu`) | Resume, Skills, Settings, Save, Main menu, Quit, party line, Leave co-op. Skills closes pause and then opens the skill screen |
| Settings | `scripts/ui/settings_ui.gd` | From pause, or the title screen | Layer 4, full rect. Rebind list plus the accessibility options. Saves `user://keybinds.cfg`, not the game save |
| Inventory | `scripts/ui/inventory_ui.gd` | Tab (`inventory`) | Backpack, worn slots, compare card, dust, potions, quest-item buttons, trash, junk, Ember Mark import |
| Skills | `scripts/ui/skills_ui.gd` | K (`skills`) | Core column plus seven element tabs. Pad LB/RB already cycle those inner tabs. Respec at the Old Oak. Capstone confirm |
| World map (painted) | `scripts/ui/world_map_screen.gd` | M (`map`), and the waystone | Pan, zoom, fog, waystones, travel confirm card. Labyrinth band on the card still says "Lv 5-12" |
| World map (text) | `scripts/ui/world_map_ui.gd` | Shown from the level load path | A left-side list, "Elyria" or the level name, Here / Visited / Unseen. A second map, not the M screen |
| Fast travel list | `scripts/ui/fast_travel_ui.gd` | From a waystone | Point list on top of the map |
| Vendor | `scripts/ui/vendor_ui.gd` | Interact at a vendor | Buy, sell, junk sell, reroll. Gold and dust |
| Assembly station | `scripts/ui/station_ui.gd` | Interact at a station | Parts, preview, assemble. Not a pause tab |
| Co-op lobby | `scripts/ui/coop_menu.gd` | Title screen | Host, join, roster, ready. Not an in-game panel |
| Character creator | `scripts/ui/character_creator.gd` | Title screen | Name, color, archetype |
| Credits | `scripts/ui/credits_ui.gd` | Title screen | |
| Main menu | `scripts/ui/main_menu.gd` | Before a game | Also owns a settings screen |

### What should stay a HUD element

These are not menus. They stay on the play view.

- Health, shield, mana, and Breath bars, dash pips, weapon slots, skill-cooldown line (`Hud`).
- Crosshair, hit x, damage numbers, hurt flash, low-health vignette.
- Subtitles (`dialogue_ui.gd`).
- The compare card for the item under the crosshair (`compare_card.gd`). The inventory has a second compare card. The world one stays.
- Interaction prompt ("[F] ...").
- Minimap.
- Party frames (`party_frames.gd`).
- Vote banner (`vote_banner.gd`) during a stair vote.
- Toasts, level-up burst, boss bar, downed overlay.
- Loading screen and the letterbox cinematic. Esc during a cinematic still skips it, and does not open the menu.
- The objective tracker, once it shows only the tracked quest. It moves so it no longer sits on the minimap.

### Co-op and saves, as they are

The host's save holds the world: level, `progress["quests"]`, story flags, vault. A joining character file is `SaveGame` shaped but `progress` is forced empty (`character_save.gd`). The joiner does not bring quest progress, and does not write the host's quest log. One `QuestLog` runs in the game scene, so a kill on the host advances that one log. Loot itself stays instanced per player.

### Accessibility already in place

`Settings` and `Accessibility` already cover text scale, subtitle size, high contrast, colorblind tints, and reduced motion. `UiAnim.reduced_motion` makes panel open and close instant. High contrast is drawn on enemies and loot, not on menu chrome. The skill screen's inner tabs do not use a sliding underline.

## The Auto-Scribe™

One in-game menu. Esc opens it and pauses, as the pause menu does now. The last tab you used is the one that opens. First run opens Map.

Eight tabs, left to right:

1. **Map**
2. **Missions**
3. **Inventory**
4. **Skills**
5. **Character**
6. **Challenges**
7. **Social**
8. **Settings**

Shoulder buttons move the tab on a pad (LB / RB). On a keyboard, Q and E move the tab only while this menu is open. In the world, Q stays the action skill. E is not a gameplay key (interact is F), so this does not take E away from anything. The skill tree's own Core / element tabs stay inside the Skills tab and keep their own LB / RB once that tab is focused. While the echo tab strip has focus, LB / RB change echo tabs. That split is the only way both strips can keep a shoulder button.

### Motion

- The active tab's underline slides to the new tab.
- The outgoing page fades and slides 24 px. The incoming page fades and slides in from the other side.
- Opening the menu fades a dim layer and slides the sheet up. Closing reverses it.
- A hovered tab or row lightens. A selected row keeps a bar on its left edge.
- Focus for a pad starts on the first row of the open tab, which the menus already try to do.

`UiAnim.reduced_motion` makes every one of those instant. Fade time becomes 0. The underline jumps. Hover still changes color, with no scale. Flash reduction does not turn motion off. High contrast draws the underline and the selection bar thicker, and uses the existing high-contrast outline color. Text scale and subtitle scale keep coming from `Accessibility`. The menu uses the same theme font size the settings screen already pushes.

Headless and tests stay instant, which `UiAnim.instant()` already does.

### What folds into which tab

| Tab | Built from | What goes away as its own screen |
|---|---|---|
| Map | `WorldMapScreen` (the painted map), the fast-travel confirm card, waystone list | `WorldMapUI`'s text list. Its Here / Visited / Unseen lines become a corner of the map tab. M still opens the menu on this tab |
| Missions | `QuestLog` tracker text, clue log, quest detail | The top-right multi-quest label. The clue panel that has no key. Clues are a section of the selected mission |
| Inventory | `InventoryUi` backpack, worn slots, dust, potions, trash, junk, Ember Mark | Tab still opens the menu on this tab. The quest-item buttons stay here. They are keys, not missions |
| Skills | `SkillsUi`, including the Core and element tabs and the capstone confirm | K still opens the menu on this tab. The pause menu's Skills button goes away |
| Character | New sheet over numbers the game already has: level, XP, health, shield, mana, Breath, gold, dust, archetype, name, skill-point count | Nothing to delete. The pause menu does not show this today |
| Challenges | `Bounties` rows, plus a kill count that actually gets saved | The bounty class stops being test-only |
| Social | Pause party line, Leave co-op (still a second press to confirm) | Those two controls leave the old pause list |
| Settings | `SettingsUi`, including every accessibility row and the rebind list | The layer-4 settings sheet. The title screen keeps its own settings screen |

Save, Main menu, and Quit stay on a footer of the echo menu, not as tabs. Resume is Esc or the footer. The old pause button list is removed.

### What stays out of the echo menu

- Vendor and assembly station. They open from the world, on top of play, and close with Esc without opening the echo menu. They should use the same item card as Inventory so the compare text is not written twice.
- Dialogue, subtitles, cinematics, the vote banner, the loading screen.
- The title screen, character creator, co-op lobby, and credits.
- Every HUD piece listed above.

## Missions

### Kinds

- **Main.** The story chain. One is the tracked quest unless the player tracks something else. Gold title in the log and on the HUD. A yellow mark in the world.
- **Side.** Optional story tasks that already exist (`joes_marks`, `joes_seals`) and any later ones. Blue title. A blue mark. Accepting one does not replace a tracked main quest.
- **Challenges.** The bounty rows. Not missions. They do not use a turn-in and they do not enter the mission tracker. They live on the Challenges tab. Repeatable. Gold only, which they already pay.

Optional objectives, when a quest has them, are listed under the required steps in a dimmer line. They never block completion.

### How a quest is shaped

Each quest in `quests.toml` gains, all optional so old rows still load:

- `kind`: `main` or `side`. Missing means `main` for the story chain and `side` for Joe's marks and seals. That mapping is the default below.
- `level`: a recommended level. If absent, the log shows the Act loot level of the floor the current target sits on (Filth stays the landfill band, Forgemaw 34, Choir 46).
- `giver`: an existing NPC or object id, when one already exists (Bob, the Verdant Mother's flag, the scrap spirit). No new speaker.
- `turn_in`: empty means the quest still completes itself, which is every quest on master.
- `reward_gold`, and `reward_items`: a list of item ids. Empty means no item. If the list has more than one id, the log shows a choice and the turn-in (or the auto-complete, if there is no turn-in) asks once. No quest on master gets an invented item.

Steps can set `optional = true`. Counters stay `count`. The HUD line is still `text` plus `have/need` when `need` is above 1.

### Tracking

One tracked quest id, saved on the quest block.

- Accepting or auto-starting a main quest tracks it.
- When a main quest completes, the next main quest that starts becomes the tracked one.
- A side quest never steals tracking. The Missions tab has a Track button.
- The HUD tracker shows only that quest: title, current required step, counter, and any optional step in a second line.
- The world marker is one point for the tracked step. Reach and talk use the gate, waystone, or NPC that already exists. Kill uses the entrance of the level that spawns that enemy, not a new arrow on every gnawer. The intro's gold v becomes this same marker while the intro quest is tracked, so the bot still has one target.
- The minimap and the map tab draw that point. No compass strip is added.
- `!` on a giver who has a main quest you have not started. `?` for a side quest. A small dot on the turn-in when the quest is ready. Givers who do not exist yet get no mark.

### Completion

A short panel, not a banner: quest name, XP, dust, gold, and the item if there is one. `UiAnim` fades it. Reduced motion shows it with no slide. It does not pause the game. The level-name banner from `QuestDriver.reached` stays a banner. It is not a quest popup.

### Log

The Missions tab is a list and a details pane.

Filters: Main, Side, Completed. Completed is both kinds, dimmed. The details pane shows the steps, the recommended level, the giver line, and the rewards. Track is a button on that pane. Clues that this quest granted sit at the bottom of the pane. There is no second clue screen.

### Where today's quests sit

| Quest | Kind | Why |
|---|---|---|
| `a_new_home`, `the_landfill`, `report_to_bob`, `the_breach` | Main | The prologue and the road into the Labyrinth |
| `the_overgrown_deep` | Main | Act II boss |
| `the_slagworks` | Main | Act III boss |
| `joes_marks`, `joes_seals` | Side | Optional collectibles beside the boss quest |
| New row `the_sunken_ruins` | Main | Kill `drowned_choir`. Auto-start when Forgemaw is in `known_bosses`, the same way Act III completes if he is already dead. No new dialogue |
| Abyss, Endless Descent | Not a quest | A mode. A challenge can count floors later. Not in this plan's first pass |
| Bounties | Challenges tab | Not side quests |

`the_breach` still ends on the Matriarch, which is what the file says today. Act III and Act IV are their own main quests. This plan does not rewrite that chain's targets.

## Saves

`SaveGame.VERSION` stays 1. The quest block may grow these keys: `tracked`, `kind` is data not save state, bounty counts under `progress["bounties"]`. Old saves have none of those. Load treats them as absent: no tracked id means "track the first active main quest", bounty counts start at zero. Completed quests in `done` stay completed. A quest id that was removed from the toml is still dropped, as today.

Do not bump the version for this. A version bump would reject every 0.9.0 save.

## Co-op

Main quests and their story flags stay on the host save. One log, one set of main steps, the way the host's world works now. The joiner sees that tracker. Their kills already reach the host's enemies, and the host's log is the one that advances.

Side quests and bounty counts are per character. They are written into the character file, which today forces `progress` to empty. The default is a small `progress.side` and `progress.bounties` on the character file only. They are not copied onto the host's world save. A joiner's side quest does not complete the host's copy.

Loot stays instanced, as it is now.

## Versioning

Two releases. The menu can ship on the quest data that already exists. The mission rules change save fields, markers, and co-op, and they should not block the menu.

**0.9.1, the Auto-Scribe™.** The eight tabs, the motion, reduced motion, and the Missions tab reading `QuestLog` as it is. One HUD tracker that shows every active quest until 0.9.2, but no longer under the minimap. Inventory, skills, map, and settings move into the tabs. Old keys (Tab, K, M, Esc) open the matching tab. No new quest fields required.

**0.9.2, mission rules.** Main and side, one tracked quest, waypoints, `!` / `?`, the completion panel, reward lines, the Act IV main quest row, and bounties on the Challenges tab with a save.

If both should be one release, ship them together as 0.9.1 and skip 0.9.2. That is the change to ask for. The default is the split.

## Defaults

Change any of these. Each is what the build will do if you do not.

1. **Two releases, 0.9.1 then 0.9.2**, as above.
2. **Tab order** is Map, Missions, Inventory, Skills, Character, Challenges, Social, Settings.
3. **Q and E change tabs only while the Auto-Scribe™ is open.** Q in the world stays the action skill.
4. **Pad LB / RB** change echo tabs until the Skills tab's inner tree has focus. Then they change Core / element, as they do now.
5. **Esc** opens and closes the menu and pauses. It still skips a cinematic instead of opening the menu.
6. **One tracked quest** in 0.9.2. Auto-track the main quest. Side quests do not take the slot unless Track is pressed.
7. **Existing quests auto-complete.** No new turn-in NPC is added.
8. **No invented item rewards.** Reward lines show the XP and dust already in the toml.
9. **Recommended level** comes from the act loot level of that step's floor when `level` is absent.
10. **`joes_marks` and `joes_seals` are side.** Every other current quest is main. Act IV gets one main quest, kill the Choir, with no new lines.
11. **Bounties are challenges**, not side quests. Repeatable. Gold. Saved. No board NPC.
12. **The Abyss is not a mission.**
13. **Save version stays 1.** New keys are optional.
14. **Main quests are the host's.** Side quests and bounties are per character.
15. **Reduced motion** makes the new tab motion instant. High contrast thickens the underline. Text scale keeps using `Accessibility`.
16. **Vendor and station stay world screens.** The title screen stays a title screen.
17. **The intro marker and the quest marker become one marker** in 0.9.2, so the playtest bot still walks to a single point.
18. **Kill steps do not mark every enemy.** They mark the level entrance that already leads there.

## What this plan does not build

New dialogue, hymn-shards, a second Choir body, a filled sarcophagus, an Act V quest, or a quest for the Abyss. Those stay out until you ask for them.
