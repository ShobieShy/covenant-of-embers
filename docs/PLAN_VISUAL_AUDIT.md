# Covenant of Embers: art match audit and remake plan

Written by Luna for ShobieShy, Nov 22 2026 (planning only; nothing in the repo or the agents was touched).

Inputs: the 108 audit captures from master `456a4c7` and PR #88 head `b2f3d5d` (`artifacts/audit/`), every level painting, creature sheet and weapon sheet in `/workspace/coe-map/`, and both layout specs. Every capture was opened and compared against its reference by eye. The game agent's inventory was used only for what meshes are in the scene, never for whether they match.

**Result: 41 items. KEEP 1, IMPROVE 8, REMAKE 32.** Average score 0.9 / 5. Nothing scores 4 or 5.

Score scale: 0 = nothing or a raw primitive; 1 = wrong shape and placeholder materials; 2 = right idea, wrong models or materials; 3 = close, minor fixes; 4 = matches with small deviations; 5 = matches the painting.

## Five worst items
1. **Act IV: Sunken Ruins (0)**: nothing renders at all; the level is collision boxes only and all four shots are empty sky.
2. **Act V: Inverted Spire (0)**: same; one orange placeholder in an empty sky; the inverted tower does not exist.
3. **Act III: Slagworks (0)**: pure greybox; brown boxes and flat red planes for lava; no furnace, rails or cavern.
4. **Forgemaw (0)**: the Act III boss is an orange cube. Drowned Choir and Storm Warden are the same (blue and lilac cubes).
5. **Town, PR #88 (1)**: the third Town attempt. The outline is finally close, but it is 734 primitive meshes: salmon box houses with grey lids, a brick-box cathedral and a low-poly blob oak, overexposed from above.

## Systemic bugs seen across captures (fix before any art work)
- Facing: the Goblin King and every town NPC show their backs in the 'front' shot (180 degree model rotation).
- Grounding: most creatures float above the floor (origin and scale-to-hitbox offset).
- Weapons: StaffKit parts float apart along the shaft with visible gaps; the staff is tiny in frame.
- Act IV and Act V render nothing; the capture harness still wrote the PNGs, and the agent still produced them as evidence.
- Top-down captures are washed out to near-white (Town, Landfill), so an overlay 'pass' cannot be judged from them.
- Ground textures smear at player height (texel density and mipmaps), visible in Town PR #88.
- Old Oak exterior and Bob's Lab are the same scene; the oak crown pokes through the lab walls.
- The HUD draws on top of the Auto-Scribe menu; the Map tab is empty.

## Item table

| Category | Item | Score | Verdict | Top issues |
|---|---|---|---|---|
| Level | Town (master) | 0 | REMAKE | Washed-out white void; square paved pad with straight roads; fountain is a flat white slab; Kenney rock-large stands in for cliffs; no cathedral, no dome, no Old Oak; wards are purple boxes |
| Level | Town (PR #88) | 1 | REMAKE | Outline is the best yet (round wall, east lobe, curved lanes, plateau drop), but 734 primitive meshes: houses are salmon BoxMesh slabs with flat grey lids, cathedral a brick box, Old Oak reads as a low-poly green blob, dome is a translucent sphere; top-down is overexposed; ground texture smeared at player height |
| Level | Landfill | 1 | REMAKE | One 900 m straight trench instead of the round 300 m pit; white untextured Kenney rocks as cliffs; yellow BoxMesh 'midden' blocks; flat pale-green sheet for the toxic pool; no S-curve path, no shacks, no Breach vista |
| Level | Mage Association | 1 | REMAKE | Single 40 x 56 m Kenney hall interior with lavender flat-colour walls and a sand floor; summoning circle is a pink slab, not a floor inlay; no grounds, curtain wall, garden, fountain or library wing; no stained glass |
| Level | Old Oak exterior | 1 | REMAKE | Shares one scene with Bob's Lab; OldOak_Giant reads as faceted low-poly green blobs with no bark detail; no violet runes, no amethyst root crystals, no trunk door, no fenced herb garden or stone arch gate; camera clips inside geometry |
| Level | Bob's Lab | 1 | REMAKE | A square brown box room; stair is a flat ramp, not a spiral; pots are stall-stool stand-ins; flat untextured walls; tree crown pokes through; no shelves of bottles, cauldrons, slab table or pinned map |
| Level | The Breach | 1 | REMAKE | A 2-room brick corridor maze; walls are the only textured surface; no elliptical crater, no Labyrinth Gate, none of the 10 named chambers; boss shot is pitch black |
| Level | Act I: Goblin Warrens | 2 | IMPROVE | Right palette (timber, torchlight) and an Ember warrens kit, but rooms are square boxes; throne hall is dark with a blue placeholder slab; no bone-and-spike throne pyramid, no stolen crates, no violet crystals, no green ward pots |
| Level | Act II: Blightcoil | 1 | REMAKE | Two diagonal green slabs floating in grey; flat card-like wall panels; no Rotheart, no three tiers, no mire pools; grey void lighting |
| Level | Act III: Slagworks | 0 | REMAKE | Pure greybox: brown boxes, red flat planes for lava, no textures; no round cavern, furnace-anvil, rails, gantries, lift or slag cast |
| Level | Act IV: Sunken Ruins | 0 | REMAKE | Nothing renders: collision and areas only, all four shots are empty grey sky |
| Level | Act V: Inverted Spire | 0 | REMAKE | Nothing renders except one orange placeholder; no inverted tower, platforms, bridges, nests or star ceiling |
| Boss | Goblin King | 2 | IMPROVE | Recognisable (green, crown, spiked club) but a smooth untextured blob; faces away in the 'front' shot; floats above the ground; thin limbs instead of a hulking build; no armour, furs or spiked shoulders |
| Boss | Blightmaw Matriarch | 1 | REMAKE | A blocky purple box with tusks and a lime crown; nothing like the fungal vine horror with the heart-maw; ~3.4 m is right |
| Boss | Forgemaw | 0 | REMAKE | An orange cube; no mesh at all |
| Boss | Drowned Choir | 0 | REMAKE | A blue cube; no mesh at all |
| Boss | Storm Warden | 0 | REMAKE | A pale lilac cube; no mesh at all |
| Boss | The Filth | 1 | REMAKE | A 2 m olive blob with two horns (Quaternius Filth_Brute) floating above ground; painting is a 5 m+ trash mound with a glowing yellow core cave |
| Boss | Breach Warden | 1 | REMAKE | Quaternius garbage golem: green bin torso, trash-can legs and bag hands floating apart; painting is a 4 m dark rubble colossus with a violet back seam |
| Enemy | Goblin Grunt | 2 | IMPROVE | Ember voxel-style goblin: readable, but blocky Minecraft look versus the painterly sheet; reads larger than its 1.32 m hitbox in the shot |
| Enemy | Goblin Archer | 2 | IMPROVE | Same blocky voxel style; green pyramid hood |
| Enemy | Goblin Shaman | 2 | IMPROVE | Same voxel style; pink cone hat is a raw primitive |
| Enemy | Gnawer | 3 | KEEP | Quaternius mutated rat is close to the painted rat in shape and scale; slightly too green and floats |
| Enemy | Heap | 1 | REMAKE | Garbage-bag golem with parts floating apart; sheet shows a dark rubble heap with violet cracks |
| Enemy | Ooze | 2 | IMPROVE | Olive Filth_Sludge blob; sheet shows a mossy green muck mound |
| Enemy | Earth training dummy | 0 | REMAKE | Brown box (the hub sheet paints an earthen humanoid dummy) |
| Enemy | Water training dummy | 0 | REMAKE | Blue box (sheet paints a tidal humanoid dummy) |
| Enemy | Spore-cap Husk | 1 | REMAKE | White blocky tooth shape with detached floating legs |
| Enemy | Spore Beast | 1 | REMAKE | Lime box head on a purple low-poly body with peg legs |
| Enemy | Mossbound Treant | 1 | REMAKE | Blocky voxel trunk with leaf blobs; sheet is a hulking mossy root giant |
| Enemy | Branded Troll | 0 | REMAKE | Orange cube |
| Enemy | Forge Construct | 0 | REMAKE | Brown cube |
| Enemy | Scorchling | 1 | REMAKE | Procedural spheres and a yellow cone flame |
| Enemy | Drowned Cultist | 0 | REMAKE | Blue cube |
| Enemy | Harpy | 0 | REMAKE | Lilac cube; no nest prop |
| Enemy | Storm Elemental | 0 | REMAKE | Pale blue cube |
| Weapon | Staff (all parts) | 1 | REMAKE | StaffKit primitives: cylinders, spheres and cones; parts float apart with gaps; tiny in frame versus the 1.8 m staff on the sheet; no gem sockets; 'Unique' is just gold tint |
| Weapon | Wand (all parts) | 1 | REMAKE | Same primitives and gaps; 0.4 m scale not shown; no crescent head |
| NPC | Town hub NPCs | 2 | IMPROVE | Real rigged Quaternius bodies, but modern clothes (t-shirt and jeans, sundress, cowboy hat, overalls); all face away in the 'front' shot; Bob is a generic elder |
| UI | Auto-Scribe menu | 1 | REMAKE | Default grey Godot theme; Map tab is empty; HUD bars bleed through the menu |
| UI | Combat HUD | 2 | IMPROVE | Works, but four bare bars, tiny pixel font that is hard to read, grey placeholder skill slots, no icons |

## Per-item fixes and approach
### Levels
- **Town (master)** (0/5, REMAKE): Superseded. Delete this layout once the new Town ships; nothing worth carrying forward.
- **Town (PR #88)** (1/5, REMAKE): Keep only PR #88's terrain heightmap, wall spline and lane splines as the layout layer. Rebuild every building from a real medieval kit (timber-frame houses, slate roofs, stone curtain wall with towers), a bespoke gothic Association facade and a bespoke giant Old Oak (trunk 10 m, canopy 45 m). Fix exposure and texel density, add golden-hour light and fog, foliage scatter, 3-basin fountain, market stalls, Flagon tavern.
- **Landfill** (1/5, REMAKE): Rebuild as a Terrain3D bowl (rim 25 to 35 m above floor) traced off the painting; S-curve dirt path in a gully; NW and NE junk lobes; central 25 to 30 m glowing pool with bubbling shader; Poly Haven cliff and rock meshes; shacks, carts, scrap from Quaternius and Kenney; violet crystals; Breach glow visible NW from the gate.
- **Mage Association** (1/5, REMAKE): Build the ~200 m walled grounds; a gothic nave (bespoke Ember Art shell or modular gothic kit) with slate roofs, 4 spires, rib vaults, stained glass; emissive blue circle decal inlaid at hall centre; reading tables and benches; east library wing with 2-storey shelves; west garden with 3-tier fountain; warm candlelight versus blue arcane glow.
- **Old Oak exterior** (1/5, REMAKE): Make it part of the Town's east lobe, not a separate box scene. Bespoke hero oak (Ember Art) with bark PBR, emissive rune strips, amethyst clusters, arched door; fenced garden with giant red-cap mushrooms, flower patch, stone arch gate, cobbled path.
- **Bob's Lab** (1/5, REMAKE): Separate interior: round root-bark hollow (curved living-wood walls), wooden spiral stair, ground-floor benches, barrels, jars; upper lab with stone slab table, west potion shelves, violet cauldrons east, hanging lanterns, pinned map. KayKit/Quaternius props plus bark PBR.
- **The Breach** (1/5, REMAKE): Rebuild as a ~260 m elliptical stepped crater (Terrain3D plus Poly Haven cliffs); south entrance hall; central ring with a bespoke Labyrinth Gate and violet light column; 10 ringed chambers per spec; Warden Arena pillar ring; violet crystal rim; purple dusk mood.
- **Act I: Goblin Warrens** (2/5, IMPROVE): Round off rooms with earthen cave shells; add the stepped bone throne pyramid, crate stacks with blue sigils, corner crystals, green-flame ward pots, spike barricades, the red 'Joe's Graffiti' plaque; light the throne hall properly (torches plus fill); per-floor plan overlays plus a side elevation.
- **Act II: Blightcoil** (1/5, REMAKE): Build the single cavern with three bands around a bespoke Rotheart trunk; root bridges, fungal shelves and giant mushrooms, torn cocoon, yellow-green Sump pools; volumetric spore fog and bioluminescence.
- **Act III: Slagworks** (0/5, REMAKE): Round terraced basalt cavern; bespoke conical Furnace-Anvil; spiral rails, iron gantries, main lift, crucible arena, emissive lava with heat haze, hollow humanoid slag mold.
- **Act IV: Sunken Ruins** (0/5, REMAKE): Build from zero: round flooded galleries, water shader with caustics, coral, air-bell alcoves, Drowned Temple Spire landmark, mural wall, choir nave with cracked coral sarcophagus, exit shaft.
- **Act V: Inverted Spire** (0/5, REMAKE): Build from zero: cylindrical void, painted false-star ceiling, bespoke inverted gothic tower, floating rock platforms with crystals, emissive light-ribbon bridges, harpy nests, low Warden floor, wind particles.

### Bosss
- **Goblin King** (2/5, IMPROVE): Fix facing and ground offset now; rebuild as a bulky 2.4 m textured model with leather armour, fur, spiked pauldrons and tusks (Ember Art, image-to-3D from the sheet), rigged.
- **Blightmaw Matriarch** (1/5, REMAKE): Ember Art hero mesh from the sheet: vine-and-fungus body, glowing heart-maw weak point, mushroom caps on the back; 3 phase states.
- **Forgemaw** (0/5, REMAKE): Ember Art hero mesh: 3.2 m molten-cracked brute with a forge hammer and tongs, emissive lava seams, phase-3 exposed core.
- **Drowned Choir** (0/5, REMAKE): One fighting body (rule): a 2.8 m mass of fused drowned singers with kelp, coral and violet water glow; singers are sculpted into the single mesh, not separate actors.
- **Storm Warden** (0/5, REMAKE): Ember Art hero mesh: 2.6 m storm-wrapped stone-and-crystal giant with violet crystal crown and wind-ribbon VFX.
- **The Filth** (1/5, REMAKE): Bespoke trash-mound mesh (5 to 6 m) built from scrap and bag sub-meshes with a slime shader, glowing core cavity that opens in phase 3.
- **Breach Warden** (1/5, REMAKE): Ember Art hero mesh: dark rubble and slag colossus with a glowing violet seam on the back, enrage glow.

### Enemys
- **Goblin Grunt** (2/5, IMPROVE): Restyle the goblin family together: smoother sculpt, leather and cloth PBR, correct 1.3 m scale, ground offset.
- **Goblin Archer** (2/5, IMPROVE): Same goblin restyle; bow and quiver meshes.
- **Goblin Shaman** (2/5, IMPROVE): Same goblin restyle; fire-staff with emissive ember.
- **Gnawer** (3/5, KEEP): Keep; recolour to mangy brown and fix ground offset.
- **Heap** (1/5, REMAKE): New mesh (or a scaled-down Breach Warden variant) with violet crack emissive.
- **Ooze** (2/5, IMPROVE): Retexture to mossy green slime with drips; size up to the sheet; slime shader.
- **Earth training dummy** (0/5, REMAKE): Cheap: one shared humanoid dummy mesh with stone/earth material.
- **Water training dummy** (0/5, REMAKE): Same dummy mesh with a water material.
- **Spore-cap Husk** (1/5, REMAKE): Ember Art mesh from the Act II sheet: hunched mushroom-capped humanoid.
- **Spore Beast** (1/5, REMAKE): Ember Art mesh: violet fungal ape-beast per sheet.
- **Mossbound Treant** (1/5, REMAKE): Ember Art mesh with bark and moss PBR.
- **Branded Troll** (0/5, REMAKE): Ember Art mesh from the Act III sheet: molten-branded troll.
- **Forge Construct** (0/5, REMAKE): Ember Art mesh: iron-plated furnace golem with lava core.
- **Scorchling** (1/5, REMAKE): Small ember imp mesh with fire VFX.
- **Drowned Cultist** (0/5, REMAKE): Ember Art mesh: kelp-draped drowned human, 1.8 m.
- **Harpy** (0/5, REMAKE): Ember Art mesh: pale winged harpy; nest prop for Act V.
- **Storm Elemental** (0/5, REMAKE): Crystal-and-wind body mesh with particle VFX.

### Weapons
- **Staff (all parts)** (1/5, REMAKE): Model 5 part meshes x 6 tiers from the 62 sheets (crescent heads, carved shafts, wrapped handles), snap to sockets with no gaps, element materials, gem sockets always drawn.
- **Wand (all parts)** (1/5, REMAKE): Same modular approach, wand-scaled parts.

### NPCs
- **Town hub NPCs** (2/5, IMPROVE): Swap to medieval-fantasy outfits (Quaternius fantasy/medieval character packs), fix facing, bespoke Bob wizard, guard armour.

### UIs
- **Auto-Scribe menu** (1/5, REMAKE): Parchment-and-brass theme matching the map art; real map tab using the painted level maps; hide the HUD under the menu.
- **Combat HUD** (2/5, IMPROVE): Framed bars, readable serif/rune font at 1080p, skill icons, element colours, damage numbers.

## Root cause: why builds keep coming out flat and empty

**1. The asset library has nothing that looks like the paintings, so the agent draws landmarks with primitives.** The repo's kits are Kenney low-poly pieces (flat palette colours, 2 to 4 m wall tiles) plus a few Quaternius props. There is no gothic cathedral, giant oak, cliff, cave shell, coral, furnace or inverted tower mesh. When a landmark has no mesh, the code generates a `BoxMesh` and tints it. Evidence: PR #88 has 734 primitive meshes against 442 real ones; Act III has 24 primitives and zero meshes; 10 of the 24 creatures are a single box. Kenney tiles scaled up to Borderlands size become big flat walls with no detail.

**2. Levels are generated from code and TOML, not authored and looked at.** Placement is coordinates in GDScript, so nobody sees the scene until the final capture. There is no density requirement, so scaling the Town to 320 m (and the Landfill to a 900 m trench) multiplied empty ground without adding content: master has 89 meshes in the whole town, and even PR #88's 442 real meshes are mostly repeated wall and lantern tiles.

**3. The ship gate is self-graded, and the evidence is broken.** The overlay test only checks the outline, which a field of boxes can pass. It says nothing about models, materials, density or light. The captures themselves are unreliable (overexposed top-downs, empty Act IV/V frames, creatures shot from behind), and the agent has still reported "passes" on them twice for the Town.

**4. Lighting and post are default.** Procedural sky, no fog, no SSAO or GI, overexposed tonemapping, and wrong texel density. Even good meshes would read flat.

**5. Ember Art output has no quality bar.** The Ember meshes that exist (goblins, Matriarch, treant, husk) are voxel or faceted low-poly blobs, a different style from the painterly sheets, with no scale, poly or texture spec and no turntable review before integration.

### Pipeline changes that fix it

1. **Hard art gate, not self-review.** CI fails any level, enemy or weapon scene that contains a primitive `MeshInstance3D` (collision shapes and VFX allowlisted). The capture harness writes one contact sheet per item: reference, top-down at 50% overlay, 3 player-height shots, and creature turntables next to a 1.8 m figure. Ember QA scores it, then I score it against the painting; it ships only at 4/5 or better from both. The game agent cannot certify its own work.
2. **Fix the capture harness first** (exposure, facing, grounding, and fail loudly on an empty frame), so the evidence can be trusted.
3. **Kitbash library, curated and catalogued.** Import CC0 packs that match a medieval dark-fantasy look: Quaternius Medieval Village, Fantasy Props and Stylized Nature megakits, KayKit Dungeon and Forest, Poly Haven rocks, cliffs, trees and castle pieces, and ambientCG 2K terrain, rock, wood, masonry and slate materials (licence checked per pack on import). Write a catalogue page with a thumbnail and real-world size per piece. Kenney stays for small props only, never architecture.
4. **Mesh and density budget per level.** Hubs: at least 60 unique meshes and one dressed prop cluster per 100 square metres of walkable space; acts: at least 40 unique meshes per floor; foliage and debris through Terrain3D instancing; zero primitives; a triangle and draw-call ceiling so it stays performant.
5. **Bespoke hero assets from Ember Art**, each with a brief (scale, poly budget, 2K texture set, reference sheet) and a turntable review before it enters a level: Old Oak, Association facade and nave, Town gatehouse, Labyrinth Gate, Filth mound, Rotheart, Furnace-Anvil, Drowned Temple Spire, Inverted Spire, plus all 7 bosses. An image-to-3D starting point from the concept sheets (for example TRELLIS, MIT licence) followed by cleanup and rigging would make this feasible; it is a new tool, so it needs your OK.
6. **Build small first, then scale up.** Each level starts with a 60 x 60 m golden slice around its landmark (for the Town: Main Gate to fountain to cathedral view) built to the full bar. You approve the slice, then it expands outward with the same kit and density.
7. **Lighting presets per biome**: Poly Haven HDRI sky, volumetric fog, SSAO, SDFGI or baked GI, filmic tonemap and fixed exposure, and a 512 px per metre texel density standard.
8. **Agree the style target.** The paintings are painterly, realistic dark fantasy and CC0 kits are stylized. The realistic target is stylized-realistic PBR that matches the shapes, palette and composition, with bespoke hero pieces carrying the likeness.


## Phased plan (priority order)

Each phase is one PR and one prerelease, and ships only after it passes the art gate. Sizes: S is about a day of agent work, M a few days, L a week or more.

| Version | Phase | Scope | Acceptance | Size |
|---|---|---|---|---|
| 0.11.3 | Art gate and capture fixes | Primitive-mesh CI lint; contact-sheet generator; fix exposure, facing, grounding and empty-frame detection in the harness; fix StaffKit part gaps, NPC and Goblin King facing, creature ground offsets; HUD hidden under menus; biome lighting presets; texel density standard | Re-run audit captures: every frame lit and readable, creatures face camera and stand on the ground, CI goes red on a test scene with a BoxMesh | M |
| 0.11.4 | Asset library and hero briefs | Import and catalogue the CC0 kits and ambientCG materials; asset catalogue doc; Ember Art briefs for every hero asset; trial one hero asset (Old Oak) end to end through the image-to-3D route if approved | Catalogue lists every piece with size and thumbnail; Old Oak turntable approved by Ember QA and me | M |
| 0.12.0 | Town (with Old Oak exterior and NPC restyle) | 60 m golden slice first, then the full 320 m town on PR #88's terrain and splines: kit houses, slate roofs, curtain wall and towers, gatehouse, Association facade, Flagon, market, 3-basin fountain, ward crystals, Old Oak lobe and garden, golden-hour light; NPCs in medieval outfits and bespoke Bob | Overlay within 5%; spawn shot reproduces the painting's composition (fountain, cathedral on axis, oak right); zero primitives; density budget met; gate score 4+ | L |
| 0.12.1 | Bob's Lab interior | Round root-bark hollow, spiral stair, two floors dressed per spec, its own scene | Per-floor plans plus side elevation match the cutaway; no tree poking through | S |
| 0.12.2 | Mage Association | Walled grounds, gothic nave, summoning inlay, library wing, garden and fountain | Overlay within 5%; interior and exterior shots score 4+ | L |
| 0.12.3 | Landfill | Round Terrain3D pit, S-curve gully path, junk lobes, toxic pool shader, cliffs, Breach vista | Overlay within 5%; gate view shows the bowl, pool and Breach glow; 4+ | L |
| 0.12.4 | The Breach | Elliptical stepped crater, entrance hall, 10 chambers, Labyrinth Gate hero piece, Warden Arena | Overlay within 5%; every named chamber present and dressed; 4+ | L |
| 0.13.0 | Act I: Goblin Warrens | Earthen cave shells over the existing kit, throne pyramid, crate stacks, ward pots, graffiti plaque, lighting | Per-floor plans plus side elevation; throne hall 4+ | M |
| 0.13.1 | Act II: Blightcoil | Three-band cavern around the Rotheart hero piece, root bridges, fungus, cocoon, Sump pools, spore fog | Side elevation matches the painting; 4+ | L |
| 0.13.2 | Act III: Slagworks | Round basalt cavern, Furnace-Anvil hero piece, rails, gantries, lift, crucible arena, hollow slag mold | Overlay within 5%; furnace visible from everywhere; 4+ | L |
| 0.13.3 | Act IV: Sunken Ruins | Flooded galleries, water and caustics, coral, bells, Temple Spire hero piece, choir nave and sarcophagus | Overlay within 5%; 4+ | L |
| 0.13.4 | Act V: Inverted Spire | Void, false-star ceiling, inverted tower hero piece, platforms, light bridges, nests | Side elevation matches; 4+ | L |
| 0.14.0 | Bosses | The Filth, Breach Warden, Goblin King, Blightmaw Matriarch, Forgemaw, Drowned Choir (one body), Storm Warden: hero meshes, rigs, phase looks | Turntable next to a 1.8 m figure matches each sheet in silhouette, scale and palette; 4+ | L |
| 0.14.1 | Regular enemies | Goblin family restyle, Gnawer recolour, Heap, Ooze, dummies, Act II to V trash | Same turntable gate; zero box enemies | L |
| 0.15.0 | Staffs and wands | Modular part meshes for 5 parts x 6 tiers from the 62 sheets, element materials, gem sockets | Every part type and tier renders seamlessly on both forms and matches its sheet; 4+ | M |
| 0.15.1 | UI | Parchment-and-brass Auto-Scribe theme with a working Map tab, framed HUD, readable font, skill icons | Screens reviewed against the map art style; 4+ | M |

Notes:
- The order is as you asked (levels, then creatures). Shipping a level whose boss is still a cube is ugly; if you prefer, each boss can be folded into its level's version instead.
- Standing rules hold throughout: the Core stays closed, music stays silent, the Choir stays one body, no Demon Lord body, and no merge without your go.

## Decisions

ShobieShy, 22 Nov 2026. These answers replace the open questions above.

1. **Art gate.** Yes. CI fails a shipped scene that contains PrimitiveMesh or CSG geometry, other than collision shapes and debug nodes. Scenes that have not been remade yet are reported and do not fail the build. A remade scene does. Nothing ships until Ember QA and ShobieShy have both scored it 4/5 or higher against its painting.
2. **Image-to-3D.** Yes. Ember Art may turn the concept sheets into 3D with an image-to-3D tool (for example TRELLIS) for landmarks and creatures. Imports are retopologized or decimated to the budget and given PBR materials before they enter the game.
3. **PR #88.** Closed, not merged. The Town starts fresh. PR #88's buildings, terrain, and splines are not the layout base. PR #85 stays open until he says otherwise.
4. **Bosses.** All seven stay in the single 0.14.0 phase. The Drowned Choir stays one body.
5. **Start.** Building starts at 0.11.3: the art gate and the capture fixes. The Core stays closed. Music stays silent. No new names.

0.12.0 in the table above is the Town. It is not a Core release. The Core does not open.
