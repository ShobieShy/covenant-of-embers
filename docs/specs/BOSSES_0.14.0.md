# Boss hero meshes (0.14.0)

Specs taken from the creature sheets in `docs/concepts/creatures/` before the meshes were built. Hitboxes stay the sizes in `data/enemies/`. The mesh is the sheet's silhouette, palette and scale next to a 1.8 m figure. Names stay as they are. No new bosses.

Each body is one skinned mesh (hips, spine, chest, head, arms, legs, feet) with Idle, Walk, Run, Attack, HitReact and Death. Phase nodes start hidden and turn on with the existing phase numbers. They do not change health, speeds, or collision.

The mesh is a closed sculpt. The sheet is the reference for scale, silhouette and palette. It is not projected or extruded onto the surface, so the sides and the back are the same volume as the front.

## The Filth

Landfill boss. A heap of slime, not a humanoid. About 5.5 m to the crown of the mound and wider than it is tall, next to a 1.8 m scavenger. The hitbox stays 2.2 × 2.0 × 2.2 m.

Shape: a slumped cone with a cave mouth in the front, drips along the lip, barrels, bags, planks and cans stuck in the sludge. The base spreads into trash. Phase 1 is the closed heap. Phase 2 adds more scrap (`Phase2_Debris`) for the regen. Phase 3 opens the mouth on a yellow-green spiral core (`Phase3_Core`).

Materials: wet olive slime, dull rust and burlap, a soft yellow emission in the cavity. Palette: #5c6a28 slime, #3a4218 shadow, #c6a24a barrels, #d6e25a core.

## Breach Warden

Crater vault boss. A rubble-and-slag colossus, hunched, no neck, fists like broken slabs. Drawn about 6.4 m beside the 1.8 m figure (the sheet's 2.8 m mark is on the scale bar, not the top of the head). The hitbox stays 1.8 × 2.8 × 1.8 m.

Shape: wide shoulders, short legs, a gap under the arms, drips of slag. The back carries a vertical violet seam (`WardenEye`). Phase 2 (`Phase2_Enrage`) brightens the cracks when health is at half. The enrage still only changes speed and slam timing in `warden.gd`.

Materials: dry cracked stone, matte, with a violet emission in the seams. Palette: #2a2230 stone, #4a3a55 mid, #b06cff seam.

## The Goblin King

Act I boss. A bulky green goblin, 2.45 m to the crown spikes, a little taller than the 1.8 m figure and much wider. The small human and 1.3 m goblin on the sheet are a scale legend, not a second pose. The hitbox stays 1.6 × 2.4 × 1.6 m.

Shape: heavy belly, short legs, long arms, tusks, spiked pauldrons, a ragged leather tunic, a crowned head, a spiked mace in the right hand. The crown is its own mesh (`Crown`) and still hides on death for the drop. Phase 2 (`Phase2_Enrage`) is the roar: the eyes heat up. Throw, Slam and Roar clips stay on the rig.

Materials: leathery green skin, worn brown hide, tarnished iron. Palette: #6a8a3a skin, #5a4630 leather, #8a7a55 metal, #c2a15a crown.

## Blightmaw Matriarch

Act II boss. A vine-and-fungus brute, about 5.4 m to the mushroom caps, standing over a 1.8 m figure. The hitbox stays 2.2 × 3.4 × 2.2 m.

Shape: a huge open maw, a heart-shaped chest maw, clawed arms, root legs, purple mushroom shelves on the back. Phase 1 is the body, caps included (the sheet's "spores and husks"). Phase 2 shows the back spines (`Phase2_Spines`). Phase 3 shows the glowing heart (`Phase3_Heart`) and still opens the weak point in code. No arena lock.

Materials: wet bark, moss, fleshy maw, violet fungus emission. Palette: #3d4a28 bark, #6a3050 maw, #c46a98 heart, #7a4ad0 caps.

## Forgemaw

Act III boss. A molten brute, about 5.8 m, hammer in one hand and tongs in the other, lava underfoot. The hitbox stays 2.4 × 3.2 × 2.4 m.

Shape: heavy gut, horned head, lava cracks, a square forge hammer, open tongs, spikes down the back. Phase 3 (`Phase3_Core`) is the chest core opening when the rings fall. The gantry and lava strips stay the floor's job.

Materials: cooling slag skin, bright cracks, dark iron tools. Palette: #6a3020 hide, #ff5a18 cracks, #2a2422 iron, #ffb040 core.

## Drowned Choir

Act IV boss. One body. Many singers sculpted into a single mass, about 5.0 m from the pool to the tallest kelp, beside a 1.8 m figure. The hitbox stays 2.2 × 2.8 × 2.2 m. No extra actors.

Shape: robed drowned bodies fused in a column, coral crowns, kelp plumes, a violet knot of light in the middle, water at the waist. Phase 1 is the surfaced form. Phase 2 (`Phase2_Water`) raises the water and the violet arc when `submerged` is set. The fight script is unchanged.

Materials: soaked cloth, coral, kelp, glowing water. Palette: #1e4a55 cloth, #d07068 coral, #6a8a40 kelp, #c080ff arc, #1a6a88 water.

## Storm Warden

Act V boss. A cloaked stone-and-crystal giant, about 4.8 m to the crystal crown, wrapped in wind. The hitbox stays 2.0 × 2.6 × 2.0 m. The sheet says the outline is approved and the floor caption is not a name.

Shape: a hood of violet crystals, a tattered grey cloak, one crystal pauldron, clawed hands, white wind ribbons. There is no separate brain phase. `Phase2_Gale` adds more ribbons under half health and does not change movement or damage.

Materials: layered stone cloth, sharp crystal, additive wind. Palette: #8a8494 stone, #b9a6e8 crystal, #f2f4ff wind, #7a5ad8 glow.
