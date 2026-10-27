# World layout (OW1)

Every outdoor level keeps its own scene and local coordinates. `[level] world_offset = [x, z]`
in data/levels/*.toml (16 m multiples) places it on the shared world map; toml_to_scene.py
emits it as `metadata/world_offset` on the level root.

| zone | world_offset | world footprint [x0, z0, x1, z1] (m) |
|---|---|---|
| breach | [1104.0, -64.0] | [994, -164, 1214, 156] |
| midden | [576.0, -240.0] | [226, -300, 926, 300] |
| old_oak | [-272.0, 0.0] | [-352, -93, -192, 67] |
| town_square | [0.0, 0.0] | [-120, -120, 120, 120] |
| mage_association | [0, -256] | interior, no terrain (entered from the town) |

Rules (checked by `tools/build_world.py --check`):
- offsets on the 16 m grid;
- at least 64 m between any two terrain footprints (the transition strips, OPEN_WORLD_PLAN section 2);
- west to east: Old Oak, Town Square, Midden, Breach, matching the story route.

Pipeline:
1. `godot --headless --path . -s res://tools/export_zone_heights.gd` writes build/world/<id>.f32 + .json.
2. `tools/build_world.py` cuts each zone's 24 m rim, places it at its offset on a 2 m grid snapped
   to 512 m (256-vertex) Terrain3D regions, and fills the gaps with a harmonic (Laplace) blend that
   falls to 0 at the world edge. Output: build/world/world_height.f32, world.json, world_preview.png.

Current result: 1281x1025 vertices, 5x4 regions,
origin [-1024.0, -1024.0]. The fill drops toward 0 only a few tens of metres outside each zone. OW2
(the world scene) shapes the strips into roads and ridges, so the blend is a placeholder.
