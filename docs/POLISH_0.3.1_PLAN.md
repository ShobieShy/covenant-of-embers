# 0.3.1 Polish Round (plan only)

Status: DRAFT, awaiting approval. Requested 2026-10-28 ~08:05 CDT (t102u: "UX improvements
and general UI and gameplay animations and fluidity. Stuff that smooths rough edges.").
Build P1 onward only after 0.3.0 (Labyrinth Act I) ships. No new content, no balance
changes, no save-format changes: 0.3.1 is feel, clarity and flow only.

## 1. What the audit found (read-only, at 0dd5859)

Sources: scripts/ui/*.gd, scripts/player/camera_feel.gd, scripts/audio/game_audio.gd,
scripts/labyrinth/*, scripts/net/labyrinth_sync.gd, the l3 playtest screenshots, the
0.2.0/0.3.0 changelogs and the earlier plans (PLAN.md "Feel", FX_SPREE_PLAN.md).

- **Almost nothing animates in the UI.** Only 3 scripts use a Tween (interior_fade,
  loading_screen, viewmodel). Every panel (pause, inventory, skills, vendor, station,
  fast travel, map, dialogue, co-op menu) pops in and out by setting `visible`.
- **The co-op stairs vote has no UI.** labyrinth_sync.gd `gate()` only `print()`s
  "waiting for the party at the stairs"; players see nothing, no countdown, no who-is-missing.
- **Dialogue is bare:** text appears all at once, no typewriter, no portrait, no
  "press E" prompt, no open/close fade; the box hides instantly on end.
- **Fast travel is a plain button list** ("Teleportation Crystal" + Close) separate from
  the world map screen; no map preview, no confirm, no travel transition beyond the load.
- **Stairs are a CSG box + Label3D** that fire on touch: no prompt, no confirm, easy to
  trigger by accident while fighting near them.
- **No music** (the Music bus exists, "Music has no track yet"). Several sounds are
  borrowed placeholders (e.g. "enemy_death" is a heavy metal impact, "cast" and
  "brand_crystal_set" share glass_002), no UI hover/open/close sounds, no stairs,
  chest, level-up, shrine or loot-rarity cues.
- **Inventory trash** works (Rare+ confirm row) but has no undo, no hold-to-confirm, and
  the confirm row appears in place without focus moving to it on gamepad.
- **Feel is solid at the core** (head bob, landing dip, step smoothing, recoil, shake,
  reduced-motion switch, damage numbers, hit/crit/kill markers) but missing: enemy hit
  reactions beyond a flash, FOV kick on dash/sprint, pickup magnet/arc, loot beams by
  rarity, a level-up moment, death/respawn transition.
- **Loading and transitions:** interiors fade, but fast travel, stairs and death use hard
  cuts into the loading screen; loading tips are static.
- **Lobby/co-op:** coop_menu is functional but has no join progress states, no
  "host is loading" feedback on the joiner, and party frames don't animate damage.

## 2. Principles

- Every animation is short (0.12-0.3 s), skippable, and obeys the existing reduced-motion
  setting (fade instead of slide/scale; no shake/FOV kick).
- One shared helper (`UiAnim`: open/close/pulse/shake/count-up) so panels don't each
  roll their own tweens. Gamepad focus always lands somewhere visible.
- Headless/test safety: tweens are skipped (instant) when `DisplayServer` is headless,
  so the suite timing and SafeLoad path are unchanged.

## 3. Items by priority

Size: S = under half a day, M = about 1 day, L = 2 days.

### High (rough edges players hit every session)

| # | Item | Problem | Fix | Size |
|---|---|---|---|---|
| H1 | Stairs vote UI | Co-op vote is log-only | Banner "Waiting for party 7 s" + names of who is missing, on host and joiners; cancel when all arrive; sound tick on last 3 s | M |
| H2 | Stairs interaction | Touch-to-descend triggers mid-fight | Prompt "E: go down" with 0.5 s hold; proper stair mesh from the Warrens kit; glow pulse | S |
| H3 | UI open/close motion | Every panel pops | `UiAnim` helper: fade+8 px slide in 0.15 s, fade out 0.1 s; apply to pause, inventory, skills, vendor, station, map, fast travel, dialogue, co-op | M |
| H4 | Dialogue flow | Instant text, no prompt | Typewriter (skippable with Interact, 1st press completes, 2nd advances), "E" continue arrow, speaker name colour per NPC, fade in/out | M |
| H5 | Transitions | Hard cuts on fast travel, stairs, death | Reuse interior_fade for every scene change: fade to black, loading screen, fade in once ground_now() is true | S |
| H6 | Music pass | Silent game | Ambient loops per area (town, overworld, Warrens) + boss track with crossfade on the Music bus; volume slider already exists | M |

### Medium (feel and feedback)

| # | Item | Problem | Fix | Size |
|---|---|---|---|---|
| M1 | Enemy hit reactions | Hits only flash | Short flinch (scale punch / knockback lean), stagger on crit, death dissolve or ragdoll-lite instead of pop | L |
| M2 | Pickups | Items just vanish | Magnet pull + arc, rarity beam/colour on drops, rarity sound pitch, pickup toast stack in HUD | M |
| M3 | HUD bars | Bars jump | Trailing "damage chip" bar on health/shield/boss, smooth fill, low-health heartbeat vignette | S |
| M4 | Level-up / unlock moment | XP line only | Banner + burst + sound, skill-point badge on HUD and pause menu "Skills" entry | S |
| M5 | Casting feel | Cast sound shared, little anticipation | Distinct per-element cast sounds, small muzzle flare, FOV kick on dash (0 under reduced motion) | M |
| M6 | Inventory/trash UX | Confirm row lacks focus, no undo | Focus moves to "No" by default, hold-to-trash on pad, 5 s "Undo" toast for the last trashed item, hover tooltips animate in | M |
| M7 | Fast travel | Button list | Open the world map screen in travel mode (pins clickable, confirm card with region + level band); keep list as fallback | M |
| M8 | Skill trees | Static nodes | Hover scale, purchase pulse along the path, refund confirm, points-left counter animates | S |

### Low (nice to have)

| # | Item | Problem | Fix | Size |
|---|---|---|---|---|
| L1 | Menus | Instant main menu | Title fade-in, button hover sound + nudge, save-slot cards with playtime / location | S |
| L2 | Lobby/co-op | Silent waiting | Join states (connecting, loading, in world), joiner "host is loading" overlay, party frame damage chip | S |
| L3 | Loading screen | Static tips | Rotating tips (Labyrinth, brands, co-op), progress smoothing, Act art backdrop | S |
| L4 | Damage numbers | Overlap in crowds | Stack/merge per target in 0.2 s, crit scale pop | S |
| L5 | Camera | No death/respawn camera | Slow fall + desaturate on death, short rise on respawn | S |
| L6 | Audio UI set | No hover/open/close/chest/shrine cues | Fill the missing keys from Kenney CC0 packs already in the repo | S |

## 4. Steps

| # | Step | Items | Estimate |
|---|---|---|---|
| P1 | UiAnim helper + headless skip + panel open/close everywhere; transitions | H3, H5 | 1.5 days |
| P2 | Labyrinth flow: stairs prompt + vote UI (host and joiner) | H1, H2 | 1.5 days |
| P3 | Dialogue polish | H4 | 1 day |
| P4 | HUD feedback: chip bars, level-up, damage numbers, pickups | M2, M3, M4, L4 | 2 days |
| P5 | Combat feel: hit reactions, casting, camera death/respawn | M1, M5, L5 | 3 days |
| P6 | Menus: inventory/trash, skill trees, fast travel on the map, main menu, lobby, loading tips | M6, M7, M8, L1, L2, L3 | 3.5 days |
| P7 | Audio: music loops + crossfade, missing UI/world cues | H6, L6 | 1.5 days |
| P8 | Ember QA pass, screenshot diff, full suite, 0.3.1 changelog and release | all | 1 day |

Total: about 15 days. A "high only" cut (P1, P2, P3, P7 music, P8) is about 6.5 days.

## 5. Art and audio needs (Ember Art; CC0, CC-BY with in-game credit, or original)

- Music: 4 loops (town, overworld, Warrens, Goblin King boss), 1-3 min, seamless.
  First choice original from Ember Art; otherwise CC0 (e.g. OpenGameArt CC0 tag).
- SFX: per-element cast (6), chest open, shrine use, stairs, level-up, rarity pickup
  (3 tiers), UI hover/open/close, vote tick. Kenney CC0 packs cover most; new ones go
  into docs/credits.
- Art: Warrens stair mesh, loot beam texture, typewriter "continue" arrow, chip-bar
  style, 3-4 loading backdrops (Act I). Add to docs/EMBER_ART_REQUESTS.md under "0.3.1".
- No Borderlands assets; style reference only.

## 6. Testing

- Unit tests per step: UiAnim (instant under headless and reduced motion), vote UI state
  (countdown, missing names, cancel), stairs hold prompt, typewriter skip/advance,
  trash undo, chip bar math, music crossfade bus state.
- tools/ui_shots.gd, menu_shot.gd, skills_shots.gd, trash_shots.gd, loading_shot.gd re-run
  for before/after screenshots each step (mid-animation frames captured too).
- Playtest bots (solo labyrinth, co-op labyrinth, open world) must stay green: the stairs
  hold prompt needs the bot to hold Interact; the vote UI must not change the gate logic.
- Ember QA: manual-feel checklist per step (gamepad-only pass, reduced-motion pass, co-op
  vote with a lagging joiner). Full suite only at P4 and P8 milestones, as now.
- GPU check: tween and particle cost on the integrated-GPU target once allowed.

## 7. Open questions (recommended defaults)

1. Scope: full round (~15 days) or high-priority only (~6.5 days)? Default: full, ship the high cut early as 0.3.1 and the rest as 0.3.2 if it runs long.
2. Stairs: hold Interact to descend instead of touch? Default: yes, 0.5 s hold, and the vote still runs in co-op.
3. Dialogue typewriter speed? Default: 45 chars/s, setting to make it instant.
4. Music source: original from Ember Art, CC0 fallback? Default: yes.
5. Fast travel moves into the world map screen? Default: yes, keep the list as a fallback tab.
6. Trash undo window? Default: 5 s, last item only, local only.
7. Enemy death: dissolve shader vs. quick sink-and-fade? Default: sink-and-fade (cheaper on Deck).
8. FOV kick on dash/sprint? Default: on, +4 degrees, off under reduced motion.
9. Should animations affect the playtest bots' timing? Default: no, headless skips all tweens.
10. Release cadence: polish lands after 0.3.0 ships and before Act II? Default: yes.
