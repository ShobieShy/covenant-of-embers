# batch_09_polish (0.3.1). Drop folder: incoming_art/batch_09_polish/

Everything is under `assets/original/ember_art/`. Suggested repo destination: the same path.

## 1. Warrens stair: `warrens/stairs_warrens.glb`
- Fits the 08a 4 m grid. The footprint is **4 wide × 8 long, i.e. two 4 m modules**, and it drops **4.0 m** (one room height) over 16 steps (0.25 m rise, 0.5 m run, about 27°, so it can be walked).
- **Pivot:** centre of the footprint, at upper floor level.
  - The top step is on the **-Z edge** (z = -4), the same convention as 08a stair_down.
  - It descends toward +Z. The bottom floor is at y = -4 on the +Z edge (z = +4), where a floor_4m at y = -4 meets it.
- **Nodes** (under the root `stairs_warrens`):

| node | content | tris |
|---|---|---|
| stairs_warrens_LOD0 | treads, risers, shaft walls, timber posts, stone bases, top arch | 648 |
| Glow (child of LOD0) | violet emissive rune lintel plus strips on the top and bottom treads (for the "glow pulse") | 72 |
| stairs_warrens_LOD1 | solid step blocks, walls, arch | 264 |
| stairs_warrens_LOD2 | one ramp slab, walls, arch block | 48 |
| stairs_warrens_col-colonly | collision only: a smooth 3.2 m wide ramp plus two side walls. Godot's `-colonly` suffix turns it into a StaticBody3D/ConcavePolygonShape on import | 6 |
| PromptPoint (empty) | (0, 1.2, -3.5), where to show "Descend [E]" | n/a |
| BottomExit (empty) | (0, -4, +4), where the lower floor joins | n/a |

- **Wiring the LODs:** either use VisibilityRange (LOD0 0–25 m, LOD1 25–60 m, LOD2 60 m+), or keep only LOD0 and let Godot's importer auto-LOD it. Hide or delete whichever LOD nodes are not used.
- **Shaft:** the shaft walls stop at upper floor level. Leave a 4×8 opening in the floor tiles (skip two floor_4m tiles).
- **Material:** it uses the same atlas swatches as 08a. The embedded atlas is identical to 08a's warrens_atlas, so you can remap it to that material.

## 2. Loot beam: `fx/loot_beam.png` (128×1024 RGBA) and `fx/loot_beam_ring.png` (256² RGBA)
White/grey with alpha. The beam is bright at the bottom and fades out at the top. Tint it with `Rarity.color(tier)`.

```gdscript
var m := StandardMaterial3D.new()
m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y   # beam stays upright, faces camera
m.cull_mode = BaseMaterial3D.CULL_DISABLED
m.albedo_texture = preload("res://assets/original/ember_art/fx/loot_beam.png")
m.albedo_color = Rarity.color(item.tier) * 1.5         # >1 = brighter under glow
m.no_depth_test = false
var q := QuadMesh.new(); q.size = Vector2(0.6, 4.0); q.center_offset = Vector3(0, 2.0, 0)
```

- Ring: put a flat QuadMesh (orientation FACE_Y, 1.2 m) on the ground with the same additive material and `loot_beam_ring.png`.
- Pulse it by animating the alpha, e.g. `albedo_color.a = 0.7 + 0.3*sin(t*3)`.
- Suggested beam heights by tier: BASIC none (or 1.5 m), UNCOMMON 2.5, RARE 3.5, MYTHIC 4.5, PRIMORDIAL and UNIQUE 6.

## 3. Loading backdrops: `loading/`
- There are four regions: `loading_town_square`, `loading_old_oak`, `loading_warrens`, `loading_midden`.
- Each comes as a **480×270** native pixel-art file (`*_480.png`, 48-colour palette, no dithering) plus a **1920×1080** nearest-neighbour ×4 upscale.
- They are 16:9, so KEEP_ASPECT_COVERED with the NEAREST filter crops cleanly. Use either size; the _480 one is smaller and looks identical with NEAREST.
- **Hookup idea** for loading_screen.gd: in `painting_for(level)`, try `EmberArt.texture("loading_"+region)` first and fall back to `map_`+region. Warrens levels map to `warrens`.
- **Gaps:** there are no breach or mage_association backdrops in this batch; they keep the map_ art.

## 4. Sounds: `sfx/` (.ogg Vorbis q5, mono 44.1 kHz, every file peak-normalised to -1 dBFS)

| file | use | source |
|---|---|---|
| cast_arcane / cast_fire / cast_water / cast_earth / cast_air / cast_light / cast_dark | one cast per `Element` (all 7 in element_table.gd) | original synth (earth layers impactMining_003) |
| chest_open | chest open | Kenney mix + original creak |
| shrine_use | shrine activate | Kenney bell + original chord |
| stairs | descend/ascend stairs | Kenney footsteps ×3 |
| level_up | level up | original arpeggio |
| pickup_basic / _uncommon / _rare / _mythic / _primordial / _unique | one per `Rarity.Tier` (6). Each tier is longer and has more notes; mythic+ adds shimmer and primordial+ a sub-octave | original synth |
| ui_hover / ui_click | menu hover / click | Kenney (normalised copy) |
| ui_open / ui_close / vote_tick | extras for the §5 plan items (panel open/close, vote tick) | Kenney (normalised copy) |

Suggested buses: casts, world and pickup sounds on SFX; ui_* and vote_tick on UI.

### Reused Kenney sounds: repo paths (all were unused before this batch)
To use the originals in place instead of the normalised copies, point the SOUNDS dict at these paths:
- ui_hover ← `res://assets/kenney/interface-sounds/Audio/select_001.ogg`
- ui_click ← `res://assets/kenney/ui-pack/Sounds/click-b.ogg`
- ui_open ← `res://assets/kenney/interface-sounds/Audio/open_001.ogg`
- ui_close ← `res://assets/kenney/interface-sounds/Audio/close_001.ogg`
- vote_tick ← `res://assets/kenney/interface-sounds/Audio/tick_001.ogg`
- stairs uses `res://assets/kenney/impact-sounds/Audio/footstep_concrete_002.ogg`, `…_003.ogg` and `…_004.ogg`
- chest_open uses `res://assets/kenney/impact-sounds/Audio/impactMetal_light_001.ogg` and `…/impactWood_medium_000.ogg`
- shrine_use uses `res://assets/kenney/impact-sounds/Audio/impactBell_heavy_001.ogg`
- cast_earth uses `res://assets/kenney/impact-sounds/Audio/impactMining_003.ogg`

## Not included
- No music.
- No breach or association loading backdrop.
- No vote-chip-bar or typewriter-arrow UI art.
