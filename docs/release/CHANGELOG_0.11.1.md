# Changelog: 0.11.1-prealpha (2026-11-20)

Eldoria grows into a hub. Co-op protocol stays 7.
The in-game build string is `0.11.1-prealpha`. The menu name is Pre-Alpha 0.11.1.
SaveGame stays on version 1. Windows is unverified. The Core stays closed.

## 0.11.1

- The town ring is about 320 m across. The paved square is 120 m. North, south, and east roads reach the gates. The west arc is a cliff. A straight sprint from the north gate to the south gate is about 45 seconds at 7 m/s.
- The ground outside the streets is a Terrain3D heightmap: hills, a shallow moat, rock outcrops, grass cards (instanced, no collision, faded at 50 m), and grass/rock/cobble blending. The dome is the sky. Four purple ward stands mark the square. There is no crystal mesh in the tree yet.
- Kenney `rock-large.glb` still stands in for the cliff face. A thin safety wall sits at the far edge of the heightmap, behind that cliff.
- The playtest bot sprints on open ground longer than 24 m. Breath still cuts the sprint off.
- Town `map_version` is 3. An older town save arrives at the waystone.
