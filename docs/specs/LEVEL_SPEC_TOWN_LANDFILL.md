# Layout spec from the paintings: Town and Landfill
Written by Luna from docs/maps/levels/town.jpg and landfill.jpg, Nov 20 2026, for ShobieShy.
The paintings are three-quarter views. Read them as a TOP-DOWN plan by un-squashing vertically (circle on paper = circle in world).
Coordinates are normalized to the painting: x 0 = west edge, 1 = east; y 0 = north (top), 1 = south (bottom). North is up (compass top-right).

## Rules for both levels (non-negotiable)
1. SHAPE: the walkable outline must trace the painting. Put the painting (un-squashed) as a top-down underlay plane in the scene, scaled to the target size, and build on top of it. Acceptance overlay: top-down render at 50% opacity over the painting; outer boundary, main paths and every landmark must line up within ~5% of map width.
2. PATHING: paths curve as painted. No straight grid roads, no single straight corridor.
3. NO GREYBOX IN SHIPPED LEVELS: no untextured blocks, no white primitive "rocks", no flat colored quads. Every surface uses a real PBR material (cobblestone, packed dirt, grass, mud, rock, wood, stone masonry) from CC0 sources (Poly Haven, ambientCG) and real meshes (Kenney fantasy-town/medieval kits, Quaternius medieval village & nature packs, KayKit, Poly Haven rocks), or Ember Art.
4. LANDMARKS READ FROM SPAWN, as in the painting's composition.
5. LOOK: warm golden-hour light, light fog/atmosphere, foliage scatter (grass, bushes, trees as painted), proper sky. Match the painting palette.
6. Ship gate: side-by-side + overlay renders, plus 3 player-height shots. If it doesn't match, it doesn't ship. Report honestly.

## TOWN (Eldoria) - target ~320 m diameter inside the wall
Overall: a ROUND walled town on top of a raised hill/plateau. Outside the wall the ground drops 10-15 m via a rocky escarpment ring, then grassy slopes. A translucent dome covers it (golden on the west half, violet on the east half).

Wall ring: circular curtain wall, center ~(0.52, 0.52), with an EAST LOBE bulging out to enclose the Old Oak (wall wraps around the oak, ~x 0.72-0.93, y 0.30-0.65).
Gates:
- Main Gate: due south (0.50, 0.80). Arched gatehouse flanked by two tall towers each topped with a violet crystal. A cobbled road leaves the gate straight south and descends the hill.
- East Gate: southeast (0.71, 0.66), smaller arched gate in the oak lobe's south wall. A dirt path leaves it curving south/south-east down the slope.
- West: sealed (solid wall).

Districts (inside the ring):
- Town Square: circular cobblestone plaza at center (0.50, 0.55), radius ~ 1/5 of town radius (~30 m). Tiered stone fountain (three basins, water) at its exact center. Lamp posts around its rim.
- Mage Association: NORTH, centered (0.50, 0.22). Gothic cathedral facade with blue-slate roofs and two flanking spires, tall arched stained-glass window, big double doors facing SOUTH, wide steps down to a short cobbled lane into the square. The doors are the level transition to the Association. Library wing (long building, blue roof) attached to its north-east (0.64, 0.22).
- Courtyard Garden: NORTH-WEST (0.28, 0.30). Raised grassy terrace behind its own low wall, trees, small fountain at (0.30, 0.35).
- The Flagon: WEST (0.24, 0.53). Two-storey timber-frame tavern, dark shingle roof, chimney, hanging sign, door facing EAST toward the square. Small yard with barrels.
- Market: two stalls with red/white striped awnings NW of the square (0.40-0.45, 0.43), two to three stalls with red/blue awnings NE of the square (0.58-0.64, 0.45). Crates, barrels, sacks.
- Old Oak: EAST lobe (0.82, 0.38). Enormous oak (trunk ~10 m wide, canopy ~45 m) with glowing violet rune carvings and amethyst crystals in the roots; arched wooden door in the trunk facing south-west (Bob's lab entrance). Grass yard around it.
Ward crystals (violet, on stone plinths ~3 m tall):
- Two flanking the Main Gate on the towers.
- Inner ring of six around the square: (0.33, 0.42), (0.35, 0.60), (0.38, 0.68), (0.62, 0.66), (0.69, 0.40), (0.34, 0.27-west wall).
- Two more on the north wall either side of the Association (0.18, 0.38) and (0.70, 0.30).
Paths (cobbled, curving, 4-6 m wide, lamp posts every ~15 m):
- Main Gate -> square (straight short run, widening into the plaza).
- Square -> Association steps (north).
- Square -> east gate: curves east then south-east past the NE market to the East Gate; a branch to the Oak door.
- Square -> Flagon (west, short).
- Flagon/square -> garden terrace steps (north-west).
Ground: grass with flower patches between paths and buildings; no big empty paving.
Spawn: just inside the Main Gate looking north: fountain, then the cathedral on the axis, the Oak on the right. That is the painting's composition.

## LANDFILL (the Filth junkyard) - target ~300 m across the pit
Overall: ONE huge ROUND sunken pit (not a trench), pit floor ~25-35 m below the rim, ringed by steep eroded dirt-and-rock cliffs. Earth palette (browns), toxic yellow-green at the center, scattered violet Breach crystals.
Entry: Eldoria's south gate wall sits on the NORTH rim (0.50, 0.15), stone wall with gate towers and violet crystals. Player arrives here.
Main path (packed dirt, ~5 m wide): from the gate it winds DOWN an S-curve (0.50,0.20) -> (0.53,0.30) -> (0.48,0.40) -> (0.50,0.50), descending between two big trash-heap ridges, to the center.
Pit interior structure:
- North-west lobe (0.20-0.42, 0.30-0.55): terraced trash slopes and a heap mound, a shack.
- North-east lobe (0.58-0.85, 0.25-0.50): large junk mound, shack with roof, carts.
- A raised dividing ridge between the entry path and each lobe (the path runs in a gully).
- Center: THE FILTH - a round glowing yellow-green toxic pool (0.50, 0.65), ~25-30 m wide, surrounded by a ring of green-stained mud ~15 m wide. This is the boss arena.
- South and east bowl floor: dense junk field - wooden shacks, broken carts, crates, scrap piles, barrels, a ramshackle hut on stilts (0.80, 0.55) - with small trails winding between.
Breach route: a branch path leaves the main path near (0.45, 0.42), runs WEST and climbs back up the pit wall to the NORTH-WEST rim, ending at the Breach crater OUTSIDE the pit (0.18, 0.20): a jagged crater with violet light pouring up. In this level it's the exit and vista (it should be visible from the gate), and the transition to the Breach level.
Tutorial flow (stays linear): gate -> descend the S-path -> fights in the gully and lobes -> the Filth at the central pool -> after the boss, the west branch opens -> climb to the Breach exit.
Boundary: the pit cliffs ARE the boundary (natural, unclimbable), plus the town wall on the north rim. No invisible box walls or white blocks.
Materials/props: muddy dirt, gravel, rock cliffs (real rock meshes), toxic water shader with bubbles for the pool, wood planks, rusted metal, cloth tarps, crates, carts, barrels, garbage bags; violet emissive crystal props; light dust/fog in the bowl.
Spawn: at the gate looking south: the whole bowl spread out below, with the green pool glowing at center and the Breach glow to the right-rear (NW).
