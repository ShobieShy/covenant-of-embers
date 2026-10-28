# Changelog: 0.3.0-prealpha (2026-10-28)

From 0.2.0-prealpha. Steps L1 to L5 in docs/build_state.json.

## Added
- The Labyrinth, Act I: the Goblin Warrens. Enter through the Breach crater gate and go down
  five floors: four generated from the Warrens room kit (seeded per save, so a floor is the
  same when you come back) and the Goblin King's throne hall on floor 5.
- Rest shrines on every floor (heal, save, respawn point, crafting), stairs up and down, and
  floor progress kept in your save (old saves load with an empty Labyrinth).
- The Goblin King: rock throw, ground slam and a roar that calls in grunts.
- Act I loot: item levels rise with depth, secret-room chests a tier above the floor, and
  bigger drop chances with more players.
- Co-op: the host's floor decides; the party goes down the stairs together.

## Fixed
- Leaving the Breach rooms no longer drops you through the ground outside. Terrain collision
  now follows the player when no camera is active, and it is rebuilt as soon as you leave an
  interior or arrive from fast travel (commit 6d748e2, regression test
  tests/unit/test_breach_ground.gd).
- Co-op: a teammate standing in your line of fire no longer soaks your bolts. Only Light
  bolts stop on a teammate (to heal them); every other bolt flies through to the enemy
  behind (regression test tests/unit/test_bolts_teammate.gd).

## Known issues in earlier versions
- **0.2.0: falling through the ground outside the Breach.** When you leave the Breach rooms,
  the crater floor outside can have no collision yet, so you fall through the world. This is
  fixed in 0.3.0 (see Fixed above).

## Known issues
- Co-op: the joining game can exit with code 134 (SIGABRT) while shutting down, after the
  session has ended. Progress is already saved; nothing is lost.
- The first Labyrinth floor you enter can hitch once (about 60 ms) while its shaders compile.
