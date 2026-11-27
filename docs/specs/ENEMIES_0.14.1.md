# Regular enemies, 0.14.1

Specs taken from the creature sheets. Collision stays the box in `data/enemies/`. The mesh may stand taller than that box when the sheet's silhouette (cap, wings, horns, flame, staff) rises above the face. The face, seam, or core stays on the authored weak point so shots still land. No new names. Bosses are not in this pass.

Heights below are the mesh, feet on y = 0, face toward +Z. A 1.8 m figure is the sheet's scale.

Every mesh is an image-to-3D shape from its cropped sheet, decimated to about 5k–7k triangles, with the sheet baked as a PBR albedo and a thin Idle/Walk rig (foot bones included). The goblin family and Heap are Hunyuan3D-2.1 shapes. The rest are TripoSR shapes from the CPU space `codemaker2015/TripoSR`, because the ZeroGPU quota for Hunyuan and TRELLIS was exhausted. Gnawer plague and the tidal dummy are tints of those shapes.

## Act I (`enemies_act1_warrens.jpg`)

Goblin Grunt. Stocky olive goblin, about 1.42 m to the ear tips. Big pointed ears, heavy brow, underbite tusks, pot belly, short bowed legs, large bare feet. Ragged brown leather: one shoulder strap, a belly plate, bracers, a torn loincloth. Right hand holds a notched rust cleaver. Skin `#5C7A34`, leather `#6B4630`, blade `#8C5A3C`. Weak point is the face.

Goblin Archer. Same family, a little leaner, about 1.38 m to the hood tip. Pointed leather hood, short bow held across the body, a small quiver on the back. Skin a yellower green `#6A8438`, hood and bow `#5C4030`.

Goblin Shaman. Thinner, about 1.32 m to the hood, staff tip near 1.62 m. Tattered purple robe and hood, bone staff with an orange ember head and a small flame. Skin the family green, robe `#6A3A72`, ember `#FF6A1A`.

Gnawer. The sheet labels it: 0.45 m tall, 0.8 m long. Low plated rat, mangy brown-grey, lighter belly, bald snout, long bald tail, small ears. Not the green mutated rat. Plates `#6E6256`, belly `#8A7968`, snout `#C4A090`. A second spawn is the same sculpt, slightly greyer.

## Landfill and the Breach (`enemies_hub_landfill_breach.jpg`)

Heap. A hunched biped of dark rubble, about 2.55 m, no neck, thick hanging arms, root-like feet. A vertical violet crack on the back, which is the weak point. Rubble `#3A332F`, crack `#C080FF`.

Ember Scorchling. A small charred imp, crouched, horned, with a flame mane. Body and flame about 1.05 m. The ember head sits on the weak point. Char `#2A140E`, cracks and flame `#FF6A12`.

Mire Ooze. A moss-green mound, wider than it is tall, about 1.0 m tall and 1.7 m across, with hanging drips, a face pressed into the front, and a puddle. Moss `#4E7A32`, wet highlights `#8AAA55`. Not the olive sludge blob.

Earthen Training Dummy. A humanoid of packed earth and stones, arms at its sides, featureless slit face, about 1.80 m. Ochre `#7A5A32`, crevices darker. The weak point is the top of the head.

Tidal Training Dummy. The same sculpt. Wet blue-grey `#3E5E78`, pale drip edges `#9BB4C4`.

## Act II (`enemies_act2_blightcoil.jpg`)

Spore-cap Husk. Hunched mossy humanoid. The face sits under a wide tan cap with purple spots; the cap is the top of the silhouette, about 2.2 m. Vine skirt, root fingers and toes, open mouth. Body `#4A6A32`, cap `#C2A060`, spots `#7A4A9A`.

Mossbound Treant. Bark-and-moss giant. The face is the weak point; branch antlers and root beard rise above it to about 3.4 m. Long arms, root feet. Bark `#5A4030`, moss `#3E6A30`, eyes dim amber.

Spore Beast. Violet fungal ape, hunched, knuckle-long arms, root feet, glowing eyes, white teeth. Mushroom stalks on the shoulders reach about 2.4 m. The head is the weak point. Flesh `#3A4030`, growths `#7A48A8`, eyes `#E0C0FF`.

## Act III (`enemies_act3_slagworks.jpg`)

Branded Troll. Cracked stone brute, hunched, horns, glowing mouth and belly seams, one fist a spiked lump. About 2.7 m to the horns. The face meets the weak point. Stone `#5A3024`, lava `#FF5A14`.

Forge Construct. Iron-plated furnace golem, not a single cube. Layered chest plates, a glowing open mouth with a lava drip, chimney shoulders, heavy feet, a hanging chain. About 2.9 m. The mouth is the weak point. Iron `#4A4440`, lava `#FF6418`.

## Act IV (`enemies_act4_sunken.jpg`)

Drowned Cultist. One kelp-draped drowned human, crouched and reaching, about 1.85 m to the head and 2.15 m where the coral rises. Barnacles, open mouth, bone claws. Flesh `#8A7A6A`, robe `#2A4558`, coral `#8A4060`. The head is the weak point. The plan's 1.8 m is the body.

## Act V (`enemies_act5_spire.jpg`)

Harpy. Pale grey feathered raptor. The head is the weak point, near 1.4 m; raised wings carry the silhouette to about 2.4 m and a span near 4 m. Crest, hooked beak, talons, a long tail. Feathers `#C8C8C4`, beak and claws `#E8E4DC`.

Storm Elemental. A standing shard of violet crystal wrapped in wind. The bright core is the weak point; shards and ribbons reach about 2.8 m. Crystal `#C8C0E8`, core `#A090E0`, wind `#E8E4FF`.
