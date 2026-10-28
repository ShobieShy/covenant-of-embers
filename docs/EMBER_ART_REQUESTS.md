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

## Labyrinth Act I: Goblin Warrens (0.3.0, steps L1-L3)

Rooms are built from greybox boxes until these land (the kit is data/labyrinth/warrens.toml;
each room fits a 24 m slot with 4 m doorways centred on each side). Original, CC0, or CC-BY
credited in game; textures can be CC0 ambientCG/Poly Haven sets credited in CREDITS.md.

| Slot | Path | Spec |
|---|---|---|
| Warrens tile kit | assets/original/ember_art/warrens/{wall_4m,wall_door_4m,pillar,floor_4m,ceiling_4m,stair_down}.glb | packed earth + timber shoring, 4 m grid, under 1.5k tris each, one shared 2k atlas |
| Props | assets/original/ember_art/warrens/{torch_sconce,barricade,bone_pile,crate_stack,spike_trap,goblin_banner,mushroom_cluster}.glb | under 1k tris each; torch has an `Emit` node for the light |
| Rest room set | assets/original/ember_art/warrens/{bedroll,cook_fire,craft_bench}.glb | the fungus cellar rest room (save, heal, craft station) |
| Labyrinth gate | assets/original/ember_art/labyrinth_gate.glb | ~8 m portal arch for the Breach crater (floor 1 entrance), violet emissive |
| Goblin King | assets/original/ember_art/goblin_king.glb | ~2.4 m, rigged (idle, walk, slam, throw, roar, death); crown as a separate `Crown` node (boss drop) |
| Goblins x3 | assets/original/ember_art/goblin_{grunt,archer,shaman}.glb | ~1.3 m, rigged with the Quaternius-style anim names the enemy code already uses |
| Boss arena | assets/original/ember_art/warrens/throne_hall.glb | ~32x32 m handmade floor 5 hall with a raised throne, 3 LODs |
| Warrens map painting | assets/original/ember_art/map_warrens.png | 512x300, for the Labyrinth tab of the world map |

## 0.3.1 (polish)

Requested for docs/POLISH_0.3.1_PLAN.md. CC0 (original or Kenney), credited in CREDITS.md. No music.

| Slot | Path | Status |
|---|---|---|
| Warrens stair | assets/original/ember_art/warrens/stairs_warrens.glb | arrived (batch_09_polish), P2 |
| Loot beam + ring | assets/original/ember_art/fx/loot_beam{,_ring}.png | arrived, P4 |
| Act I loading backdrops | assets/original/ember_art/loading/loading_{town_square,old_oak,warrens,midden}.png | arrived, P6 |
| Breach + Mage Association loading backdrops | assets/original/ember_art/loading/loading_{breach,mage_association}.png | arrived (batch_09b_polish), P6: loader tries loading_<level>, then loading_<region>, then map_<region> |
| Vote banner chip-bar style | ui/vote/chip_bar.png (9-slice, margin 4) + 8x8 chips (empty/waiting/yes/no/local) | arrived (batch_09b_polish), P2 |
| Dialogue continue arrow | ui/typewriter/continue_arrow (6 frames, 8 fps loop) | arrived (batch_09b_polish), P3 |
| Sounds: 7 casts, 6 rarity pickups, chest, shrine, stairs, level-up, ui hover/click/open/close, vote_tick | assets/original/ember_art/sfx/*.ogg (Kenney reuses point at the repo copies) | arrived, P5/P7 |
