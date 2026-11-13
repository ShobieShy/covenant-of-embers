# Level remake: Association, Landfill, Town

Planning only. Written against master `d208b07`. No level geometry in this change.

The three hub levels are small slabs. A step past the slab, or through a gap in the wall, drops the character with nothing under them. The remake makes each one a bit larger and a bit more built, and it closes the sides with ground you can see. Until that ground exists, a kill plane is the floor under every level.

Old Oak stays Old Oak. This plan does not touch it, the Breach, or the labyrinth floors except for the kill plane.

## What is there today

Sizes are the collider boxes in `data/levels/*.toml`. A box marked `hidden` still collides. The dress props (Kenney town kit, Kenney trees, Quaternius trash) are visuals on top of those boxes. Jump height is about 1 m (`jump_velocity` 4.5, gravity 9.8). A 4 m wall cannot be jumped. The falls are through gaps and off the end of a slab.

### Mage Association (`mage_association`)

The hall floor is 20 m by 30 m (x -10..10, z -15..15). North and south walls are one piece each. East and west walls are split, leaving a door gap about 5 m wide at z 0. Two wings sit on either side. Each wing floor is 20 m by 90 m (east x 10..30, west x -30..-10, both z -45..45), with an outer wall and end walls. The inner wall is split so the hall door can open into the wing. The library mezzanine and the archive sit on the east wing. The courtyard, fountain, and six Kenney trees sit on the west wing.

The hall and the wings are mostly boxed in. The fall is where two slabs meet and a foot misses the join, and off the mezzanine or the archive if the rail does not close that edge. The roof box is a collider. If the player can stand on it, the edge of the roof is open air. The wings are long and flat. Ninety metres of one floor, with shelves or trees, is the empty part. It is not a hill and it is not a cliff.

Placed content that has to survive: player start `(0, 0, 12)`, Crazy Joe on the dais, exit `to_town` at z 13, exit `to_landfill` (the back door) at z -13.5, anchors and POIs `library` and `courtyard`. The Clerk is an intro spawn, not a row in this file.

### The Landfill (`midden_greybox`, scene `midden`)

Three floor slabs, none of them a sealed bowl.

| Slab | Size | Top |
|---|---|---|
| Upper trench `ground` | 22 m by 54 m, z -20..34 | y 0 |
| Filth bowl `bowl_floor` | 24 m by 34 m, z -50..-16 | y -2 |
| North road `road_floor` | 8 m by 18 m, z -66..-48 | y -2 |

The sides are trash heaps, not a continuous wall. A heap can be walked around. The south lip ends near z 34, a few metres past the town exit at z 30.5. The north road ends near z -66, a few metres past the Breach exit at z -60. Past either end, and between the heaps, there is no floor.

The tutorial band still sits on the upper slab (yard, shrines, scrap ledge). The Filth is the last fight, on the north ledge of the bowl. Waystone `landfill` is at `(5.5, 0, 15)`. Dress props are Quaternius bags, cans, and bins. They do not hold the player in.

### Eldoria Town Square (`town_square`)

The floor is one 40 m by 40 m slab (x -20..20, z -20..20). The perimeter is an invisible wall, 4 m tall, with a gap in the middle of each side.

North and south gaps are about 4 m wide, centred on x 0, at z ±19.5. Those line up with the Association door and the Landfill gate. East and west gaps are about 5 m wide, centred on z 0, at x ±19.5. The Old Oak exit is at `(17, 0, 14)`, which is behind the east wall, not in that side gap. So the east and west gaps are holes, not roads.

The exits themselves sit on the slab: Association z -17, Landfill z 17.5, Old Oak x 17. Walk a few metres past the exit, through the gap, and the slab ends. Ward pillars are 6 m posts at the four corners. They do not close the gaps. The fountain, four stalls, and the Fractured Flagon are boxes plus Kenney meshes.

Placed content: player start `(0, 0, 14)`, waystone `town_gate` at `(0, 0, 11)`, NPCs Bored Guard, Potion Merchant, Tailor, Runesmith, Grizzled Patron.

## Proposed ground

Slightly larger, and closed. Outdoor ground becomes a heightmap. Rooms stay meshes on flat pads cut into that heightmap. Terrain3D 1.0.2 is already in the repo, and the decision already on the books is per-level terrain, not one seamless world. This plan keeps that. CSG is the blockout. It is not the collision that ships.

A cliff or a berm is the wall the player sees. It is taller than a jump, 4 m or more. A building wall is a wall where there is a building. An invisible collider sits 1 m outside the art, 6 m tall, only where the mesh has a hole. It is the backup, not the look of the place.

Each gate is a road on solid ground that reaches the exit volume. The exit volume is in front of the rim. The rim has no other openings.

| Level | Today, walkable | Proposed footprint | How it holds you in |
|---|---|---|---|
| Association | Hall 20×30, plus two wings 20×90 | A close 64 m by 56 m. Hall 24×32. Library 18×22 on the east. Courtyard 22×24 on the west | Precinct wall on the street sides. A grass berm and a rock cut on the back. The 90 m wing slabs go away |
| Landfill | About 24 m wide and 100 m long, in three slabs | A valley 48 m wide and 150 m long | Trash berms, 6 to 8 m, both sides. The north road ends in a rock cut with the Breach gate in it. The south lip is a ridge with the town gate in it |
| Town | 40×40 slab | 72 m by 72 m, with a raised square 36×36 in the middle | The square sits about 2 m up. Streets slope down to three gates. Outside the streets, a cliff. The east and west holes are closed. The Old Oak road is a real gate on the east, on ground, not a gap at z 0 |

Flat pads, at the height the buildings expect, stay under the hall, the library, the Flagon, the stalls, the fountain, the dais, and each gate. Terrain3D already supports a flat pad and a rim. The heightmap is 1 m. That matches the earlier terrain note.

The Association gets shorter, not longer. The wings are already huge and empty. The remake spends that length on rooms and a courtyard, and adds the berm so the outside is not a slab edge. Town and the Landfill grow. Both are the ones you can walk off today without looking for a roof.

## Kill plane

This ships before the new ground, and it stays after, including on levels this plan does not remake.

The rule is the death note in the bible (the 13 Nov 2026 text). When a life ends, you come back at the last waystone you touched, or at the spawn the run stored if you have not touched one. You keep your loot, your story, and your gold. You do not respawn at the Mage Association, and you do not drop the gold. That older note is withdrawn.

A fall is not a fight. There is nothing to kill, and a teammate cannot stand in the void to pull you up. The kill plane skips the downed window and runs the same respawn the window would have run when it ended.

- The plane is a y value: the lowest walkable point of that level, minus 8 m. It is data on the level, not one world constant.
- The check is the feet, in the player tick. A cinematic does not trigger it.
- Respawn uses the current `respawn()` refill (health, shield, mana, Breath). Gold, dust, inventory, and quest flags are not touched.
- The point is the last waystone position stored for this run. If there is none, it is that level's player start.
- Solo and co-op use the same rule. Only the player who fell moves. The others stay where they are. The host decides the y and the destination. A client does not pick their own coordinates.
- Old Oak, the Breach, and each labyrinth floor get a plane too, using that floor's lowest y. No new art.

## What stays put

Level ids, exit targets, NPC speakers and node names, waystone point ids (`town_gate`, `landfill`), anchor names (`library`, `courtyard`), and the quest ids that say "reach the landfill" or "reach Old Oak". Those systems key off ids, not off a pretty mesh.

Positions may slide by a few metres onto the new pad. The default cap is 4 m from today's coordinates for player start, exits, NPCs, waystones, and anchors. If a gate has to move further than that, the playtest bot is updated in the same change. Nav is rebaked from the new collision. It is not hand-edited.

## Detail, and what Ember Art prepares

The new ground is not a bigger grey box. Each level gets props, a landmark you can see from the spawn, terrain that is not one height, and lights that are not only the sun. Kenney and Quaternius stay as the blockout until an Ember Art mesh replaces that slot. Ember Art is not asked to redraw those packs. The list is original meshes and textures, one file each, named so dress props can point at them.

Lighting stays on the grades already in the toml (cool hall, sickly landfill, warm town). What gets added is practical lights: lanterns, fires, the ward glow. Reduced motion does not turn lights off. It only skips a flicker if one is added.

### Town

Landmark: the Association arch, seen from the spawn, with the four ward pillars still reading as the barrier.

Terrain: cobble on the raised square, a worn cobble on the slopes, a dirt verge against the cliff. Reuse `PavingStones131` as one layer. Ember Art adds a second cobble, more broken, and a cliff face.

| Asset | Count | Replaces |
|---|---|---|
| Ward pillar, stone, with a glass cage for the barrier light | 4 | Kenney `pillar-stone` plus the hidden ward boxes |
| Ward lantern | 4 | Kenney `lantern` on the wards |
| Association door arch, round, two leaves | 1 | Kenney `wall-doorway-round` and the door box |
| South gate, two pillars and a lintel | 1 | Kenney gate pillars |
| East gate, lower, for the Old Oak road | 1 | the east wall gap |
| Street lantern, iron, warm | 8 | Kenney lanterns along the roads |
| Banner, vertical, association colours | 4 | Kenney banners |
| Market stall frame and striped awning | 4 | the stall boxes |
| Crate stack, two heights | 4 | dressing on the stalls |
| Hand cart | 1 | Kenney cart |
| Fountain basin | 1 | the fountain box |
| Fountain water sheet | 1 | the flat water box |
| Flagon front, stone and timber, with a sign | 1 | the flagon boxes |
| Flagon roof and chimney | 1 | Kenney roof pieces |
| Flagon lantern | 1 | Kenney lantern |
| Row-house facade, one door, two windows | 1 | Kenney wall strips |
| Cliff face texture, grey rock, tileable | 1 | none today |
| Broken cobble texture, tileable | 1 | none today |

### Landfill

Landmark: the Filth bowl, a sunken circle you see from the south lip, with the compactor housing on the way down.

Terrain: the valley floor steps down in three pads (yard, bowl, north road), same heights as today (0, then -2). The berms are the new height. Ground037 and Rock030 stay as layers. Ember Art adds a garbage overlay and a wet dark patch for the bowl.

| Asset | Count | Replaces |
|---|---|---|
| Berm section, rock and packed trash, 8 m long | 8 | the heap boxes as the side wall |
| Heap, small | 6 | Quaternius bags used as walls |
| Heap, tall, with a metal sheet | 4 | the larger heap boxes |
| Trash bag cluster | 6 | Quaternius `Trash_Bags` |
| Split barrel | 4 | Quaternius cans |
| Compactor housing, one bay | 1 | the compactor boxes |
| Scrap plate, walkable, 2 m | 6 | the scrap climb boxes |
| Bowl lip, curved rock, 8 m segment | 4 | the open edge of `bowl_floor` |
| North rock cut, with a gate mouth | 1 | the open end of `road_floor` |
| Barrel fire, low flame | 4 | no practical light today |
| Yard lamp, hanging, sickly | 1 | the sun alone on the tutorial band |
| Wet-ground decal for the bowl | 1 | flat colour |
| Filth residue decal | 2 | none |

### Mage Association

Landmark: the summoning circle on the dais, lit, visible from the south door.

Terrain: only the courtyard and a berm behind the close. The hall, library, and archive stay interior meshes on flat pads. The 90 m wing floors are removed, so Ember Art is not asked to dress a corridor.

| Asset | Count | Replaces |
|---|---|---|
| Hall pillar with a capital | 6 | the pillar boxes |
| Summoning circle inlay | 1 | the dais colour |
| Dais step run | 1 | `dais_steps` |
| Bench | 6 | Kenney benches |
| Stool | 6 | Kenney stools |
| Open book, two poses | 4 | Kenney books |
| Shelf run, 4 m | 6 | the shelf boxes |
| Mezzanine rail, 4 m | 4 | `archive_rail` |
| Stair flight, 10 steps, with a rail | 2 | the stair boxes |
| Courtyard fountain, smaller than the town one | 1 | the wing fountain box |
| Courtyard tree, one species, two sizes | 6 | Kenney nature-kit trees |
| Banner, hall, narrow | 8 | Kenney banners |
| Wall lantern, cool | 8 | Kenney lanterns |
| Precinct wall segment, ashlar, 4 m | 10 | the hall's hidden wall boxes |
| Back berm texture, dark rock and moss, tileable | 1 | none |
| Door leaf, library and courtyard | 2 | Kenney `wall-door` |

## Risks

The playtest bot walks to exits, NPCs, and the intro marker by coordinates. Moving those more than a few metres without updating the bot fails Act I. The default keeps them within 4 m, and the same PR updates the bot if a gate cannot stay that close.

Nav is generated. A cliff that is too steep, or a pad that does not meet a door, bakes a hole and the bot stalls. Each remake PR rebakes and runs the solo playtest.

Terrain3D in headless already has a known harmless `res://` error pair. A new heightmap must not add a new error, or the test run goes red.

Taking the invisible town walls down before the cliff is in is a week of falling off the map. The cliff, the rim collider, and the removal of the old slab edge land together.

The Association wings are long because the library stair and the courtyard were generated into them. Shortening the wings means those beats move onto the new pads, with the same anchor names. The intro still looks up `library` and `courtyard`.

## Versions

Two kinds of change. The kill plane is code and a y value. The remakes wait on meshes.

**0.9.3, the kill plane.** Every current level, including ones this plan does not rebuild. No new art. Respawn as above. This is the safety net while the slabs are still slabs.

**Then one PR per level,** so a missing Flagon front does not block the landfill berms.

- 0.10.0 Town
- 0.10.1 Landfill
- 0.10.2 Association

If the meshes for all three are ready together, they can still ship as those three versions back to back. They do not merge into one PR.

## Defaults

1. **0.9.3 is the kill plane only.** The three remakes are 0.10.0, 0.10.1, and 0.10.2, one PR each. Town, then Landfill, then Association.
2. **Outdoor ground is per-level Terrain3D.** Interiors stay meshes on flat pads. The seamless world stays rejected. CSG does not ship.
3. **The hold is a cliff or a berm you can see,** 4 m or taller. An invisible collider is only the backup on the outer rim.
4. **A fall skips the downed window** and respawns like a finished death. Last waystone, or the level spawn if there is no waystone yet. Gold, loot, and story stay. The bible's death note is the rule.
5. **Co-op respawns only the player who fell.** The host picks the point. The others do not move.
6. **Every level gets the plane,** not only these three.
7. **Town grows from 40×40 to 72×72.** The square is raised. Only three gates open the rim, and each gate has ground under it.
8. **The Landfill grows to a valley about 48 m by 150 m,** with berms on both sides and a rock cut at the north end.
9. **The Association close is 64 m by 56 m.** The 90 m wing slabs are removed. The hall, library, and courtyard stay, on shorter pads.
10. **Starts, exits, NPCs, waystones, and anchors move at most 4 m.** Further than that updates the playtest bot in the same PR. Ids do not change.
11. **Kenney and Quaternius stay until the Ember Art mesh for that row exists.** Ember Art is asked for the rows in the three tables, not for a redraw of those packs.
12. **Old Oak, the Breach, and the labyrinth are not remade here.** They only gain the kill plane.
