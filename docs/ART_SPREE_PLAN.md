# Art Spree Plan: models and textures (PLAN ONLY, waiting on user go)

Planned 2026-10-24 from an audit of `scenes/`, `scripts/` and `assets/`. Nothing here is built.
Rules: free assets only (CC0 preferred; CC-BY allowed with credit), or Magewar assets. No paid, no Borderlands.
Ember Art sources into `incoming_art/<batch>/` with CREDITS.md + HANDOFF.md; Luna imports, scales and wires code.
Every import adds a line to `data/credits.toml`.

## Audit summary (current state)
- Procedural primitives (BoxMesh/CapsuleMesh/SphereMesh/CylinderMesh) are still built in code in:
  `enemy.gd`, `filth.gd`, `ooze.gd`, `heap.gd`, `loot_pickup.gd`, `quest_pickup.gd`, `vault_chest.gd`,
  `breach_switch.gd`, `arena_lock.gd`, `level_gate.gd`, `light_summon.gd`, `viewmodel.gd`, `remote_player.gd`,
  `mentor_arrival.gd` (violet torus vortex), `intro_director.gd`, and all five level scenes.
- Imported: Kenney fantasy-town + nature kits (Town Square, Association, Old Oak), Kenney ui-pack / blaster-kit,
  ambientCG Bricks076C, Ground037, Metal032, PavingStones131, Rock030, Wood049 (Landfill/Breach first pass),
  Quaternius rigged GLBs (Bob, Joe, clerk, Gal, Buff placeholder; one shared 24-anim skeleton).
- Known issues: town ground washed out (mostly lighting, see FX plan, plus ground texture tiling/albedo too bright),
  Old Oak crown too small, Quaternius characters taller than Kenney doors.

## Inventory
Legend: Src = EA (Ember Art sources) / PROC (Luna builds procedurally or in-engine) / MW (Magewar repo asset). Pri = P0 (pre-alpha 0.2 must) / P1 / P2.

### Characters and archetypes
| Item | Current | Target | Suggested source | Src | Pri |
|---|---|---|---|---|---|
| Nerd | capsule placeholder | rigged humanoid, robe + glasses | Quaternius Ultimate Modular Characters / Universal Base Characters (CC0) | EA | P0 |
| Gal | Quaternius Adventurer_female | keep; tint slots for player colour | imported | - | done |
| Buff | King_armored placeholder | heavier build, no crown | Quaternius modular men / KayKit Adventurers (CC0) | EA | P0 |
| Loli (name kept per decisions) | capsule placeholder | small, non-sexualised young mage, cloak | Quaternius chibi/kid or KayKit Adventurers Mage (CC0) | EA | P0 |
| Player colour slot | albedo tint on whole mesh | colour mask on cloak/trim material only | shader param, mask texture | PROC | P0 |
| First-person hands/arms | viewmodel primitives | low-poly sleeved arms per archetype | Quaternius FPS arms or KayKit (CC0); tinted | EA | P1 |
| Remote player (co-op) | capsule in `remote_player.gd` | same archetype model as owner | reuse archetype GLBs | PROC | P0 |

### NPCs
| Item | Current | Target | Source | Src | Pri |
|---|---|---|---|---|---|
| Bob | Quaternius Farmer | keep, add hat/staff prop | imported | - | done |
| Crazy Joe | Animated_Wizard_old_man (CC-BY 3.0, credited) | keep | imported | - | done |
| Clerk | Quaternius green dress | keep | imported | - | done |
| Elders (3) | placeholders | robed elders, 3 colour variants | Quaternius wizard / KayKit (CC0) | EA | P0 |
| Vendors (3) | npc.gd placeholder | shopkeep variants + stall props | Quaternius townsfolk (CC0) + Kenney stalls | EA | P1 |
| Gate guard | placeholder | armoured guard | Quaternius knight (CC0) | EA | P1 |
| Scavenger (Light lesson) | placeholder | ragged civilian | Quaternius townsfolk alt | EA | P1 |
| Other Summoned in solo cinematics | placeholders | reuse 3 archetype models | archetype GLBs | PROC | P0 |
| Townsfolk ambience | none | 4-6 idle walkers | Quaternius (CC0) | EA | P2 |

### Enemies
| Item | Current | Target | Source | Src | Pri |
|---|---|---|---|---|---|
| Gnawer | primitive body | rat-like scavenger, rigged walk/bite/die | Quaternius Animated Animals / Ultimate Monsters (CC0) | EA | P0 |
| The Filth | primitive blob + core | 3-phase sludge mass, exposed core mesh, blend shapes or vertex-shader wobble | sculpted low-poly base (Quaternius slime CC0) + shader | EA+PROC | P0 |
| Ooze / small slime | sphere | slime | Quaternius Ultimate Monsters slime (CC0) | EA | P1 |
| Mutated rats (Storyline) | not built | rat variant with growths | Quaternius rat + PROC tumour meshes | EA | P1 |
| Garbage golems (Storyline) | not built (Heap stand-in) | junk-assembled golem | Kenney props kit-bashed onto golem rig (Quaternius CC0) | EA+PROC | P1 |
| Heap (legacy) | primitives | retire or reuse golem model | - | - | P2 |
| Scorchling (Breach) | primitive | fire imp | Quaternius Ultimate Monsters (CC0) | EA | P1 |
| Breach Warden (boss) | primitive | armoured warden | Quaternius / KayKit Skeletons (CC0) | EA | P1 |
| Elites | tint/scale | keep base + elite overlay material | shader | PROC | P1 |
| Training dummies | primitives | straw dummy | Kenney / Quaternius (CC0) | EA | P2 |

### Staffs, wands and parts
| Item | Current | Target | Source | Src | Pri |
|---|---|---|---|---|---|
| Staff parts: Handle, Shell, Internals, Head | primitive viewmodel pieces | 3-4 modular variants per slot, shared socket points so any combo assembles | Kenney/Quaternius fantasy weapons (CC0), kit-bashed; Magewar item refs | EA+PROC | P0 |
| Part rarity look | colour only | trim/emissive mask driven by rarity colour | shader | PROC | P0 |
| Wands | primitive | 3 wand bodies + gem socket | Quaternius weapons (CC0) | EA | P1 |
| Element gems | sphere | faceted gem, element colour | PROC (low-poly icosphere + shader) | PROC | P1 |
| Prologue staff / Apprentice fire staff | primitives | distinct hero mesh | EA | EA | P1 |

### Gear and pickups
| Item | Current | Target | Source | Src | Pri |
|---|---|---|---|---|---|
| Loot drop (part/gear) | box + beam | small mesh per slot (hat, clothes, belt, shoes, potion, grimoire, wand) on ground | Quaternius/Kenney props (CC0) | EA | P0 |
| Gold / mana / dust / potion auto-pickups | spheres | coin pile, mana orb, dust pouch, flask | Kenney (CC0) | EA | P1 |
| Quest items (Joe's Trash, crystal, map, rusty dagger) | glowing primitive | unique props | EA + PROC crystal | EA | P0 |
| Vault chest | box | chest with lid anim | Kenney/Quaternius (CC0) | EA | P1 |
| Equipped gear on character | not shown | hat + clothes visible (P2) | modular characters | EA | P2 |

### Props and environments
| Area | Current | Target | Source | Src | Pri |
|---|---|---|---|---|---|
| Town Square | Kenney town kit; ground washed out | darker cobble (PavingStones131 re-tiled, triplanar), market stalls, barrier pylon, Landfill gate + guard | Kenney + ambientCG (CC0) | EA | P0 |
| Association hall (interior) | Kenney pieces + greybox | interior walls, summoning circle decal, appraisal crystal, Elder dais, back door | Kenney castle/dungeon kits, ambientCG (CC0) | EA+PROC | P0 |
| Old Oak | Kenney nature tree, small crown | hero oak 3-4x scale with hollow door, interior room, Bob's lab/potion garden slots (later) | Quaternius Stylized Nature (CC0) scaled, or kit-bashed | EA+PROC | P0 |
| Landfill (renamed Midden) | ambientCG first pass | trash piles, junk walls, shrines, Joe's camp, Filth arena ring | Kenney survival/city kits, Quaternius (CC0) | EA | P0 |
| Breach | first pass | dungeon tiles, switches, warden arena | KayKit Dungeon Remastered (CC0) | EA | P1 |
| Level gates / waystones / assembly station / stash | glowing pillars | stone gate arch, rune waystone, forge bench, chest | Kenney/KayKit (CC0) | EA | P1 |
| Arena lock walls | boxes | junk/stone walls rising | PROC from props | PROC | P1 |
| Sky | flat colour | panoramic sky (day/night) | Poly Haven HDRIs (CC0) | EA | P0 |
| Small Town / Dungeons 2-5 | not built (plan-only steps) | later | - | - | P2 |

### UI and icons
| Item | Current | Target | Source | Src | Pri |
|---|---|---|---|---|---|
| HUD frames, buttons, panels | Kenney ui-pack | fantasy-styled theme (parchment/stone) | Kenney Fantasy UI Borders (CC0) | EA | P1 |
| Item/part icons | text/colour squares | icons per slot + rarity frame | game-icons.net (CC BY 3.0, credit) or PROC renders of 3D parts | EA/PROC | P0 |
| Element + status icons | none/text | 6 element + 4 status icons | game-icons.net (CC BY 3.0) | EA | P0 |
| Skill tree icons | placeholders | per skill | game-icons.net | EA | P2 |
| Fonts | default | readable fantasy title + clean body | Google Fonts OFL (e.g. Cinzel + Inter) | EA | P1 |
| Map / bark map / title cards | text | painted-style map texture | PROC | PROC | P2 |
| Steam capsule art / icon | basic icon | capsule images from in-game renders | PROC | PROC | P2 |

## Batches (ordered)
Each batch = one BUILD_PLAN step (119-126).

| # | Step | Batch | One line |
|---|---|---|---|
| A1 | 119 | Archetypes + remote players | Nerd, Loli, real Buff models; colour mask; co-op remote players use archetype models |
| A2 | 120 | Intro NPCs | Elders, guard, scavenger, vendors, other Summoned in cinematics |
| A3 | 121 | Tutorial enemies | Gnawer and The Filth (3 phases + core) |
| A4 | 122 | Staff/wand parts | Modular Handle/Shell/Internals/Head kit with sockets, wands, gems, rarity trim |
| A5 | 123 | Loot, pickups, quest items | Ground meshes per slot, currency pickups, Joe's Trash, crystal, dagger, chest |
| A6 | 124 | Environments pass 2 | Town ground fix, Association interior, hero Old Oak, Landfill dressing, sky HDRIs |
| A7 | 125 | Breach + Storyline enemies | Breach tileset, Scorchling, Warden, mutated rats, garbage golems, ooze |
| A8 | 126 | UI and icons | Fantasy UI theme, fonts, item/element/status icons |

## Acceptance checks (every batch)
- **Scale vs doors:** Kenney door ~2.2 m; humanoids 1.7-1.85 m (Loli ~1.3 m); a scene test asserts every character AABB fits through the Association and Old Oak doors.
- **Texel density:** target ~5.12 px/cm (512 px per metre); props 512-1024 px, characters 1024, hero props (Old Oak, Filth) up to 2048. Checked with a debug texel-density view.
- **Polycount / LOD:** characters <= 15k tris, enemies <= 8k (Filth <= 20k), props <= 3k, staff assembled <= 4k. Godot auto-LOD on for imports; visibility ranges on clutter; MultiMesh for repeated junk.
- **Style:** low-poly stylised, flat/hand-painted palettes matching Kenney + Quaternius; no photoreal mixing except tiled ambientCG ground/rock with tuned albedo.
- **Credits:** every file has a row in `incoming_art/<batch>/CREDITS.md` and `data/credits.toml`; CC-BY items shown in the in-game credits; license check script fails CI on unknown licenses.
- **Perf:** graphical Wayland playtest stays >= 60 FPS on RX 6950 XT; screenshots saved to `playtest/art_<batch>/`.
- **Tests:** `tools/run_tests.sh` and `tools/lint.sh` green; solo + co-op playtests pass.
