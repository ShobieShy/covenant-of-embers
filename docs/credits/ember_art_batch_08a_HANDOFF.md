# batch_08a_warrens_kit handoff (Labyrinth Act I, Goblin Warrens)
This folder mirrors `assets/original/ember_art/`: `warrens/*.glb`, `labyrinth_gate.glb`, `map_warrens.png`.
Conventions: Y up, 1 unit = 1 m, flat colour. Each GLB is a single mesh with UVs into one shared atlas, `warrens/warrens_atlas.png` (2048², 16 flat 512 px swatches, Nearest filter recommended). A copy of the atlas is embedded in each GLB; to share one texture, re-point the material in Godot to `warrens_atlas.png`. Emissive parts use separate small materials: g_fire, g_violet, g_shroom.

## Tile kit: 4 m modules, 24 m room slot = 6 modules
| id | pivot | bounds (m) | tris |
|---|---|---|---|
| floor_4m | centre of the tile, top surface at y=0 | 4 x 4, -0.2..0 thick | 132 |
| ceiling_4m | same as floor (place at the same position) | 4 x 4, underside beams at 3.7, slab 4.0..4.3 | 36 |
| wall_4m | bottom centre of the wall line; wall runs along X, thickness ±0.3 (+0.25 timber trim per side) | 4 wide x 4 tall | 228 |
| wall_2m | same | 2 wide x 4 tall | 132 |
| wall_door_4m | same | 4 wide x 4 tall, clear opening 3.6 wide x 3.0 tall (posts 0.2 m inside each edge) | 144 |
| pillar | grid vertex (corner), floor level | 1.1 x 1.1 base x 4 | 60 |
| stair_down | tile centre, top step at y=0 on the -Z edge, 10 steps descending 4 m toward +Z | 4 x 4, down to -4.2 | 276 |
Room height is 4 m.

**Doorway alignment, important:** a 24 m side holds 6 four-metre modules, so its centre falls on a grid line, and a 4 m door centred on the side would straddle two modules. So I added `wall_2m`. Each side, from corner to corner: wall_4m, wall_4m, wall_2m, wall_door_4m (centred on the side, pivot at offset 0), wall_2m, wall_4m, wall_4m. That's 4+4+2+4+2+4+4 = 24, and the door spans -2..+2 exactly. Wall pivots for a side running from -12 to +12: -10, -6, -3, 0 (door), +3, +6, +10. Rotate 90° for the east and west sides. Pillars go at the room corners (±12, ±12) and can be added at other vertices.

## Props
| id | notes | tris |
|---|---|---|
| torch_sconce | back plate at local z=0 (the wall face), sticking out toward -Z (glTF/Godot forward). **`Emit`** node at the flame (local 0, 2.5, -0.58) for an OmniLight | 84 |
| barricade | 3.1 m wide | 108 |
| bone_pile | ~1.6 m | 340 |
| crate_stack | ~2.3 m | 144 |
| spike_trap | 2 x 2 plate; spikes are a separate child node `Spikes` (raise it on Y to animate, rest pose 0..0.6) | 120 |
| goblin_banner | 3.2 m pole, skull emblem | 128 |
| mushroom_cluster | some caps glow cyan (g_shroom) | 308 |

## Rest room (fungus cellar)
bedroll (64 tris), cook_fire (312 tris, has an `Emit` node at 0, 0.5, 0), craft_bench (200 tris, 2 x 0.9 m, height 0.9 m).

## labyrinth_gate.glb
~9 m wide x 8.6 m tall (inner opening 5.6 x 7.5), 333 tris, pivot at ground centre, violet emissive portal surface plus rune studs and keystone. The portal surface is a single-sided flat face in the XY plane at z=0; duplicate it or enable double-sided if needed.

## throne_hall.glb
32 x 32 m hall, 6 m walls, door 4 m wide centred on the south and both side walls, no door on the north. Raised 10 x 7 m dais (1.2 m) with steps and a throne at the north end, pillars, banners and braziers. LODs are child nodes `throne_hall_LOD0` (916 tris), `LOD1` (324), `LOD2` (192). All are visible on import, so hide two of them or set visibility ranges. No ceiling, so it's open for top lighting; add ceiling_4m tiles if wanted.

## map_warrens.png
512x300 in the style of the batch_06 maps: a room-and-corridor layout, with the violet gate marker bottom-left and the crowned throne room top-right.
