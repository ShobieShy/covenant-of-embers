# Intro and tutorial plan (New Game -> world open)

Planned 2026-10-24. **Plan only: nothing here is built yet.** BUILD_PLAN steps 109-118 implement it.
Source: `~/game/Magewar Storyline.md` (Prologue: The Summoning / Welcome to ? Town / A New Home; Chapter 1: Bob?)
and `~/game/Magewar Bible.md` (locations). Dialogue lines below are placeholders taken from
`data/story/dialogue.toml`, which was ported from the Storyline. New lines are marked *(new)*.

## What happens today
- `GameFlow.new_run` drops a fresh character straight into `midden` (the Landfill), with the fire staff and the wind wand already equipped.
- `Prologue` (step 64, `scripts/story/prologue.gd`) has the beats summoning -> expulsion -> grant -> welcome_to_town -> a_new_home, but **nothing calls it** (`main.gd` never makes one).
- `MentorArrival` (step 66) only plays if you walk to the Old Oak and `home_unlocked` is set. Nothing on the normal path sets that flag.
- The quests in `data/story/quests.toml` (a_new_home -> the_landfill -> report_to_bob) and `QuestDriver` (step 67) work, but nothing walks the player through them in order.
- Every exit is open from the start: the Town Square already has `to_landfill`, `to_old_oak` and `to_association`.
- Fast travel (step 68) is already gated on `fast_travel_crystal` + `tutorial_done`. That part is kept.

## Shape
One linear path through 4 locations (~15-20 min):
**Association hall -> Town Square -> Old Oak (night) -> Association back door -> Landfill -> Filth arena -> back to the Old Oak.**
An `IntroDirector` owns the beat index (saved as the flag `intro_beat:<id>`) and drives the systems that already exist.
Each beat lists: **where / trigger / cinematic / objective (tracker text + marker) / gated / unlocks / reuses + new**.

Cinematic rules (step 110):
- A cinematic is a short camera path: 2-4 keyframes, eased, with letterbox bars and the HUD hidden. Player input is frozen.
- Dialogue boxes show over the letterbox.
- **Skip:** hold Esc/Start for 1 s. The first run can skip too (recommended, see Q19).
- A skipped cinematic still applies its flags and gear.
- Saving is off during cinematics. The autosave checkpoint is at the start of each beat.

---

### Beat 1 - The Summoning (Mage Association, grand hall)
- **Trigger:** New Game (from the menu, after the slot is picked). The hall loads with `intro_beat:summoning`.
- **Cinematic (skippable):** fade in from black onto a glowing ritual circle. The camera dollies down from the hall ceiling while robed mages gasp and the circle flares, then cuts to first-person as the player stands.
  - Joe *(from joe_summoning)*: "*mumbles incoherently* ...interdimensional echoes... forgotten gods..." / "Ah! The ritual worked! You're actually here!"
- **Objective:** none (flows into beat 2).
- **Gated:** all exits (the front-door gate is dormant), the pause menu's Save, inventory, skills, the map and fast travel.
- **Reuses:** the `mage_association` level, Joe's `Npc`, `DialogueRunner`/`DialogueUI`. **New:** `IntroDirector`, `CinematicCamera` + `Letterbox`, a ritual-circle prop (CSG + emissive, like the vortex).

### Beat 2 - Appraisal = character creation (same hall)
- **Trigger:** the end of the beat 1 cinematic.
- **Cinematic:** Joe holds up the appraisal crystal and the camera faces it. The **character creator opens as the crystal's readout**: archetype (Nerd/Gal/Buff/Loli), name and colour, the same data as the step 73 picker.
  - On confirm, Joe *(from joe_summoning)*: "...well, the appraisal crystal says you're 'underwhelming.' But I KNOW you have potential!"
- **Objective:** "Let the crystal read you". The UI is modal and can't be skipped (you need a character).
- **Unlocks:** applies `new_identity` (the existing `_apply_new_identity`) and sets `identity_chosen`.
- **Reuses:** `Archetype`, the step 73 picker logic (lifted out of `main_menu.gd` into a shared `CharacterCreator` control). **New:** the crystal framing. The main menu's New Game no longer shows the picker; it goes straight to beat 1. The co-op client's new-character flow keeps the menu picker (see Co-op).

### Beat 3 - Expulsion (same hall)
- **Trigger:** `identity_chosen`.
- **Cinematic (skippable):** Elders step in (silhouette NPCs, placeholder capsules). The camera cuts between the Elders and Joe. Joe is marched out through the **back door**, which slams behind him. This plants the back door for beat 7.
  - Joe *(from joe_summoning)*: "Unfortunately, my colleagues didn't appreciate my... initiative. They expelled me. 'Reckless,' they called it. ME! After three centuries!" / "Check the landfill. Find what's causing it."
  - Elder *(new)*: "The Summoned stay. The Association will... provide."
- **Reuses:** the Prologue `expulsion` narration. **New:** an Elder NPC prop and a back-door gate node (`LevelGate`, locked).

### Beat 4 - The Grant (same hall)
- **Trigger:** the end of beat 3. A clerk NPC walks up (or is already standing at the front desk).
- **Cinematic:** none. This is a normal talk.
  - Objective: **"Speak to the Clerk"**, with a marker over the clerk.
  - Lines reuse Joe's grant lines, spoken by the clerk *(retargeted)*: "Fifty gold. It's not much..." / "...the Old Oak... Edge of town. Big dead tree. Here's the residency permit."
- **Unlocks:** 50 gold, `basic_clothes`, `permit_given`. The front door (`to_town`) opens. The back door stays locked: "Staff only. By order of the Elders." *(new)*
- **New objective:** **"Leave the Association"**, with a marker on the front door.
- **Reuses:** the Prologue `grant` beat, `StoryFlags`, gold (step 61). **New:** the clerk speaker and dialogue entries, and the `locked_text` prompt on `LevelGate`.

### Beat 5 - Welcome to ? Town (Town Square)
- **Trigger:** the player arrives in `town_square` while `intro_beat:welcome`.
- **Cinematic (skippable, ~6 s):** an establishing pan over the square (fountain, stalls, the barrier shimmer above) that ends behind the player. The title card reads "Eldoria" *(Storyline "? Town"; Bible name)*.
- **Objective:** **"Find the Old Oak at the edge of town"** (the existing `a_new_home` quest, which auto-starts on `permit_given`). The marker sits on the `to_old_oak` exit.
- **Optional (not tracked):** talk to the townsfolk; the guard, merchant and patron "pity" lines already exist. Shops can be browsed with the starting 50 gold.
- **Gated:**
  - `to_landfill`: the Bored Guard blocks it. *(new)* "Barrier edge. Summoned don't go out there without say-so."
  - `to_association`: open, but there is nothing to do inside; the back door is still locked.
  - The waystone is visible but dormant: "It hums. You don't know how to use it." *(new)*
  - Fast travel and the world map stay locked (already true).
- **Reuses:** the town_square level, NPCs, vendors and `QuestTrackerUI`. **New:** the guard gate block, the dormant waystone text, and a world-space objective marker.

### Beat 6 - A New Home, then night (Old Oak)
- **Trigger:** `reach old_oak` (completes `a_new_home`; rewards XP and `old_oak_unlocked`).
- **Objective:** **"Rest on the moss bed"**, with a marker on `moss_bed_1`. Interacting sets `home_unlocked`.
- **Cinematic (skippable):** fade to black, then "That night..." The lighting swaps to night (darker ambient, candles). The `MentorArrival` vortex opens and the camera cuts to the vortex as Bob steps out.
  - Bob *(from bob_intro)*: "...Who are you? Why are you in my tree?" / "Name's Bob. This is my home. You lot are squatting." / "*examines you with a glowing orb*" / "You're weak now. Pathetically so..."
  - The existing choice "Why should we help you?" / "We'll go." stays.
- **Unlocks:**
  - `bob_met`, `starter_gear_given`: a mana potion, plus the **starter weapon** (see Q18; recommended: Bob hands over the fire staff here instead of giving it at spawn, plus the rusty dagger as a key item that glows in danger).
  - Bark map: the world map UI opens, but only the town is shown.
  - The stash opens. `the_landfill` quest auto-starts.
- **Gated until this beat:** the inventory and skills screens (you have nothing yet). Save is enabled from here on; this is the first manual-save point.
- **Reuses:** `MentorArrival` (already does the vortex, the flags and the potion), `Stash`, `bob_intro`. **New:** the moss-bed interact, a night lighting preset, the "That night..." card, and the gear hand-off moved from spawn to Bob.

### Beat 7 - The back door (Old Oak -> Town Square -> Association -> Landfill)
- **Trigger:** `starter_gear_given`.
- **Objective:** **"Go to the landfill"** (the existing objective). The text grows to "Go to the landfill - through the Association's back door".
  - The markers chain: Oak exit, then the square's `to_association`, then the back door.
  - Bob's added line *(new)*: "Association's back door opens on the landfill. Joe's been dumping through it for years. Tell the clerk I sent you."
- **Unlocks:** `landfill_route_open` lets the Association back door (a new `[[exit]] to_landfill` in `mage_association.toml`) take you to `midden`. The Town Square `to_landfill` gate stays guarded until beat 12 (Q20).
- **Optional cinematic:** none; the clerk only barks "Bob? ...Fine. Go." *(new)*
- **Reuses:** `LevelGate`, `GameFlow.travel`, the quest `reach landfill`. **New:** the gate's `requires_flag`, and a chained marker for the next exit.

### Beat 8 - Combat lesson (Landfill entrance)
- **Trigger:** arriving in `midden` with `intro_beat:landfill`.
- **Cinematic (skippable, ~4 s):** a pan over the heaps as rats skitter. Mid-screen hint card.
- **Objective:** **"Clear the Gnawers (0/3)"** (existing). Timed hint toasts appear in order:
  1. Cast (LMB).
  2. Dash / dodge.
  3. Mana: watch the bar, drink the potion when low (the potion from Bob).
  4. Swap weapon (if two are held).
- **Gated:** an invisible wall (`ArenaLock` reused as a soft wall) keeps the player in the entrance yard until 3 Gnawers die. Only Gnawers spawn here (a scripted small `Encounter`, not the full wave spawner).
- **Unlocks:** the first part drops (guaranteed). The wall drops.
- **Reuses:** `Encounter`, `ArenaLock`, `XpRewarder`, `HUD`. **New:** a `TutorialHints` toast queue keyed to input actions (shows the bound key).

### Beat 9 - Crafting lesson (Landfill, Joe's dump camp)
- **Trigger:** picking up the guaranteed part (`collect`).
- **Objective:** **"Fit the part at Joe's workbench"**. The marker sits on the Assembly Station, which moves from "beside the start" to a camp spot in the Landfill.
- **Hint toasts:** E opens the station; drag the part in; the compare card shows the stat change.
- **Gated:** the path to the arena is blocked by a junk wall until a part is fitted (`crafted_once`).
- **Reuses:** `AssemblyStation`, `StationUi`, the compare cards. **New:** a station marker in the level TOML, plus the `crafted_once` flag emitted by StationUi.

### Beat 10 - Light and Dark (Landfill, past the junk wall)
- **Trigger:** `crafted_once`.
- **Setup:** two shrines (glowing sludge puddles, CC0 emissive) each give a scripted tutorial part.
  - **Light lesson:** a wounded scavenger NPC (or the co-op ally) sits here. "Hit them with Light to heal them." This shows Light's heal; there's a toast noting Light hits enemies slightly weaker.
  - **Dark lesson:** a lone Gnawer. "Dark sometimes turns an enemy." The first Dark hit in the tutorial is **forced** to convert (a one-time `tutorial_force_convert` flag), so players actually see it, then a toast: "Normally ~1 %. Dark parts raise it."
- **Objective:** **"Learn Light (heal the scavenger)"**, then **"Learn Dark (turn the Gnawer)"**. Either shrine order is fine.
- **Gated:** the arena gate opens after both (`light_learned`, `dark_learned`).
- **Reuses:** `MagicEffects` (step 108 Light heal / Dark convert), `WieldablePart.DARK_BONUS`. **New:** the shrine props, the scavenger NPC (with a Health but no AI), the forced-convert hook, and two objectives (a new `use` objective kind, or `talk`/`collect` with flags).

### Beat 11 - The Filth (Landfill arena)
- **Trigger:** entering the arena volume.
- **Cinematic (skippable, ~5 s):** the arena walls rise (`ArenaLock`). The camera tilts up the mound as The Filth heaves out of the trash. A name card reads "THE FILTH". The cinematic returns control on the boss roar.
- **Objective:** **"Defeat The Filth"** (existing), with the boss health bar.
- **Gated:** the arena is locked (existing). Death respawns at the beat 11 checkpoint (the arena entrance), not the level start.
- **Unlocks:** `joes_discards` drop. The walls drop.
- **Reuses:** The Filth boss, `ArenaLock`, the boss bar. **New:** the intro cinematic and the checkpoint respawn.

### Beat 12 - Joe's Trash, then home (Landfill -> Old Oak)
- **Trigger:** `collect joes_discards` completes `the_landfill` (rewards `filth_defeated`, XP, dust).
- **Objective:** **"Bring the samples to Bob"** (existing `report_to_bob`). The markers chain back via the back door (or the now-open town gate, see Q20).
- **Unlocks on leaving:** the guard opens the town `to_landfill` gate: "Heard you cleaned out the dump. Go on then." *(new)*
- **Reuses:** the quest chain, the gates and the markers.

### Beat 13 - Bob? / the crystal; the world opens (Old Oak)
- **Trigger:** talking to Bob with `filth_defeated`.
- **Cinematic (skippable):** Bob works at his bench. The camera pushes in on the crystal forming, with a sparkle burst.
  - Bob *(bob_after_filth)*: "Hmm? You defeated The Filth? That's... surprisingly competent." / "Joe's madness has its uses..." / "There. A Fast Travel Teleportation Crystal." / "...welcome to Elyria, Summoned. Try not to break anything I can't fix."
- **Unlocks:**
  - `tutorial_done`, `fast_travel_crystal` (existing). The Oak waystone attunes automatically, and the town/landfill waystones attune if visited.
  - The full map and all menus; every gate is ungated; Breach is reachable.
  - `intro_done` is set; the director removes itself.
  - Optional plan-only step 106 (basic skills unlocked here).
- **End card:** "Prologue complete - Chapter 1: Bob?". After it, the tracker shows the next open quests (or "Explore Elyria").
- **Reuses:** `FastTravel`, `FastTravelUi`, `WorldMapUi`, `bob_after_filth`. **New:** the crystal cinematic and the end card.

---

## Co-op: a client joining mid-intro
The options were:
- **(A)** Block joining until the host has `intro_done`.
- **(B)** Shared intro: host-authoritative beat, clients ride along.
- **(C)** Clients join and get a post-intro world.

**Recommended: B.**
- **Host is in charge.** The host's `IntroDirector` owns the beat. It sends a `beat` message (and the flags), and clients mirror the gates, markers and tracker text. Level changes already follow the host (`travel` message, step 79).
- **Joining during a cinematic:** the client waits on a "Joining... (the party is in a cutscene)" card until it ends, then spawns beside the host.
- **Joining after a cinematic:** the client sees a one-line recap card ("Summoned, expelled, given a tree. Now: find the Old Oak.").
- **Cinematics** play on everyone's screen. A skip needs the host (or a majority vote, see Q22).
- **Beat 2 (character creation)** is per-player. A client with no character file makes one in the co-op menu picker (as today), so it never sees the crystal.
- **Rewards and flags.** Gear hand-offs (Bob's starter kit, the crystal) are granted to every player present. A client who missed them gets them on arrival if the host is past that beat.
- The client's character file records `intro_done` when the host finishes. A client who is already past its own intro is never re-gated in its own game.
- **Lessons (beats 8-10)** complete when anyone finishes them. Light's scavenger can be another player.

## Saves
- **Mid-intro saves:**
  - The beat is stored in story flags (`intro_beat:<id>`). Continue loads that beat's checkpoint level and position, never mid-cinematic.
  - Before beat 6, saving is disabled (Continue instead restarts the summoning). Optional: autosave at each beat start.
- **Saves made before this feature:**
  - A save with `tutorial_done` (or `filth_defeated`, or player level >= 3, or any non-intro level) is marked `intro_done`, and nothing changes.
  - A save with none of those still sits in the old spawn-in flow. It gets a one-time prompt on load: "Play the new intro?" Yes starts at beat 5 with the character kept. No marks `intro_done` and grants the crystal flags only if `filth_defeated` is set.
  - The migration lives in `SaveGame.apply` and is tested.
- **Skipping on later New Games:** once any slot has `intro_done`, New Game offers "Skip prologue". This jumps to beat 13's end state: Bob's kit, the crystal, `tutorial_done`, spawn in the Old Oak. `--skip-intro` does the same for playtests and tests.

## Open questions
- **Q17/Q18 Rusty dagger and starter weapon.** There is no melee system. Options:
  - (a) A key item that glows when enemies are near (Storyline flavour), with the staff as the real weapon.
  - (b) A low-tier wieldable "Rusty Dagger" reskin of a wand.
  - (c) A real melee weapon (a new system).
  - Also: should the fire staff and wind wand still be given at spawn, or only by Bob? Recommended: (a), with Bob giving the staff.
- **Q19 Skippable cinematics on the very first playthrough?** Recommended: yes (hold to skip).
- **Q20 Landfill route.** Is the Bible's "Back Door: Landfill?" confirmed as the intro path? Should the town gate stay guarded until the Filth dies?
- **Q21 Joe at the summoning.** Joe is the summoner per the Storyline; does he stay visible through the grant, or is the clerk new? Does Joe show up later in the Landfill (flavour)?
- **Q22 Co-op skip.** Can only the host skip cinematics, or does it need a majority vote?
- **Q23 The other Summoned in solo.** The Storyline has four Summoned (Nerd/Gal/Buff/Loli). In solo, are the other three silent NPCs in the cinematics, or absent?
- **Q24 Landfill enemies.** Should the tutorial use the existing Gnawers, or wait for plan-only step 103 (mutated rats and garbage golems)?
- **Q25 Skip prologue on later New Games.** OK to offer it (recommended), or should every new game play the intro?
- **Q26 The Midden name.** Rename the Landfill level from "The Ashen Midden" to "The Landfill" everywhere visible?
