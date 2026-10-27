# Changelog: 0.2.0-prealpha (2026-10-27)

From 0.1.4-prealpha. Steps OW1 to OW11 in docs/build_state.json.

## Added
- **Open world (now the default).** Old Oak, Town Square, the Landfill (Midden) and the Breach
  are one continuous Terrain3D world, laid out west to east as in docs/WORLD_LAYOUT.md. The 1 m
  grid has 70 regions, and 64 m transition strips join the zones. `--classic-levels` falls back
  to the old level flow.
- Cell streaming: 128 m cells on threaded loads. Enemies sleep beyond 96 m of every viewer.
  The navmesh is baked offline per cell.
- Instanced interiors (the Mage Association and the Breach rooms) with a fade and a slow-load overlay.
- Waystone fast travel inside the world. It streams the destination behind the loading screen
  and is refused during combat.
- World map screen, fog of war (saved, and merged in co-op) and a rotating minimap.
- A first-load loading screen when you enter the world.
- The intro (prologue and all 13 beats) runs in the open world.
- Co-op in the open world: a 400 m leash (warning at 300 m), the host's fast travel pulls
  joiners along, and joiners share the host's intro enemies.
- Perf tooling: `tools/perf_capture.gd --world` walks Town to the Landfill to the Breach.
  Results are in docs/perf_ow11.md.

## Changed
- Terrain paint (OW11 polish):
  - Zone strips blend into a shared transition material: mud between Eldoria and the Landfill,
    ash between the Landfill and the Breach, grass between Old Oak and Town. The edges are
    broken up with noise, and there's no seam at the midline.
  - Landfill paths are muddy rubble with feathered edges. The flat tan squares are gone.
  - Mud patches now break up the Landfill's flat rubble.
- Shaders warm up behind the first-load screen, so the first walk into the Landfill no longer
  hitches on a cold cache (was about 400 ms). `tools/perf_cold.sh` captures cold-cache perf.
- The Arena walls also drop when the Filth dies.
- Tightened the breach loft geometry (annex stair), so the loft stays on the navmesh.

## Fixed
- Co-op: the joiner now follows the host's fast travel, and world enemies are shared during the
  host's intro, so the joiner no longer stalls.
- Co-op shutdown is clean (Coop.end is re-entrant, and the bots end the session before quitting).
  Known issue: the joiner process can still exit with code 134 at teardown after a successful
  run. The test harness accepts it only after PASS and prints a warning.
- Freed-RID errors when the loading screen or interiors were freed in the middle of a threaded load.
- Material-null errors on headless, from a Godot 4.7.2 dummy-renderer race. SafeLoad loads
  synchronously on headless.

## Saves
- 0.1.4 saves load. Migration only adds fields (progress.world_pos, region, fog, world_v=2;
  level_id is kept). SaveGame.VERSION is unchanged.
