# Step 134 perf capture (FX F8)

`tools/perf_capture.gd` - 1280x800, vsync off, FPS cap lifted, stress load: 8 gnawers with
burn / frost / Dark-ally aura, a summoning circle, a spell impact burst every 6 frames.
300 frames after a 60-frame warm-up. Raw numbers: `docs/perf/perf_134.json`.

Captured on PC Luna (RX 6950 XT, Forward+). **Not a Steam Deck measurement** - the Deck target
(60 fps at 1280x800, 40 fps floor, Low preset) still needs an on-device run.

| Preset | Level | avg ms | avg fps | 1% low fps |
|---|---|---|---|---|
| Low | midden | 0.60 | 1658 | 627 |
| Low | breach | 0.64 | 1552 | 575 |
| Low | town_square | 0.64 | 1553 | 589 |
| Medium | midden | 0.77 | 1293 | 579 |
| Medium | breach | 0.77 | 1305 | 606 |
| Medium | town_square | 0.85 | 1180 | 575 |
| High | midden | 0.89 | 1120 | 515 |
| High | breach | 0.92 | 1091 | 502 |
| High | town_square | 0.87 | 1153 | 559 |

Low costs ~30% less frame time than High here (SSAO, volumetric fog, glow, shadows off;
particles halved; burst cap 12). The Deck GPU is roughly 1/10-1/12 of this card, which
puts Low around ~6-8 ms/frame by rough scaling - inside the 16.7 ms budget, unverified.
