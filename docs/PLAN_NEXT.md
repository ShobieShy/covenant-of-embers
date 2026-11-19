# What to build next

Planning only. Written 19 Nov 2026 against master `7daafd1884de80c93d5818f4500c071115535c53`. That commit is also the tag `v0.9.4-prealpha`. The in-game string is `0.9.4-prealpha`. Co-op protocol is 6. Save version is 1.

This file replaces the version table that used to live here. That table, approved 5 Nov 2026, called 0.10.0 Act V. [PLAN_LEVEL_REMAKE.md](PLAN_LEVEL_REMAKE.md) later assigned 0.10.0, 0.10.1, and 0.10.2 to the Town, the Landfill, and the Association. ShobieShy confirmed that order on 19 Nov 2026. Act V is 0.11.0. The twelve calls at the end are decided. Nothing in this update is implemented yet.

The version scheme from 5 Nov 2026 still holds, and it is repeated in [PLAN_0.8.0_SLAGWORKS.md](PLAN_0.8.0_SLAGWORKS.md).

- A patch (`x.x.y`) is a bugfix, or a large addition that is not a new act and not a major feature.
- A minor (`x.y.0`) is a new act, or a big feature. Act III shipped as 0.8.0, not as a patch.
- The campaign stays on 0.x. **1.0 is a release cut, and only when ShobieShy says so.** It is not a content milestone.

Sources read for this pass: [COVENANT_OF_EMBERS_BIBLE.md](COVENANT_OF_EMBERS_BIBLE.md), [COVENANT_OF_EMBERS_STORYLINE.md](COVENANT_OF_EMBERS_STORYLINE.md), [maps/MAP_LEGEND.md](maps/MAP_LEGEND.md) and the four JPGs it names, every `docs/PLAN_*.md`, [PLAN_LEVEL_REMAKE.md](PLAN_LEVEL_REMAKE.md), [PLAN_IMPLEMENTATION_0.8.5-0.9.md](PLAN_IMPLEMENTATION_0.8.5-0.9.md), [PLAN_UI_QUESTS_0.9.x.md](PLAN_UI_QUESTS_0.9.x.md), and the 0.9.4 code. The bible and the storyline were written against v0.9.0. Where 0.9.1 through 0.9.4 shipped something those docs still call missing, the changelog and the code win for "is it in the game." Story decisions that are still unbuilt stay with the bible.

## 1. Gap table

Status is against master `7daafd1` / v0.9.4-prealpha.

### World, levels, and the remakes

| Item | Status | Where it lives |
|---|---|---|
| Elyria as a realm you hear about and do not drive across | Shipped as text. No overland travel. | Bible "World"; `scripts/core/game_flow.gd` has five level ids |
| Eldoria town square, 40×40 greybox, three exits | Shipped, still the old slab | `data/levels/town_square.toml` header "Greybox"; floor box 40×40 |
| Town remake, 72×72 close, raised 36×36, three real gates, cliffs | Missing | [PLAN_LEVEL_REMAKE.md](PLAN_LEVEL_REMAKE.md) defaults 7; [maps/MAP_LEGEND.md](maps/MAP_LEGEND.md) says the sizes are the plan, not the slabs |
| Mage Association hall 20×30 plus two 20×90 wings | Shipped greybox | `data/levels/mage_association.toml` |
| Association remake, 64×56 close, hall 24×32, library 18×22, courtyard 22×24, wings removed | Missing | PLAN_LEVEL_REMAKE defaults 9 |
| Landfill / Filth bowl, three slabs about 24×100 | Shipped greybox (`midden_greybox`) | `data/levels/midden_greybox.toml` |
| Landfill remake, 48×150 valley, berms, north rock cut, south ridge | Missing | PLAN_LEVEL_REMAKE defaults 8 |
| Old Oak / Great Oak, both names | Shipped hollow, Bob, and station. The tree-top lab is decided for 0.10.3. The potion garden stays a few pots in that room, not a new yard. The rest of the tree stays | Bible "The Great Oak"; decision 8 |
| The Breach crater and the Warden | Shipped greybox slice | `data/levels/breach_slice.toml`; boss `breach_warden` |
| One shaft, not five separate dungeon trips | Shipped as the labyrinth entered from the Breach | `scripts/core/main.gd` loads floors inside the Breach; storyline "The Breach" |
| Kill plane under every level, last waystone or spawn, loot and gold kept, only the fallen player moves | Shipped in 0.9.3, joiner line stored on the level in 0.9.4 | `scripts/player/kill_plane.gd`; [CHANGELOG_0.9.3.md](release/CHANGELOG_0.9.3.md), [CHANGELOG_0.9.4.md](release/CHANGELOG_0.9.4.md) |
| Per-level Terrain3D outdoor ground | Missing on the hub. Textures exist and unused layers are kept out of the export | `tools/export_set.py`; no `[terrain]` in `data/levels/*.toml` |
| Outer kingdoms (Valdoria, Sylvandar, Ironforge, the Wastes, Luminar, Willowbrook, Stonehaven, Arcana Spire) | Missing as levels. Folded into acts or left as lore, as the bible says | Bible "The lands"; map legend |
| Map plates | Shipped as docs, not as an in-game surveyed map | `docs/maps/*.jpg`, [maps/MAP_LEGEND.md](maps/MAP_LEGEND.md) |

### Story beats and people

| Item | Status | Where it lives |
|---|---|---|
| Intro beats 1–13: summoning through the crystal | Shipped | `IntroDirector.BEATS` in `scripts/story/intro_director.gd` |
| Appraisal, the four Summoned, name and color | Shipped | Bible "The Summoned"; intro creator |
| Archetype perks (mana, vendor discount, health, move speed) | Shipped as the hall lines describe | Bible table under "The Summoned" |
| Auto-Scribe™ handed over by the Clerk; Esc pauses only until then | Shipped in 0.9.4. The bible's v0.9.0 wording is behind the game | `scripts/ui/echo_menu.gd`; `IntroDirector.SCRIBE` |
| Elder, Clerk | Shipped as intro spawns, not permanent rows | `intro_director.gd` `_dress_association` |
| Bob, the kit, the crystal, "someone caused it" | Shipped. He does not say the Demon Lord's name | Storyline "What Bob does with the sludge" |
| Bob's model | Partial. Bible says the on-screen model is still a placeholder | Bible "Bob" |
| Crazy Joe in the hall, then the landfill camp, wind wand, bench | Shipped | `mage_association.toml` NPC; `scripts/story/intro_landfill.gd` |
| Town NPCs: Bored Guard, Potion Merchant, Tailor, Runesmith, Grizzled Patron | Shipped | `town_square.toml` |
| Wounded scavenger, Light can get them up | Shipped. Lines called placeholders in the bible | Bible "The hall and the square" |
| Verdant Mother, Scrap-spirit | Shipped as labyrinth speakers | `data/story/dialogue.toml` (`verdant_met`, `scrap_met`) |
| Association head | Missing. **Open** in the bible | Bible "Factions" |
| Rebels as a joinable faction | Missing. Joining is decided; leader, join, and pay are **Open** | Bible "Factions" |
| Fiery blacksmith and enigmatic bard | Missing. **Open** | Bible "Factions" |
| Rival Summoned from Joe's earlier rites | Missing. **Open** | Bible "Factions" |
| Sylvandar caravan, merchant's lost expedition | Missing. **Open** | Storyline "What Bob does with the sludge" |
| Willowbrook farmer as an NPC | Missing on purpose. The raids became Act I | Bible side-story table |
| Prism focus: seal or crack, Demon Lord learns your name | Missing. The choice is decided, the scene is not written. **Open** | Bible "Cosmology"; "Open, in one list" |
| Fast-travel crystal after the Filth | Shipped as waystones | Bible "Bob" |

### Acts and bosses

| Item | Status | Where it lives |
|---|---|---|
| Act I, Goblin Warrens, floors 1–5, Goblin King | Shipped | `scripts/labyrinth/labyrinth_floor.gd`; `data/labyrinth/warrens.toml` |
| Act II, Blightcoil, floors 6–8, Matriarch, empty cocoon | Shipped | `scripts/labyrinth/blightcoil_cavern.gd` |
| Act III, Slagworks, floors 9–13, Forgemaw, empty slag cast | Shipped | `scripts/labyrinth/slagworks_floor.gd` |
| Act IV, Sunken Ruins, floors 14–18, Gallery / Pocket / Murals / Spire / Nave | Shipped | `scripts/labyrinth/sunken_floor.gd` |
| Drowned Choir as many singers | Contradicts, and the one body stays for now. The story still wants a crowd later. Do not rebuild it in 0.10.x or 0.11.0 | `scripts/enemies/drowned_choir.gd`; decision 7 |
| Hymn-shards, cult name, dry-prophet lines | Missing. **Open** | Storyline Act IV |
| Empty coral sarcophagus | Shipped as the end prop. The walker is unnamed, which matches the docs | Storyline Act IV |
| Quest "The Sunken Ruins" | Shipped in 0.9.2. The bible's quest table, frozen at v0.9.0, still says Act IV has no entry | `data/story/quests.toml` `the_sunken_ruins` |
| Act V, Inverted Spire, Storm Warden, lit path, Joe waiting | Missing. Approved outline | Storyline Act V; map legend marks it *planned* |
| The Core: fight Joe, then the Demon Lord, then he escapes | Missing. Order is decided. Fights, loot, and the leaving shot are not written. **Open** | Storyline "The Core" |
| Three shells in order (cocoon, slag cast, sarcophagus), no fourth shell in Act V | Partial. The three empties are in Acts II–IV. Act V is not built, so the "no fourth shell" beat cannot play | Storyline "What the shells are for" |
| One continuous walk from the King's hall to the nave | Partial. The story is one shaft. The build still offers later acts as their own stretches after each boss | Storyline "The Breach"; `scripts/labyrinth/lab_gate.gd` |
| Breach Warden, The Filth, Heap | Shipped | Breach waves; landfill Filth |

### Quests, scribe, and toys

| Item | Status | Where it lives |
|---|---|---|
| A New Home, Trash Talk, Report to Bob, The Breach, The Overgrown Deep, Joe's Marks, The Slagworks, Joe's Seals | Shipped | `data/story/quests.toml`; bible quest table |
| The Sunken Ruins main quest | Shipped. Bible table is stale | `quests.toml`; [PLAN_UI_QUESTS_0.9.x.md](PLAN_UI_QUESTS_0.9.x.md) default 10 |
| Act V quest, Core quest, Demon Lord quest | Missing. Plan said not to invent them yet | PLAN_UI_QUESTS "What this plan does not build" |
| One tracked quest, main vs side, markers, bounties saved | Shipped in 0.9.2 | `scripts/story/quest_log.gd`, `quest_marker.gd` |
| Turn-in NPCs, item-choice rewards, full co-op quest sync | Missing, on purpose for 0.9.2 | PLAN_UI_QUESTS defaults 7–8 and 14 |
| Intro marker and quest marker as one marker | Partial. The quest marker hides while the intro marker is up | `quest_marker.gd` |
| Auto-Scribe™ eight tabs | Shipped. Class is still `EchoMenu` | `scripts/ui/echo_menu.gd` |
| Bounty board after Forgemaw | Shipped | `scripts/world/bounties.gd`; bible "Bounties" |
| Breach-key chest, vendor stall, slot machine | Shipped | `scripts/world/hub_toys.gd` |
| Mantle (no sheet change) and enemy barks | Shipped | `scripts/world/mantle.gd`, `enemy_barks.gd` |

### Combat, gear, and feel

| Item | Status | Where it lives |
|---|---|---|
| Seven elements, the cycle, Light heal, Dark convert, Arcane neutral | Shipped | Bible "Magic"; element tables |
| Six brands and their fire modes | Shipped | `scripts/magic/brand_table.gd` |
| Path of Embers and seven element trees, level cap 50, respec | Shipped | `scripts/player/skill_tree.gd` |
| Action skill on Q, dash on V, verb from the tree you spent | Shipped | `scripts/player/action_skill.gd` |
| Four weapon slots | Shipped | `scripts/player/loadout.gd` |
| Shield, flask, relic systems | Partial. The code exists. `GearDrops.chance` is 0, so a normal kill does not add one. That matches the bible | `scripts/player/gear_kit.gd`; `scripts/loot/gear_drops.gd` |
| Consecrations on Rare+ | Shipped | `scripts/player/consecrations.gd` |
| Named uniques in the bible's table | Shipped as defs | `scripts/loot/named_uniques.gd` |
| Rarities through Unique, no separate legendary tier | Shipped | Bible "Rarities" |
| Assembly station in the tree; Runesmith rerolls, does not build | Shipped | Bible "Building a weapon" |
| Catch-up XP, +25% per level behind, capped at double | Shipped as Resolve. This is not `Vigil.xp_mult` | `scripts/player/progression.gd` `resolve_multiplier` |
| `Vigil.xp_mult` (+10% XP per tier) | Left unwired on purpose. Quick win 12 is closed as "leave" | `scripts/loot/vigil.gd`; decision 2 |
| Second Wind, crouch-jump, loot magnet, compare card | Shipped | Bible "How a minute of play feels" |
| Death window, revive, waystone return, gold kept | Shipped. A fall uses the kill plane and skips the window | Bible "Death"; `kill_plane.gd` |
| Co-op, 1–4 players, host authority, +60% enemy health per extra player, own loot | Shipped. Protocol 6 | `scripts/net/net_session.gd`; `scripts/net/coop_world.gd` |
| Music | Stays silent until a track exists. Do not block a version on it | `scripts/audio/game_audio.gd`; decision 6 |

### After the story

| Item | Status | Where it lives |
|---|---|---|
| Covenant Escalation tiers 0–10, enemy health and damage, omens | Partial. Math and save exist (`PostClear`, `Vigil`). No hub dial. Loot does not read the vigil unless a test sets it | `scripts/world/post_clear.gd`; `scripts/loot/vigil.gd`; bible says you can turn it after Forgemaw |
| Cleared-floor remix | Partial. `remix()` is implemented and only tests call it | `scripts/labyrinth/labyrinth_state.gd` |
| The Forgotten Abyss (generated floors while the Demon Lord is unbeaten) | Missing as a mode you can start. `Descent` has abyss fields and tests, and the campaign never calls them | `scripts/labyrinth/descent.gd`; bible "The Forgotten Abyss" |
| Endless Descent (mixed-act floors after the Demon Lord falls) | Missing. Cannot start, because the Demon Lord is not in the game. On-screen older names are a known gap | Bible same section |
| Deep gear in a story run | Missing in play. `DeepGear.chance` is 0, which the bible asked for until the rate is set | `scripts/loot/deep_gear.gd` |
| DLC towns, each with a chapter and a labyrinth | Missing. Shape is decided. Names and level minimums are **Open** | Bible "DLC" |
| `apply_void_on_player` | Missing from the call graph. The joiner's fall uses `player.apply_void` instead | `scripts/net/coop_world.gd` |

## 2. Where the code and the docs disagree

| Disagreement | Which side wins |
|---|---|
| This file used to set 0.10.0 as Act V. PLAN_LEVEL_REMAKE sets 0.10.0–0.10.2 as Town, Landfill, Association | Decided. The remake numbers win. Act V is 0.11.0 |
| Bible and storyline say "not in v0.9.0" for the Auto-Scribe handoff, the Sunken quest, the kill-plane death rule, and several 0.8.x gear lines | The game wins for what you can play. Those sentences are stale, not design changes. A later docs pass should say 0.9.4. Do not treat them as open features |
| Map legend says Act V is not in the v0.9.2 build | Still true at 0.9.4. The version number in that sentence is stale. The label *planned* is right |
| Storyline and bible: the Choir is many singers. The fight is one body, two phases | The docs stay the later target. ShobieShy decided the one body stays for now. Do not change it in 0.10.x or 0.11.0 |
| Bible: on-screen "Abyss" and "Endless Descent" should become Forgotten Abyss and Endless Descent | The bible wins when those modes are actually on a menu. Until then the code's `Descent` names are internal. Not a story fight |
| Bible: Covenant Escalation is a dial you set after Forgemaw, and it adds 10% experience per tier | The dial is still missing. Health and damage in `PostClear` do run. ShobieShy left `Vigil.xp_mult` unwired, so the 10% XP line waits with the dial. Do not wire it in these versions |
| Bible: a normal kill does not drop a shield, flask, relic, or deep-gear piece until the rate is set | The code matches (`chance := 0.0`). No contradiction |
| Storyline: the five depths should feel like one descent. The build offers Railhead only after both the King and the Matriarch are dead, and each act is its own stretch | The build matches what v0.9.0 shipped. The "one walk" is the story's shape, not a bug in the gate. Leave it until Act V forces a throat |
| `EchoMenu` is the class name. The title the player reads is Auto-Scribe™ | The player-facing name wins. Renaming the class is optional cleanup, not a feature |
| PLAN_NEXT (old) called Vigil "unused as a playable run" while `PostClear` already scales enemy health | Both were half right. Scaling is in. The playable dial is not. This file is the correction |
| README still says the campaign is playable through v0.9.0 | Stale label. Acts I–IV are in 0.9.4. Not a design split |

Story calls that stay **Open**, with no recommended winner:

- The prism scene, beyond the decided choice.
- The Association head's name and face.
- The cult's name, the hymn, and the dry prophet's words.
- Who shed the three skins. The reveal is in the Core. The name is unwritten.
- Rebel leader, how you join, and the pay.
- The blacksmith and the bard.
- Whether any of Joe's earlier summonings left a rival.
- DLC town names, level minimums, and whether a DLC has its own lord.
- The Sylvandar escort and the merchant's expedition as missions.

Bob's laboratory is no longer open. It is 0.10.3. The potion garden is a few pots in that room, not a new outdoor plot. The rest of the Old Oak stays.

Proposed lines in the bible (the crystal's insult is the Demon Lord's block; Breach-fire is his heat) stay proposed. They are not in dialogue. Do not write them into a level until ShobieShy accepts them.

## 3. Carried over

### 0.10.0 Town, 0.10.1 Landfill, 0.10.2 Association

Not started as geometry. Master is still the greyboxes in section 1. What did land first, as the remake plan asked:

- 0.9.3 kill plane, every level, including ones the remake does not rebuild.
- 0.9.4 stores that line on the level so a joiner is judged against the floor they are on.
- Terrain layers a level does not name stay out of the export, so the remake textures can exist on disk without shipping in 0.9.4.
- Intro spots for the hall and the landfill are anchors, with the old constants as the fallback (`mage_association.toml`, `midden_greybox.toml`). Moving a pad later does not require a new constant.

Old Oak's exterior, the Breach, and the labyrinth floors are out of the three remakes, except for the kill plane they already have. The lab is a later 0.10.3 interior. Ember Art's mesh list is the three tables in [PLAN_LEVEL_REMAKE.md](PLAN_LEVEL_REMAKE.md). If those cliff meshes are not in the tree, the remake ships Kenney cliffs and swaps them later. Kenney and Quaternius stay for every other slot the same way.

### Quick win 12

Closed as "leave." Do not wire it in these versions.

- `Vigil.xp_mult` in `scripts/loot/vigil.gd` returns `1 + 0.10 * tier`. No gameplay XP path reads it. Catch-up XP stays Resolve.
- `CoopWorld.apply_void_on_player` in `scripts/net/coop_world.gd` has no caller. A joiner who falls stays on `player.apply_void` from `_on_void`.

### Dropped co-op hits (55 of 68)

This predates #72.

On master before the compact snapshots (`a4b368b`, F4 already merged), a lagged run (`COOP_LAG=150`, `COOP_LOSS=0.02`) applied 70 of 84 joiner hits. The snapshot branch applied 55 of 68. After both were on master, a later run applied 84 of 95. The share that lands sits around four fifths to nine tenths, and it moves with the fight.

Hits are reliable. The loss setting does not drop them. `coop_world.gd` counts a hit only when the host still has that enemy and it is not dead. Under 150 ms, the joiner keeps shooting a puppet the host has already killed. Those messages arrive and are ignored. The compact snapshot did not add that rule.

The same pre-#72 run also logged `unknown peer ID` while the session was closing, which failed the playtest script even though both bots had passed. #72 stops a send to a peer that is already gone. That teardown error is separate from the 55 of 68.

ShobieShy changed the rule. A hit that arrives after the body is dead still pays the shooter loot and XP, once. It does not kill the enemy again. The how is under 0.10.0, because that is the next version, and the credit ships in that version before the new town geometry. It needs co-op protocol 7. A 0.9.4 peer cannot join.

### Windows on a real PC

There is no Windows PC. CI still exports the zip and checks the PE version. The zip ships. Windows stays unverified, and that does not block a version.

### Silent music

Still true. `game_audio.gd` says there is no track yet. Slagworks and Blightcoil cue paths point at ogg files that are not in the tree, and the cue refuses to play when the file is missing. SFX and UI audio are in. The bible lists music as a placeholder, and the 5 Nov roadmap said music stays on placeholders until it is composed.

### Grey-box halls

Still the walkable hubs. Town is one 40×40 slab with gaps that are not all doors. The Association is a 20×30 hall plus two wings of 90 m. The Landfill is three slabs and heaps you can walk around. The kill plane is what catches the fall. The map paintings show the remake, and the legend says so.

### AppImage

`tools/package.sh` builds `CovenantOfEmbers-<version>-x86_64.AppImage`, smoke-runs it headless, and writes the Windows zip. v0.9.4 left the AppImage off the public release. From the next prerelease on, the AppImage is attached next to the Windows zip and `SHA256SUMS.txt`.

## 4. Ordered roadmap

Each version below is a minor or a patch under the 5 Nov scheme. None of them is 1.0.

### 0.10.0 — Late-hit credit, then the Town

Two changes, in this order, in this version. The credit is not a town feature. It ships here so the protocol bump is not buried in a later level.

**Late-hit credit.** Today `coop_world.gd` applies a `"hit"` only while `not e.dead`. A joiner's shot that arrives after the host has already killed the body is ignored. Loot and XP already fire once, on `EventBus.enemy_killed`, on each peer: the host when the real enemy dies, the joiner when the reliable `"kill"` runs `confirm_kill` on the puppet (`loot_dropper.gd`, `xp_rewarder.gd`). Firing that signal again would drop a second pile and count the quest twice.

The rule:

- A hit on a living enemy is unchanged. It damages. If that damage kills, death, the `"kill"` message, quest credit, and one loot roll happen once, as now.
- A hit on a dead enemy does not call `apply_damage`, does not call `died`, and does not emit `enemy_killed` again. Quest counts, boss flags, Second Wind, and Dark convert stay tied to the one death.
- The host keeps a set of peer ids already paid for that enemy id. The killer is marked when the enemy dies. A later hit from a peer not in the set marks them and sends one reliable `"credit"` (`id`, def id, position, element, level). A peer already in the set gets an ack and nothing else.
- The joiner pays loot and XP from `"credit"` only if that corpse was not already rolled from `"kill"`. `"kill"` then `"credit"`, or `"credit"` then `"kill"`, is one roll. The key is `(peer, enemy id)`.
- The hit sequence is still acked, so the joiner's prediction settles.

**Compat.** New message `"credit"`, and the dead branch of `"hit"`. Bump `NetSession.PROTOCOL` from 6 to 7. A p6 peer cannot join. Do not change `Compat.fingerprint()` unless a loot table changes. The fingerprint stays the item and loot hash. The protocol number is the gate, the same way the snapshot bump was.

**Tests.** One corpse, two peers: the second peer's late hit rolls loot once and does not raise the kill count. A second late hit from the same peer rolls nothing. Kill-then-credit and credit-then-kill each roll once. `COOP_LAG=150` `COOP_LOSS=0.02`: hits that do not damage still credit, and pickup counts do not double.

**Town scope.** Replace the 40×40 slab with a 72×72 close. Raised square 36×36, about 2 m up. Streets to three gates only: north Association, south Landfill, east Old Oak. Cliff outside the streets. East and west holes closed. Ids stay: `town_square`, `to_association`, `to_landfill`, `to_old_oak`, `town_gate`, the five NPC speakers. Starts, exits, NPCs, and the waystone move at most 4 m, or the playtest bot moves in the same PR. Nav is rebaked from the new collision. The old town nav tiles, the old minimap, and the old slab layout are not reused. Kill plane stays, retuned to the new lowest walkable y.

**Depends on.** 0.9.4 (kill plane, export excludes, anchors). The credit lands before the new ground, in the same version. Cliff art is Kenney if the Ember Art cliff mesh is not in the tree. Swap it when the mesh arrives.

**Ember Art.** Ward pillar, ward lantern, Association arch, south gate, east gate, street lanterns, banners, stall frames, crate stacks, hand cart, fountain basin and water, Flagon front, roof, lantern, one row-house, cliff texture, broken cobble. Counts are the Town table in PLAN_LEVEL_REMAKE.

**Risks.** The bot walks to coordinates. A gate that jumps more than 4 m fails the slice until the bot is updated. A cliff that does not meet a door bakes a nav hole. Terrain3D texture arrays must share one compression format or the level fails to draw. Taking the invisible walls down before the cliff exists brings the fall back.

**Tests.** Rebake nav. Solo playtest through the square, both directions. Full tier. One co-op join on the square. The export must include the town's terrain layers and still exclude unused ones.

### 0.10.1 — Landfill

**Scope.** A valley about 48 m by 150 m. Berms 6–8 m on both sides. South ridge with the town gate. North rock cut with the Breach gate. Three pads at the current heights (yard at 0, bowl and north road at −2). Tutorial band, Joe, the Filth, waystone `landfill`, and the intro anchors stay. The Filth is still the last fight.

**Depends on.** 0.10.0's terrain and nav lessons, not on the town mesh itself. Can start from the same art batch if the landfill meshes are ready.

**Ember Art.** Berm sections, small and tall heaps, trash clusters, split barrels, compactor, scrap plates, bowl lip, north rock cut, barrel fires, yard lamp, wet-ground decal, Filth residue. Landfill table in PLAN_LEVEL_REMAKE.

**Risks.** The intro bot's yard, shrines, and Filth trigger are coordinate-sensitive. The kill plane must use the bowl's y, not the town's. A berm the nav treats as a wall traps the bot in the tutorial.

**Tests.** Intro through the Filth, save, load, the north road into the Breach. Full tier. Lagged co-op once, as a regression check that the new floor does not change the dead-hit rule.

### 0.10.2 — Association

**Scope.** A close 64×56. Hall about 24×32. Library 18×22 on the east. Courtyard 22×24 on the west. The 90 m wing slabs go away. Summoning circle stays the landmark from the south door. Back door to the landfill stays behind the dais. Anchors `library` and `courtyard` keep their names. Intro spots `dais`, `elder`, `clerk`, `summoned_*` move only within the 4 m cap.

**Depends on.** 0.10.0 and 0.10.1 only for process. The hall can be built while those ship. Do not delete the wing geometry until the new pads and the intro bot agree.

**Ember Art.** Hall pillars, circle inlay, dais steps, benches, precinct wall, back berm texture, door leaves. Association table in PLAN_LEVEL_REMAKE. No art for a 90 m corridor.

**Risks.** The library stair and the courtyard currently live on the long wings. Shortening them without moving those beats breaks the intro. The roof edge is already a fall; the new precinct wall has to close it.

**Tests.** Intro from summoning through the grant and the back door. Full tier. Confirm the Clerk still grants the scribe before Esc opens it.

### 0.10.3 — Bob's laboratory

The Old Oak is otherwise unchanged. No new footprint, no new yard, no renamed tree. Both names stay.

**Scope.** A stair or ladder in the existing hollow, up to one room in the branches: a star chart, an autopsy slab, a shelf of artifacts, and a short bench of potion pots. That bench is the potion garden. It is not a garden outside the bark. Bob can stand in the room after the tutorial. The Magic Assembly Station, the stash, the waystone, and the hollow bed stay where they are. The intro still meets him downstairs.

**Depends on.** The three hub remakes only so this patch does not fight their nav and gate work. It does not need their meshes.

**Ember Art.** One lab interior: chart, slab, shelf, stair, a handful of pots. If those meshes are missing, Kenney furniture blocks the room in and is swapped later. Do not ask for a new oak.

**Risks.** A stair that opens the roof without a wall brings back the fall the kill plane is catching. The room needs a floor and a closed edge. The playtest bot must still find Bob in the hollow during the intro, not up the stair.

**Tests.** Intro `new_home` still talks to Bob downstairs. After the crystal, the stair can be walked and the room has a floor. Full tier. Old Oak's exterior nav is rebaked only where the stair mouth changes the hollow. The old exterior layout stays.

### 0.11.0 — Act V, the Inverted Spire

**Scope.** The approved outline, not a remake. Five floors in the shaft after the Sunken Ruins. Platforms, long falls, wind that reverses, the downward tower, echoes of the four acts on its facets. Boss: the Storm Warden, fought with no safe floor. On death, a lit path down, not a fourth empty shell. Waystone home still works. One main quest, kill the Warden, in the same shape as the Sunken quest. No hymn text, no rebel join, no Core.

**Depends on.** Acts I–IV as they are. A kill plane on each platform floor (the fall is the hazard, so the plane and the designed pits must not be the same y). Ember Art for harpies or storm elementals, the spire facet kit, and the wind-lock read.

**Ember Art.** A platform kit, a downward-tower landmark readable from the first floor, a storm elemental or harpy, the Warden's silhouette, a crystal throat. Blockout can be grey until those exist. Do not ask Ember Art to redraw Kenney.

**Risks.** The kill plane will fight the design if every long fall is treated as a death. The plan for this act has to mark which falls are kills and which are the Warden's arena. The playtest bot has never pathfound a vertical void. Wind that shoves the player will desync in co-op unless the host is the only one who applies it.

**Tests.** New floor tests in the style of `test_sunken.gd`. Solo descent from the nave into the spire and home. Full tier. Co-op on the Warden once, including a fall that is supposed to kill and a shove that is not.

### 0.12.0 — The Core, and the names on the dial

**Scope.** Only if ShobieShy opens it. Fight Joe, corrupted, with spells that feel like the player's brands. Then the Demon Lord. Then he leaves. Loot and the leaving shot need a written pass first; this version should not invent them in code. In the same minor, or a patch on it: the hub dial for Covenant Escalation after Forgemaw, the Forgotten Abyss as a mode you can start while he is unbeaten, and the on-screen names matching the bible. Endless Descent stays off until he has a defeat flag.

**Depends on.** Act V's lit path, or an explicit skip. A written Joe fight and a written Demon Lord, even if short. `Vigil.xp_mult` stays unwired until a later ask. The Core does not start off this plan. ShobieShy has to write the fights first.

**Ember Art.** Joe's corrupted read, distinct from the landfill camp. A Demon Lord silhouette only after the face is no longer Open. The ward-pillars flickering is a DLC hook in the storyline and does not need a new mesh.

**Risks.** Building the Core before the face and the phases are accepted will freeze a guess. Wiring Endless Descent before his defeat flag exists will ship the wrong mode.

**Tests.** Boss-kill quests, the dial's save, a Forgotten Abyss floor that does not change dialogue, protocol unchanged unless the snapshot gains a field.

### Later 0.x — Endless Descent, rebels, DLC towns

Not scheduled as numbers.

- **Endless Descent** starts when the Demon Lord has been beaten. Floors may mix every act, including the spire. No new dialogue. Depends on 0.12.0's flag and on Act V's tiles existing so the mix is real.
- **Rebels** stay a faction you can join. No build until a leader, a join, and a reward are accepted. The Potion Merchant's tax line is enough foreshadowing.
- **DLC towns** each get a square, a chapter, shops, and a labyrinth, with a level minimum. Eldoria stays the main hub. Escalation on a DLC waits until the main Demon Lord is beaten. Names are Open. No art request until a town has a name.

Patches between these versions do not reopen quick win 12, the Choir, music, the rebels, or the DLC names. Windows ships unverified.

## 5. Decisions

ShobieShy answered these on 19 Nov 2026. They are no longer open.

1. **Order.** Decided. Town 0.10.0, Landfill 0.10.1, Association 0.10.2, Act V 0.11.0.
2. **Quick win 12.** Decided. Leave `Vigil.xp_mult` unwired. Leave `apply_void_on_player` uncalled. Closed as "leave."
3. **Late hits.** Decided, and the earlier default is withdrawn. A hit that arrives after the death still pays that shooter loot and XP, once, with no second kill and no second pile. How: the 0.10.0 section. Protocol 7.
4. **AppImage.** Decided. Attach it to public releases from the next prerelease on.
5. **Windows.** Decided. There is no PC. Build the zip anyway. Windows stays unverified and does not block.
6. **Music.** Decided. Silent until a track exists.
7. **Choir.** Decided. One body for now.
8. **Bob's lab.** Decided. Add it in 0.10.x. This plan puts it at 0.10.3, after the Association and before Act V, so the three remake PRs stay the three levels. The Old Oak exterior does not change. Scope and art are in the 0.10.3 section.
9. **The Core.** Decided. Closed until ShobieShy writes the fights.
10. **Rebels and DLC towns.** Decided. No leader and no town names yet.
11. **Proposed bible lines.** Decided. They stay out of dialogue.
12. **Late cliff art.** Decided. Ship Kenney cliffs and swap in Ember Art when the meshes exist.
