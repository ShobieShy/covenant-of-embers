# Ember Art requests (step 163)

Original art for Covenant of Embers. Drop each file at the path given and it replaces the
placeholder with no code change (`scripts/world/ember_art.gd`). Models are `.glb` with Y up
and 1 unit = 1 m, origin at ground centre. Textures are `.png` in sRGB. Placeholders stay
until a file lands; the slot list is `EmberArt.SLOTS`.

| Slot | Path | Spec |
|---|---|---|
| Junk mountain (Landfill / Midden) | assets/original/ember_art/junk_mountain.glb | ~60 m tall heap at (0,0,300); 3 LODs, LOD0 under 20k tris |
| Association spire | assets/original/ember_art/association_spire.glb | ~45 m tower behind the Mage Association; 3 LODs |
| Old Oak LOD set | assets/original/ember_art/oak_lod.glb | the great oak, LOD0/1/2 + impostor; LOD2 under 2k tris |
| Breach crater rim | assets/original/ember_art/breach_crater_rim.glb | ring of shattered rock ~70 m across at (0,0,125) |
| Waystone variants x4 | assets/original/ember_art/waystone_{town,landfill,oak,breach}.glb | ~2.5 m tall, under 2k tris; glow emissive in town gold / landfill green / oak green / breach violet |
| Filth decals | assets/original/ember_art/filth_decal.png | 512x512 with alpha, projected 6x6 m |
| Chest tiers x3 | assets/original/ember_art/chest_{normal,hidden,vault}.glb | 1.2x0.7 m footprint; a separate node named `Lid` for the open anim |
| Skyline billboards | assets/original/ember_art/skyline.png | 2048x512 tileable silhouette strip with alpha (12 quads ring each terrain map) |
| World map paintings | assets/original/ember_art/map_<region>.png | 512x300 per WorldMap.REGIONS id (eldoria, landfill, ...) |

Earlier gaps still open: the element tree icons and the trash / junk item icons noted in the
step 150-159 build log.
