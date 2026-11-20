# Layout specs from the paintings: every remaining level
Written by Luna from docs/maps/levels/*.jpg (Nov 20 2026) for ShobieShy. Same method and rules as LEVEL_SPEC_TOWN_LANDFILL.md:
the painting is the spec; build over an un-squashed underlay; no greybox or primitive placeholders; real CC0 PBR materials and meshes (or Ember Art); a top-down overlay at 50% must line up within ~5% (outline, paths, landmarks); 3 player-height shots; and you review your own renders before shipping. Coordinates are normalized to the painting (x 0 = west, 1 = east; y 0 = north/top, 1 = south/bottom).
For the CUTAWAY paintings (Act I, Act II, Act IV partly, Spire), the image is a vertical section: each painted tier is one FLOOR or elevation band. The overlay test applies to each floor's plan against that tier's shape and contents, plus a side-elevation render against the whole painting.
Acts keep the existing 5-floors-per-act and hybrid generation. Handmade landmark rooms, the boss floor and the transitions must match the painting. Generated filler rooms must use the act's kit, materials and props, never greybox.

## MAGE ASSOCIATION (association.jpg), ~200 m grounds
- A walled ROUND-cornered enclosure (low stone curtain wall with pointed-cap towers) on grassy rolling hills.
- Entrance: south (0.50, 0.85). The cobbled path from the Town comes up to a gothic gatehouse with big double doors at (0.50, 0.75), then steps up into the Great Hall.
- Great Hall: center (0.50, 0.30-0.75). A gothic cathedral nave with blue-slate roofs, two front spires and two rear spires, rib vaults and tall stained glass. Wooden reading tables and benches fill the floor. A large glowing blue SUMMONING CIRCLE is inlaid on the floor at (0.50, 0.50), and the dais with steps and the great stained-glass window are at the north end (0.50, 0.25).
- Library Wing: a long east wing (0.70-0.90, 0.25-0.65), attached along the hall's east side. Two-storey bookshelves, reading tables and a blue roof.
- Courtyard Garden: west, outside the hall (0.10-0.35, 0.30-0.80). Trees, grass, a three-tier fountain at (0.20, 0.58), all inside the curtain wall.
- North: closed by the wall and hills (the back door that opens toward the Landfill, if it exists in lore, stays as data only).
- Look: warm interior candlelight against the blue arcane glow. Exterior is golden-hour.

## OLD OAK and BOB'S LAB (bobs_lab.jpg)
Exterior (in the Town's east lobe, matching the Town spec):
- A giant oak with glowing violet rune carvings running up the trunk. Big amethyst crystals cluster in the roots on both sides. An arched wooden door sits in the trunk base.
- A fenced herb and mushroom garden in front (giant red-cap mushrooms on the left, a flower patch and blue mushrooms on the right). A stone arch gate signed toward the East Gate, with a cobbled path to the door.
Interior (separate level):
- Ground floor: an organic round hollow with root-bark walls. A wooden SPIRAL staircase runs up the west/center. Workbenches, barrels, jars and lanterns.
- Upper floor: the alchemist's laboratory. A stone slab table in the center, potion shelves on the west wall full of colored bottles, a workbench with bubbling violet cauldrons to the east, hanging lanterns, and a pinned parchment map on the north wall.
- Walls are curved living wood, not boxes. There should be no tree crown poking through walls.

## THE BREACH (breach.jpg), ~260 m crater
- A huge ELLIPTICAL crater with stepped rock walls and violet crystal clusters around the rim. A narrow walled ENTRANCE HALL corridor enters from the south (Landfill Road, 0.50, 0.95 -> 0.50, 0.75).
- Central sunken ring (0.50, 0.45), with THE LABYRINTH GATE: a carved stone portal with a violet light column, on a raised plinth ringed by a shallow moat path.
- Chambers arranged ring-like around the center, each a sunken rocky room linked by paths:
  - GNAWER DEN at SW (0.22, 0.65), with bones and nests.
  - EMBER GALLERY at W (0.15, 0.45), lit orange with embers.
  - OSSUARY at NW (0.30, 0.25), a bone room.
  - WARDEN ARENA at N (0.50, 0.15), a ruined pillar ring around a circular floor with an arch at the back. This is the Breach Warden boss.
  - THE VAULT at NNE (0.62, 0.20).
  - BELL LOFT at NE (0.75, 0.25), a violet-lit pit.
  - CRATER APPROACH at ENE (0.70, 0.38), a path.
  - RELIQUARY at E (0.82, 0.42).
  - SWITCH ROOM at E/SE (0.78, 0.58), with standing stone pillars.
  - MIRE CISTERN at SE (0.70, 0.78), a green water pool.
- Flow: entrance hall -> side chambers loop around the ring (switch room opens the way) -> Warden Arena -> the Labyrinth Gate opens -> into Act I.

## ACT I: THE GOBLIN WARRENS (act1_goblin_warrens.jpg), 5 floors + throne
Vertical cutaway, top to bottom = floor 1 to the boss:
- F1 "Descent from the Breach": a timber-shored entry gallery with a big wooden roof frame, barrels and crates, goblin lookouts and torches.
- F2 "Ambush Rooms": a row of round earthen rooms linked by short tunnels, with timber props and wooden spike barricades.
- F3 "Spike Traps" + "Gnawer Nests": a central trap room with green-glowing ward totems and spike pits. To the east are gnawer nest burrows with bones. Joe's chalk graffiti is in the west room (ignore the garbled painted label).
- F4 "Green Fire Wards": tunnels lined with green-flame ward pots and torches.
- F5 "Joe's Graffiti": a big red painted "Joe's Graffiti" wall plaque landmark, with side rooms.
- Boss "Throne Hall": a large ellipse with a stepped bone-and-spike throne pyramid in the center. Stacked stolen Association crates (blue-glow sigils) stand on the left and right, with violet crystals in the corners.
- Exit "Roots to the Blightcoil": a root-choked tunnel under the throne.
- Materials: packed earth, timber, torch-lit orange with green ward accents.

## ACT II: THE BLIGHTCOIL (act2_blightcoil.jpg), three tiers around the Rotheart
- One huge cavern with three elevation bands linked by a spiral root path. The ROTHEART (a giant corrupted tree) stands at the center axis and spans all tiers.
- Entry "From the Warrens": a ruined stone wall/gate at the top center (0.50, 0.12).
- Top band, THE CROWN: the Rotheart's canopy with fungal shelves and giant mushrooms (west and east), violet crystals, drifting spore fog, and Joe's marks carved in the bark. The Blightmaw Matriarch fights here. The EMPTY COCOON is a torn glowing pod in the trunk at (0.50, 0.45).
- Middle band, CANOPY RING: a root-bridge ring around the trunk over two dark-green hollows (west and east). The CANOPY SHRINE is a small clean shrine at the trunk base, with the Verdant Mother beside it. Stairs/roots spiral down on the west.
- Bottom band, THE SUMP: a poison mire with yellow-green pools in two lobes (west and east) with root islands. The DOOR TO THE SLAGWORKS is at the bottom center (0.50, 0.95).
- Follow the act story's flow order (the painting places the Crown at the top; if the act flow climbs from the Sump to the Crown, the entry should reach the Sump first: keep the story order and the painting's spatial layout).
- Materials: bark, moss, roots, wet mud, bioluminescent fungus, violet crystal, fog volumes.

## ACT III: THE SLAGWORKS (act3_slagworks.jpg), ~240 m cavern
- A huge ROUND cavern with terraced rock walls. Rails spiral around the walls in descending loops.
- Entry "From the Blightcoil": a mine tunnel at the NW top (0.17, 0.12). The rails descend clockwise from there.
- FURNACE-ANVIL: a towering conical furnace at N-center (0.42, 0.25), with a molten glowing mouth and smoke stacks. This is the landmark visible everywhere.
- CRUCIBLE ARENA: NE (0.65, 0.30), a round two-ring stone arena with a molten pool center and a gantry ring. This is the Forgemaw fight.
- MAIN LIFT: center (0.52, 0.47), a stone-and-iron lift tower.
- FORGE CONSTRUCT/ORE areas: W-center gantry platforms (0.35, 0.42). ORE VEINS along the N walls. ORE CHANNEL (lava river) down the E wall (0.85, 0.50). LAVA CHANNELS along the W walls (0.18, 0.55).
- SLAG CAST: a bottom-center sunken pit (0.50, 0.75) holding an EMPTY humanoid-shaped mold in cooling slag (a hollow, not a solid figure).
- Exit "Door to the Sunken Ruins": a stone door at the bottom center (0.50, 0.92).
- Materials: dark basalt, iron rails and gantries, emissive lava with heat haze, ore veins, warm orange light.

## ACT IV: THE SUNKEN RUINS (act4_sunken_ruins.jpg), ~240 m flooded complex
- A ROUND sunken complex of flooded stone galleries in terraced rings, knee-to-waist deep water (with swim zones), and coral (orange/red/violet).
- Entry "From the Slagworks": an arch at the bottom center (0.47, 0.90).
- CORAL GALLERIES: SW arcade (0.25, 0.80), an arched colonnade over water.
- AIR-BELL SHRINES: NW (0.15, 0.30) and W (0.15, 0.60), arched alcoves with hanging bronze bells (breath refills).
- DROWNED TEMPLE SPIRE: center (0.43, 0.48), a gothic shrine-spire with a glowing violet doorway. This is the landmark.
- CULT MURALS: E (0.75, 0.48), a long mural wall of the choir with a stone tablet.
- HYMN VAULTS: SE (0.70, 0.80), with a stone tablet/book vault.
- CHOIR NAVE: NE (0.70, 0.20), a pillared nave with pews and a cracked CORAL SARCOPHAGUS (cracked from within), where the Drowned Choir fights. Water level animates.
- SHAFT TO THE SPIRE: N-center (0.50, 0.12), a vertical shaft with wind and falling water. This is the exit.
- Materials: wet stone, coral, caustics, murky teal water, violet glow.

## ACT V: THE INVERTED SPIRE (inverted_spire.jpg), vertical void
- A cylindrical void cavern. The ceiling is a painted FALSE STARRY SKY (violet nebula with stars).
- THE INVERTED SPIRE: a gothic tower hanging UPSIDE DOWN from the ceiling at the center, tapering downward to a point above the Middle Platform. It needs a real mesh (inverted cathedral). This is the landmark.
- Floating rock platforms with violet/pale-blue crystal clusters are linked by glowing CRYSTAL BRIDGES (light ribbons) and drops:
  - HIGH PLATFORMS on the left and right walls at the top.
  - MIDDLE PLATFORM at center (0.50, 0.65), with a violet light column falling from the spire tip.
  - LOW WARDEN FLOOR at bottom center (0.50, 0.85), a wide platform for the Storm Warden fight.
- HARPY NESTS on side ledges (E side).
- Wind corridors are shown with particle streaks.
- Materials: dark stone, emissive crystal, star sky, fog falloff into the void.
