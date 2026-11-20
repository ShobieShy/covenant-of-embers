# Art pass: the charts, then the levels

Written 20 Nov 2026, against master `1137b6c` (v0.11.0-prealpha). This is a plan. It does not change a level, a mesh, or a release.

The before pictures are the 20 Nov 2026 captures: a top-down of each remade level beside [docs/maps/eldoria-hub-map.jpg](maps/eldoria-hub-map.jpg) or [docs/maps/labyrinth-cross-section.jpg](maps/labyrinth-cross-section.jpg), plus in-game shots from player height. [maps/MAP_LEGEND.md](maps/MAP_LEGEND.md) is how to read those paintings. They are arrangements of documented places, not surveys. Bearings of the outer kingdoms on the world map stay illustrative. This plan does not use them.

## What stays decided

These are closed. This plan does not reopen them.

- Kenney cliffs, berms, and blockout ship until an Ember Art mesh for that slot is in the tree. The swap is the point of the patches below. [PLAN_LEVEL_REMAKE.md](PLAN_LEVEL_REMAKE.md) already lists the original pieces. Ember Art is not asked to redraw Kenney or Quaternius.
- The Core stays closed. The heart at the bottom of the shaft chart is not built. No Joe fight, no Demon Lord, no leaving shot.
- Music stays silent until a track exists.
- The Drowned Choir stays one body.
- Proposed bible lines stay out of dialogue. The art pass adds no spoken lines.
- No rebel leader and no DLC town names. The ward-pillar flicker in the storyline is a later hook, not a scene here.
- `Vigil.xp_mult` stays unwired. `apply_void_on_player` stays uncalled.
- Protocol stays 7. Save version stays 1. Windows stays unverified and does not block. The AppImage stays on the prerelease.
- Gameplay anchors stay. Level ids, exit targets, NPC speakers, waystone ids, and the intro anchors do not change. Starts, exits, NPCs, waystones, and anchors move at most 4 m, or the playtest bot moves in the same patch. The 0.10.x footprints stay: town 72 m close and 36 m square, landfill 48×150 m with pads at y 0 and y −2, Association hall 24×32 with library 18×22 east and courtyard 22×24 west, Old Oak hollow 16×16 with the lab up the west stair, Spire checkpoints 19–23.

## The gap

The 0.10.x and 0.11.0 levels are the right places in the right order. They do not yet look like the charts.

| Level | Chart | Built, v0.11.0 |
|---|---|---|
| Town | Circular stone wall, dome, four crystal wards, cathedral to the north, fountain, stalls, Flagon, south and east gates, oak outside the east gate | Raised square, three gate notches, west cliff shut, Kenney walls as cliffs, fountain and stalls and two roofs. No dome, no crystal cages, no cathedral |
| Landfill | Round junk pit, green Filth pool, trash piles, crater at the rim | Long rectangular trench, Kenney rocks as berms, trash props, pads at the old heights. No round pool, no crater in this level |
| Association | Gothic hall, glowing circle on the dais, library as a wing, small courtyard | Greybox hall, shelf room to the east, walled court and fountain to the west, berm behind. The circle does not read. The 90 m wings are gone on purpose |
| Old Oak | Huge rune-cut tree, door in the trunk, crown outside the wall | Interior hollow. The crown mesh sticks out of the north wall. The lab is a stair and a small upstairs room with Kenney stand-ins. The chart does not show that room |
| Act V | Crystal void, islands, a tower growing down from a false sky, under the other four acts | Three collision pads on the Warden floor. No mesh, no crystal, no tower, no false sky. Harpies and the Warden are data, not a silhouette |

## Rules for every patch

- A visual mesh does not get a collider unless it is the floor, a gate, a rail, or a wall the player must not walk through. Dress props stay out of the nav bake. [tools/bake_nav.gd](../tools/bake_nav.gd) runs only when a collider moves. Interior nav ([tools/bake_interior_nav.gd](../tools/bake_interior_nav.gd)) runs only if the Association or the Breach interior collision changes.
- Do not add a wide slab lower than the current lowest walkable top. [scripts/player/kill_plane.gd](../scripts/player/kill_plane.gd) sets the line from the lowest wide box, minus 8 m. A decal, a pool sheet, or a tower must not become that box.
- Co-op snapshots do not carry meshes. No protocol bump. Wind and the Warden's failing platforms stay as they are: the host applies the shove, a client does not add it again, and a fall between Spire platforms stays above the kill line.
- Lighting stays on the grades already in the level toml. New lights are practical: ward glow, barrel fire, hall lantern, lab candle. Reduced motion does not turn them off. It only skips a flicker.
- Each patch regenerates the 20 Nov capture: top-down of the playable area, two or three player-height shots (spawn, landmark, boundary), and a labeled side-by-side with the chart. The capture script stays out of the repo. The before image is the previous side-by-side. The after image is the same camera.
- Full tier, solo playtest, and `COOP_LAG=150 COOP_LOSS=0.02` on every patch. Intro still finds Bob downstairs, the Filth last, the Choir one body, and the nave door still shut until the Choir falls.

## Asset strategy

Three sources, used in this order.

1. **CC0 packs already in the tree, or another CC0 pack with a license note in CREDITS.** Stone, trash, wood, sky gradients, a simple crystal shard. Kenney and Quaternius stay where no original mesh exists yet.
2. **Ember Art, commissioned.** The original pieces named in [PLAN_LEVEL_REMAKE.md](PLAN_LEVEL_REMAKE.md), plus the five landmarks this plan adds: dome sky, round bowl lip, gothic hall shell, oak rune skin, inverted tower. One file per slot, named so `tools/dress_levels.py` can point at it. A person checks the mesh before it replaces Kenney.
3. **AI-assisted concepts, not shipped meshes.** A mood board for a commission (gothic silhouette, tower from below, rune layout on the existing oak). The board is not a texture and not a collider. Nothing generated goes in `assets/` until someone accepts it as the commission brief.

Materials, fog, and sky are cheaper than new geometry and land in the same patch as the mesh they support. Reuse the terrain layers already shipped (`path_cobble`, `rock`, `dirt`, Ground037, Rock030, PavingStones131). Do not add a second terrain zone to a level that has one.

## Per level

### Town — 0.11.1

**Chart.** A round wall under a dome. Four crystal wards. Cathedral north. Fountain, stalls, Flagon, south gate, east gate, oak beyond the east gate.

**Keep.** 72×72 close, 36 m square at about y 2, exits at the current xz (Association north, Landfill south, Old Oak east), west side shut, four ward posts, fountain at the origin, stalls, Flagon.

**Change.**

- The cliff reads as a ring, not four straight Kenney runs. The ring sits on the existing cliff colliders. Gate mouths stay on the three roads. The west arc has no mouth.
- Ward pillars gain a glass cage and an emissive crystal. Four, not five. The chart's extra post by the south gate is the legend's own note that canon is four.
- Sky is a pale dome gradient, brighter at the zenith, with the barrier as a faint horizon band. It is a skybox. It is not a shell the player can hit.
- The north gate's arch is the landmark from the spawn, tall enough to read as the hall beyond. The cathedral mesh itself is the Association patch, seen through the gate, not a second building inside the square.

**Assets.** CC0 sky if one matches the grade. Ember Art: ward pillar with cage, cliff face texture, arch, south gate, east gate, as already listed. Kenney cliffs remain until that cliff texture and a trim mesh are in the tree, then the dress swap is the same patch.

**Collision.** None of the new meshes collide. The cliff boxes stay. Nav rebake only if a gate collider moves. Kill line stays on the street and square tops.

### Landfill — 0.11.2

**Chart.** A round pit of trash, a green pool, the crater at the edge of the pit.

**Keep.** 48×150 m valley, yard at y 0, bowl and north road at y −2, berms, south ridge at the town gate, north rock cut at the Breach gate, intro anchors, Filth last.

**Change.**

- From the south lip the bowl reads as a circle. Four curved lip meshes sit on `bowl_floor`. The valley stays a rectangle in the berms. The pit is the bowl, not a new outline for the whole 150 m.
- The pool is a green translucent sheet and a wet decal on the existing bowl top. It is not a lower collider. Standing in it does not move the kill line and does not add a new hazard unless a later plan says so.
- The crater is a visual mouth at the north cut: broken rock and a violet gap, framing `to_breach`. The crater gameplay stays `breach`. This level does not gain the crater floor.

**Assets.** Quaternius trash stays as scatter. Ember Art: berm section, curved bowl lip, wet decal, Filth residue, north rock cut, as already listed. CC0 for the pool sheet if it is a flat material. Kenney berm rocks swap when the berm section mesh exists.

**Collision.** Lip and pool are visual. Rock cut can replace the existing `rock_cut` box only if the gate volume still fires and the road stays at y −2. Rebake landfill nav if that box moves. Kill line stays on the bowl top.

### Mage Association — 0.11.3

**Chart.** A gothic cathedral, a glowing circle, a library wing, a small court.

**Keep.** Hall 24×32, library 18×22 on the east, courtyard 22×24 on the west, dais and intro spots, side doors shut until `tutorial_done`, back door to the landfill behind the dais. The 90 m wings stay gone.

**Change.**

- A gothic shell (roof, gable, one west window run) sits on the hall so the south door frames a cathedral, not a flat Kenney roof. The shell is visual. The wall boxes remain the collision.
- The summoning circle is an emissive inlay on the dais, visible from the south door. No new dialogue.
- The library reads as a wing from the east door: shelf runs, a cooler light, no mezzanine and no archive stair. The chart's long library is the old wing. This plan does not put it back.
- Courtyard fountain stays smaller than the town fountain. Trees stay. The back berm texture replaces the flat berm when the texture exists.

**Assets.** Ember Art: hall shell, circle inlay, shelf run, precinct wall segment, courtyard tree if the Kenney trees are the remaining blockout. CC0 stone trim only where it matches the shell. Kenney pillars and benches swap per slot, not all at once if a mesh is late.

**Collision.** Shell and circle do not collide. No nav rebake if the boxes are untouched. Interior nav stays the tile cache. Kill line unchanged. The roof must not become a walkable wide slab above the kill check in a way that traps the bot; if the shell is only a mesh, it will not.

### Old Oak and Bob's lab — 0.11.4

**Chart.** The tree from outside: a trunk with a door, runes, a crown. It does not draw the upstairs room.

**Keep.** Hollow 16×16, bark walls, moss beds, stash, waystone, town door, the west stair, the upstairs room. Bob is still met downstairs. The exterior footprint does not grow. The potion garden stays the bench of pots in that room. It is not a yard outside the bark.

**Change.**

- The oak mesh keeps its pivot at the north bark. Runes and vines are a material or a replacement mesh on that pivot, so the crown still breaks the wall line and the door still reads from the hollow.
- The lab stand-ins swap when the pieces exist: chart, slab, shelf, pots. Until then Kenney stays, which is what 0.10.3 shipped.
- A candle or two in the lab, warm, on the existing grade. No new sky.

**Assets.** Ember Art: rune and vine set for the existing oak, plus the lab set already named (chart, slab, shelf, pots). No new oak species. AI only as a rune layout for the commission, not as the texture that ships.

**Collision.** Stair, floor, and rails stay the colliders. A new oak mesh must use the same collision as today (the bark boxes). No nav change if those boxes do not move. Kill line stays on the hollow floor. The lab floor is above it and must not become a lower slab.

### Inverted Spire — 0.11.5

**Chart.** Under the other acts: a crystal void, floating rock, a tower growing downward from a false sky. The Core heart under that is out of scope.

**Keep.** Checkpoints 19–23, three platforms, kill line below the lowest platform, the Warden fight on platforms that fail, the lit path instead of a fourth shell, waystone home, one quest to face the Warden. No hymn, no Core room, no new floor under 23.

**Change.**

- A false-sky environment on the Spire only: a bright underside, darker toward the shaft, no sun disc that reads as outdoors on the surface.
- The three platforms get a crystal material and a simple rock skirt. Collision size stays. The capture no longer has to invent a white box to be visible.
- An inverted tower mesh hangs above the high platform, non-colliding, readable from checkpoint 19 looking along the stack. It is the landmark. It is not a floor and not a path to the Core.
- Harpy and elemental stay the rusher data. A silhouette mesh can replace the capsule when one exists. The Warden silhouette is the same rule. No new attacks.

**Assets.** CC0 crystal shader only if it is a material on the existing pads. Ember Art: tower mesh, one rock-island kit piece instanced for the three pads, Warden silhouette. The chart's whole-shaft painting is not a request to re-dress Acts I–IV in this patch.

**Collision.** None added. No nav bake (the Spire is built in code and has no tile cache). Kill line still comes from the lowest wide platform. The tower must not include a wide box. Failing platforms still disable the same shapes.

## Performance

Budgets are for one player view, not the whole zone loaded as unique meshes.

| Slot | Limit |
|---|---|
| Landmark (cathedral shell, tower, oak) | 30k triangles, one draw |
| Kit piece (berm, wall, island, stall) | 2k triangles, instanced |
| Materials | The sets already on the level, plus one emissive for crystals, circle, pool, sky |
| Practical lights | Town 8, landfill 4, hall 8, lab 2. Ward crystals are emissive, not one real light each |
| New terrain zones | None |
| Particles | None required. A flicker is a light energy tweak and it skips when reduced motion is on |

Co-op cost is the same as today if the meshes have no collision and no gameplay state. A patch that only swaps a visual does not need a protocol test beyond the lagged playtest already required.

## Version sequence

These are 0.11.x patches. 0.12.0 stays the Core, and it does not start.

| Version | What lands | Done when |
|---|---|---|
| 0.11.1 | Town ring, four crystals, dome sky, gate meshes if ready | Side-by-side with the hub chart shows a ring and a dome. Spawn still frames the north arch. Gates and NPCs within 4 m. Full tier, solo, lagged co-op. Kenney cliff called out in the notes if the trim mesh is not in yet |
| 0.11.2 | Round bowl, green pool sheet, crater mouth at the north cut | South-lip shot shows a circle and a green pool. Breach exit still fires. Kill line unchanged. Same tests |
| 0.11.3 | Gothic shell, glowing circle, library shelves | South-door shot reads as a hall, not a flat roof. Circle visible from that door. Library is still one room. Same tests |
| 0.11.4 | Oak runes and vines, lab piece swap | Exterior shot shows the same tree with runes. Intro still talks to Bob downstairs. Stair and room floor still pass `test_bobs_lab.gd`. No new yard. Same tests |
| 0.11.5 | False sky, crystal pads, inverted tower | Top-down is no longer an empty sky. A shot from the high platform shows the tower and the drop. Lit path still replaces a shell. `test_spire.gd` still passes. Same tests |

Each patch is its own PR, its own prerelease, AppImage plus Windows zip plus SHA256SUMS. Windows unverified does not block.

## Decisions

These are the open calls. The default is what the next patch should do if ShobieShy does not say otherwise.

1. **How literal is the chart?** Recommended: it is the look, not a new floor plan. Rings, domes, shells, and the tower are visuals on the 0.10.x and 0.11.0 collision.
2. **Town dome.** Recommended: a skybox and a horizon band. Not a collider, and not a new zone outside the 72 m close.
3. **Landfill circle.** Recommended: round the bowl only. The valley stays 48×150 m. The crater stays the Breach level, with a visual mouth at the north gate.
4. **Association library.** Recommended: keep the 18×22 room. Do not restore the 90 m wing to match the painting.
5. **Oak garden.** Recommended: the bench of pots is the garden. Dress it. Do not add ground outside the bark. Runes go on the existing oak.
6. **Spire tower.** Recommended: one non-colliding mesh over the high platform, plus a false sky and a crystal material on the three pads. Do not build the Core, and do not add a floor under the lit path.
7. **Who makes the original meshes?** Recommended: Ember Art commissions from the lists above. CC0 for generics. AI only as a signed-off concept board, never as a shipped mesh.
8. **When do Kenney cliffs leave?** Recommended: in the patch for that level, the day the replacement mesh is in the tree. A late mesh does not block the rest of that patch. Kenney stays on the slots that are still empty, and the release notes say which slots those are.
