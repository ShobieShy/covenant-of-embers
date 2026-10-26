# Terrain maps plan: every map grows to looter-shooter zone scale (Phase W)

Planned 2026-10-26. **PLAN ONLY, WAITING ON USER GO.** Questions answered 2026-10-26 (defaults; Q7 Deck check deferred). Steps 152-166 in BUILD_PLAN.md.
Design patterns only (zone sizes, loop structure, POI density). No Borderlands/Wonderlands content, names, layouts or assets.

## 1. Where the maps are today (survey)
All 5 levels are TOML box greyboxes (`data/levels/*.toml` -> `tools/toml_to_scene.py` -> `scenes/levels/*.tscn`). They use flat `[[box]]` ground/wall/platform/ramp entries, `tools/dress_levels.py` props, and CC0 ambientCG materials (Ground037, PavingStones131, Rock030, Bricks076C, Wood049, Metal032). `LevelNavigation` bakes a navmesh from Boxes at load.

| Level id | Name | Footprint today | Contents |
|---|---|---|---|
| mage_association | Eldoria - Mage Association | 20x30 m hall, 6 m walls | intro beats 1-4, Crazy Joe, exits to town and the Landfill (back door) |
| town_square | Eldoria - Town Square | 40x40 m, 4 m walls | merchant, tailor, runesmith, patron, guard gate; exits to the Association, Landfill and Old Oak; "town_gate" waystone |
| old_oak | The Old Oak | 16x16 m, 8 m bark walls | home/respec hub, Bob, the crystal; exit to town; waystone |
| midden | The Landfill | 40x40 m plus a scrap ledge | 4 placed enemies, waves gnawer_pack / flank / the_filth; quest the_landfill; waystone |
| breach | The Breach | 30x48 + 16x56 m, 3 rooms + dais + vault | 6 encounters, 2 levers -> switch gate, Breach Warden, vault chest, exit to midden; waystone |

- Quest chain: a_new_home (reach old_oak) -> the_landfill (reach, kill 3 gnawers, kill the_filth, collect joes_discards) -> report_to_bob (talk Bob; sets tutorial_done + fast_travel_crystal).
- The intro (INTRO_PLAN) is one linear path: Association -> Town -> Old Oak (night) -> Association back door -> Landfill -> Filth arena -> Old Oak.
- Saves store only `progress.level_id`. The player always spawns at the level's PlayerStart, and no world position is saved. This makes save compatibility cheap (section 10).
- In total the game has about 4,000 m2 of walkable space. A single looter-shooter zone is 100-200x that.

## 2. Terrain tech for Godot 4.7

| Option | License | Export | Perf / LOD | Co-op determinism | Verdict |
|---|---|---|---|---|---|
| **Terrain3D** (TokisanGames) | MIT | C++ GDExtension, Windows + Linux binaries (macOS too). v1.0.2-stable supports Godot 4.4-4.7. v1.1.0-rc1 (2026-10-17) supports 4.5-4.8. | GPU clipmap, up to 10 mesh LODs, 32 textures, foliage instancer with LODs + shadow impostors, holes, region streaming. Sizes from 64 m to 65 km. | Height/control data is a saved resource (`.res` per region). Every peer loads the same bytes, and nothing is generated at runtime. | **Recommended** |
| HTerrain (Zylann) | MIT | Pure GDScript + shaders, so it exports anywhere | Chunked LOD, but slower on large maps and in the editor. Fewer active features. | Same as Terrain3D (saved images) | Fallback if the GDExtension ever breaks on the Deck |
| Custom heightmap -> ArrayMesh | ours | anywhere | We would write our own LOD and texturing. A good fit for faceted low-poly. | Deterministic if built from the PNG | Only if Terrain3D's look can't be made low-poly (Q2) |

Why Terrain3D:
- It is MIT, so it goes in CREDITS and `check_assets.py`.
- It runs natively on Linux, which matters for SteamOS/Proton-free Deck builds.
- It is the most actively maintained of the three.
- It has built-in navmesh source geometry (`Terrain3D.generate_nav_mesh_source_geometry`), a foliage instancer and holes for caves and Breach pits.
- Pin **v1.0.2-stable** now (Godot 4.7.2). Move to 1.1.x only when the project moves to 4.8.
- Godot Steam is already a GDExtension, so `export.sh` and `package.sh` already handle `.so`/`.dll`. The plan is to vendor `addons/terrain_3d` and add its binaries to the package check.

## 3. Keeping the low-poly look
- Terrain uses a vertex spacing of 1.0 m (Low preset: 2 m via LOD bias) and flat shading (Terrain3D shader override: `NORMAL` from screen-space derivatives) to get faceted hills like our props.
- Texture detail stays low: 512 px tiles, the existing AgX palette tint, and no parallax.
- Cliffs and rock are faceted Quaternius/KayKit rock meshes placed on the terrain. Cliffs are not sculpted overhangs.
- Grass, scrub and junk scatter use Terrain3D instancing of existing CC0 kit meshes.
- Skyline silhouettes are low-poly mountains and walls on a far billboard ring.

## 4. Splat texturing (CC0 only)
- Use 6-8 layers per biome from ambientCG (CC0): Ground037 (dirt), PavingStones131 (town), Rock030 (rock), plus new Grass004, Ground054 (mud), Gravel022, Moss and a junk/rubble layer for the Landfill.
- Use Terrain3D's control map with auto-slope (rock over 35 degrees) and hand-painted paths.
- `check_assets.py` checks that every layer has a CC0 entry in CREDITS.
- Keep textures to 1K albedo+normal each and 512 on Low.

## 5. Target sizes
**Reference pattern:** a typical looter-shooter open zone is about **0.5-1.2 km across** (about 0.3-1 km2 playable). It has:
- 1 main path and 3-6 branching side areas;
- a landmark visible from anywhere;
- 1-3 fast-travel stations;
- 8-15 enemy camps or POIs;
- 15-30 chests including 1-3 hidden/red-tier ones;
- 2-3 vertical tiers.

Hub towns are smaller (150-300 m), and dungeons are linear 200-400 m runs. We match the pattern and scale it down slightly for a 1-4 player co-op indie game and the Deck.

## 6. Per-map plan
**Mage Association: 60x90 m interior, 3 floors.** It stays a building, not terrain.
- Spaces: grand hall (beats 1-4), library gallery (mezzanine), courtyard (a small terrain patch), and the back-door cellar to the Landfill.
- Story stays linear (section 7). After the tutorial the side wings unlock: an archive with 3 lore clues, a sealed vault room, and a training yard with dummies.
- Chests: 4 normal + 1 hidden (roof).

**Eldoria town: 240x240 m terrain hub.** The Town Square expands to districts:
- Market (merchant, tailor, runesmith), Temple/Patron hill (verticality: stairs + overlook), Docks/Canal, Guard Gate (south exit to the wilds) and the Old Oak path (east).
- Landmark: the Association spire.
- Fast travel: the Town Gate waystone, plus a Market waystone.
- No combat. Side areas: rooftops reachable by a jump route with a hidden chest, a sewer entrance (locked until a later step) and 6 NPC flavour spots.
- Chests: 6 + 2 hidden.

**Old Oak grove: 160x160 m.** The Oak interior stays the hub (16x16 home), with a grove around it:
- Pond, root caves (a small dungeon pocket with 1 hidden chest) and a bark lookout platform 20 m up the tree (the landmark).
- Night variant for beat 6.
- Fast travel: the Old Oak waystone. Safe zone with no camps.

**The Landfill: 700x600 m open zone.** This is the first real zone.
- Layout: an entrance funnel (tutorial beats 8-10, linear), then Joe's dump camp, then a ring of POIs around a central junk mountain landmark 60 m high.
- POIs (10):
  - Gnawer Warren (camp);
  - Scrap Bridge (verticality);
  - Toxic Pools (Filth-corrupted, hazard + oozes);
  - Crane Yard (sniper perches);
  - Compactor Pit (arena);
  - Burned Shacks (scorchlings);
  - Sunken Tip (caves);
  - Heap Graveyard (mini-boss);
  - Joe's Old Stash (hidden vault);
  - Overlook (fast travel).
- Filth areas: the Filth arena is a sealed bowl at the north end (beat 11, arena_lock). After `filth_defeated`, residue zones spread purple ground decals and spawn elite variants.
- Fast travel: 3 (Entrance, Joe's camp, Overlook).
- Camps: 8 respawning camps.
- Chests: 20 + 2 hidden + 1 vault (lever puzzle).
- Breach portals: 2 fixed spots.

**The Breach: 220x320 m dungeon instance.** It has an outdoor approach:
- A corrupted crater (terrain, 120 m) leads to the existing 3-room interior, which grows to 6 rooms on 2 levels.
- Lever gate puzzle expanded to 3 levers, Warden dais, vault.
- Plus 1 optional side wing (challenge room + hidden chest).
- It stays mostly linear like a dungeon.
- Fast travel: the entrance waystone only. Its position anchors the exit back to the Landfill.

**New (optional, Q5): Ashen Wilds, 900x900 m.** This is the zone past the Town Guard Gate, so the world continues after the tutorial. It is not part of the core steps and is only planned if the user says yes.

## 7. Keeping the intro linear
- The open zones are built so the intro uses a **corridor carve-out**. Beats 7-11 run through gated sub-areas: the Landfill entrance funnel is walled with junk walls and soft-blocked by IntroDirector `[[gate]]` boxes with a `requires_flag` key.
- Each gate shows a short reason ("Bob said to stick to the path"). Gates drop at `tutorial_done`.
- Fast travel is still gated on crystal + tutorial_done, as today.
- The cinematic camera keyframes move with the new beat anchors (named markers in the TOML, so the cinematics never hard-code coordinates).
- Intro length target stays at 15-20 min. The bot measures it (section 13).

## 8. Streaming, occlusion, LOD (Low preset = Steam Deck)
- **Levels:** each zone stays one GameFlow level (level-to-level loads stay the same). Inside a zone:
  - Terrain3D region streaming;
  - POIs as sub-scenes loaded with `ResourceLoader.load_threaded_request` within 150 m (Low) or 250 m (High), unloaded with hysteresis at +50 m.
- **Occlusion:** baked OccluderInstance3D for the junk mountain, town buildings and Oak trunk, plus visibility ranges on every prop (Low: 60/120 m, High: 120/250 m).
- **LOD:** Godot auto mesh LOD on all props. Terrain3D LODs 0-6 (Low: 4) and a foliage distance of 40 m on Low and 100 m on High.
- **Deck budgets (Low, 1280x800, target 60, floor 40 fps):**

| Item | Budget |
|---|---|
| Frame | ≤ 14 ms GPU, ≤ 8 ms CPU |
| Draw calls | ≤ 1,500 |
| Visible triangles | ≤ 600 k |
| Terrain | ≤ 2 ms |
| Shadows | 1 cascade, 60 m |
| Active enemies | ≤ 24 |
| VRAM | ≤ 1.5 GB |
| Zone load | ≤ 8 s |

- The `perf_capture.gd` run adds a flythrough route per zone. Fail when the Low p95 is over 2x the desktop baseline. A real-Deck check is deferred (Q7) until the user allows it.

## 9. Navmesh for enemies
- Replace the whole-level bake with **chunked navmesh**: one NavigationRegion3D per 64 m tile around each camp and path. The source geometry is Terrain3D plus the collision of the props in that tile.
- Bake offline in `toml_to_scene.py` / an editor tool, save it as a `.res`, and **don't bake at load** (bakes on the Deck would take seconds).
- Tiles are linked by edge connection. NavigationLinks cover jumps, ladders and drops.
- Enemies only pathfind inside their camp leash (40 m) and return home after it. This keeps agent counts low.
- The playtest bot uses the same tiles plus a coarse waypoint graph for long routes.

## 10. Co-op spawn, sync and save compatibility
- **Co-op:**
  - The terrain and navmesh are static resources with a content hash. The client checks the hash on join and refuses with a clear message if it doesn't match (same as the version check).
  - Camps spawn on the host only, as today. Clients get puppets.
  - Camp activation is per-player proximity: a camp activates if any player is within 80 m.
  - Interest management: replicate an enemy only to peers within 150 m.
  - A joining client spawns at the host's nearest waystone, or at the nearest beat anchor during the intro.
  - Players more than 300 m apart can still play. The arena locks pull or teleport stragglers (existing arena_lock rule).
- **Saves:**
  - Positions are not saved today. New: save `progress.anchor` (the last waystone or beat anchor id) and `map_version`.
  - When a level's map_version is newer than the save's (all v1 saves), spawn at the anchor matching the saved story state: an intro beat anchor, otherwise the zone waystone, otherwise PlayerStart.
  - Chests opened, vaults and attuned waystones are already flags. New chest ids are namespaced `<level>:<poi>:<n>`, so old flags still match the old chests that are kept.
  - Test: load each committed v1 fixture save.

## 11. Asset needs (Ember Art)
- CC0 first: ambientCG textures (6-8 new), Quaternius/KayKit nature + dungeon kits (rocks, cliffs, trees, ruins), Kenney props. Junk and scrap kits for the Landfill.
- **Ember Art (original):**
  - the junk mountain landmark;
  - the Association spire;
  - the Oak (enlarged LOD set);
  - the Breach crater rim;
  - 4 waystone variants;
  - Filth residue decals;
  - 3 chest tiers (normal / hidden / vault);
  - skyline billboards;
  - a world map painting per zone for `world_map.gd`.
- Each asset needs 3 LODs or must be under 2k triangles.

## 12. Tools
- `toml_to_scene.py` gains:
  - `[terrain]` (region dir, map_version, biome layers);
  - `[[poi]]` (id, centre, radius, sub-scene, camps, chests);
  - `[[camp]]` (enemies, leash, respawn);
  - `[[chest]]`;
  - `[[waystone]]`;
  - `[[gate]] requires_flag`;
  - `[[anchor]]`.
- Boxes stay valid for interiors (the Association and Breach rooms).
- Spawn points are snapped to the terrain height at build time, and the validator fails if something floats or is buried (extends `on_surface`).

## 13. Tests and the playtest bot
- **Unit:** TOML schema for the new tables. Every chest, camp, waystone and anchor sits on terrain and on navmesh. The terrain hash is stable. Old saves migrate to an anchor.
- **Per-zone:** the navmesh connects the PlayerStart to every POI and waystone (path query). Every gate has a flag that the quest chain sets.
- **Playtest bot:**
  - New routes: the intro route (asserts the gates hold, beat order, and time under 20 min simulated) and a zone sweep route (visit every POI, open every chest, clear every camp, attune every waystone).
  - Breach route updated for 3 levers + 2 floors.
  - Co-op bot: host + client in the Landfill, where the client spawns at the host's waystone and puppets stay in sync.
- **Perf:** a `perf_capture` flythrough per zone checks the section 8 budgets on Low.
- **Screens:** `level_shots.gd` adds overview + POI shots per zone (XDG_DATA_HOME=/tmp/coe_x).

## 14. Ordered build steps (Phase W)
- **152 W1 Terrain3D vendor + pipeline:**
  - pin v1.0.2;
  - export.sh / package.sh / check_assets / CREDITS;
  - add `[terrain]` + new tables to toml_to_scene.py and level_toml.gd;
  - low-poly shader;
  - 1 test zone; tests.
- **153 W2 Streaming/LOD/occlusion framework:** POI sub-scenes, visibility ranges, Low/High settings, perf flythrough harness.
- **154 W3 Chunked offline navmesh:** tiles + links, camp leash, bot long-route graph.
- **155 W4 Saves + co-op plumbing:** map_version, anchors, migration, terrain hash check, interest management, join-at-waystone.
- **156 W5 Intro gates:** `[[gate]] requires_flag`, beat anchors, cinematic markers.
- **157 W6 Old Oak grove (160 m):** terrain, root caves, lookout, night variant.
- **158 W7 Eldoria town (240 m):** districts, rooftops, 2 waystones.
- **159 W8 Mage Association interior (60x90 m, 3 floors):** post-tutorial wings.
- **160 W9 Landfill part 1:** terrain, tutorial funnel, Joe's camp, Filth arena; the intro must still pass.
- **161 W10 Landfill part 2:** the 10 POIs, 8 camps, chests, vault, 3 waystones, Filth residue, Breach portals.
- **162 W11 Breach (220x320 m):** crater approach, 6 rooms on 2 levels, 3 levers, side wing.
- **163 W12 Ember Art pass:** landmarks, chests, waystones, decals, skyline, world map paintings.
- **164 W13 Bot routes + perf pass:** zone sweeps, co-op bot, Low budgets, fixes.
- **165 W14 Docs + balance:** camp density, loot per zone, CREDITS, PLAN/README.
- *(Optional, Q5)* **166 W15 Ashen Wilds (900 m):** first post-tutorial zone.

## 15. Questions (answered 2026-10-26, t72u: all defaults accepted except Q7, see below)
- Q1 Terrain tech: **Terrain3D v1.0.2 now, 1.1 when the project moves to Godot 4.8** (alt: HTerrain or custom).
- Q2 Look: **faceted flat-shaded terrain at 1 m spacing** (alt: smooth terrain + low-poly props).
- Q3 Zone scale: **Landfill 700x600 m, town 240 m, Oak 160 m, Breach 220x320 m, Association 60x90 m** (alt: 50% larger/smaller).
- Q4 The Association stays an interior: **yes**.
- Q5 New zone (Ashen Wilds) in this phase: **no, planned as optional step 166**.
- Q6 Camp respawn: **on zone reload or after 10 min away**.
- Q7 Steam Deck budgets: **ANSWERED: keep the section 8 targets; the real-Deck check is DEFERRED** until the user allows it (no longer a release requirement for now).
- Q8 Filth residue after the boss: **yes, elite variants + purple decals**.
- Q9 Chest counts: **Landfill 20 + 2 hidden + 1 vault, scaled down for hubs**.
- Q10 Fast-travel count: **Landfill 3, town 2, Oak 1, Breach 1**.
- Q11 Co-op leash: **no hard leash; arena locks gather players; enemies replicate within 150 m**.
- Q12 Old saves: **spawn at the matching anchor; nothing reset**.

## Build log

- Step 153 (W2): `ZoneStreamer` on the generated `Pois` node (TOML `[[poi]]`, props take `poi = "<id>"`); load 150/200/250 m (Low/Medium/High), unload +50 m; prop visibility ranges 90/140/220 m; occlusion culling on Medium/High; `perf_capture.gd -- <out> --flythrough`. POI content is detached rather than loaded from separate .tscn files (same memory win for rendering/physics, no load hitches).
- Step 154 (W3): `LevelNavigation` bakes terrain levels in 64 m tiles (one NavigationRegion3D per tile, bake AABB grown by the 1 m border so tiles share edges; no seams); greybox levels keep one region. `CampLeash` pulls camp enemies home past 35 m; `RouteGraph` (POI/anchor waypoints) gives the playtest bot long routes. `tools/bake_nav.gd` caches tiles per `[terrain]` level. Terrain3D logs a harmless `load("res://")` error pair on init; tests/export/package greps allowlist exactly those two lines. Headless terrain uses its own fallback camera.
- Step 155 (W4): `MapAnchors` + TOML `[[anchor]]` (name, position, yaw_deg, beat) / `[[waystone]]` (point, position) -> `Anchors` / `Waystones` markers. Saves add `progress.anchor` (closest marker within 30 m) and `progress.map_version`; a save older than the level's map spawns at the intro beat anchor, else the zone waystone, else PlayerStart (v1 saves on v1 maps: PlayerStart as before; fixtures in `tests/fixtures/saves_v1/`). Co-op: hello carries `Compat.terrain_fingerprint()` (every level's Terrain settings + `TerrainZone.GEN_VERSION`; mismatch = "map data mismatch"), snapshots are per peer with enemies within 150 m, the lobby carries the host's anchor so clients spawn at it (else the waystone), encounters trigger on any player, `CampLeash.camp_active` (80 m, any player) for the camps of step 161.
- Step 156 (W5): TOML `[[gate]]` (name, center, size, requires_flag = tutorial_done, reason) -> `Gates/<name>` `FlagGate` soft-blocks (translucent wall + reason label, not navmesh source) bound to story flags by main; they drop when the flag is set. `IntroDirector.spot(id, fallback)` reads `Level/Anchors/<id>` (dais, elder, clerk, back_door, joe_bench, joe_camp, light_shrine, dark_shrine) for beat spots and cinematic from/to/look, falling back to the greybox constants, so the redesigned maps move the intro by data. Intro/tutorial/co-op intro tests green; `test_intro_gates.gd`.
