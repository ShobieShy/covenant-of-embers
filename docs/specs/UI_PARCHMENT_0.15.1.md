# Auto-Scribe parchment and brass (0.15.1)

Written from the painted maps, before the theme change. The pictures are the spec. Nothing here adds a name, a song, a save version, or a Core release.

## What the art actually is

The charts in `docs/maps/` are the style target. `levels/town.jpg`, `eldoria-hub-map.jpg`, `elyria-world-map.jpg`, and `labyrinth-cross-section.jpg` were opened and sampled.

They share one surface:

- Paper, not a grey panel. The field is a warm tan, about `rgb(196, 168, 122)` in the open page and `rgb(122, 90, 50)` in the stained margin. Fibers and speckles are visible. The edge is darker than the middle.
- A brass cartouche, not a flat stroke. Two dark-brown rules with a gold band between them. Corners and the middle of the long sides carry a small acanthus knot. The metal reads as antique brass, highlight about `rgb(212, 175, 110)`, shade about `rgb(92, 62, 28)`.
- Ink, not white type. Titles are a high-contrast serif in near-black brown. The subtitle under "ELDORIA" is a smaller italic. At the size of a 1080p menu, the strokes are thick enough to read. The current Kenney pixel face at HUD sizes is not.
- Each playable place has its own painted plate: town, Association, Old Oak and Bob's laboratory, Landfill, Breach, and one plate per labyrinth act. The world chart is the fallback. The plates already include their own titles. The Map tab has to show the plate for where the player is, including the act when the party is under the Breach.

The combat HUD is not a page. It sits on the world. Bars and slots take the same brass frame. Numbers and names stay light, with a dark outline, so they survive a dark room. Element colour stays on the fill, the gem, and the damage number.

## What the screens do

- Auto-Scribe, inventory, vendor, skills, settings, dialogue, and the main menu use the parchment panel, brass buttons, and Libre Baskerville. Body size is at least 20 px at 1080p. Button labels are dark ink. The title is the same face, larger.
- The combat HUD frames health, shield, mana, and breath in brass. Carry slots show the wieldable's icon inside the brass slot, with the element colour kept. Skill buttons show a medallion for that element. Damage numbers use the same serif and the element's colour.
- The Map tab draws the painted plate. Town, the Association, the Old Oak, Bob's laboratory, the Landfill, and the Breach each have one. A labyrinth floor uses `ActLoot.act_of` and that act's plate. An unknown place uses the Elyria chart. The legend text, travel list, and waystone card stay. The minimap and its quest pin are unchanged in behaviour. The HUD stays hidden while the Auto-Scribe is open.
- The inventory detail row no longer puts Trash, the quantity, Unmark junk, and Favorite on one line. Trash and the quantity share a row. Unmark junk and Favorite each take the full width of the detail column, so the words are not clipped.
- The vendor's Buy / Sell / Sell all junk / Sell all / Re-roll / Close row wraps on a three-column grid so those labels fit the panel.

## Assets

Frames, medallions and the map plates are drawn for this project (CC0) or copied from the painted charts. The face is Libre Baskerville (OFL-1.1). Each is registered in `ASSETS.toml`. No Kenney pixel panel is the menu surface anymore. Kenney cursors and item icons stay. Music stays silent. `SaveGame.VERSION` stays 1. The game version string is not moved to 1.0.
