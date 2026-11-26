# Town golden slice, 0.12.0

Spec for the first build of the Eldoria remake. The painting is `docs/maps/levels/town.jpg`. The full town notes are in [LEVEL_SPEC_TOWN_LANDFILL.md](LEVEL_SPEC_TOWN_LANDFILL.md). This file is the contract for the 60 m slice. The live Town stays the 0.11.4 hub until this slice is scored 4/5 by Ember QA and Luna and then expanded.

## World lock

The painted town is a circle about 320 m across. Painting x 0 is west, 1 is east. Painting y 0 is north, 1 is south. World +X is east, -Z is north. The circle center is painting (0.52, 0.52), world origin.

```
world_x = (paint_x - 0.52) * 320
world_z = (paint_y - 0.52) * 320
```

| Landmark | Paint | World (x, z) |
|---|---|---|
| Main Gate | (0.50, 0.80) | (-6.4, 89.6) |
| Town Square / fountain | (0.50, 0.55) | (-6.4, 9.6) |
| Mage Association doors | (0.50, 0.22) | (-6.4, -96.0) |
| Old Oak door | (0.82, 0.38) | (96.0, -44.8) |
| East Gate | (0.71, 0.66) | (60.8, 44.8) |
| The Flagon | (0.24, 0.53) | (-89.6, 3.2) |

The gate-to-fountain run is about 80 m at this scale. The fountain-to-cathedral run is about 106 m. A 60 m square cannot hold the gate, the cathedral, and the oak at true size. The detailed slice is the square. The scoring camera stands at the gate and looks north, so the cathedral and the oak are placed at their true coordinates and read in that shot.

## The 60 m square

Center the slice on the fountain, (-6.4, 9.6). The square is 60 m across, cobblestone, circular plaza about 30 m in radius. Inside it:

- A three-basin stone fountain on the center. The Kenney square fountain is a stand-in until an Ember Art fountain matches the painting's tiered basins. That hero is required before a 4/5 score.
- Cobble from the south edge of the slice toward the Main Gate. The path widens into the plaza. It is not a grid road.
- Six violet crystals on plinths around the plaza rim, at the painting points that fall inside the slice. The two Main Gate crystals are outside this square, on the gatehouse.
- Market stalls: two red/white awnings on the north-west rim, two or three red/blue awnings on the north-east rim. Crates and barrels at their feet.
- Lamp posts on the path, about every 15 m.
- Grass and flowers between the path and the stalls. No empty tan ground.

## What the gate camera must show

Eye at the Main Gate, (-6.4, eye height, 89.6), looking toward -Z (north). In that frame, in this order:

1. The gate arch and two crystal towers, close, left and right.
2. The cobble road running away, widening into the plaza.
3. The fountain on the axis.
4. The Mage Association facade on the same axis, blue-slate roof, two spires, doors facing the camera.
5. The Old Oak large on the right, door facing south-west, violet stars readable.
6. The East Gate as a smaller arch on the right wall, with a dirt path leaving it.
7. The Flagon as a timber house on the left, not the subject of the shot.

Warm late-day light. A light warm haze, not a purple wash. The dome reads gold on the west and violet on the east.

## Heroes still required from Ember Art

These Kenney pieces are layout only. They are not the score:

- Curtain wall, Main Gate arch, and the two crystal towers.
- Three-basin fountain.
- Association cathedral, slate roof, spires, stained glass, library wing.
- The Flagon timber house and hanging sign.

The Old Oak v4 already in `assets/landmarks/old_oak/` is the oak. Do not replace it with a new tree.

No new character, place, or item names. The Core stays closed. Music stays silent. No primitive meshes in the shipped slice. Collision shapes are allowed.

## Acceptance

- A unit test checks the six landmark coordinates above within 1 m.
- A top-down capture of the slice, overlaid at 50% on `town.jpg`, keeps the plaza center, the road south, and the oak within 5% of the map width.
- Three player-height shots: the gate view above, the fountain at eye height, and the oak door. A contact sheet of those plus the overlay.
- Ember QA and Luna both score that sheet 4/5 or higher before this replaces the live Town.
