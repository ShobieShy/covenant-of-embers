# OW11 performance re-measure (open world walk)

Date: 2026-10-27. Tool: `tools/perf_capture.gd -- <out> --world --res WxH`. A camera walks
Town Square -> Landfill funnel -> Landfill pit -> the Landfill/Breach strip -> Breach at run
speed (7 m/s), 1.7 m above the terrain. It streams cells and nav as the player would, and runs
11,540 frames per preset with vsync off and no fps cap. The raw data is in `docs/perf/perf_ow11_*.json`.

The machine is the dev box (AMD RX 6950 XT, RADV). It was run while Ember QA's suite may also
have been on the machine, so treat the numbers as a ceiling check, not a final measurement.

| Res | Preset | avg fps | 1% low | worst frame | frames > 33 ms | RAM (static) | VRAM |
|---|---|---|---|---|---|---|---|
| 2560x1440 | Low | 1028 | 383 | 4.7 ms | 0 | 229 MB | 273 MB |
| 2560x1440 | Medium | 854 | 374 | 4.6 ms | 0 | 231 MB | 410 MB |
| 2560x1440 | High | 855 | 362 | 4.0 ms | 0 | 231 MB | 410 MB |
| 1920x1080 | Low | 1316 | 476 | 4.1 ms | 0 | 231 MB | 221 MB |
| 1920x1080 | Medium | 1097 | 441 | 3.7 ms | 0 | 232 MB | 325 MB |
| 1920x1080 | High | 1092 | 442 | 3.9 ms | 0 | 232 MB | 325 MB |
| 1280x800 | Low | 1472 | 518 | 6.0 ms | 0 | 230 MB | 190 MB |
| 1280x800 | Medium | 1129 | 489 | 5.2 ms | 0 | 230 MB | 266 MB |
| 1280x800 | High | 1137 | 493 | 4.3 ms | 0 | 230 MB | 266 MB |

The 1280x800 row is from the second run. The first run after the terrain repaint had one
432 ms frame at Low (shader and pipeline compile on a cold cache), and one 10.1 ms frame at Medium.

## Against OPEN_WORLD_PLAN section 10

- High at 60 fps at 1440p: met on the dev GPU, with a lot of headroom.
- Streaming hitch under 8 ms: met on a warm cache (worst frame 4.0 to 6.0 ms). Not met on a cold
  first run: one 432 ms compile stall and one 10.1 ms frame. Shader precompile or warmup behind
  the first-load screen is a follow-up.
- RAM under 3 GB and VRAM under 2 GB: met. Static RAM is about 230 MB. VRAM peaks at 410 MB
  (Medium and High at 1440p).
- Low at 60 fps at 1080p on an integrated GPU, and the Steam Deck at 40 to 45 fps at 800p:
  **not measured**. No iGPU or Deck was available. 1280x800 on the dev GPU is only a stand-in.
  This is the open item before 0.2.0.
- Medium and High are nearly the same in the open world, so the High extras barely show in this scene.
