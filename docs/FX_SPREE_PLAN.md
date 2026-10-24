# FX Spree Plan: shaders and FX (PLAN ONLY, waiting on user go)

Planned 2026-10-24. Nothing here is built. Renderer: Forward+ (low preset may use the same renderer with reduced settings).

## Audit summary (current state)
- No `.gdshader` files in the project; everything uses StandardMaterial3D with emission.
- All levels: `tonemap_mode = 0` (Linear), flat ambient colour (`ambient_light_source = 2`), fog on, `fog_sky_affect = 0`.
  Town ambient is 0.70 grey on top of the sun, which flattens and washes out the ground.
- Night cinematic (`intro_director.gd: set_night()`) multiplies sun energy by 0.15 and sets a dark background and
  ambient colour under linear tonemap with no fill light, so the frames come out black.
- Loot beams are translucent cylinders tinted by `rarities.tres`.
- Element colours (data/magic/elements.toml): Fire #FF4D1A, Water #1A66FF, Earth #80591A, Air #CCF2FF, Light #FFF2B3, Dark #4D0080 (Arcane #B3B3B3).
- Rarity colours (Magewar RARITY_COLORS in resources/loot/rarities.tres): Basic #B3B3B3, Uncommon #33CC33, Rare #3366FF, Mythic #9919E6, Primordial #FF9900, Unique #FFD900. Accessibility overrides (step 76) must still apply.

## Items
Pri: P0 / P1 / P2. Test: SS = scripted screenshot set in `playtest/fx_<batch>/`; PERF = 60 s capture with Godot monitors (FPS, draw calls, GPU frame time) at 1440p.

### Spells (six elements)
| Item | Technique | Deps | Pri | Test |
|---|---|---|---|---|
| Shared bolt shader | spatial shader: fresnel core + scrolling noise, element colour uniform; trail via GPUParticles3D (trail mode) | elements.toml colours | P0 | SS per element, PERF with 4 players spamming |
| Fire | flame noise core, ember sparks, impact flash + scorch decal | shared bolt | P0 | SS |
| Water | refractive droplet (screen texture), splash particles | shared bolt | P0 | SS |
| Earth | rock chunk mesh projectile, dust burst | A4 meshes optional | P1 | SS |
| Air | distortion ripple, streaks | screen texture | P1 | SS |
| Light | bright core + god-ray sprites; **Light heal**: green-gold rising motes + ring on healed ally, number popup | ally heal code (t41u) | P0 | SS on ally hit, co-op test |
| Dark | violet smoke trail; **conversion aura**: dark swirl decal + outline shader on converted enemy for 30 s, fade at end | Dark convert code | P0 | SS, co-op both screens |
| Cast / muzzle | viewmodel flash per element, staff head glow | A4 sockets | P1 | SS |

### Status effects
| Item | Technique | Pri | Test |
|---|---|---|---|
| Burn | GPUParticles flames on mesh surface (emission from mesh), red-orange rim | P0 | SS |
| Slow | blue frost overlay (next_pass shader), drifting flakes | P0 | SS |
| Stagger | stars/shock ring + brief hit-stop on the enemy | P1 | SS |
| Chain | arc lines between targets (ImmediateMesh / ribbon with noise shader) | P0 | SS with 3+ targets |

### Hit and death
| Item | Technique | Pri | Test |
|---|---|---|---|
| Hit flash | per-instance shader param flash white 0.08 s | P0 | SS |
| Crit | larger spark + crit number | P1 | SS |
| Damage numbers | Label3D with outline, rarity/element tint | P1 | SS |
| Death | dissolve shader (noise threshold) + particle puff; ragdoll optional P2 | P0 | SS sequence |
| Player hurt | screen-edge vignette shader | P1 | SS |

### Loot beams
| Item | Technique | Pri | Test |
|---|---|---|---|
| Beam by rarity | additive cylinder with vertical scroll + soft edges; height and pulse scale with rarity; Primordial gets swirl, Unique gets rotating rune rings; colours from rarities.tres (Accessibility override respected) | P0 | SS of all 6 rarities side by side |
| Close-range fade | keep existing distance fade, move into shader | P0 | SS at 1 m |
| Ground ring | decal under drop | P1 | SS |

### The Filth
| Item | Technique | Pri | Test |
|---|---|---|---|
| Body wobble | vertex shader noise displacement, wet specular | P0 | SS |
| Acid blobs | projectile shader + GPUParticles drip; acid pool decal with damage area | P0 | SS |
| Regeneration | green pulse inward + healing motes | P0 | SS |
| Phase transitions | shockwave sphere, camera shake, arena wall rise dust | P0 | SS each phase |
| Exposed core | emissive pulsing core, crit highlight | P0 | SS |

### Environment
| Item | Technique | Pri | Test |
|---|---|---|---|
| Lighting baseline | sun + sky ambient (`ambient_light_source = Sky`), SDFGI or LightmapGI-free SSAO + SSIL on high | P0 | SS before/after each area |
| **Fix black night frames** | night = moonlight DirectionalLight (energy ~0.35, blue), ambient from night sky at 0.25-0.4, warm OmniLights at Old Oak door/lanterns, auto-exposure off; do it as an Environment preset swap, not multiplying sun energy | P0 | SS of "That night..." cinematic frames, mean luminance check > threshold in test |
| Fog | volumetric fog in Landfill (green-brown) and Breach; depth fog in town | P1 | SS + PERF |
| Day/night | Environment presets (day, dusk, night) with tween; sky shader or HDRI pair | P1 | SS |
| Water | shader with scrolling normals, depth fade (Landfill puddles, potion garden later) | P2 | SS |
| Sky | PanoramaSky from Poly Haven HDRI (CC0) or ProceduralSky tuned per area | P0 | SS |

### Post-processing
| Item | Technique | Pri | Test |
|---|---|---|---|
| Tonemap | switch Linear -> ACES/AgX, exposure ~1.0 | P0 | SS |
| **Fix washed-out ground** | AgX/ACES + lower flat ambient (use sky ambient ~0.5), SSAO on, re-tune PavingStones albedo/roughness, adjustments contrast 1.05 saturation 1.1 | P0 | SS of Town Square vs old shot |
| Bloom | glow enabled, HDR threshold ~1.0, levels 3-5 | P0 | SS |
| Colour grade | per-area 3D LUT (color_correction): warm town, sickly Landfill, cold Breach | P1 | SS |
| Low preset | no SSIL/SDFGI/volumetric fog, half-res SSAO off, glow 2 levels, FXAA | P0 | PERF |

### UI shaders
| Item | Technique | Pri | Test |
|---|---|---|---|
| Rarity frame shine | canvas_item shader sweep on Mythic+ | P1 | SS |
| Health/mana bars | gradient + damage lag ghost | P1 | SS |
| Low-health pulse | screen vignette | P1 | SS |
| Menu background | animated noise embers | P2 | SS |

### Cinematics and camera
| Item | Technique | Pri | Test |
|---|---|---|---|
| Letterbox | animated black bars (CanvasLayer) on cinematic start/end | P0 | SS |
| Fades / title cards | ColorRect fade + Tween; title card glow | P0 | SS |
| Camera polish | eased Path3D/Tween camera moves, DoF on close-ups, subtle shake | P1 | SS sequence |
| Summoning circle / Bob vortex | shader-driven rune circle + vortex (replace violet torus) | P0 | SS |
| Crystal finale | refraction/fresnel crystal + light burst | P1 | SS |

## Performance budget
- Target RX 6950 XT, 1440p, High: >= 60 FPS (aim 90+), GPU frame <= 11 ms, draw calls <= 2500, active GPUParticles <= 40 systems / 30k particles.
- Per spell effect <= 300 particles; status effect <= 80; loot beam = 1 draw call.
- Low preset: >= 60 FPS on integrated / older GPU target (e.g. Steam Deck class), half particles, no volumetrics.
- Settings menu: Quality preset (Low/Medium/High) + toggles for bloom, SSAO, volumetric fog, particles density.
- PERF capture script `tools/perf_capture.sh` records the Filth fight and a 4-player co-op spam scene.

## Co-op sync concerns
- FX are cosmetic and spawned locally from already-synced gameplay events (cast, hit, status applied, convert, phase change); never send per-particle data.
- Status/convert durations come from host state so both screens end the aura together.
- Random FX variation seeded from event id so screens look alike.
- Light heal FX must show on the healed player's screen and the caster's.
- Cinematic letterbox/fades follow the host-driven intro sync (step 117); joiners mid-cinematic skip FX.
- Graphics presets are per-client and never synced.

## Batches (ordered)
| # | Step | Batch | One line |
|---|---|---|---|
| F1 | 127 | Lighting + post baseline | Tonemap, sky ambient, bloom, SSAO, fixes washed-out ground and black night frames |
| F2 | 128 | Spell shaders | Shared bolt shader and all six elements, Light heal, Dark conversion aura |
| F3 | 129 | Status + hit/death | Burn, slow, stagger, chain, hit flash, dissolve death, damage numbers |
| F4 | 130 | Loot beams | Rarity beams with Bible colours, ground rings, close fade |
| F5 | 131 | The Filth FX | Wobble, acid, regen, phase shockwaves, core |
| F6 | 132 | Environment pass | Fog, day/dusk/night presets, sky, water, per-area colour grade |
| F7 | 133 | Cinematics + UI shaders | Letterbox, fades, camera polish, summoning circle, vortex, crystal, UI shine/bars |
| F8 | 134 | Perf + presets + co-op check | Quality presets incl. Low, perf capture, co-op FX parity test |
