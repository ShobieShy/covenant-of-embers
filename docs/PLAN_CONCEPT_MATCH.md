# Concept match

Written 20 Nov 2026, against master `781a260` (v0.11.2-prealpha). This extends [PLAN_WORLD_SCALE.md](PLAN_WORLD_SCALE.md). It is a plan. It does not change a level, a mesh, a hitbox, or a release.

0.11.3, the town dressed to [maps/levels/town.jpg](maps/levels/town.jpg), is in review and is not part of this document's build list. Nothing in the sequence below starts until ShobieShy has reviewed that town and approved this plan.

The paintings are the look. The numbers already in `data/enemies/*.toml` are the hitboxes. A figure drawn twice a person's height is not a request to double `size`. Where a sheet and the data disagree, the data wins unless a decision at the end says otherwise.

Some captions are garbled. The names in the data files are the names. Unreadable words are not new lore and not new dialogue.

## What stays decided

- The Core stays closed. [concepts/creatures/lore_crazy_joe.jpg](concepts/creatures/lore_crazy_joe.jpg) is marked NOT BUILT. Crazy Joe is not remade from it, and the Demon Lord is not built from it. No Core fight.
- Music stays silent.
- The Drowned Choir stays one fighting body. The sheet shows many singers. That crowd is a decision below, not a new enemy.
- Proposed bible lines stay out of dialogue. Hymn books on the Act IV sheet stay unreadable props. No hymn text.
- No rebel leader and no DLC town names. No new creature names. Every id below already exists.
- `Vigil.xp_mult` stays unwired. `apply_void_on_player` stays uncalled.
- Protocol stays 7. Save version stays 1. A visual mesh is not a snapshot field.
- Windows stays unverified and does not block. The AppImage stays on the prerelease.
- Kenney and Quaternius stay until a replacement mesh for that slot is in the tree. Ember Art is not asked to redraw a kit piece.

## How a mesh gets made

Same three sources as the world-scale plan, in this order:

1. A CC0 kit already in the tree, or another CC0 pack with a line in CREDITS, when the silhouette is close enough to read at gameplay distance.
2. An Ember Art commission for a hero: each boss, the Old Oak's rune skin, the cathedral, the Filth's mound. One file per slot. A person accepts it before it replaces the stand-in.
3. AI only as a concept board, or as a draft that a person retopologizes, rigs, and accepts. The draft is not a mesh in `assets/` and not a texture on a creature.

Every creature keeps its script, its AI kind, and its attacks. The patch swaps the body. It does not add a phase, a spell, or a line of speech.

## Scale, hitbox, readability

`size` in the enemy toml is the hitbox, in metres, yaw 0 facing -Z. The mesh fills that box. A weapon or a wing may stick out a little. The attack range is not retuned to a poster.

The First on the sheets is 1.8 m, the player's eye line. Use him as the scale bar, then fit the creature into its toml size. Painted heights that ignore the bar are poster scale.

A regular enemy must be recognizable at 20 m. A boss must be recognizable at 30 m. That is silhouette and palette, not polygon count.

| Slot | Tris, near | Tris, far | Fade |
|---|---|---|---|
| Regular | at or under 2,000 | a box or a 300-tri card | 25 m |
| Boss | at or under 8,000 | the regular card is not used; a 1,500-tri body | 40 m |
| Level dress piece | at or under 2,000, instanced | hidden with the existing prop distance | 40 m |

One shadow-casting light per boss, no shadows on regulars. The Scorchling keeps the one small lamp it has. Grass and level foliage stay on the world-scale cap (8,000 visible, fade by about 50 m).

The visual mesh has no collision and is not in the nav bake. The hitbox is the collider the game already uses. Co-op keeps sending that body. Peers build the same mesh locally. No protocol bump.

## Levels

Each patch ships a top-down, two or three player-height shots, and a labeled side-by-side with the concept on the left. The capture script stays out of the repo. Full tier, solo playtest, and `COOP_LAG=150 COOP_LOSS=0.02`. Gameplay ids, exits, and quests stay.

### Town

Concept: [maps/levels/town.jpg](maps/levels/town.jpg). 0.11.3 is the pass that tries to match it. This plan does not schedule a second town rebuild. If the review names a miss, that miss is a follow-up on the town, not a new act.

### Landfill

Concept: [maps/levels/landfill.jpg](maps/levels/landfill.jpg). 0.11.2 made the valley about 900 m long, kept the tutorial yard, and put a green sheet on the bowl. The painting is a round junk pit: shacks, trash heaps, purple crystals, the gate on the rim, and the Breach as a crater beside the pit. The gap is the round read and the shacks, not the length. A later pass dresses the bowl so a shot from the south lip shows a circle and a green pool. The tutorial coordinates stay. The Filth stays the last fight.

### Mage Association

Concept: [maps/levels/association.jpg](maps/levels/association.jpg). Built: a greybox hall, a small library to the east, a walled court to the west. The painting is a gothic cathedral, a glowing circle on the dais, a courtyard fountain, and a library that looks like a long wing. The world-scale default still holds: the hall stays about 40 by 56 m, the library stays one room, the grounds are the precinct. This pass is the shell, the circle, the spires, and the hill outside the wall. It does not restore a 90 m wing.

### Old Oak and Bob's lab

Concept: [maps/levels/bobs_lab.jpg](maps/levels/bobs_lab.jpg). Built: the hollow, the stair, the upstairs room. The painting adds the exterior tree with rune light, crystals, a fenced path, and mushrooms. The potion garden stays the pot bench upstairs. The fenced ground is dressing on the grove, not a new quest. The town's east lobe, if 0.11.3 lands it, is the view of the tree from outside. This pass is the bark, the runes, and the room the player already walks.

### Breach

Concept: [maps/levels/breach.jpg](maps/levels/breach.jpg). Built: a linear greybox that already names the cistern, the ossuary wing, and the Warden. The painting is a round crater: landfill road at the south gate, the labyrinth gate as a central arch with a purple fall, the Warden's arena at the north, ember gallery, gnawer den, mire cistern, switch room, reliquary, bell loft. The pass dresses those existing rooms into that crater. It does not add a fight past the Warden, and it does not move the labyrinth door off the flag that already opens it.

### Act I, the Goblin Warrens

Concept: [maps/levels/act1_goblin_warrens.jpg](maps/levels/act1_goblin_warrens.jpg). Built: generated warren floors. The painting is a stack of burrows: descent from the Breach, ambush rooms, spike traps, gnawer nests, green fire, Joe's mark, the throne, roots down to the Blightcoil. The doubled graffiti caption is one mark, not two. Dress the existing rooms toward that stack. Do not write new graffiti lines.

### Act II, the Blightcoil

Concept: [maps/levels/act2_blightcoil.jpg](maps/levels/act2_blightcoil.jpg). Built: the cavern pads (Sump, canopy, Crown) and the boss on the Crown. The painting is a living tree: Rotheart, empty cocoon, canopy ring, shrine, sump, the door down. Dress the pads and the trunk. The Crown stays the high pad. The nav bake stays the cached one. A rebake in play is still a failure.

### Act III, the Slagworks

Concept: [maps/levels/act3_slagworks.jpg](maps/levels/act3_slagworks.jpg). Built: generated forge floors. The painting is an open crater of rails, a furnace, a crucible, a slag cast, and the door down. Dress the floors so a shot from the entry shows lava light and the furnace. The Forgemaw stays the last fight on that floor. Lava stays the hazard it is. It does not become a new damage type.

### Act IV, the Sunken Ruins

Concept: [maps/levels/act4_sunken_ruins.jpg](maps/levels/act4_sunken_ruins.jpg). Built: the drowned floors and one cultist type. The painting is flooded galleries, air-bell shrines, coral, a drowned temple, the choir nave, and a shaft up to the Spire. The regular-enemy sheet has only the Drowned Cultist. Do not invent a second sunken enemy to fill the empty page. Hymn vaults stay props without text. The Choir stays one body.

### Act V, the Inverted Spire

Concept: [maps/levels/inverted_spire.jpg](maps/levels/inverted_spire.jpg). Built: checkpoint floors 19–23 and, on the Warden's floor, collision pads. The painting is a false sky, an inverted tower, crystal shelves, and bridges of light. The world-scale default still holds: five shelves of about 100 m, a real drop between them, the tower non-colliding, no Core under the lowest shelf. The garbled middle label means Middle Platform. The garbled line on the Warden sheet (it does not read as a word) means the floor that fails under the fight, which the game already has.

## Creatures

Current bodies are built in script from primitives (the Scorchling is the only one with a real silhouette). The sheet is the target silhouette. The toml size stays the hitbox.

| Id | Hitbox (m) | Sheet | Gap | First mesh |
|---|---|---|---|---|
| gnawer | 0.5 × 0.45 × 0.8 | [enemies_act1_warrens.jpg](concepts/creatures/enemies_act1_warrens.jpg) labels 0.45 tall and 0.8 long. Armadillo rat | The data and the label agree. The body is still a box | CC0 or a small commission. This one can match the sheet |
| heap | 1.5 × 2.4 × 1.5 | [enemies_hub_landfill_breach.jpg](concepts/creatures/enemies_hub_landfill_breach.jpg) draws a giant | Poster scale. Keep 2.4 m tall | Trash golem in that box, purple seam on the back |
| scorchling | 0.5 × 0.8 × 0.5 | Same sheet draws a person of fire | Poster scale. Keep 0.8 m | Keep the current parts, push the palette toward the sheet |
| ooze | 1.0 × 0.7 × 1.0 | A wide slime mound | Poster scale. Keep the low box | Green sheet, a face, the split already in the script |
| earth / tidal dummy | 0.7 × 1.6 × 0.7 | The two practice figures | Close to the bar | Kit bodies, earth brown and tide blue |
| goblin_grunt | 0.7 × 1.32 × 0.7 | Green, cleaver, earth rusher | Painted nearer 1.8 m. Keep 1.32 | One goblin mesh, three materials |
| goblin_archer | 0.7 × 1.32 × 0.7 | Bow, air | Same mesh, bow | Same |
| goblin_shaman | 0.7 × 1.32 × 0.7 | Staff, fire, purple cloth | Same mesh, staff and cloth | Same |
| goblin_king | 1.6 × 2.4 × 1.6 | Boss sheet | Needs a crown and a bigger read inside 2.4 m | Ember Art. Kit goblin scaled up until it lands |
| spore_husk | 0.7 × 1.5 × 0.7 | Act II lineup | Mushroom husk | CC0 fungus on a humanoid |
| spore_beast | 1.1 × 1.6 × 1.3 | Act II lineup | Low beast | CC0 quadruped, spore hide |
| mossbound_treant | 1.4 × 2.6 × 1.4 | Act II lineup | A tree that walks | Kit tree pieces on the tank rig |
| blightmaw_matriarch | 2.2 × 3.4 × 2.2 | Boss sheet | The Crown boss | Ember Art. A larger treant until it lands |
| branded_troll | 1.1 × 2.2 × 1.1 | Act III lineup | Brand on the skin, not a new name | Kit troll, one emissive brand |
| forge_construct | 1.6 × 2.4 × 1.6 | Act III lineup | Furnace armor | Kit golem, hot metal |
| forgemaw | 2.4 × 3.2 × 2.4 | Boss sheet | The slag-cast giant | Ember Art. The construct, larger, until it lands |
| drowned_cultist | 0.8 × 1.8 × 0.8 | [enemies_act4_sunken.jpg](concepts/creatures/enemies_act4_sunken.jpg) only | Painted as a giant. Keep 1.8 m. No second sunken enemy | Coral robe on a humanoid |
| drowned_choir | 2.2 × 2.8 × 2.2 | [boss_drowned_choir.jpg](concepts/creatures/boss_drowned_choir.jpg) | Many singers, and the caption says one will | One hitbox. See the decision |
| harpy | 0.9 × 1.7 × 0.9 | [enemies_act5_spire.jpg](concepts/creatures/enemies_act5_spire.jpg) | Painted with a huge wingspan | Wings may extend past the box. The body stays in it |
| storm_elemental | 1.1 × 2.0 × 1.1 | Same sheet, and it looks like the Warden | Too close. See the decision | Lightning body, small spines, no cloak |
| storm_warden | 2.0 × 2.6 × 2.0 | [boss_storm_warden.jpg](concepts/creatures/boss_storm_warden.jpg) | Cloak, crystal crown, wind. The garbled floor caption is the failing floor | Ember Art. Outline on the sheet, not built yet |
| the_filth | 2.2 × 2.0 × 2.2 | [boss_the_filth.jpg](concepts/creatures/boss_the_filth.jpg) | A hill of slime with a glowing mouth, three phases, regeneration | One phase. The mouth and the slime, inside the box |
| breach_warden | 1.8 × 2.8 × 1.8 | Boss sheet | The arena guardian | Ember Art. A tall armored figure in that box |

Training dummies are on the hub sheet and in this table. They are not bosses.

## Version sequence

These start only after the 0.11.3 town review and after this plan is approved. Until then they are not branches. 0.12.0 is the Core and does not start. Each line is its own PR and its own prerelease.

| Version | Lands | Done when |
|---|---|---|
| 0.11.4 | Gnawer, Heap, Scorchling, Ooze, both dummies | Side-by-side with the hub sheet. Hitboxes unchanged. The gnawer reads as the 0.8 m rat |
| 0.11.5 | The Filth's body | A shot in the bowl shows the slime and the mouth. One phase. The tutorial still ends on that kill |
| 0.11.6 | Breach dressed to the crater chart | The named rooms are still the rooms. The labyrinth door still waits on its flag |
| 0.11.7 | Breach Warden body | Readable at 30 m. Same attacks |
| 0.11.8 | Warren rooms dressed, three goblins, one mesh | Grunt, archer, and shaman share a rig. No new graffiti text |
| 0.11.9 | Goblin King body | The throne fight is unchanged apart from the mesh |
| 0.11.10 | Blightcoil dress, husk, beast, treant | Crown nav is still the cache. `test` that forbids a rebake still passes |
| 0.11.11 | Matriarch body | Still the Crown boss |
| 0.11.12 | Slagworks dress, troll, construct | Lava is still the old hazard |
| 0.11.13 | Forgemaw body | Still the last fight on that floor |
| 0.11.14 | Sunken dress, cultist body | No second enemy type. No hymn text |
| 0.11.15 | Choir body | One hitbox. Any extra singers do not fight and do not take hits |
| 0.11.16 | Spire shelves to the shaft chart, harpy, storm elemental | Elemental is not a second Warden. Tower stays non-colliding. No Core |
| 0.11.17 | Storm Warden body | Same wind, same failing platforms, host applies the shove |

A missing Ember Art file does not hold the patch. The kit stand-in ships, and the notes name it.

## Decisions

The default is what the first patch should do if ShobieShy does not say otherwise. None of these patches start until he approves this plan and has reviewed 0.11.3.

1. **When does this start?** Recommended: after the 0.11.3 town review, and only the rows he has not sent back. The town is not rebuilt again from this document.
2. **Hitboxes.** Recommended: keep every `size` in the table. The painted giants are the material and the silhouette, squeezed into the box. Wings may stick out. Attack ranges stay.
3. **The Filth's phases.** Recommended: do not add them. One body, the slime and the mouth. Regeneration off debris and a second phase are not in the script and are not in this plan.
4. **The Choir.** Recommended: one fighting body, as now. Up to six extra singers may stand in the nave as props. They have no hitbox, no AI, and no lines. The caption on the sheet says one will.
5. **Storm Elemental and Storm Warden.** Recommended: the elemental is lightning and small crystal spines, no cloak, no crown, hitbox 1.1 × 2.0 × 1.1. The Warden keeps the cloak, the crown, and 2.0 × 2.6 × 2.0. They must not share a mesh.
6. **Act IV's empty roster.** Recommended: the Drowned Cultist is the only regular enemy there. Do not invent another to fill the sheet.
7. **Crazy Joe and the Core.** Recommended: the lore sheet stays a reference. It is not a mesh, not a fight, and not new dialogue. The garbled robe caption is not a line.
8. **Garbled captions.** Recommended: ignore them. Use the ids in the table. The Spire's middle label means Middle Platform. The Warden sheet's broken floor caption means the platforms that already fail.
9. **Who builds the mesh.** Recommended: CC0 or a kit for the first body, Ember Art for each boss and for the Filth. AI only as a board or a draft a person retopos. A late commission does not hold the patch.
10. **Protocol and the Core.** Recommended: protocol stays 7. 0.12.0 does not start.
