# batch_09b_polish: fills the batch_09 gaps

Files go to `assets/original/ember_art/`, the same place as batch_09.

## 1. Loading backdrops: `loading/`
- `loading_breach` and `loading_mage_association` follow the batch_09 format: 1920×1080 (×4 nearest-neighbour upscale) plus a native `_480` file at 480×270 with a 48-colour palette.
- The ids are the **level ids** used in `WorldMap.LEVEL_REGION` (`breach`, `mage_association`), the same as batch_09's town_square, old_oak and midden.
- So `painting_for(level)` should look up `"loading_" + level_id` and fall back to `map_` + region.
- Note: LEVEL_REGION maps these to the regions eldoria and landfill, so keying on the region would collapse them into shared images.
- Breach: a view from above the crater rim, with a violet rift glow, crystal shards and the breach waystone in the foreground.
- Association: the spire at night with a stone-pillar avenue, lanterns, red and green banners and stairs, using the Kenney pieces the association_hall scene uses.

## 2. Vote chip bar: `ui/vote/`
Uses the batch_05 bar_frame palette (outline #2B1E25, brown #785A3C).

| file | size | use |
|---|---|---|
| chip_bar.png | 32×12 | the bar background. NinePatchRect / StyleBoxTexture with **patch margins 4/4/4/4** (L/T/R/B), so the centre stretches. Chips sit inside with 2 px padding: content margins 3/3/3/3 |
| chip_empty.png | 8×8 | an empty slot (no voter) |
| chip_waiting.png | 8×8 | a voter who hasn't voted yet (grey with a dot) |
| chip_yes.png / chip_no.png | 8×8 | voted yes (green check) / voted no (red cross) |
| chip_self.png | 8×8 | the local player, waiting (gold ring). Or show it by modulating the yes/no chip |
| chips_strip.png | 40×8 | the same 5 chips in one strip, in order empty, waiting, yes, no, self; AtlasTexture regions are 8 px wide |

- Layout: an HBoxContainer of TextureRects, with separation 1 px and STRETCH_KEEP, inside a PanelContainer whose StyleBoxTexture is chip_bar.
- Draw at whole-number scales (×2 to ×4) with the Nearest filter.
- A chip is 8 px tall, so the bar's inner height of 8 + 3 + 3 = 14 px suits it (stretch the 12 px bar vertically, or set the bar's minimum height to 14).

## 3. Typewriter continue arrow: `ui/typewriter/`
- `continue_arrow_strip.png` is 48×8, with 6 frames of 8×8: a gold down-arrow that bobs 0, 1, 2, 2, 1, 0 px and brightens on frames 2–3.
- The single frames are `continue_arrow_0..5.png`.
- Godot: use an AnimatedSprite2D or TextureRect with SpriteFrames from the strip (hframes 6) at **8 fps, looping**.
- Alternatively, show it only after the typewriter finishes: `visible = label.visible_ratio >= 1.0`.
- Place it at the bottom right of the dialogue box. Scale ×3 or ×4 with Nearest.

## Gaps
None of the requested items are missing.
- The art hasn't been tested inside Godot.
- No sounds are included because none were asked for.
- The arrow comes in one colour only (gold). Modulate it for other tints.
