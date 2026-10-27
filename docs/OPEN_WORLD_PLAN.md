# Open World Plan (one seamless Elyria + in-game map)

Status: APPROVED 2026-10-27 ~00:30 CDT. The user accepted all 12 recommended defaults in
section 12 as written and gave the go to build OW1-OW11 in order; no release until OW11
(0.2.0). Supersedes the "one level per scene" part of TERRAIN_MAPS_PLAN.md.

## 1. Goals and non-goals

- Walk from the Town Square to the Breach without a loading screen.
- An in-game map (full screen) and a minimap, with fog of war, markers, quests and co-op partners.
- Keep co-op (host authority), old saves, the intro flow and Low / Steam Deck performance.
- Non-goals for this pass: seamless interiors for every building, dynamic weather, the
  locked regions' content (Whispering Woods, Shattered Peaks, Crimson Sea get terrain and
  border gates only).

## 2. World layout

The world is one Terrain3D data set on a 1 m grid (Terrain3D regions are 256 m squares;
region size 256 keeps edits and streaming granular). Elyria is about 4 x 4 km (16 x 16
regions, at most 256 regions; only about 120 hold land at first, the rest is sea / void).
North is -z, matching the current maps.

```
                 Shattered Peaks (locked)
                        | scree foothills (rock -> snow)
 Whispering Woods  -- Luminar -- Stonehaven
   (locked)   forest     |  heath   | quarry road (rock / gravel)
        edge (grass->mud)|          |
 Willowbrook ---- meadow -- ELDORIA -- dry scrub -- The Landfill (Midden) -- Breach
                        (Town Sq, Assoc,  (dirt -> rubble)    (rubble/ash)    (ash/crystal)
                         Old Oak)
                         | salt marsh (mud -> sand)
                     Crimson Sea coast (locked)
```

| Region | Today's level(s) | Footprint | Borders | Transition biome (materials) |
|---|---|---|---|---|
| Eldoria | town_square (240 m), mage_association (interior), old_oak (160 m) | 0.8 x 0.8 km | Landfill E, Luminar N, Willowbrook W, Crimson coast S | barrier edge: path_cobble -> grass -> dirt |
| The Landfill | midden (~640 m) | 0.8 x 1.0 km | Eldoria W, Breach E, Stonehaven NE | dry scrub: dirt -> rubble_junk -> mud_filth |
| Breach | breach (220 x 320 m) | 0.4 x 0.5 km, inside a crater rim | Landfill W only (dead end) | scorch belt: rubble_junk -> ash_scorched -> crystal |
| Luminar / Willowbrook / Stonehaven | none yet (towns, barrier) | 0.5 km each | see sketch | heath, meadow, quarry road |
| Locked regions | none | 1 km+ | outer ring | gated by a barrier wall + story flag |

Current level coordinates become offsets into world space (a `world_offset` per level
TOML); the greybox, POIs, camps and anchors move with it unchanged. Region transitions are
24 to 64 m strips painted with the blend materials above (control-map blend in Terrain3D,
not hard seams), and the edge walls/rims of each zone are removed except on the world edge.

## 3. Streaming

- Terrain: Terrain3D streams its own regions and renders with its clipmap LOD; one
  Terrain3DData for the world (`res://world/terrain/`), saved region files, so only the
  data is loaded, not regenerated (the per-level FastNoise generation becomes an offline
  `tools/build_world.py` step; the co-op hash becomes a hash of the region files).
- Content cells: the world is cut into 128 m cells (scene per cell:
  `world/cells/x_z.tscn`, generated from the TOMLs). A `WorldStreamer` keeps the 5 x 5 cells
  around each local player (and around the host's view of each partner, see 7) loaded,
  loads with `ResourceLoader.load_threaded_request`, and adds at most one cell per frame
  (2 ms budget, the rest deferred). Unload hysteresis: one cell ring beyond the load ring.
- Navmesh: the existing 64 m tiles (LevelNavigation, cache in scenes/levels/nav) become
  world tiles baked offline per cell and loaded with the cell; NavigationRegion3D edge
  connections already join neighbours. Landmark colliders (batch 07) are part of the bake.
- LOD: Terrain3D clipmap; Ember Art landmark LOD0/1/2/impostor ranges (90/260 m etc.)
  stay; a far "skyline" band of impostors for every landmark in loaded regions; MultiMesh
  foliage per cell with visibility ranges; enemies beyond 96 m sleep (no AI tick).
- Physics: Terrain3D collision mode Dynamic (around players) instead of FULL_GAME.

## 4. Interiors, dungeons, the town

- Town Square, Old Oak, the Landfill camps: seamless (they are open-air already).
- The Mage Association: instanced interior. The front door is a door trigger that fades
  (0.3 s) and loads `interiors/mage_association.tscn` far below the world (y -2000) so the
  outside stays streamed; the back door leads out at the Landfill edge of Eldoria. The
  loading screen shows only when the load takes over 250 ms.
- Breach rooms: instanced (they are a run with a vault and a timer; seams there buy
  nothing). The crater is seamless; the portals are the instanced entrance.
- Future caves / dungeons: instanced by default, seamless only when shallow.

## 5. Waystones and fast travel

Waystones stay as fast-travel nodes (discover by touching, as now). Fast travel is a
teleport within the world: stream the destination cells (loading screen with real stage
progress), then move the party. Exits that used to change level become plain roads; the
`[[exit]]` entries turn into map markers. Co-op: only the host starts fast travel; the
party follows (clients get the loading screen).

## 6. The in-game map

- Full map (M): a painted world texture per region (the batch 06 map paintings, stitched),
  pan/zoom, region names, Locked regions greyed.
- Fog of war: 32 m cells over the world, a bitset per save (about 16 KB for 4 x 4 km),
  revealed in a 48 m radius around each player; co-op partners reveal for the host's save
  and their own character file.
- Markers: waystones (fast travel button), interiors, camps, quest objectives (from the
  quest system), custom pins (up to 32), the junk mountain, the Breach.
- Co-op partners: coloured arrows with names, sent with the existing state sync (1 Hz is enough for the map).
- Minimap: top-right, 160 px, rotating with the camera (option to lock north), same marker
  layers, rendered from the map texture (not a second camera, cheaper on Low).

## 7. Co-op range and host authority

- The host stays authoritative for enemies, loot and chests in all loaded cells.
- Leash: partners may roam up to 400 m from the host (Recommended), soft warning at 300 m,
  then a pull back to the host. The host streams the cells around every partner (server
  side, without rendering) so enemies there simulate; cap 4 players.
- Region locks and story gates use the host's flags.

## 8. Save migration

- New save version: `position` becomes a world position plus `region`; old saves with a
  `level` id map through a table (level id + local position + world_offset). Unknown or
  interior positions land at the level's waystone / entrance.
- Visited regions / levels seed the fog of war (whole visited level footprint revealed).
- Co-op character files keep loading (they carry no position). A test loads the 0.1.4
  save fixtures.

## 9. Intro flow

The intro (INTRO_PLAN) still starts in the Mage Association interior; leaving through the
front door drops you into the seamless world at the Town Square with the loading screen
once (initial world load). The "skip" new-run option starts at Old Oak, as now.

## 10. Performance targets

| Tier | Target | Budgets |
|---|---|---|
| High (desktop GPU) | 60 fps at 1440p | 7x7 cells, foliage full, shadows 4 cascades |
| Low | 60 fps at 1080p on an integrated GPU | 5x5 cells, terrain textures 512 px mips, foliage 40 %, 2 cascades |
| Steam Deck | 40-45 fps at 800p (40 Hz mode), < 12 W | Low preset, FSR 1, 3x3 cells + far terrain |
| All | streaming hitch < 8 ms per frame | one cell instance per frame, threaded loads, no sync navmesh bake at runtime |
| All | RAM < 3 GB, VRAM < 2 GB (Deck) | Terrain3D region cache, unload ring |

Perf runs extend tools/perf (docs/perf) with a scripted walk Town -> Landfill -> Breach.

## 11. Steps and estimate

| # | Step | Estimate |
|---|---|---|
| OW1 | World layout doc + `world_offset` per level, stitched heightmap tool (build_world.py) | 2 days |
| OW2 | Single Terrain3DData for the world, regions saved, transition painting | 2 days |
| OW3 | Cell generation from the TOMLs, WorldStreamer (threaded, budgeted) | 3 days |
| OW4 | World navmesh tiles per cell, enemy sleep, Dynamic collision | 2 days |
| OW5 | Instanced interiors (Association, Breach rooms), door triggers, loading screen hook | 2 days |
| OW6 | Waystone fast travel in-world, exits to roads | 1 day |
| OW7 | Map screen, fog of war, markers, pins | 3 days |
| OW8 | Minimap, co-op partner markers | 1.5 days |
| OW9 | Co-op leash, host-side streaming for partners | 2 days |
| OW10 | Save migration + fixtures, intro flow | 1.5 days |
| OW11 | Perf pass (Low, Steam Deck), playtests 1x / 4x / co-op on the walk route | 2 days |
| | Total | about 22 working days (4 to 5 weeks of agent sessions), not counting new region content |

The loading screen (queued) is built first and reused for initial load, fast travel and
instanced interiors.

## 12. Open questions (recommended defaults)

1. World size: 4 x 4 km with three new towns as placeholders? Default: yes, 4 x 4 km,
   towns as greybox until their art arrives.
2. Interiors seamless or instanced? Default: instanced Association and Breach rooms,
   everything else seamless.
3. Fast travel: free, or does it cost something (mana, an ember)? Default: free between
   discovered waystones, blocked in combat.
4. Co-op leash distance? Default: 400 m, soft warning at 300 m.
5. Fog of war shared in co-op? Default: each player reveals their own; the host's save
   also gets what partners reveal.
6. Minimap rotation? Default: rotates with the camera, a setting locks north.
7. Locked regions: visible but walled off by a barrier, or hidden? Default: visible,
   greyed on the map, a barrier wall at the border.
8. Keep the per-level scenes for tests and the Breach run? Default: yes, the TOMLs stay
   the source; cells and the world are generated from them.
9. Old 0.1.x saves: migrate positions or reset to the nearest waystone? Default: migrate
   with a table, falling back to the waystone.
10. Day/night and weather in the open world? Default: out of scope for this pass.
11. Steam Deck: 40 fps or 30 fps target? Default: 40 fps in 40 Hz mode.
12. Release: ship as 0.2.0 after OW11? Default: yes, one prerelease at the end, none per step.
