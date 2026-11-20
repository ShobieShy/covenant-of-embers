# World scale and natural ground

Written 20 Nov 2026, against master `1137b6c` (v0.11.0-prealpha). This replaces `docs/PLAN_ART_PASS.md`. It is a plan. It does not change a level, a mesh, or a release.

The 20 Nov captures showed the remade levels next to [docs/maps/eldoria-hub-map.jpg](maps/eldoria-hub-map.jpg) and [docs/maps/labyrinth-cross-section.jpg](maps/labyrinth-cross-section.jpg). The places are in the right order. They are too small, and the ground is still a pad with a wall. This plan sets a size for each playable area and replaces the block ground with sculpted terrain. Painted maps for each level are not in the tree yet. The placeholder is at the end.

[maps/MAP_LEGEND.md](maps/MAP_LEGEND.md) still applies. The hub chart is a bird's-eye arrangement, not a survey. Outer-kingdom bearings on the world map stay illustrative. This plan does not treat them as meters.

## What stays decided

- Kenney cliffs ship until an Ember Art cliff mesh for that face is in the tree. The swap is part of the patch for that level. Ember Art is not asked to redraw Kenney or Quaternius.
- The Core stays closed. The heart on the shaft chart is not a level.
- Music stays silent until a track exists.
- The Drowned Choir stays one body.
- Proposed bible lines stay out of dialogue. This plan adds no spoken lines.
- No rebel leader and no DLC town names.
- `Vigil.xp_mult` stays unwired. `apply_void_on_player` stays uncalled.
- Protocol stays 7. Save version stays 1. Windows stays unverified and does not block. The AppImage stays on the prerelease.
- Level ids, exit targets, NPC speakers, and waystone ids stay. Gate order stays: Association north of town, Landfill south, Old Oak east, Breach north of the dump. The 4 m slide cap from [PLAN_LEVEL_REMAKE.md](PLAN_LEVEL_REMAKE.md) cannot survive a real resize. The same patch that grows a level updates the playtest bot. Intro still finds Bob downstairs. The Filth is still last. The nave door stays shut until the Choir falls.

## How big a Borderlands zone is

Gearbox has not published zone dimensions in meters. A 2019 note from Randy Pitchford says locations vary, some bigger than past averages and some smaller, and that Borderlands 3 as a whole is a lot bigger ([ComicBook](https://comicbook.com/gaming/news/borderlands-3-map-size-teased-by-gearbox-ceo/)). Later writeups say the exact figures were never released ([ExpertBeacon](https://expertbeacon.com/is-borderlands-3-map-bigger-than-borderlands-2/)). Unreal landscape math (1 unit = 1 cm) is a UE4 convention ([Unreal forums](https://forums.unrealengine.com/t/calculating-exact-map-size/19644)). It is not a measured Borderlands 2 bounding box, so this plan does not invent a Sanctuary width from it.

What is published is how long the walk feels.

- Sanctuary is the hub: a town with streets, vendors, and a bounty board, played as a place you cross on foot ([GamingLives](http://www.gaminglives.com/2012/07/13/borderlands-2-interview-with-gearbox-vp-steve-gibson/), [Sanctuary](https://borderlands.fandom.com/wiki/Sanctuary)). No meter figure turned up.
- Three Horns Divide is the early open zone. Without a car, the road from the boat to the Sanctuary entrance is described as about five minutes ([NamuWiki, Borderlands 2 locations](https://en.namu.wiki/w/%EB%B3%B4%EB%8D%94%EB%9E%9C%EB%93%9C%202/%EC%9E%A5%EC%86%8C)). That is one road, not the diagonal of the map, and it is their walk, not ours.
- Southern Shelf is a separate region. "Several hundred miles" and a fifteen-hour ferry are the trip between regions, not the playable ice ([Southern Shelf](https://borderlands.fandom.com/wiki/Southern_Shelf)). Those numbers are not a zone size.
- A large Borderlands 3 map, walked with no vehicle, is described as well over ten minutes. Splinterlands is described as about two to three times Borderlands 2's Highlands and as the widest map in the series, with stretches meant for a vehicle ([NamuWiki, Borderlands 3 locations](https://en.namu.wiki/w/%EB%B3%B4%EB%8D%94%EB%9E%9C%EB%93%9C%203/%EC%9E%A5%EC%86%8C)). No Wonderlands meter figure turned up. It uses the same pattern: a hub, then zones you cross on foot or faster.

Our sprint is 7.0 m/s and our walk is 4.0 m/s (`sprint_speed` and `walk_speed` in [scripts/player/player_tuning.gd](../scripts/player/player_tuning.gd)). A straight sprint of one minute is 420 m. Five minutes is 2.1 km. Ten minutes is 4.2 km. Those are straight lines at our speed. A Borderlands road bends and stops for fights, and their on-foot speed is not 7 m/s, so a five-minute BL2 road is not a surveyed 2.1 km. It is the band this plan aims at: a hub is about a minute across, an early open zone is a few minutes along its road, and a vehicle-scale desert is out of scope until we have a vehicle.

## Target playable size

"Playable" means the ground you can walk, not the terrain margin past the cliff. Times are straight lines at 7.0 m/s and 4.0 m/s with no fight and no slope. Slopes make the walk longer.

| Place | Now | Target | Sprint | Walk | Borderlands read |
|---|---|---|---|---|---|
| Town ring, outer | 72 m | 320 m across | 46 s | 80 s | Sanctuary-class hub. A loop of the ring is about two and a half minutes sprinting |
| Town square, built up | 36 m | 120 m across | 17 s | 30 s | The paved heart inside the ring. Fountain, stalls, Flagon, three gates |
| Landfill, long axis | 150 m | 900 m | 129 s | 225 s | Early open zone. About two minutes sprint, under the five-minute Three Horns road |
| Landfill, across | 48 m | 220 m | 31 s | 55 s | Wide enough for a bowl, berms, and a side path |
| Association hall | 24×32 m | 40×56 m | 8 s on the long side | 14 s | A building, not a zone. You still see the dais from the south door |
| Association grounds | about 64×56 m | 180×140 m | 26 s and 20 s | 45 s and 35 s | The cathedral close on the north side of town |
| Old Oak grove | 16 m hollow | 200×160 m | 29 s on the long side | 50 s | The tree at the edge of town, with hills around it |
| Old Oak hollow and lab | 16 m, stair up | hollow stays about 20 m | 3 s | 5 s | A room. The lab stays upstairs |
| Act V, one shelf | pads of 6–8 m | about 100 m across, about 50 m of drop to the next shelf | 14 s across | 25 s | A vertical set piece, five shelves. Not a second Three Horns |

The five Spire shelves stacked with those drops are a few minutes of descent, mostly falling and fighting, not a 2 km plain. That matches the chart, which draws Act V as a void under the other acts, not as a map you drive.

## Natural ground

Flat pads and wall boxes are the blockout. The ground that ships is a Terrain3D heightmap, which the project already uses on the town and the landfill.

Each outdoor level gets:

- A sculpted heightmap: hills, a slope you walk, a ravine that is a path, rock outcrops.
- Texture blend across the layers already named on that level, plus one emissive only where the chart needs it (ward crystal, pool, circle, spire crystal).
- Foliage and grass as instances, no collision, faded with distance.
- A cliff or a steep rim as the boundary. A wall box remains only where there is a building, a gate, a rail, or a room (the hall, the hollow, the lab, the Flagon).
- Kenney cliff meshes on the steep faces until the Ember Art cliff for that face is in the tree. Then the dress swap removes the Kenney run. The heightfield is the collider either way.

Interiors stay meshes on a flat pad cut into the heightmap: the hall, the library, the hollow, the lab. The pad is the floor. The terrain is everything outside it.

### Which levels are rebuilt

| Level | What happens |
|---|---|
| Town | Full ground rebuild. The 72 m close cannot be stretched into a 320 m ring. New heightmap, new ring, same ids and the same three gate directions |
| Landfill | Full ground rebuild. The 150 m trench is the blockout of a 900 m valley. Bowl, yard, and north road stay in that order |
| Association hall | Upgrade. Gothic shell and circle on the existing room, grown only to 40×56 m |
| Association grounds | Rebuild of the outdoor close into the 180×140 m precinct. The hall pad is the flat cut |
| Old Oak hollow and lab | Upgrade. Same stair, same room, dressed. Hollow stays a room |
| Old Oak grove | Rebuild. New exterior terrain around the same tree pivot |
| Act V | Rebuild of the blockout pads into five sculpted shelves. Checkpoints 19–23, the kill rule, the lit path, and the quest stay |
| Breach, Warrens, Blightcoil, Slagworks, Sunken | Not this sequence. They are not on the two charts this plan is answering |

## Performance, nav, co-op, kill line, export

**Heightmap.** One heightmap per outdoor level is enough at the targets above. A 900×220 m valley at 1 m spacing is about 200k samples. A 400 m town zone is smaller. A 2 km square at 1 m is about four million samples and is the reason the long landfill target stops at 900 m until a vehicle exists. Spacing stays 1 m on paths and can go to 2 m on rims nobody walks.

**LOD and streaming.** Use Terrain3D's own LOD. Do not add a second terrain system. Do not stream chunks in these patches. One zone in memory is the budget. Chunk streaming is the follow-up only if a later decision takes the landfill to the multi-kilometer band.

**Foliage.** Instanced, no collider, no nav. A view should stay under about 8k visible instances, faded by about 50 m. That number is a cap to measure, not a claim about the engine. Grass does not outline the kill line.

**Occlusion.** Buildings and the oak occlude. The heightfield does not get a custom occlusion pass in 0.11.x.

**Nav.** Offline tiles, as now. Bake the slopes the agent can walk (max slope 45°) and the pads. Do not bake the rim. Town at 320 m and the landfill at 900 m will be many more tiles than the four town tiles shipped in 0.10.0. The bake stays a tool run, not a hitch at join. A visual cliff mesh is excluded. If a gate collider moves, that level's cache is rebaked in the same patch and `test_nav_tiles.gd` has to see it fresh.

**Co-op.** Peers build the same heightmap from the level data and compare `content_hash()`, which they already do. A larger image makes that compare heavier. It does not add snapshot fields, so protocol stays 7. Foliage is local. Wind and failing platforms stay host-applied. A client does not add the shove.

**Kill line.** The line is 8 m under the lowest wide walkable top. A ravine the player is supposed to walk must be that walkable top, or the line is stamped under the thalweg on purpose. A ditch that is only a texture must not be a wide collider or it becomes the line and kills people on the path. On the Spire, a fall between platforms stays above the line. A fall past the lowest shelf is the kill. The tower mesh must not include a wide box.

**Export.** Height and control images plus the layers that level names. `tools/export_set.py` keeps unused layers out. A 900 m valley is on the order of a megabyte of raw height, not a new distribution problem. The tower and the hall shell are the large meshes, capped at 30k triangles each. Kit pieces stay at or under 2k and are instanced.

**Lights.** Practical only. Town 8, landfill 4, hall 8, lab 2. Ward crystals and the pool are emissive, not one real light each. Reduced motion skips flicker. It does not turn lights off.

## What each level still has to look like

Scale does not drop the chart. The same patch that grows the ground puts the landmark in.

### Town

Ring of about 320 m on a sculpted rim, not four straight walls. Three gate roads, west arc shut. Square about 120 m, fountain, stalls, Flagon. Four crystal wards, not five. Dome is the skybox and a horizon band, not a collider. The north arch is tall enough to read as the hall. The cathedral mesh is the Association patch, seen past the gate.

### Landfill

A 900×220 m valley. Hills and a slope from the yard down to the bowl, then the north road. The bowl is round, with a green sheet on the existing height, not a lower collider. Berms and outcrops close the sides. The north cut frames the Breach with a crater mouth. The crater floor stays the Breach level. Trash scatter stays on the valley floor. The Filth is still the last fight, in the bowl.

### Association

Grounds 180×140 m of precinct: grass, a slope up to the hall, the courtyard open to the sky, the library as the east wing of one room. Hall interior 40×56 m under a gothic shell. Emissive circle on the dais, visible from the south door. No 90 m wing. Side doors stay shut until `tutorial_done`.

### Old Oak

Grove 200×160 m. The trunk stays the pivot it has now, crown outside the playable hollow. Runes and vines on that mesh. The hollow and the upstairs lab stay rooms. The bench of pots is the garden. No yard outside the bark. Bob is still downstairs.

### Act V

Five shelves, each about 100 m across, about 50 m of drop between them. Crystal material and a rock skirt on the pads. False sky on these floors only. One non-colliding tower hanging from that sky, readable from the first shelf. No floor under the lit path. No Core. Harpies and the Warden stay the current data until a silhouette mesh exists. No new attacks and no hymn.

## Asset sources

1. CC0 already in the tree, or another CC0 pack with a line in CREDITS. Sky gradients, a pool material, grass cards.
2. Ember Art commissions. Cliff face, ward pillar, gate, bowl lip, hall shell, circle inlay, oak rune skin, tower, one rock-island kit. One file per slot. A person accepts it before it replaces Kenney.
3. AI only as a concept board for a commission. The board is not a texture and not a mesh in `assets/`.

## Version sequence

These stay 0.11.x. 0.12.0 is the Core and does not start. Each one is its own PR and its own prerelease (AppImage, Windows zip, SHA256SUMS). Windows unverified does not block.

Every patch: full tier, solo playtest, `COOP_LAG=150 COOP_LOSS=0.02`. The capture script stays out of the repo. Ship a top-down of the whole playable area, two or three player-height shots (spawn, landmark, boundary), and a labeled side-by-side. The left side is the painting in `docs/maps/levels/` for that level.

| Version | Lands | Done when |
|---|---|---|
| 0.11.1 | Town rebuilt to the ring and the 120 m square. Terrain, three gates, dome sky, crystals if the mesh is in | Straight sprint across the ring is about 45 s. North arch reads from the spawn. Exits still go north, south, and east. Bot updated in the same PR. Side-by-side shows a ring, not a 72 m square |
| 0.11.2 | Landfill rebuilt to about 900×220 m. Sculpted valley, round green bowl, crater mouth | Sprint of the long axis is about two minutes. South lip sees a circle and a green pool. Breach exit still fires. Filth still last. Kill line under the bowl path, not on it |
| 0.11.3 | Association grounds rebuilt. Hall shell and circle on a 40×56 m interior | Grounds take about 25 s to sprint. Circle visible from the south door. Library still one room. Side doors still wait on `tutorial_done` |
| 0.11.4 | Oak grove rebuilt around the same tree. Hollow and lab dressed | Grove is about half a minute to sprint. Intro still finds Bob downstairs. `test_bobs_lab.gd` still passes. No new yard |
| 0.11.5 | Five Spire shelves, false sky, crystal pads, tower mesh | A shot from the first shelf shows the tower and the drop. Top-down is not an empty sky. `test_spire.gd` still passes. No Core geometry |

A Kenney cliff that is still standing is named in that version's notes. It does not block the rest of the patch.

## Painted level maps

The full set, including Breach and Acts I–IV, is listed in [maps/levels/README.md](maps/levels/README.md). Creature sheets are in [concepts/creatures/README.md](concepts/creatures/README.md). The normalized layout taken off each painting is in [specs/](specs/). A build uses that painting as the underlay and has to pass the overlay check in the spec.

These are the visual target for each level. They are arrangements, not surveys: the meter table above is the size, and these paintings are the look. Each file is already under 1 MB.

- [Town](maps/levels/town.jpg). A round walled close: paved square, fountain, striped stalls, the Flagon on the west, four purple ward crystals, main gate south, east gate, the cathedral and its glowing circle to the north, the Old Oak outside the east wall. The cathedral and the oak are the neighboring levels, seen through those gates. The town level is the ring.
- [Landfill](maps/levels/landfill.jpg). A round junk pit: green Filth pool in the middle, trash and shacks, purple crystals in the heaps, a gate on the rim, and the Breach as a crater with a purple fall beside the pit. That bowl is the set piece inside the 900×220 m valley. The south road is the town gate. The north road is the Breach.
- [Association](maps/levels/association.jpg). Gothic hall, blue roof, glowing summoning circle on the dais, courtyard garden and fountain to the west, library to the east, a stone wall, hills outside. The long library wing in the painting is the look of the east room. The room stays one room inside the 40×56 m hall. It does not come back as a 90 m wing.
- [Old Oak](maps/levels/bobs_lab.jpg). The rune-cut tree, a door in the trunk, purple crystals, a fenced path, mushrooms, and the cutaway of the hollow: ground floor with the stair, upstairs slab, potion shelves, and the pot bench. The fenced crystals and the path are dressing on the 200×160 m grove. The potion garden stays the upstairs pot bench.
- [Act V](maps/levels/inverted_spire.jpg). A false starry sky, an inverted tower hanging from it, crystal islands, and bridges of light. The middle label on that painting is garbled. It means Middle Platform. The extra side ledges are dressing on the five shelves (checkpoints 19–23). They are not extra floors. There is no Core under the lowest shelf.

## Decisions

ShobieShy locked every recommended default on 20 Nov 2026 ("finalize and implement"). The patches below do these. They do not reopen them.

1. **No published meter, so use the walk.** The levels use the traversal bands above, at our 7.0 m/s sprint and 4.0 m/s walk. The ferry's hundreds of miles and the Unreal landscape formula are not zone sizes.
2. **The landfill is about 900×220 m.** A two-minute sprint. The five-minute Three Horns road stays the upper reference until there is a vehicle. 0.11.2 does not build a 2 km valley. The painting's round pit is the bowl in that valley.
3. **The Association is not a zone.** The hall is a building, about 40×56 m. The grounds around it are the 180×140 m precinct. The library stays one room.
4. **Act V is not an open zone.** Five shelves of about 100 m, with a real drop between them. The garbled middle label means Middle Platform.
5. **Rebuilds.** Full ground rebuild for Town, Landfill, Association grounds, and the Oak grove. Upgrade only for the hall interior, the hollow, the lab, and the Spire rules (kill line, lit path, quest).
6. **The 4 m cap is lifted** for these five patches. Ids and gate order stay. The playtest bot moves in the same PR as the ground it walks.
7. **Outdoor boundaries are cliffs, rims, and steep ground.** Wall boxes stay for buildings, gates, rails, and rooms. A thin safety wall may sit at the far edge of the heightmap, behind the cliff, so a step off the data does not leave the kill line.
8. **Kenney cliffs stay** on any face whose Ember Art mesh is not in the tree yet. The swap is in that level's patch. A late mesh does not hold the scale. The stand-in is `rock-large.glb` from the Kenney fantasy town kit. There is no separate cliff mesh in the tree.
9. **The potion garden is the upstairs pot bench.** The grove outside the bark is the 200×160 m outdoor rebuild, dressed like the painting (path, crystals, mushrooms, fence). It is not a second garden and not a new quest spot.
10. **Original meshes are Ember Art commissions.** CC0 covers generics. AI is only a concept board, never a shipped mesh. These five patches use meshes already in the tree plus Kenney and Quaternius stand-ins. They do not invent a new commission.
