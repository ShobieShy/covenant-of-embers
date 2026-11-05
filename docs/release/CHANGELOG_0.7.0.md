# Changelog: 0.7.0-prealpha (2026-11-05)

From 0.3.1-prealpha. The build string stayed at 0.4.0-prealpha through the closed-level
work. This cut is Labyrinth Act II. SaveGame stays on version 1.

## Also since 0.3.1
- Closed levels (0.4.0) and a linear flow: Old Oak, town, the Landfill, the Breach, then
  the crater portal into the Labyrinth. One scene per level. Co-op level changes wait on
  a gate vote. The open-world path was removed (0.5.0).
- 0.6.0 trust pass: one Landfill travel row, the Warrens label, a freed body no longer
  ends a gate vote, a dead player cannot take a gate, and a finished vote is not logged
  as cancelled.

## Added
- The Labyrinth, Act II: The Blightcoil. One walkable vertical cavern around the Rotheart,
  in three pads you climb: the Sump, the Canopy Ring, and the Crown.
- Waystones as checkpoints on those pads.
- Act II loot leans Earth and Dark.
- Vines slow you. They do not deal damage.
- The Blightmaw Matriarch, fought in three phases.
- The Verdant Mother, and Joe's marks.
- After the Matriarch: an empty torn cocoon, and a Forge door. The door is a stub. It
  does not load Act III.

## Art
- Ember Art batch_12 is wired in for the cavern props and the Act II creatures.

## Known issues
- Music cues are silent (the slots do not play a file).
- The Forge door is a stub and does not load Act III.
- The Matriarch's authored health is 120, which is low for the fight.
- Her Death animation is not played out.
- Outdoor co-op: the joining game can still exit with code 134 (SIGABRT) while shutting
  down, after the session has ended. Progress is already saved.
- Slabs, the shrine, chests, and fog volumes are still greybox.
