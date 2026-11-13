# Covenant of Embers map legend

Illustrated maps of Elyria and of Eldoria's hub, drawn from the canon documents. Place names were overlaid in type so the spelling would stay exact. The images in this folder are the labeled JPGs.

**Sources**

- `docs/COVENANT_OF_EMBERS_BIBLE.md` — the bible
- `docs/COVENANT_OF_EMBERS_STORYLINE.md` — the storyline
- `docs/PLAN_LEVEL_REMAKE.md` — approved remake of the three hub levels
- `data/levels/*.toml` — current exits, waystones, and layout (town square, Association, Landfill, Old Oak, Breach)

The archived open-world file `docs/archive/WORLD_LAYOUT.md` is **not** used. It was superseded on 4 Nov 2026 and laid the hub out west-to-east (Old Oak, square, Landfill, Breach), which disagrees with the bible and with the current level exits.

## How to read the charts

The bible names the outer lands but does **not** give them a compass. On the world map, Valdoria, Sylvandar, Ironforge, the Wastes, Luminar, Willowbrook, Stonehaven, Arcana Spire, the Whispering Woods, the Shattered Peaks, and the Crimson Sea are placed by terrain type only (sea, peaks, woods, river, mines, waste, a floating citadel). Those bearings are illustrative, and the footer on the world map says so.

The Eldoria chart is a bird's-eye arrangement of documented places, not a surveyed plan. The bible and the town file put the Association north of the square, the Landfill south (just past the barrier), the Old Oak east, and the Breach as a crater north of the dump. In the Landfill's own coordinates the town gate sits at the south lip and the Breach gate at the north rock cut, so a single north-up view cannot make the town both north of the dump and at the dump's south lip. This painting keeps the city's three gates and shows the Breach beside the bowl, north of the Filth.

Act V, the Storm Warden, and the Core fights are approved or outlined, not in the v0.9.2 build. They are still labeled, and Act V is marked *planned*.

## 1. The realm of Elyria — `elyria-world-map.jpg`

| Label | What it is | Source |
|---|---|---|
| Elyria | The realm: kingdoms, ancient forests, mountains, a sea | bible, “World” |
| Eldoria | Walled capital under an arcane barrier; the city you actually live in; ward-pillars hold the dome | bible, “World”; storyline |
| Valdoria | Human kingdoms that sat down with the Association to raise the domes. Not a level. The bible does not say Eldoria is Valdoria's capital, so the chart does not either | bible, “The lands”; storyline |
| Sylvandar | Elven enclaves. A caravan out of Sylvandar is an old side story, not a mission you can take | bible, “The lands” |
| Whispering Woods | Trees that murmur secrets and hide ambushes. Pulled underground as Act II, the Blightcoil | bible, “The lands” |
| Arcana Spire | The Association's floating citadel, the old headquarters. You do not go there; the hall in Eldoria is the chapter that summoned you | bible, “The lands”; Association section |
| Ironforge | Dwarven holds. The living holds are off the playable map; the buried mines are Act III, the Slagworks | bible, “The lands” |
| Stonehaven | A mining outpost that supplied iron for enchanted weapons. The barriers reached it. Not a level | bible, “The lands”; storyline |
| Luminar | A scholarly haven / library-city whose libraries the Fracture did not touch. Received a dome early, with capitals like Eldoria. Not a level | bible, “The lands”; storyline |
| Willowbrook | A riverside village of apple orchards. The barriers reached it. Goblin raids are the memory of Act I, the Goblin Warrens. The painting shows the orchards and the river; a modest dome is not distinctly drawn | bible, “The lands”; storyline |
| The Wastes | Nomadic orc tribes, brought into the barrier alliance. Not a level | bible, “The lands”; storyline |
| Shattered Peaks | Avalanche mountains and aerial dungeons. The memory of **Open** Act V, the Inverted Spire | bible, “The lands” |
| Crimson Sea | A monster-infested ocean and its underwater ruins. Act IV, the Sunken Ruins, is that sea pulled under Elyria and left on its side | bible, “The lands”; storyline, Act IV |
| (uninhabited wilds) | About sixty percent of habitable land is still wild: adventurers, bandits, refugees, and the things that came up | bible, “World”; storyline |

Domes are shown over Eldoria, Luminar, and Stonehaven, matching the bible's account of barriers first raised over capitals and library-cities, then over smaller towns such as Willowbrook and Stonehaven.

## 2. Eldoria, the Landfill, and the Breach — `eldoria-hub-map.jpg`

Directions below follow the bible and `data/levels/town_square.toml` (engine: −Z is north). Sizes in parentheses are the approved remake in `PLAN_LEVEL_REMAKE.md`, not the current greybox slabs.

| Label | What it is | Source |
|---|---|---|
| Eldoria | The walled capital, under the barrier | bible; toml display name “Eldoria – Town Square” |
| Arcane barrier | Dome of arcane energy, powered by crystal obelisks; ward-pillars are its face on the square. The Landfill sits just past it | bible, “World,” “Cosmology”; `town_square.toml` header |
| Mage Association | Eldoria chapter hall. Front door opens on the square. Cool, dim, expensive marble, a dais | bible, “The Mage Association”; `mage_association.toml` |
| Summoning circle | On the dais; the rite that brought the Summoned. The remake's landmark, visible from the south door | bible; `PLAN_LEVEL_REMAKE.md`, Association |
| Library | East of the hall (remake: 18×22). The current file also puts the archive on the east wing | bible; `PLAN_LEVEL_REMAKE.md`; `mage_association.toml` |
| Courtyard | West of the hall (remake: 22×24), with a smaller fountain and trees | `PLAN_LEVEL_REMAKE.md`; `mage_association.toml` |
| Association doors | South-facing front doors / arch, opening on the square. The remake's town landmark | bible; `town_square.toml` exit `to_association` at z −17; plan |
| Back door to the Landfill | Staff-only door behind the dais. Joe has been throwing things through it for years. A level gate, not a street running north of the hall | bible; storyline; `mage_association.toml` exit `to_landfill` at z −13.5 |
| Town Square | The hub. Paved (remake: raised 36×36 in a 72×72 close). North to the Association, south to the Landfill, east to the tree | bible, “Eldoria, Town Square”; `town_square.toml`; plan default 7 |
| Fountain | Center of the square | `town_square.toml` (`fountain` at the origin); plan |
| Stalls | Market stalls; barrier-safe herbs. Four stall boxes sit north of the fountain in the current file | bible; `town_square.toml`; plan |
| The Fractured Flagon | Tavern, stone and timber. Ale that tastes like barrier dust. The Grizzled Patron is here. In the current file the building sits on the southwest of the square | bible; storyline; `town_square.toml`; plan |
| Ward-pillars | Four stone posts with a glass cage for the barrier light, at the four corners of the square. The painting adds an extra glowing post by the south gate; canon is four | bible; `town_square.toml`; `PLAN_LEVEL_REMAKE.md` |
| South gate | Landfill gate, two pillars and a lintel. The Bored Guard stands here. `to_landfill` at (0, 0, 17.5), waystone `town_gate` just inside | bible; `town_square.toml`; plan |
| East gate | Real gate on the east road to the Old Oak (the current east wall is a gap; the remake closes it and builds this gate) | bible; `town_square.toml` exit `to_old_oak` at (17, 0, 14); plan |
| Old Oak / Great Oak to Bob | Bob's home tree at the edge of town. The permit, signs, and quests say Old Oak; Bob calls it the Great Oak. Both names stay. Hollow, carved runes, vines | bible; storyline (decision of 13 Nov 2026); `old_oak.toml` |
| The Landfill / The Filth's Bowl | Junkyard tutorial, just past the barrier. South back to town. After the Filth, the north road goes to the Breach. Remake: a valley about 48×150 m with berms and a north rock cut | bible, “The Landfill”; `midden_greybox.toml`; plan default 8 |
| Joe's camp | Joe camps in the dump after his banishment, with a bench and a wind wand | bible; storyline |
| The Breach | A crater north of the landfill, and the mouth of the one labyrinth. The Demon Lord caused it | bible, “World”; `breach_slice.toml`; `midden_greybox.toml` exit `to_breach` |

The waystone `town_gate` is in the level data, just north of the south gate, but it is not distinctly painted, so it is not labeled on the image.

## 3. The labyrinth — `labyrinth-cross-section.jpg`

One shaft under Elyria. The Magewar plan of five separate dungeon trips collapsed into these five depths, then the Core.

| Label | What it is | Source |
|---|---|---|
| The Labyrinth | “One shaft under Elyria.” Five acts are what remains of Willowbrook's hidden entrance, the whispering wood, Ironforge's mines, the sunken ruins, and the peaks | bible, “The lands”; storyline |
| Eldoria, The Landfill, The Breach | Surface band: the domed city, the dump, and the crater that opens the shaft | bible; storyline |
| Act I — Goblin Warrens | Packed earth, stolen timber, goblin banners, the King's hall. Memory of Willowbrook's raids. Joe's graffiti starts here | bible, Act I; storyline |
| Act II — The Blightcoil | Underground jungle around the Rotheart, a world-tree that had no business growing here. The Whispering Woods pulled under. The Verdant Mother is bound to the tree | bible; storyline, Act II |
| The Rotheart | Landmark of Act II. It dies when the Matriarch falls | storyline, Act II |
| Act III — The Slagworks | Mines the Association charts filed as a collapse. Rails, ore, lava, branded trolls, forge-constructs. Ironforge's buried mines | bible; storyline, Act III |
| Furnace-anvil | The molten mouth every floor can orient by. Forgemaw kept the fires lit | storyline, Act III |
| Act IV — The Sunken Ruins | Flooded halls, coral, a drowned spire with Breach-violet light. The Crimson Sea's ruin, pulled under and left on its side | bible; storyline, Act IV |
| The Drowned Choir | Many singers, one will. Boss of Act IV | storyline, Act IV (decision of 13 Nov 2026) |
| Act V — The Inverted Spire | *Planned.* Platforms from the Shattered Peaks in a vertical void, a tower growing downward from a false sky. Not in the current build | bible (**Open**); storyline, Act V |
| Storm Warden | *Planned.* Keeps the spire's wind locks | storyline, Act V |
| False sky | The inverted tower hangs from a sky that should not be underground | storyline, Act V |
| The Core | End of the main campaign. You fight Joe, then the Demon Lord. Who shed the three skins is revealed here; the name is not written, and this chart does not guess a face | bible; storyline, “The Core” (decision of 13 Nov 2026) |

The Forgotten Abyss (until the Demon Lord is beaten) and Endless Descent (random floors that mix every act, after he falls) are later modes of this same shaft. They are not separate places on the chart.

## Files

| File | Contents |
|---|---|
| `elyria-world-map.jpg` | 3840×2160 labeled realm map |
| `eldoria-and-the-labyrinth.jpg` | 5144×2574 combined hub plan and shaft cross-section |
| `eldoria-hub-map.jpg` | 3456×2592 labeled hub, also used in the combined plate |
| `labyrinth-cross-section.jpg` | 2592×3456 labeled descent, also used in the combined plate |
