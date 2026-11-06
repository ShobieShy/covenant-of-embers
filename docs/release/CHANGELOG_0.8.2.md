# Changelog: 0.8.2-prealpha (2026-11-06)

From 0.7.0-prealpha. 0.8.0 and 0.8.1 were never released. This cut is everything
since 0.7.0: Act III, the linear path, and the Landfill tutorial. SaveGame stays
on version 1.

## Added
- The Labyrinth, Act III: The Slagworks. Floors 9 to 13. Forgemaw is the boss on
  the last floor. Waystones send you home and keep the floor you left.
- After the Matriarch, the Crown door opens the Railhead. Lava, furnace heat,
  carts, and falls spend health only.
- Forgemaw is fought in three phases. He does not heal between them, and the
  arena does not lock.
- The Scrap-spirit, on the Overlook.
- After Forgemaw: an empty slag cast, and a door toward the Sunken Ruins. That
  door does not load the next act.

## Changed
- A new game starts in the Mage Association. The open-world terrain is gone.
- Town Square is the walled square again. The vendors, the doors, and the Flagon
  work.
- The Landfill is named The Landfill on the level, the map, the waystone, and
  the save card. The Breach keeps its own name.
- The Breach quest continues after Bob. Beating the Filth opens the north road
  and starts the quest: go to the Breach, enter the Labyrinth, face the
  Matriarch.
- The Landfill is a tutorial trash valley, walked south to north: the entry
  dump, the compactor, the deeper rot, the Filth bowl, then the north road into
  the Breach.

## Fixed
- The wounded scavenger lies on open ground by the Light shrine and has dialogue.
  Light still stands him up. The lines are a placeholder.
- Moss beds lie flat on the platforms.
- Bob is a haggard old wizard. That model is a placeholder until his own file
  lands.
- Staff casts and impacts play short tonal placeholders.

## Known issues
- Music cues are silent. The Blightcoil and Slagworks slots do not play a file.
- The staff sounds, Bob's model, and the scavenger's lines are placeholders.
- The Matriarch's authored health is 120, which is low for the fight. Her Death
  animation is not played out.
- The door after Forgemaw does not open the Sunken Ruins.
- Acts II and III are still separate stretches, not one continuous run through
  the Breach labyrinth. Acts IV and V are not built (#30).
- Still to do: picking up items and parts from a distance (#22), crouch jumping
  onto objects (#23), and richer enemy attacks (#24).
- Co-op: the joining game can still exit with code 134 (SIGABRT) while shutting
  down, after the session has ended. Progress is already saved.
- In the Blightcoil, slabs, the rest shrine, chests, and fog volumes are still
  grey boxes. The Slagworks is greybox until its art lands.
