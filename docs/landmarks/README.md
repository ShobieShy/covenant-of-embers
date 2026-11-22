# Old Oak — Covenant of Embers hero landmark

Trial 0.11.4 deliverable for Luna, **v4** (revised in place after a 2.5/5 review of v3). Godot 4-ready giant oak for the Town east lobe / Bob's Lab entrance.

v3 is archived at `_v3/`, v2 at `_v2/`, and v1 at `_v1/`. None of the archives were overwritten.

## Changelog (v4)

Luna scored v3 2.5/5 and corrected the brief: the painting's oak is **columnar**, and the earlier "wider than tall" note was wrong. v4 rebuilds the tree against `/workspace/coe-map/level_refs/town.jpg` (east-lobe oak).

What stayed: the <~40k LOD0 budget, LOD1 at ~30%, `old_oak-colonly`, the `Door` empty, the yaw-135 documentation (door still faces local −Z), bark / door-wood PBR (ambientCG CC0), and the licensing.

What changed:

- **Proportions.** The trunk is the hero: it runs **21.0 m before the crown** (56% of the 37.51 m crown-tip height; 52.4% of the 40.10 m axis-aligned bound, which includes a 2.59 m root dip). Crown width is **44.01 m** (1.17× the crown-tip height, inside the 1.1–1.2× band). Authored column width at the root flare is about **15.3 m**, tapering only slightly up the bole.
- **Trunk.** A bundle of 10 thick rope-like strands (plus a slender core, flare roots, and a door-arch pair) spiral up and are voxel-merged, so the bole is fluted rather than a smooth single cylinder. No carved face-like knots. The first v4 bake of a cavity albedo went wrong (green candy-stripes) and was discarded; the shipped mesh uses the tiling bark albedo + normal + roughness, and the grooves come from the remeshed strand geometry.
- **Door.** An arched door is set into the trunk at a **6.20 m threshold** (29.5% of trunk height, inside the requested 1/4–1/3). It is framed by parted strands and a shallow niche (no dark triangle cavity above the arch). A root ramp rises from the ground to the landing and is included in the collision. The `Door` empty sits on the threshold. A small lantern was authored to the door-right; it can be occluded by a strand. A cheap wooden platform remains on the mid-upper +X side.
- **Crown.** The 5–7 smooth metaball lobes are gone. The canopy is a dense, finely broken cloud of **hundreds of small alpha-card tufts** (crossed cards, dark olive with warmer tops baked into `foliage_card_albedo.png`). Irregular cumulus shape with edge breakup and sky holes. Some limbs are visible inside; tips were pulled into the envelope. **Godot must render `FoliageCards` with alpha scissor (MASK / alpha cutoff ~0.35) and double-sided (cull disabled).**
- **Violet.** Small six-point star flowers are scattered over the trunk strands, densest in the middle third, with more in the lower crown. Root crystals stay small. Long wisteria was dropped; only short moss drapes remain, secondary.
- Unused v1 rune/root mask textures stay deleted from live `textures/` (they exist only in the archives).

## Changelog (v3)

v3 kept the v2 broad crown and tried to merge foliage into 5–7 lobed masses with a baked grade, a taller bole at ~44% of height, vines, and a stronger door. Luna's 2.5/5 and the corrected columnar spec superseded that silhouette. The v3 delivery is in `_v3/`.

## Changelog (v2)

v2 shortened the v1 lollipop, documented yaw 135, and replaced jagged lightning runes with small glyphs. That yaw work is what v4 still ships. The v2 delivery is in `_v2/`.

## Method

**Hand-built procedurally in Blender 4.5.3** (headless Python), not image-to-3D.

Image-to-3D was attempted for v1, as approved, and was not repeated. This box has no CUDA GPU, and an unattended TRELLIS / ZeroGPU run was not feasible. The v4 mesh was rebuilt in `source/build_oak.py` and judged against ShobieShy's `/workspace/coe-map/level_refs/town.jpg` and `LEVEL_SPEC_TOWN_LANDFILL.md` (Old Oak, east lobe, door facing south-west).

Concept references (ShobieShy's own Magewar / Covenant of Embers art — do not redistribute as third-party stock):

- `/workspace/coe-map/level_refs/town.jpg` — Eldoria Town, Old Oak on the east lobe
- `/workspace/coe-map/level_refs/bobs_lab.jpg` — The Old Oak / Bob's Laboratory, front elevation

## Scale and orientation

- Units: 1 unit = 1 metre. Origin at the trunk base on the ground (centre of the bole).
- Up axis: glTF / Godot **Y-up** (exported from Blender Z-up with `export_yup=True`).
- **Height to crown tip:** 37.51 m (inside 35–40 m). Roots from the remesh dip 2.59 m below the origin, so the axis-aligned bound is **40.10 m**, 10 cm over the 40 m cap. The visible tree is inside the requested band.
- **Crown width:** 44.01 m on X, 40.42 m on Y. **Width / crown-tip height = 1.173** (inside ~1.1–1.2). Against the 40.10 m AABB the ratio is 1.097.
- **Trunk split:** four-to-six primaries leave the bole at **21.0 m** — **56%** of the crown-tip height (52.4% of the AABB). Target was ~55% before the crown.
- **Root flare (column):** authored diameter at the lower bole is about **15.3 m** (inside 14–16 m), tapering only slightly. A mesh percentile that includes spreading surface roots reads wider (~22–26 m span); those runners are not the column flare.
- **Door:** arched wooden door, sized for a 1.8 m human, set into the bole at a **6.20 m** threshold, with a stronger frame, barred window, and a warm interior glow. A root ramp provides ground access.
- The door is authored facing Blender **+Y**, which is glTF / Godot **−Z** (object forward). The shipped GLB is **not** pre-rotated.

### Godot yaw (door faces south-west)

Project convention, from `coe-map/LEGEND.md` and `src/town_square.toml`:

- Engine **−Z is north**, +Z south, +X east, −X west.
- Yaw 0 faces north (Godot −Z / object forward).
- Positive yaw is counterclockwise when viewed from above (Godot Y rotation).

Because the asset's door faces local −Z, at yaw 0 the door faces north. To face **south-west**, the game agent should set:

```
rotation_degrees.y = 135
```

Do not bake 135° into the asset. After that yaw, world south + east is the asset's local −X.

The `Door` empty sits on the threshold at Blender `(0.0, 6.606, 6.2)`, which is Godot `(0.0, 6.200, -6.606)`. Threshold height is **6.20 m**.

## Node graph (`old_oak.glb`)

```
old_oak                  (root empty)
├── LOD0
│   ├── Trunk            bark PBR, 10-strand remeshed rope bole + flare roots + ramp
│   ├── Branches         bark PBR, primaries reaching into the crown
│   ├── FoliageCards     alpha-clip leafy tufts, dark olive / warm tops (double-sided)
│   ├── Flowers          small star-shaped violet clusters
│   ├── Moss             short hanging drapes (secondary)
│   ├── Platform         small wooden ledge on the mid-upper +X trunk
│   ├── DoorWood         arched door, frame, barred window, lantern, warm glow
│   ├── RootGlow         emissive root / lower-bole veins (tune in Godot)
│   └── Amethyst         small faceted crystal clusters in the roots
├── LOD1                 same parts, ~30% of LOD0 tris, names suffixed `_LOD1`
│                        (FoliageCards_LOD1 is a 1-in-3 tuft subset, not a decimate)
├── old_oak-colonly      simplified collision (column + root skirt + ramp + door alcove)
└── Door                 empty / marker at the threshold, facing out
```

A standalone `old_oak_lod1.glb` is also included (LOD1 meshes under root `old_oak_lod1`, plus collision + `Door` marker, clean names with no `_LOD1` suffix and no `.001`) if it is easier to hook up as a separate file.

Set Godot visibility ranges (or a LOD node) so only one of LOD0 / LOD1 draws. Hide `old_oak-colonly` as a visual; the `-colonly` suffix is the Godot 4 import hint for collision-only.

### FoliageCards in Godot

The crown is alpha-tested cards, not solid blobs. On import:

- Alpha mode **MASK** (alpha scissor), cutoff about **0.35**
- **Double-sided** (disable backface cull)
- Use the packed `foliage_card_albedo.png` (RGBA). The warm-top / dark-olive grade is in the texture, not vertex colour.

## Triangle counts (measured on clean glTF reimport in Blender 4.5.3)

| Mesh            | LOD0 | LOD1 |
|-----------------|-----:|-----:|
| Trunk           | 16,031 | 4,807 |
| Branches        |  1,338 |   400 |
| FoliageCards    |  2,148 |   540 |
| Flowers         |  9,120 |  2,720 |
| Moss            |  1,134 |   340 |
| DoorWood        |    392 |   112 |
| Platform        |     94 |    27 |
| RootGlow        |    581 |   173 |
| Amethyst        |    160 |    40 |
| **Visual total** | **30,998** | **9,350** (30.2% of LOD0) |
| old_oak-colonly | 194 | (same collider in both files) |

LOD0 is under the “~40k” cap. LOD1 is inside the requested ~30% band. Flowers are a large share of the budget (many small star meshes).

## Textures (2K PNG, also packed into the GLBs)

| File | Use | Source | Licence |
|------|-----|--------|---------|
| `textures/bark_albedo.png` | Trunk / branch colour | [ambientCG Bark014](https://ambientcg.com/a/Bark014) 2K Color, with AO multiply | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `textures/bark_normal.png` | OpenGL tangent normal | ambientCG Bark014 NormalGL | CC0 1.0 |
| `textures/bark_roughness.png` | Roughness | ambientCG Bark014 Roughness, slightly raised | CC0 1.0 |
| `textures/wood_albedo.png` | Door / frame / platform | [ambientCG Wood051](https://ambientcg.com/a/Wood051) 2K Color | CC0 1.0 |
| `textures/wood_normal.png` | Door normal (OpenGL) | ambientCG Wood051 NormalGL | CC0 1.0 |
| `textures/wood_roughness.png` | Door roughness | ambientCG Wood051 Roughness | CC0 1.0 |
| `textures/foliage_card_albedo.png` | Canopy tufts, RGBA, dark olive with warmer tops | Original (Ember Art) | CC0 / original |
| `textures/foliage_albedo.png` | Source tiling canopy albedo (kept as a spare) | Original | CC0 / original |
| `textures/foliage_normal.png` | Spare canopy normal | Original | CC0 / original |
| `textures/foliage_roughness.png` | Spare canopy roughness | Original | CC0 / original |
| `textures/moss_albedo.png` | Hanging moss | Original | CC0 / original |
| `textures/moss_roughness.png` | Hanging moss roughness | Original | CC0 / original |

v1 `rune_emission.png`, `rune_mask.png`, `root_glow_emission.png`, and `root_glow_mask.png` remain deleted from live `textures/` (archives only). A first-pass `bark_baked_albedo.png` was discarded after it produced a green stripe error; it is not shipped.

In Godot, expose emission energy on `RootGlow` (1.8 starting strength), `Flowers` (0.55), and `Amethyst` (0.80). `DoorWood` includes a `DoorWarmGlow` pane behind the barred window and a low lantern.

No paid, ripped, or third-party-game assets. No music.

## Turntable

All frames below were rendered in EEVEE from a **clean reimport of the shipped `old_oak.glb`** (LOD1 and collision hidden). 1600×2000 PNG, 1.8 m modest scale figure (rust tunic, render-only, not in the GLB) standing on the door landing, and an 8 m merlon wall section as a town-wall height reference:

- `turntable/old_oak_front.png` — door side (Godot −Z)
- `turntable/old_oak_right.png`
- `turntable/old_oak_back.png`
- `turntable/old_oak_left.png`

Extra QA close-up:

- `turntable/old_oak_door_detail.png` — elevated door, 1.8 m figure on the threshold, flowers, ramp

Spawn-camera shot (1920×1080):

- `turntable/old_oak_spawn_ne.png` — just inside the Main Gate, looking north-east, oak on the right

Comparison sheet (oaks drawn at the **same pixel height**):

- `turntable/old_oak_vs_painting.png` — v4 front (reimported GLB) beside the east-lobe oak from `town.jpg`

**Spawn layout (approximation).** The town wall is ~320 m in diameter. Painting-normalized coordinates were scaled with 0.28 units ≈ 160 m wall radius (1.0 ≈ 571 m). The oak is at (0.82, 0.38) and the Main Gate at (0.50, 0.80), so the camera is about **171 m west and 228 m south** of the oak, eye height 2.4 m, 42 mm lens. The oak is rotated 135° **in this shot only** (the shipped GLB is unrotated). The 8 m merlon wall in the left foreground is a Main Gate stand-in, not a finished gate kit. Distances are approximate from the painting / spec layout; the shot is a composition check, not a survey.

## Verification

- `old_oak.glb` (37.40 MB) and `old_oak_lod1.glb` (36.05 MB) reimport cleanly in Blender 4.5.3 (`bpy.ops.import_scene.gltf`). All named nodes above are present, including `FoliageCards`, `Flowers`, `Door`, and `old_oak-colonly`. Node names have no `.001` suffixes in the shipped files.
- Triangle counts, height, width, ratio, fork, door position, and threshold in this README are from that reimport / glTF accessor measurements, not estimates.
- The four turntable frames, the door detail, and the spawn shot were all rendered from the same reimported GLB. The comparison uses that same front render, with the painting crop scaled so both oaks have the same pixel height.

## Known limits and notes

- Image-to-3D was not used in the shipped mesh (no local GPU; unattended ZeroGPU / Gradio use was not available). The silhouette follows the paintings in a low-poly Kenney / Quaternius language, not a photogrammetry sculpt.
- After voxel remesh and a decimate down to ~16k, the rope grooves are softer than the painting's tightly wound cables. The trunk reads as a twisted, fluted column, but not as a fully separated 10-strand braid at turntable distance.
- A first cavity-baked trunk albedo failed (bright green with brown stripes) and was thrown away. Groove shading now relies on geometry + the tiling bark normal.
- The axis-aligned height including a 2.59 m remesh root dip is 40.10 m, 10 cm over the 40 m cap. Height to the crown tip is 37.51 m.
- One long, stick-like root runner still pokes out on the left/right views. Other roots are shorter and merged into the flare.
- The door close-up is a clean arch (no triangular cave), but the boolean niche has a few jagged texels at the arch edge. The authored lantern can be hidden by a neighbouring strand; the warm window glow is the clearer door light. The ramp is a single merged tongue rather than distinct root steps.
- Flower stars are stylized, fairly large, and can read as flat decals at close range. Emission is kept low.
- Foliage cards are darker and more brown-olive than the painting's sunlit tops; warm tops are present in the texture but subtle. Godot needs alpha scissor and double-sided rendering or the crown will look clipped or hollow.
- Garden fence, mushrooms, flower patch, the stone “Path to East Gate” arch, and the large wall crystal from the painting are **not** in this asset; those are level dressing.
- The spawn shot uses an untextured 8 m merlon wall as a gate stand-in; it is fairly large in the left of the frame. Layout distances are approximate, as noted above.
- The glTF exporter may print “mesh is not valid” on some remeshed / booleaned / LOD1 parts. Reimport and measured tri counts are fine; tangents were computed after triangulation.
- Emission strengths are conservative starting points so Godot bloom can be tuned per shot. The crystals are opaque emissive facets, not transmissive glass.
- LOD1 is a ~30% decimate of each LOD0 mesh except `FoliageCards`, which keeps every third tuft. Use LOD1 at distance.

## Licence summary

Original Ember Art geometry, foliage cards, flowers, moss, and platform: CC0, made for Covenant of Embers. Bark and door wood derived from ambientCG CC0 materials (credit appreciated but not required). Concept paintings remain ShobieShy's IP and were used only as modelling reference.
