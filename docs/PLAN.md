# Covenant of Embers: plan for an original game

Working title. Plan only, with no code yet. A brand-new co-op Vulkan action RPG inspired by the spirit of Magewar and by biblical themes. It is not a copy or reskin of Magewar.

## 1. Magewar material found on Luna (read-only review)

- **~/game**: The main Godot 4.7 project (git, MIT license, .github issue templates but no CI workflows, docs/ = the COGITO template's Sphinx manual rather than Magewar design docs, Cogito FPS addon, no decision records). Its last commit adds a host-authoritative co-op foundation. The GDScript covers the player, quest tracker, prologue driver, kill rewards, instanced loot and network sync, plus headless logic tests.
- **~/magewar-mmo**: A Godot 4.6 fork from June that goes in an MMO direction. It has autoloads, assets, docs, README_PROTOTYPE.md and a Steam app id.
- **~/magewar3/magewar-prototype**: An earlier prototype. The Grok /implement notes in ~/.grok/implement-memory/magewar3-*.md record GDScript typing and .tscn issues, and a weapon/save system without automated tests.
- **~/magewarweb**: A single-page web version or site: index.html, about 92 KB, plus a README.
- **Design docs**: 'Magewar Bible.md' (46 KB) and 'Magewar Storyline.md' (12 KB). Copies are in ~, ~/Downloads, ~/magewar and in each project.
- **Godot user data**: Settings and save folders for Magewar, Magewar Prototype and proto2.

Magewar's core is "Konosuba meets Borderlands". It's a co-op magic looter FPS. Modular staffs are built from Handle, Shell, Internals and Head parts, and loot comes in rarity tiers from Basic to Unique. You equip gear such as a hat, belt, grimoire and wand, and modify spells at an enchantment forge. Six elements (Fire, Water, Earth, Air, Light, Dark) counter each other rock-paper-scissors style. In the story, comically weak "Summoned" heroes arrive in Elyria after the Dungeon Fracture, along with Crazy Joe, Bob in the tree, and The Filth landfill boss.

## 2. Core concept and loop

A co-op first-person action RPG for 1–4 players. You play exiles who carry light into a land darkened by an ancient rebellion. You recover lamps and rebuild altars of remembrance, and every restored region pushes back the dark.

Loop: leave the camp, which is a tabernacle-style hub that moves as you progress. Walk the wilderness regions, fight corrupted creatures, and redeem or free them rather than only killing them. Loot guns, gear and Gifts, then return to build up the camp. It's a Borderlands-style co-op looter FPS: procedurally assembled firearms drop from every fight, and Gifts (abilities earned through service and faithfulness) plug into those guns as Seals, so loot and character growth are one system. Each Gift carries a Fruit (love, patience, self-control…) that changes how it behaves. Some Gifts only work when given to an ally, so co-op is part of the design.

- **Kept from Magewar's spirit**: Co-op first-person magic combat, ability crafting, a humble underdog cast, a hub you build up, and light and dark as opposing forces.
- **Deliberately not reused**: No staffs/wands or their part names, no Basic→Unique tier names or values, no Fire/Water/Earth/Air/Light/Dark wheel, no Elyria, Eldoria, Summoned, Mage Association, Crazy Joe, Bob, The Filth or Demon Lord. Every Magewar mechanic is rebuilt below as an original loot-FPS system; see the mapping table.
- **Biblical themes**: Exile and return, wilderness, covenant, the shepherd, redemption over destruction, Sabbath rest as a mechanic (resting renews the camp), and pillar of cloud/fire navigation.
- **Treating scripture respectfully**: Biblical figures are never playable power fantasies, and God is never depicted as a combat ability. Verses are quoted verbatim from public-domain KJV/WEB as lore and never altered for jokes. Reviewers from more than one tradition check the content against a written content guide. Humor lives in the original characters only.

## 3. Loot-gun system (Instruments)

Every weapon is a procedurally assembled firearm called an Instrument, built from six part slots and made by one of five fictional Workshops. Parts drop from enemies and can be swapped at the Workbench in camp. Gifts socket into the Seal slot, so abilities become weapon behaviour.

| Part slot | What it controls |
|---|---|
| Frame | Weapon family and base damage curve by item level. Sets the magazine size range. |
| Barrel | Projectile count, spread, range falloff and projectile speed or hitscan. |
| Chamber | Fire rate, fire mode (semi, burst, auto, charge) and reload speed. |
| Grip and stock | Recoil pattern, sway, handling (equip and ADS speed) and accuracy bloom. |
| Sight | ADS zoom (1×–8×), ADS field of view and crit bonus while aimed. |
| Seal (optional) | A socketed Gift: adds an essence, an on-hit effect or an alt-fire. The Gift's Fruit tunes it (Patience = charge shot, Self-control = lower recoil, Kindness = shots that pass an ally heal them). |

- **Weapon families**: Sidearm, Repeater (SMG), Longbarrel (rifle), Scattergun, Sling-launcher (explosive arcs), Lance (continuous beam that uses Lamp Oil instead of ammo).
- **Workshops**: Ashfall Foundry (high damage, slow reload), Lampwright & Daughters (Oil efficiency, beams), Shepherd's Arms (accuracy, ally-support Seals), Reedcutter Co. (fast, light, big magazines), Watchtower Optics (scopes, crits). Each has a visual language and a reload gimmick.
- **Firing, ammo and reload**: Physical ammo per family with a real reload (tactical vs empty reload, reload cancel). Lamp Oil is a second resource that regenerates after 1.5 s out of combat and powers Seals and Lances, so the old mana loop survives as a secondary layer.
- **ADS and accuracy**: Hold right mouse to aim: field of view tween, reduced bloom and sway, sight-based crit bonus. Hip-fire uses a spread cone that grows per shot and recovers over time.
- **Damage formula**: Hit = Frame base(item level) × Grade mult × (1 + Σ part bonuses) × essence vs armour × crit (weak point ×2, ADS sight bonus) × Calling bonuses. Shown as floating numbers, with crits and resisted hits styled differently.
- **Grades (rarity)**: Five grades: Clay (grey, ×1.0, weight 52), Bronze (green, ×1.15, 26), Silver (blue, ×1.35, 13), Gold (violet, ×1.6, 6), Crown (amber, ×1.9, 3). Higher grades roll more part bonuses. Relics are hand-designed named weapons that can drop at Gold or Crown with an original flavour line and a unique behaviour.
- **Naming**: Generated names (prefix from the strongest bonus + Workshop model), e.g. 'Stubborn Reedcutter Hound'. Humour lives in item text, never in scripture.

## 4. Gear, inventory and loadout

- **Weapon slots**: Four weapon slots (two unlocked at start, two by Calling level), quick swap on 1–4 or the D-pad.
- **Gear slots**: Mantle (armour, shield capacity), Satchel (ammo and grenade capacity), Sandals (move speed, dash), Signet (a stat ring), Lamp (Oil pool and regen), Throwable (grenade-like Flasks).
- **Consumables**: Healing Bread and Oil Flasks on a quick-use key, with stack limits.
- **Gear stats**: Health, shield, Breath (stamina), Oil, move speed, essence damage, essence resistance, Oil regen. Gear can carry an essence affinity.
- **Inventory**: Grid backpack with sort, compare cards (green/red stat deltas), mark as junk, favourite, and salvage. The camp stash is shared by all of a player's characters.
- **Auto-equip**: Optional setting: auto-equip an obvious upgrade in an empty slot.

## 5. Essences, armour and Redemption

- **Essences**: Kindling (burn over time, strong vs Flesh), Brine (corrodes, strong vs Plate), Tempest (chains, strong vs Wards/shields), Radiance (cleanses and heals allies on hit, strong vs Shadowed). Unaligned shots are Plain.
- **Enemy armour types**: Flesh, Plate, Ward (regenerating barrier) and Shadowed. Effectiveness is ×1.5 strong / ×0.6 weak, shown by a coloured health bar and hit sparks, so it's a matchup system, not a cycle.
- **Status effects**: Burning, Corroded (armour down), Shocked (chains, stuns Wards), Blessed (ally heal-over-time), Staggered (from heavy hits), Slowed.
- **Player resistances**: Per-essence resistance from gear (cap 60 %) plus a small resist from Fruits.
- **Redemption (replaces Dark corruption)**: Bring a Shadowed enemy under 25 % health with Radiance damage and hold Interact to Release it. Released creatures fight beside you for 30 s, then leave in peace. Chance scales with Radiance damage and the Shepherd Calling. Bosses can't be Released.
- **Lamp companion (replaces the Light summon)**: A small mechanical lantern drone from the Shepherd tree: lights dark areas, marks enemies, revives slowly. One per player, 30 s cooldown when destroyed.

## 6. Movement

- **Core**: WASD, jump, crouch, sprint (drains Breath), slide from sprint, mantle ledges, ground-slam from air.
- **Dash**: Short directional dash on a Breath cost with two charges; Sandals can add a third or a damage trail.
- **Traversal**: Pillar beacons (jump pads), ziplines in the Heights, swimming in the Reedlands, a summonable cart for big regions.
- **Feel**: Camera bob, landing dip, recoil kick and screen shake, all scaled by the accessibility settings.

## 7. Combat and enemy AI

- **Combat rules**: Weak points (×2), knockback and stagger, a shield that regenerates after a delay before health, downed state with a 'Second Wind' kill-to-revive window and ally revive.
- **AI states**: Idle/patrol → detect (15 m sight, sound cues) → aggro (10 m) → attack (cooldowns per move) → reposition/flank → flee at low morale. Group roles: rusher, shooter, tank, support.
- **Navigation**: Recast/Detour navmesh baked by the cooker, with off-mesh links for jumps.
- **Netcode**: Host simulates AI and damage; clients predict their own movement and shots and get reconciled.
- **Difficulty**: Enemy health scales with party size (+60 % per extra player) and level; elite affixes (Burning, Warded, Swift, Splitting) appear more often on higher Vigil levels.

## 8. Enemies

| Family | Role | Notes |
|---|---|---|
| Gnawers | Swarm rusher | Plated scavenger vermin; tutorial fodder. Flesh/Plate. |
| Heaps | Tank | Lumbering junk constructs; weak point is a glowing core seam. |
| Mire oozes | Splitter | Split into smaller oozes when hit by Kindling; leave slowing puddles. |
| Cinderkin | Ranged | Small fire imps that lob embers; flee when hurt. |
| Wastrels | Human raiders | Gunmen with cover use and grenades; drop more ammo. |
| Shades | Shadowed | Phase in and out; the main Redemption target. |
| Wardens | Support | Project Wards on allies; kill first. |
| Region specials | Varies | Each region adds two: e.g. salt crabs (Flats), cliff harpies (Heights), drowned lurkers (Coast). |

Each enemy has a level (1–50), XP value, Tally drop and a loot table with a drop chance, plus optional guaranteed quest drops.

## 9. Bosses (multi-phase)

- **Tutorial: The Midden**: A heaving mound of refuse and spoiled oil at the dump. Phase 1 (100–66 %): lobs sludge every 3 s, sweeps. Phase 2 (66–33 %): splits off Mire oozes, sludge every 2 s, regenerates from nearby trash unless the piles are burned. Phase 3: core exposed, sludge every 1.2 s. Drops the Old Lantern Coil needed for fast travel.
- **Five Breach wardens**: One per region, each 3 phases with a rule change (arena flood, Ward pylons to break, darkness needing the Lamp companion, add waves, enrage timer).
- **Finale**: The Pretender's Herald (a fallen lampkeeper who rang the bell that brought the exiles) then the Pretender in his citadel, a two-arena fight. The Pretender is a fictional usurper, never a depiction of God or a biblical figure.
- **Boss rules**: Health bar with phase pips, arena lock, checkpoint at the boss door, guaranteed Gold-grade drop per player and a Relic chance; rematch at the camp's Memorial Stones.

## 10. Progression: XP, levels and Callings

- **XP and levels**: Level cap 50. XP needed grows ×1.35 per level. Exiles earn 'Resolve' (+50 % XP while under the party's highest level) so friends can catch up. Each level adds health, Breath and Oil and gives one Calling point.
- **Callings (skill trees)**: Watchman (precision, crits, scopes), Shepherd (healing, Redemption, Lamp companion), Smith (turrets, Workbench perks, explosive Flasks), Herald (shouts, team buffs, crowd control). Each has three tiers and a capstone; respec at camp for Tallies.
- **Gifts and Fruits**: Gifts come from quests and bosses (not random drops). Each socketed Gift levels with use; Fruits are a 9-node passive board unlocked by community deeds in camp.
- **Endgame**: Vigils: replay Breaches with stacking modifiers and better Grade odds; a Pilgrimage route that chains regions with a leaderboard.

## 11. Economy and loot

- **Currency**: Tallies (start with 50). Dropped by enemies, from salvage and quests.
- **Vendors**: Quartermaster (ammo, Flasks, basic guns), Armourer (gear), Seal-cutter (re-roll one part bonus), Pilgrims' Market (rotating daily Relic-chance stock).
- **Kill rewards**: XP and Tallies go to every player in range on a kill (host-authoritative).
- **Instanced loot**: Every drop is rolled separately per player and only visible to that player; quest items go to the whole party. Optional trading of non-quest items in camp.
- **Drop feel**: Ammo and Tallies auto-collect; weapons and gear drop with Grade-coloured light pillars, a loot feed in the HUD and a pickup sound per Grade.
- **Salvage**: Break unwanted items into Scrap for Workbench crafting and Seal re-rolls.

## 12. World map, regions and fast travel

Ten years ago the old wells and vaults broke open and the land went dark; only places guarded by Watchfires are safe, and about 60 % of the map is wild. Relighting Watchfires expands safe ground and is the main measure of progress.

| Region | Feel | Breach (dungeon) |
|---|---|---|
| The Ashen Midden | Town dump outside the first settlement; tutorial. | None (the Midden boss) |
| Reedlands | River marsh, farms under raider attack. | The Drowned Cistern |
| Cedar Heights | Cliffs, wind, ziplines and aerial ruins. | The Hanging Granary |
| Salt Flats | Blinding plains, mirage fights, salt crabs. | The Pillar Mine |
| Hollow Mines | Deep tunnels and ore for gear upgrades. | The Deep Forge |
| Storm Coast | Wrecked harbour and sunken ruins. | The Leviathan Hulk |
| The Citadel | Unlocked after five Breaches. | Finale |

- **Settlements**: Each region has one safe town with vendors, quest givers and a Watchfire.
- **Fast travel**: Waystones you light by touching them; travel from any Waystone or the camp map. Unlocked after the tutorial when the mentor builds the Wayfinder from the Old Lantern Coil.
- **Level layout rules**: Open regions with linked combat arenas, landmarks visible from far away (pillar of smoke by day, fire by night points to the next objective), secrets and chests off the main path.

## 13. Hub: the Camp

- **Start**: The exiles are given a ruined cistern-house outside town as lodging; the recluse who secretly lives in it becomes their mentor.
- **Stations**: Workbench (assemble/swap parts), stash, Quartermaster, Armourer, Seal-cutter, quest board, training range with dummies, Memorial Stones (boss rematches), map table (fast travel).
- **Growth**: Restored Watchfires and finished side quests bring NPCs who move into camp and add stations; the camp visibly grows.
- **Sabbath rest**: Resting at the camp fire renews the camp (vendor stock, daily bonuses) and gives a rested-XP bonus; no penalty for not resting.

## 14. Breaches (dungeons)

- **Layout**: Entrance → 3–5 combat rooms → a traversal or switch puzzle → mini-boss → boss arena → loot vault. Hand-built rooms, shuffled order and enemy sets per run.
- **Mechanics**: Each Breach has a signature hazard (flooding, wind, darkness, salt glare, heat) that ties to an essence.
- **Rewards**: Chests per player, guaranteed Gift on first clear, boss loot.
- **Replay**: Vigil levels with modifiers for endgame.

## 15. Story, characters, NPCs and quests

- **Premise**: Four ordinary exiles are pulled into a broken land by a desperate bell-ringer's rite meant to call champions. They're weak, pitied and given a ruin to live in; the land's darkness hides a conspiracy they slowly uncover.
- **Playable exiles**: The Scholar (Oil bonus, knows too much trivia), the Talker (cheaper vendors, banter), the Hauler (health, carries everything), the Scout (Breath, dash). Archetype picked in the lobby; cosmetic plus a small perk.
- **Key NPCs**: Mother Ada (the reclusive tinkerer mentor), Brother Caspar (the disgraced bell-ringer, later the Herald), Warden Lysa (the Watchfire keepers' captain), Fennick (a merchant who knows every rumour).
- **Main quest**: Prologue: the rite, the town, the new home. Act 1: the Midden and the Wayfinder. Then the main thread stays vague: clues from NPC dialogue and rumours point to the five Breaches, then the Citadel.
- **Side quests**: Defend a farm from raiders (reveals a Breach), escort a caravan (unlocks a map region), clear a mine (upgrade ores), plus bounties and rescue jobs.
- **Quest system**: Data-driven in Lua: objectives (kill, collect, talk, reach, escort, defend), flags, rewards, a Clue Log and on-screen tracker; shared by the party in co-op.
- **Dialogue**: Branching dialogue with conditions on flags, repeat lines, voiced barks; humour in the original cast only.
- **Factions**: Watchfire Keepers vs the Free Wells (settlers who distrust the keepers' monopoly); reputation unlocks vendors and quest lines.
- **Scripture use**: Lore tablets at Waystones and Watchfires quote public-domain KJV/WEB verbatim (e.g. Psalm 119:105 KJV, 'Thy word is a lamp unto my feet, and a light unto my path.').

## 16. Co-op

- **Session**: 1–4 players, host-authoritative, lobby with archetype pick and ready-up, drop-in/drop-out, invite codes plus optional Steam integration.
- **Shared vs personal**: Shared: quest progress, world state of the host. Personal: loot, XP, Tallies, character save.
- **Team mechanics**: Revive, give-a-Gift Seals, Shepherd heals, pings (enemy, loot, place), a team buff when all four are near a Watchfire.

## 17. UI and HUD

- **HUD**: Health, shield, Breath and Oil bars, ammo and magazine, weapon and Seal icons, crosshair with hit markers, compass with quest markers, mini-map, party frames, loot feed, floating damage numbers, boss bar.
- **Menus**: Main menu, lobby, character select, inventory with compare cards, Workbench, Calling trees, Fruit board, map with Waystones, Clue Log, vendor screens, pause, options.
- **Tech**: RmlUi for game UI with controller navigation; every screen usable with a gamepad.

## 18. Audio

- **Buses**: Master, SFX, Music, Voice, UI, Ambient with separate volume sliders.
- **Weapons**: Per-Workshop firing sounds, reload foley, essence impact layers, Grade-specific pickup stingers.
- **Music**: Adaptive per region (explore → combat layers → boss stems), hymn-inspired motifs written new or from public-domain melodies.
- **Ambience**: Region beds, positional sound in miniaudio, enemy audio cues for AI telegraphs.

## 19. Art direction

- **Style**: Stylised low-to-mid poly with cel shading and ink outlines; strong silhouettes and exaggerated proportions.
- **Colour language**: Dusty, desaturated world; emissive lamplight, essence colours and Grade colours pop. Juicy feedback on every shot, hit, loot drop and phase change.
- **Avoid**: Muddy realistic grime and low-contrast darkness.

## 20. Saves, settings and accessibility

- **Saves**: Per-character save (level, gear, serialised weapon parts, Gifts, quests, Tallies) and a world save on the host; autosave at Waystones and the camp; versioned schema with migrations; round-trip tests in CI.
- **Settings**: FOV, mouse and stick sensitivity, invert Y, full rebinding for keyboard and controller, rumble, graphics (bloom, SSAO, fog, resolution scale), audio buses.
- **Accessibility**: Reduced motion (no shake or bob), colour-blind modes for Grades and essences, subtitles, hold/toggle options, aim assist on controller, Steam Deck layout.

## 21. Magewar → Covenant mapping

| Magewar | Covenant of Embers (original) |
|---|---|
| Staffs/wands from Head, Exterior, Interior, Handle, Charm | Firearm Instruments from Frame, Barrel, Chamber, Grip, Sight, Seal |
| Magic Assembly Station | Camp Workbench |
| Mana, cooldown, no reload | Ammo with reload, plus regenerating Lamp Oil for Seals and Lances |
| Right-click zoom | ADS with sight-based zoom and crit bonus |
| Basic→Unique tiers (×1–×3) | Clay→Crown Grades (×1–×1.9) plus named Relics |
| Six elements, rock-paper-scissors | Four essences vs four armour types |
| Light heal and Light summon | Radiance ally-healing and the Lamp companion |
| Dark corrupts enemies into summons | Redemption: Release Shadowed foes to fight with you |
| Hat, clothes, belt, shoes, potion, grimoire, wand | Mantle, Satchel, Sandals, Signet, Lamp, Throwable, consumables |
| XP, ×1.5 Summoned growth, gold | XP with Resolve catch-up, Tallies, vendors |
| Per-player instanced loot and kill rewards | Same principle, rebuilt host-authoritative |
| Rats, garbage golems, slimes, ember scorchlings | Gnawers, Heaps, Mire oozes, Cinderkin and more |
| The Filth, 3 phases | The Midden, 3 phases, plus five Breach wardens |
| 5 dungeons, then Demon Lord and Crazy Joe | 5 Breaches, then the Herald and the Pretender |
| Barriers, 60 % wild land | Watchfires you relight |
| Old Oak hub, Bob | Cistern-house Camp, Mother Ada |
| Teleport crystal from Joe's trash | Wayfinder from the Old Lantern Coil, Waystones |
| Nerd, Gal, Buff, Loli archetypes | Scholar, Talker, Hauler, Scout |
| Woods, Peaks, Crimson Sea, mines, Willowbrook | Reedlands, Cedar Heights, Salt Flats, Hollow Mines, Storm Coast |
| Mages vs rebels factions | Watchfire Keepers vs Free Wells |

## 22. Gap audit (Magewar material vs the previous plan)

All five copies of each design doc are byte-identical. Gaps were found by reading both docs, ~/game/magewar scripts and scenes, ~/magewar-mmo (README_PROTOTYPE, ART_STYLE, autoloads, levels, options), ~/magewar3/magewar-prototype, ~/magewarweb and the ~/.grok implement notes.

| Gap in previous plan | Added in section |
|---|---|
| Weapon types, firing, ammo/mana, reload, ADS, accuracy, damage formula, procedural parts, assembly | 3 |
| Rarity tiers, weights, multipliers, procedural names | 3, 11 |
| Equipment slots, stat bonuses, potions, inventory, quick swap, auto-equip | 4 |
| Elements, rock-paper-scissors damage, status effects, resistances | 5 |
| Light heal/summon, Dark corruption into summons | 5 |
| Sprint, crouch, dash, jump, camera feel | 6 |
| Knockback, detection/aggro ranges, AI, contact damage, party scaling | 7 |
| Enemy roster, levels, XP/gold/loot tables | 8 |
| Multi-phase bosses, final boss sequence | 9 |
| XP curve, levelling stats, growth multiplier, skill trees | 10 |
| Gold, vendors, kill rewards, per-player instanced loot, loot pillars and feed | 11 |
| World structure, barriers, regions, towns, fast travel | 12 |
| Home tree hub and its upgrades | 13 |
| Five dungeons and their layouts | 14 |
| Story arc, mentor, disgraced summoner, archetypes, NPC dialogue, quests, clue log, factions | 15 |
| Co-op lobby, host/join, archetype pick, sync | 16 |
| HUD, mana bar, damage numbers, equipment panel, menus | 17 |
| Audio buses, element cast/impact and rarity pickup sounds; empty Music Overview | 18 |
| Art style guide (juicy, saturated, low-poly) | 19 |
| Saves, settings, rebinding, colour-blind and reduced motion, controller/Steam Deck | 20 |
| Lessons from ~/.grok notes (tests for saves and data models) | 25 (CI) |
| Empty Bible roadmap | 26 (milestones) |

## 23. Technical architecture

Engine switched to Godot 4 on 2026-10-23 ([ADR-0002](adr/0002-switch-to-godot.md)); the C++20/Vulkan choices of [ADR-0001](adr/0001-language-and-libraries.md) are archived in `archive/cpp-engine/`.

| Area | Choice | Why |
|---|---|---|
| Engine | Godot 4.7.2 stable | Same engine as Magewar (~/game); renderer, physics, UI, audio, navigation and export built in. |
| Language | Typed GDScript | Fast iteration, matches Magewar's scripts. |
| Main loop | Godot physics at 60 Hz (`_physics_process`), render interpolated | Deterministic gameplay ticks; input edges per tick, mouse look per frame. |
| Renderer | Forward+ (Vulkan), MSAA 2× | Default high-end Godot renderer. |
| Physics | Godot's Jolt Physics module | Same physics library as the archived engine. |
| Input | InputMap actions | Rebindable, saved to user://. |
| UI | Godot Control nodes, Kenney UI Pack | Replaces ImGui/RmlUi. |
| Audio | Godot AudioServer buses + AudioStreamPlayer3D | Replaces miniaudio. |
| Navigation | NavigationServer3D / NavigationAgent3D | Enemy chase around walls. |
| Networking | Host-authoritative via Godot high-level multiplayer (ENet) | The lesson ~/game already learned. |
| Data | Godot Resources (.tres); TOML/JSON data converted by tools | Patches stay data (§31). |
| Build/tests | `godot --headless`; tests/run_tests.gd; tools/run_tests.sh | One headless green gate locally and in CI. |

## 24. Repo structure

- **project.godot · scenes/ · scripts/ (core, player, magic, combat, enemies, loot, ui, save) · resources/ · assets/ (kenney/, magewar/) · data/**
- **tests/** (run_tests.gd, test_case.gd, unit/test_*.gd) · **tools/** (run_tests.sh, check_assets.py) · **docs/** (PLAN, BUILD_PLAN, ADRs)
- **archive/cpp-engine/**: the archived C++20/Vulkan engine (Godot-ignored)
- **LICENSE · CREDITS.md · ASSETS.toml**

## 25. CI and testing

- **Builds**: GitHub Actions on Linux runs Godot 4.7.2 headless: import, unit tests, smoke run, asset lint; Windows/Linux exports and gdlint/gdformat after the slice.
- **Gameplay tests**: Headless GDScript tests for movement, damage formula, loot rolls and weights, part assembly, element matchups, save/load round-trips and quest flags.
- **Render checks**: Headless viewport captures where needed (e.g. viewmodel gem colour).
- **License lint**: Any asset not listed in ASSETS.toml fails the build.

## 26. Milestones

| Milestone | Duration | Scope |
|---|---|---|
| M0 Foundations | 4–6 weeks | A window, a triangle that runs clean under validation, CI, the cooker stub, and the language ADR. |
| M1 Gunplay prototype | 2–3 months | FPS controller with sprint, slide, dash; Jolt; one Workshop with Sidearm and Repeater; ammo, reload, ADS, damage numbers; Gnawers and Heaps with basic AI; greybox Midden; save round-trip tests. |
| M2 Loot core | 2–3 months | Six-slot procedural parts, five Grades, Workbench, inventory and compare cards, gear slots, essences vs armour, status effects, Tallies, Quartermaster, instanced loot. |
| M3 Vertical slice | 4–6 months | Polished Midden tutorial, The Midden boss, the Camp hub, Mother Ada, Wayfinder and Waystones, 2-player co-op, Lua quests and dialogue, HUD, audio buses, cel-shaded look, scripture lore tablets. |
| M4 Alpha | 6–9 months | Reedlands and Cedar Heights with two Breaches and wardens, all four Callings, Gifts as Seals with Fruits, Redemption and Lamp companion, all enemy families, 4-player co-op, factions, options and accessibility. |
| M5 Beta | 6+ months | Remaining regions and Breaches, Citadel finale, Relics, Vigils endgame, balancing, performance, localisation. |
| M6 1.0 | Ongoing | Packaging for Flatpak, Steam and itch, modding docs, content updates. |

## 27. Risks

- **Engine scope creep**: Resolved by switching to Godot 4 (ADR-0002); keep custom systems to gameplay.
- **Netcode complexity**: Design host-authoritative from M1.
- **Sensitive religious content**: Use reviewers and a written content guide.
- **Mixed asset styles and licenses**: Keep one art direction and enforce the manifest.
- **Solo bandwidth**: Write good contributor docs from day one.

## 28. Open source licensing

- **Code**: Recommended: Apache-2.0, which is permissive and includes a patent grant. MIT is the simpler alternative. Choose GPL-3.0 only if forks must stay open.
- **Original assets**: CC BY-SA 4.0 in LICENSE-ASSETS. Third-party assets keep their own licenses.
- **Scripture**: The WEB is public domain and the safest choice. The KJV is public domain except in the UK, where Crown patent applies, so note that. Don't bundle NIV, ESV and similar translations, which are copyrighted.

## 29. Assets

> **Downloads allowed:** The user has allowed asset downloads for this plan and future work. Record every asset in ASSETS.toml and CREDITS.md with its source URL, author, license and date.

- **Kenney (kenney.nl, CC0)**: The first choice for 3D models, textures, UI and audio.
- **Poly Haven (CC0)**: HDRIs, PBR textures and models.
- **ambientCG (CC0)**: PBR materials.
- **Quaternius (CC0)**: Stylized characters, creatures and nature packs.
- **OpenGameArt**: Licenses vary, so check each asset. Prefer CC0 or CC-BY.
- **Freesound**: Filter to CC0 or CC-BY, credit the authors, and avoid NC licenses.
- **Mixamo**: Check Adobe's terms. It's usable in games, but the raw files can't be redistributed in a public repo, so keep them out of git or bake them into the game's formats.

_Source canvas: https://cursor.com/canvas/store-396a3e54-44f5-47da-91d4-d350fd08f6ee/e70f4cd3-e188-4846-8e8b-b32b3a8143fa_

## 30. Loot-shooter core specification (implementation reference)

Buildable rules for M1–M2. **Weapons, loot and crafting follow the Magewar design directly** (ShobieShy's own IP; user-approved 2026-10-22). Sources: `~/game/Magewar Bible.md` (Gameplay Overview, Staff/Wand Crafting, Equipment and Inventory) and `~/game/magewar/scripts/{items/item_rarity.gd, items/staff_part_item.gd, items/staff_wieldable_item.gd, items/equipment_item.gd, magic/magic_element.gd, magic/loot_generator.gd, magic/magic_assembly_station.gd, player/mana_attribute.gd}` plus `resources/items/`. The earlier gun families, ammo and 5-Grade curve are retired.

### 30.1 Wieldables, casting and mana
| Type | Parts | Slot | Magewar bases (dmg / mana / cooldown) | Role |
|---|---|---|---|---|
| Staff | 4–5: Head, Exterior, Interior, Handle, Charm (optional) | main weapon | Apprentice Fire Staff 10 / 5 / 0.40 s; Earthward Battlestaff 14 / 6 / 0.55 s | Primary caster, higher damage, focus FOV 55° |
| Wand | 2–3: Head, Exterior, Handle (optional) | equipable | Novice Arcane Wand 7 / 3 / 0.25 s; Swift Wind Wand 6 / 2.5 / 0.18 s | Fast light caster, focus FOV 55° (Magewar's wand uses the staff script's `ads_fov` 55) |

- The base staff/wand **is the spell** (element, projectile speed, mana cost, cooldown) and has its own rarity; parts are modifiers added at a Magic Assembly Station.
- **Mana** is the only casting resource: 100 base, cost per cast, regen 3/s after 1.5 s without casting, equipment adds regen. No ammo or reloads.
- **Accuracy** 0–100 %: 50 base + Head + Handle + Charm bonuses; spread cone `(s_max + bloom) × (1 − acc/100) × stance` (s_max 4°, focus 0.35, crouch 0.8, moving 1.3, airborne 1.8; bloom +1° per cast, cap 4°, clears in 0.5 s). Magewar computes accuracy but never applies it to aim; the cone is our design.
- **Damage**: `dmg = base × RarityMult(rarity) + Σ part damage_bonus` (rarity = the assembled rarity, §30.3; a bare base uses its own), then `× ElementEffectiveness × (1 − Resist ≤ 0.6) × Crit (weak point ×2)` (scripts/combat/damage.gd, step 6). Resist is per incoming element like Magewar's `get_elemental_resistance`, but capped at 60 % (Magewar clamps to 90 %); weak-point crits are our addition (Magewar has none).
- **Cooldown** = base × Exterior modifier × Charm modifier, minimum 0.1 s. **Element** = Head element if set, else base element.
- **Bolts** (step 7): a straight, fast bolt ray-swept per tick from the eye (lands under the crosshair), fizzling at the wieldable's range (Magewar: base `range`; its 0.1 m projectile sphere with gravity and 8 s lifespan is reinterpreted as no-drop). Casting is semi-auto on the Fire press like Magewar; a hold-to-cast option comes with the options screen.

### 30.2 Parts and rarities
| Rarity | Colour | Multiplier | Drop weight |
|---|---|---|---|
| Basic | #B3B3B3 (gray) | ×1.0 | 50 |
| Uncommon | #33CC33 (green) | ×1.25 | 25 |
| Rare | #3366FF (blue) | ×1.5 | 15 |
| Mythic | #991AE6 (purple) | ×2.0 | 7 |
| Primordial | #FF9900 (orange) | ×2.75 | 2 |
| Unique | #FFD900 (gold) | ×3.0 | 1 |

- Luck: −5 weight per point on Basic/Uncommon (min 1), +2 per point on Rare and above.
- Part types and rolls (× rarity multiplier):
  - **Head** (staff and wand): damage 1–5, accuracy 0–10, element, gem slots 1 (+1 at Rare+, +1 at Primordial+, max 3; wands use 1).
  - **Exterior**: fire-rate modifier ×0.7–1.3 below Rare, ×0.5–1.0 (faster) at Rare+ (Magewar loot_generator; fire-rate rolls are never × rarity).
  - **Interior** (staff; base damage): damage 2–8, element.
  - **Handle** (optional on wands): accuracy 5–20, handling 2–10.
  - **Charm** (staff only, optional extra augment): damage 0–3, accuracy 0–8, fire-rate modifier ×0.85–1.0, element.
  - Stats a type doesn't roll come from Magewar's template part for that type (e.g. a Charm keeps handling 4); the element is the caller's (enemy/pool) or rolled with Magewar's element weights (Arcane 2, Fire/Water/Earth/Air 1, Light/Dark 0.5).
- Names (Magewar ladders, by rarity): Head "<Rough|Polished|Brilliant|Ethereal|Ancient|Legendary> <Element> Crystal Head", Exterior "<Oak|Ash|Ironwood|Darkwood|Starwood|Worldtree> Exterior", Interior "<Element> <Mana Core|Arcane Conduit|Ley Channel|Void Heart|Prism Core|Soul Engine>", Handle "<Leather|Silk|Chain|Rune-etched|Crystalweave|Dragonhide>-Wrapped Handle", Charm "<Element> <Charm|Talisman|Sigil|Ward|Relic|Artifact>".
- Drops (Magewar roll_procedural_drops, step 18): each kill rolls its enemy's pool once against `drop_chance` (0.3) for one weighted base wieldable of the rolled rarity (none of that rarity → the nearest lower tier, then higher), plus 1 random part (2 at enemy level ≥ 3) of a uniform part type with the enemy's element, and a 25 % chance of one Hat/Clothes/Belt/Shoes at luck × 0.5. All rarities use the table above (Magewar's procedural thresholds 45/25/15/8/5/2 % differ).
- Deterministic generation: every item stores `seed + rarity + part ids`; the host rolls, clients regenerate identically. Stored form is an **Ember Mark** (§31.5).

### 30.3 Equipment, inventory and crafting
- Equip slots (Bible): Staff, Wand, Hat, Clothes, Belt, Shoes, Grimoire, Potion.
  - Hat: mana 5–15, spell damage 0.5–3, mana regen 0.2–1.
  - Clothes/Robes: health 5–20, mana 3–10, elemental resist 5–15 % on any non-Arcane piece (Magewar; Arcane robes keep the template's 5 %, vs Arcane damage).
  - Belt: health 3–8, stamina/Breath 5–15.
  - Shoes: speed ×(1 + 0.02–0.10 × rarity multiplier) (×1.02–1.10 at Basic, up to ×1.06–1.30 at Unique), Breath 3–10.
  - Grimoire: spell damage 2–8, mana 10–25, mana regen 0.5–2.
  - Potion: health (+30) or mana (+25) potion quick-slot, stacks of 5; refused (not consumed) when that pool is full.
  All rolls × rarity multiplier; stats a slot doesn't roll keep the Magewar template's (rolled Shoes keep health 5). Worn totals: health/mana/Breath max, mana regen, speed (product), spell damage (flat, added to every cast: ShobieShy's decision, Oct 24 2026; Magewar only displays it), resist per affinity (summed, capped 60 % when a hit resolves). Step 19: scripts/loot/equipment_item.gd, equipment_roller.gd, scripts/player/equipment.gd.
- Backpack grid (30 slots), rarity-coloured borders, compare cards with stat deltas, salvage to Scrap, shared camp stash.
- **Crafting: Magic Assembly Station only.** Staff = Head + Exterior + Interior + Handle (+ Charm); Wand = Head + Exterior (+ Handle). Assembled rarity = floor(mean part rarity) and replaces the base's rarity. Preview without consuming, assemble consumes parts, disassemble returns them. Builds that don't fit are rejected with a message (Magewar silently drops Interior/Charm on a wand); the player picks the base (Magewar always uses a template). Assembled name "<Rarity> <Element> Staff|Wand" (Magewar). Handling (Σ part handling_bonus; Magewar never reads it) shortens the draw: 0.4 s × 100 / (100 + handling), ≥ 0.2 s. Wand Heads use 1 gem slot.
- **Worked examples** (Magewar parts, resources/parts; test_assembly.gd):
  1. Apprentice Fire Staff + basic_fire_head, basic_exterior, basic_interior, basic_handle: tiers 0,0,0,0 → Basic ×1.0 → 10 + 2 + 0 + 3 + 0 = **15** dmg, 0.40 s, 50 + 5 + 10 = **65 %**, Fire, "Basic Fire Staff", handling 5 → draw 0.381 s.
  2. Same + rare_light_charm: tiers 0,0,0,0,2 → 0.4 → Basic → **17.5** dmg, 0.4 × 0.9 = **0.36 s**, **75 %**.
  3. Earthward Battlestaff (Uncommon base) + primordial_fire_head, mythic_water_exterior, basic_earth_interior, rare_air_handle, unique_void_charm: tiers 4,3,0,2,5 → 2.8 → **Rare** ×1.5 → 14 × 1.5 + 12 + 1.5 + 3.5 + 0 + 8 = **46** dmg, 0.55 × 0.55 × 0.85 = **0.257 s**, 50 + 15 + 22 + 12 = **99 %**, Fire (Head beats base Earth), "Rare Fire Staff", 3 gem slots, handling 22 → draw 0.328 s.
  4. Swift Wind Wand + rare_water_head, uncommon_air_exterior, uncommon_dark_handle: tiers 2,1,1 → 1.33 → Uncommon ×1.25 → 6 × 1.25 + 6 + 0 + 1 = **14.5** dmg, 0.18 × 0.65 = **0.117 s**, 50 + 12 + 15 = **77 %**, Water, "Uncommon Water Wand", 1 gem slot (Head has 2). Without the Handle: 13.5 dmg, 62 %. Extras (our additions on Magewar's base): element gems socket into Head gem slots; parts salvage to Arcane Dust; Dust upgrades a part one rarity tier (never to Unique).

### 30.4 Elements, resistances, summons and corruption
- **Magewar elements (authoritative for the weapon system):** Fire #FF4D1A, Water #1A66FF, Earth #80591A, Air #CCF2FF, Light #FFF2B3, Dark #4D0080, Arcane (none) #B3B3B3. Cycle Fire > Earth > Air > Water > Fire (×1.5 strong / ×0.5 weak), Light and Dark ×1.5 against each other, same or Arcane ×1.0. Light heals and has one summon; Dark corrupts enemies into summons. The essence names below are kept as lore flavour only.
- Essences: Kindling, Brine, Tempest, Radiance, plus Plain. Counters are against armour types (Kindling > Flesh, Brine > Plate, Tempest > Ward, Radiance > Shadowed) — a matchup table, not a cycle. Weak match ×0.6.
- Status: Burning (DoT), Corroded (−25 % armour), Shocked (chain 3 targets, stuns Wards), Blessed (ally HoT), Staggered, Slowed. Build-up meters per status so status is earned, not a coin flip.
- Player resistance per essence from gear and Fruits, hard cap 60 %.
- **Summon (Lamp companion)**: one lantern drone per player (Shepherd tree) — lights, marks, slow revive; 30 s respawn.
- **Corruption reinterpreted as Redemption**: Shadowed enemies below 25 % HP after Radiance damage can be Released (hold Interact); they fight for you 30 s then leave. Bosses immune. Enemies can also corrupt players: Shadow build-up inverts healing until cleansed by Radiance or Bread.

### 30.5 XP, levels, currency and vendors
- Cap 50; `XP(L) = 120 × 1.35^(L−1)` (soft-capped after 30 by a flat additive). Resolve: +50 % XP while below the party's highest level.
- Per level: +health, +Breath, +Oil, 1 Calling point. Enemy XP = `base × level × eliteMult`.
- Currency Tallies (start 50); Scrap from salvage. Vendors: Quartermaster (ammo, Flasks, Clay/Bronze guns), Armourer (gear), Seal-cutter (re-roll one affix, cost doubles per re-roll on that item), Pilgrims' Market (daily rotating stock with Relic chance). Sell price = 25 % of buy.

### 30.6 Kill rewards and instanced co-op loot
- Host is authoritative. On kill: XP and Tallies to every player within 60 m or who dealt damage in the last 10 s.
- Loot rolled **per player** with a per-player RNG stream; each client only sees its own drops (no loot stealing). Quest items drop for the whole party. Bosses: guaranteed Gold+ per player. Optional trading in camp.
- Ammo/Tallies auto-collect; guns and gear drop with Grade-coloured light pillars, HUD loot feed, Grade pickup stinger.

### 30.7 Enemies, bosses and dungeons
- Roles: rusher, shooter, tank, splitter, support, Shadowed phaser; elite affixes (Burning, Warded, Swift, Splitting). Families in section 8; 2 region specials per region.
- Bosses: 3 phases at 66 %/33 %, each changing one rule (attack cadence, adds, arena hazard, exposed weak point); arena lock, phase pips, checkpoint.
- Breaches (dungeons): entrance → 3–5 shuffled combat rooms → puzzle/traversal → mini-boss → boss → per-player loot vault; signature essence hazard; Vigil replay modifiers.

### 30.8 Movement
- Sprint drains Breath (100 base, 20/s; regen 30/s after 1 s), sprint → slide, mantle, ground-slam.
- Dash: 6 m in 0.15 s, 25 Breath, 2 charges (Sandals can add a 3rd or a damage trail), brief i-frames 0.1 s; usable in air once. Charges recharge one at a time, 1.5 s each (build step 16 choice).

### 30.9 Tests required (M1–M2)
Headless tests for damage formula, Grade weight distribution (statistical), deterministic item regen from seed, affix exclusivity, essence matchups, per-player loot isolation, XP curve, and save round-trips.

## 31. Loot-system architecture (original, informed by public BL3 modding research)

> **2026-10-22 update:** the weapon/loot model now follows Magewar (§30.1–30.3). Applying this section: Patterns become part-type stat tables and drop pools for staff/wand parts (Head, Exterior, Interior, Handle, Charm), with `requires`/`forbids` tags (e.g. Charm requires `tag:staff`). Workshops become flavour on part names, not separate gun makers. "Grades" below means Magewar's six rarities (Basic…Unique). Ember Marks encode parts, assembled staffs/wands (base + up to 5 parts + gems) and equipment. Consecrations roll on Rare+ boss/vault wieldables.

Everything below is an **original** design. We studied how the community describes a well-known looter's systems (sources in §32) only to learn general architecture lessons. No game files, keys, names, numbers or data tables were used or copied; all names, weights and formats here are our own.

### 31.1 Patterns: data-driven part categories
- A weapon **Pattern** (one per Family × Workshop, plus one per Relic) is an ordered list of **part categories**. Categories are open-ended: a Workshop may add its own (e.g. Lampwright *Wick*, Ashfall *Bellows*, Reedcutter *Underslung*), so we are not locked to six slots. Frame/Barrel/Chamber/Grip/Sight/Seal remain the common core.
- Each category has: `pick = {min, max}` (default exactly 1), `allow_repeat` (same part twice, for stacking trinkets), `weighted` (use part weights when picking more than one, else uniform), and `optional` (may roll empty).
- **Inheritance with merge modes**: a Pattern may extend a parent Pattern (Family base → Workshop → Relic). Each layer declares `merge = replace | override | append` per category: replace discards the parent list, override swaps only categories it defines, append adds parts to the parent's list. Pick rules come from the top-most layer only. This keeps Relics tiny: they override one or two categories.
- **Resolve once at load**: Patterns are flattened into a runtime table when data loads (and again after balance patches, §31.6). Gameplay only ever reads the flattened table, which removes a whole class of "edited the wrong layer" bugs.

### 31.2 Part constraints: requires and forbids
- Every part may list `requires` (all must already be on the item) and `forbids` (none may be on the item), by part id or by **tag** (e.g. `tag:scope.long`, `tag:essence.kindling`). Tags are preferred so new parts don't need every constraint edited.
- Categories are rolled **in Pattern order**, and each category is filtered by the constraints against the parts already chosen. So accessory categories always come after the category they depend on (Sight before Sight-Mount, Barrel before Muzzle).
- Tooling: the cooker validates every Pattern: for each reachable partial build, at least one legal part must remain in a non-optional category. It also counts how many distinct builds each Pattern can make, which shows when constraints accidentally collapse variety. CI fails on dead-ends.
- Constraint patches can target parts from outside (an expansion file adds `requires/forbids` to existing parts), so future content packs never edit base files.

### 31.3 Workshop (manufacturer) identity
- A Workshop is a data bundle: stat bias, an always-present **signature mechanic**, its own part categories and visual kit, sound set, and naming grammar.
  - Ashfall Foundry: heavy hitting; *overpressure*: the last round of a mag deals ×1.5 and vents heat.
  - Lampwright & Daughters: Oil-fed; *wick*: fire with an empty mag by spending Oil at ×1.5 cost.
  - Shepherd's Arms: precision + support; *guiding shot*: ADS shots that miss home slightly toward allies' marked targets.
  - Reedcutter Co.: big mags, fast handling; *throw-reload*: empty mag is thrown as a small Plain grenade.
  - Watchtower Optics: crit and scopes; *steady breath*: holding ADS still for 1 s gives +25 % crit.
- Family × Workshop is a matrix; not every cell exists (sparse matrix gives each Workshop a personality). Grenade-like Flasks may roll from a weighted Workshop pool; guns have exactly one Workshop.

### 31.4 Weights, Grades, Consecrations and Vigils
- **One weight model everywhere**: `weight = base × Π(modifiers)`; a modifier is a constant or a **live attribute** (player count, player health %, ammo %, Vigil tier, luck). Weights are relative; probability = weight / Σweights. The same structure drives drop pools, Grade tables, Workshop pools, quantity rolls ("2 Tallies piles per player") and contextual drops (more health from crates when the party is hurt, more of the ammo type you're low on).
- **Named weight tiers** (our own scale) keep data readable: `staple 100, common 50, uncommon 12, scarce 3, rare 0.6, precious 0.12`. Designers pick a tier; the table is one patchable file.
- **Grades** unchanged in value (§30.2) but expressed as tiers in a Grade table so Vigil/luck modifiers can shift them.
- **Consecrations** (our anointment analogue; endgame only): a separate *generic* roll after parts, from its own pool, with a "no consecration" entry. Each is a conditional bonus tied to a game verb, e.g. "after a dash, next magazine Kindling-infused", "after Releasing a Shade, +30 % Oil regen 8 s", "while at full shield, +15 % weak-point damage". **Calling-aware weighting**: Calling-specific Consecrations start at low weight and gain weight for each party member playing that Calling, so co-op drops skew to what the party can use. They unlock after the first Breach warden and appear only on Silver+.
- **Vigils** (Mayhem-style scaling, our design): tiers 1–10 unlocked after the story.
  - Each tier scales enemy health/damage and **reward** (XP, Tallies, Grade weight shift, Consecration rate) along separate curves, so difficulty and payoff are tuned independently.
  - Each tier adds **Omens** (modifiers) drawn from Easy/Medium/Hard pools by a per-session seed: e.g. "Ember Rain", "Shades rise twice", "Wards regenerate faster". The seed is stored in the save so a run can be shared and replayed. Players can re-roll Omens at the camp Memorial Stones.
  - Items record the **Vigil tier they dropped at**, which scales their power within the tier, so old gear is clearly weaker than new gear, without invisible rules.

### 31.5 Ember Marks: item codes for saving and sharing
- Every item serialises to a compact, versioned code: `EM1-` + base32 (Crockford, grouped in fives with `-`; decode ignores case, dashes, spaces and reads O as 0, I/L as 1) of a bit-packed payload + CRC-16/CCITT-FALSE. Built in step 20 (`scripts/loot/item_codes.gd`).
- Payload v1: `version (6b) | kind (3b) | flags (3b, none defined in v1; non-zero rejected)` then by kind: bare wieldable = base index + rarity tier (3b); assembled = base index + tier + part count (3b) + parts in Head..Charm order, each `rolled (1b)` + rolled fields or a hand-made part index; rolled part = part type (3b) + tier + element (3b) + seed (32b); hand-made part = index; rolled equipment = slot (3b) + tier + element + seed (32b); equipment template = index; potion = index + count (7b). Index bit width = ceil(log2(table size)) of that version's **index table** (wieldables, parts, equipment, consumables).
- Nothing derived is stored: stats, names and assembled rarity are regenerated (`PartRoller/EquipmentRoller.from_seed`, `Assembly.assemble`; a code whose build fails `Assembly.check` is rejected). `encode()` refuses items it can't reproduce exactly (edited resources, a rolled item that no longer matches its seed).
- Later versions add the fields that don't exist yet: socketed gems (step 26), item level (step 27), grade/Vigil tier (step 28), consecration id (step 36), a "sandbox" flag for imported items (step 22+/co-op). Each adds a version; v1 codes keep decoding with defaults.
- **Index table discipline**: indices are **append-only per version**; old versions are kept forever, so old codes always decode. New content adds a new version. Tuning a seed's roll ranges/order also needs a new version (§31.6).
- Codes are **plain, not obfuscated**: it's an open-source game, and readable codes encourage sharing builds. A CRC detects typos; the host still validates (constraints, level caps) before accepting a shared item in co-op, so pasted codes can't create illegal gear online. Offline/solo can import anything ("sandbox" flag shown on the item).
- Saves store items as Ember Marks; round-trip tests (`encode(decode(x)) == x`; step 20 checks 1000 random items per run plus golden codes per version, every historic version stays tested) are mandatory.

### 31.6 Balance patches (live tuning without rebuilds)
- **Balance patch files** (`data/patches/*.toml`) apply ordered, typed edits to the loaded data: `set` (path, value), `set_if` (path, expected old value, new value: fails safely if the base changed), `append`/`remove` (lists), and `table_row` (row in a named table, e.g. Vigil curves).
- **Apply phases**, mirroring when data is alive: `boot` (global data at the main menu), `level:<id|*>` (when a region loads), `enemy:<id|*>` (when an enemy archetype first spawns), `save` (one-off save fixes, versioned and idempotent). Pattern flattening (§31.1) re-runs after `boot` patches.
- Sources: built-in patches shipped with each release, optional signed patches fetched from the project's own repo, and local mod patches. Order: built-in → online → mods. The HUD/menu shows "N balance patches active"; co-op clients get the host's patch set hash and must match (or receive it from the host).
- Every patch line is validated (path exists, type matches); bad lines are logged and skipped, never fatal. CI runs all shipped patches against the base data.

### 31.7 Levels and streaming
- Each region = a **persistent level** (terrain, lighting, Watchfires, navmesh) plus named **layers** streamed in and out: `_geo` chunks by distance, `_combat` (spawners, encounters), `_dynamic` (chests, vendors, interactables), `_story` (quest-state dependent), `_audio`.
- Layers are content-addressed by stable ids so balance patches and quest scripts can target `level:reedlands/_combat` without touching geometry. Objects added by patches spawn at an explicit transform stored in the patch (never at origin).
- Breaches are separate persistent levels with shuffled room layers (§14), loaded behind the Breach door with an async preload.
- Fast travel = unload region layers, load target persistent + nearest layers; the camp is always a tiny resident level.

## 32. What we learned (public sources)

- **Part sets are lists of categories with pick rules, and part lists merge in layers.** A balance/part-set structure resolves into one runtime part list, with complete/selective/additive merge modes and multi-pick ranges. *Our take:* Patterns with replace/override/append merges, flattened at load (§31.1). Source: https://github.com/BLCM/BLCMods/wiki/Borderlands-3-Item-and-Weapon-Parts
- **Dependencies and excluders on parts, applied in category order**, explain why accessory variety is narrower than the raw counts suggest. *Our take:* requires/forbids tags + a cooker that counts reachable builds (§31.2). Same source.
- **Manufacturers are a weighted pool on the item, usually a single entry**, and anointments are a separate "generic part" roll with a "none" option and character-aware weighting. *Our take:* Workshops with signature mechanics (§31.3); Consecrations with Calling-aware weights (§31.4). Same source.
- **Weights are layered values**: a constant × scale, or a live attribute (player count, health below a threshold) that overrides the constant; named weight tiers make data readable. *Our take:* one weight model with live modifiers and our own tier scale (§31.4). Source: https://github.com/BLCM/BLCMods/wiki/Understanding-Borderlands-Weight-and-Probability-Values
- **Hotfixes are typed, ordered data edits applied at specific moments** (global, on level load, early level load, on character load, save fixes), with an optional "expected old value" check. *Our take:* balance patches with apply phases and `set_if` (§31.6). Source: https://github.com/BLCM/BLCMods/wiki/Borderlands-3-Hotfixes
- **Levels are a persistent level plus streamed sub-levels** (e.g. combat and dynamic layers), and objects added late can be hard to place. *Our take:* named, patch-addressable layers with explicit transforms (§31.7). Source: Hotfixes page above.
- **Item serials pack part choices into indices from a versioned database, along with item level and difficulty level**, which is why save editors need that database and serial versions change with patches. *Our take:* plain, append-only Ember Marks with CRC and host validation (§31.5). Sources: https://github.com/apocalyptech/bl3data (README), https://github.com/apocalyptech/bl3-cli-saveedit (README), https://github-wiki-see.page/m/BLCM/BLCMods/wiki/Accessing-Borderlands-3-Data
- **Difficulty modes scale rewards and enemies with tiered, randomly picked modifiers stored in the save.** *Our take:* Vigils with separate difficulty and reward curves and seeded Omens (§31.4). Sources: bl3-cli-saveedit README (Mayhem level, Mayhem seed, item Mayhem level); overview at https://github.com/BLCM/BLCMods/wiki/Borderlands-3-Modding-Info
- **Not used:** the data-access page describes unpacking encrypted game archives with keys found online. We deliberately did **not** do that; this design uses only the prose descriptions above.
