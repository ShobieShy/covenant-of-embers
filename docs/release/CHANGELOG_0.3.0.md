# Changelog: 0.3.0-prealpha (DRAFT, not released)

From 0.2.0-prealpha. Steps L1 to L5 in docs/build_state.json.

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
