# 0.3.2 plan: per-player level scaling + co-op polish (plan only, nothing built)

Status: draft for ShobieShy, written 2026-10-28 at 0a44992. Ships as 0.3.2, after 0.3.1.
Part A is level scaling (sections 1-12), part B is co-op polish (sections 13-15), and
section 16 is the combined step list.

# Part A: per-player enemy level scaling

Goal (Borderlands style): one enemy shows and fights at level X for a level-X player and
at level Y for a level-Y player in the same co-op session. Solo should feel the same as
today at matching levels.

## 1. What exists today

- `EnemyDef.level` (enemy_def.gd:16, 1..50) is a fixed per-type number. It feeds **only
  drops**: `DropRoller.roll_kill(.., def.level, ..)` (extra part at >= 3) and gold
  (`gold_drop` -1 = 3 x level). Enemy health and damage do **not** scale with level today;
  they come straight from `max_health` and the AI table (`contact_damage`, etc.).
- `Enemy.level()` returns `level_override` (Labyrinth floor band from `ActLoot`, e.g. Act I
  5 / 7 / 9 / 10, King 12) or `def.level`. `LootDropper` uses it.
- `Enemy.health_scale` is the co-op multiplier (+60 % per extra player,
  `CoopWorld.HP_PER_EXTRA_PLAYER`); `max_health() = def.max_health * health_scale`.
- Co-op is host-authoritative: the host simulates enemies and sends 20 Hz snapshots with
  absolute `health` and `max_health()` (`CoopWorld.snap_row`); a client's hit is predicted
  on its puppet and sent to the host as an absolute amount (`"hit"`, `amt`), and the host
  calls `apply_damage(amt)`. Bites on a remote player go to the owner as `"hurt"` with an
  absolute `dmg`.
- Loot and XP are already per-peer: each peer's own `enemy_killed` rolls its own drops and
  XP (`XpRewarder`, PLAN §30.2). Step 70's Resolve catch-up gives a low player bonus XP.
- Player power grows with level only through mana/Breath (+5 each) and gear/skills; spells
  have no per-level damage term.

## 2. The model

Each enemy keeps one **base** definition, authored at a reference level `L0` (its
`EnemyDef.level`, unchanged). Each peer resolves an **effective level** for itself:

    eff_level(peer) = clamp(local_player_level + offset, 1, 50)

where `offset` is the enemy's tier bonus (elite +1, boss +2, Labyrinth floor offset, see
§7–8). Scaling is a pure function of level in a new `LevelScale` class:

    hp_mult(L)   = growth ^ (L - L0)      default growth_hp  = 1.09
    dmg_mult(L)  = growth ^ (L - L0)      default growth_dmg = 1.07
    xp(L)        = xp_reward * xp_curve(L) / xp_curve(L0)

If player power stays flat per level (today), exponential enemy growth would make every
level-up feel worse. So the scaling goes **with** a matching player term (§3) and the net
effect at "same level" is 1.0: an enemy at your level always takes the same number of
hits and hurts the same fraction of your health, whatever the level.

## 2b. Stat-by-stat scaling table (every EnemyDef stat and subtype tunable)

ShobieShy: all enemy stats scale with level. This audit covers every stat in the code
at 0cce536. "Scales" means multiplied by `LevelScale.mult(curve, L - L0)`, then capped.
`L0` is `EnemyDef.level`. Movement and AI timings stay fixed by default (flagged as Q9).

Curves (in `LevelScale.CURVES`, tuned in S8):
- **hp**: `1.09^dL`, cap x60 at level 50.
- **dmg**: `1.07^dL`, cap x25.
- **res**: `+0.005 * dL` added to a resistance, capped by the existing 60 % applied cap.
- **xp**: `xp_curve(L)/xp_curve(L0)`, Magewar's level curve, cap x40.
- **gold**: `3 x L`, or `gold_drop x 1.06^dL` when authored, cap x20.
- **thr**: same as hp, so a hit that broke the threshold at L0 still breaks it at a
  matching level.
- **fixed**: not scaled.

### EnemyDef (enemy_def.gd)

| Stat | Today | Scales? | Curve / cap | Note |
|------|-------|---------|-------------|------|
| id, display_name | data | no (identity) | - | |
| affinity | element | no | - | the element never changes |
| max_health | 1..100000 | yes | hp, x60 | also x co-op health_scale, x ELITE_HEALTH |
| level | 1..50 | is L0 | - | becomes the base level |
| xp_reward | 0..10000 | yes | xp, x40 | per peer at its own level |
| gold_drop | -1 / 0..100000 | yes | gold, x20 | per peer |
| size, color | visuals | no | - | |
| resist{} | 0..1 per element | yes | res, 60 % applied cap | small, so gear stays meaningful |
| has_weak_point, weak_point_offset, weak_point_size | geometry | no | - | the x2 multiplier stays x2 |
| ai{} | see RusherDef | per key | below | |

### RusherDef ai keys (rusher_def.gd RANGES)

| Key | Scales? | Curve / cap | Note |
|-----|---------|-------------|------|
| attack_damage | yes | dmg, x25 | the core enemy-to-player damage |
| knockback_threshold | yes | thr | otherwise a high-level enemy staggers on every hit |
| attack_cooldown | no (default) | - | attack rate; Q9. If yes: `0.99^dL`, floor x0.7 |
| attack_windup | no (default) | - | readable telegraphs; Q9 |
| detect_range, aggro_range, attack_range, min_range | no | - | AI geometry |
| walk_speed, sprint_speed, turn_rate_deg | no (default) | - | movement; Q9 |
| knockback_strength, knockback_time | no | - | this is what it does to the player |
| projectile_speed | no (default) | - | dodgeability; Q9 |
| flee_below | no | - | already a fraction |
| kind | no | - | brain choice |

### Subtype and brain constants

| Constant | Scales? | Curve / cap | Note |
|----------|---------|-------------|------|
| Elites: BASE_CHANCE, PER_TIER | no | - | spawn odds |
| Elites: ELITE_HEALTH x1.5, ELITE_XP x2 | no (these multiply scaled values) | - | the elite offset (+1 level) covers it |
| GoblinKing THROW_DAMAGE 14 | yes | dmg, x25 | |
| GoblinKing THROW_MIN/MAX, THROW_COOLDOWN, ROCK_SPEED/HIT/LIFE, ROAR_S, THROW_FALLBACK | no (default) | - | timings and geometry; Q9 |
| Filth REGEN_PER_S 4 | yes | hp, x60 | regen in HP has to keep pace with HP |
| Filth PHASE_2_AT/3_AT, BLOB_*, REGEN_DELAY, CORE_GROW | no | - | fractions, geometry, timings |
| Warden PHASE_2_AT, ENRAGE_SPEED, ENRAGE_TEMPO | no | - | fractions and tempo (Q9) |
| Ooze SPLIT_COUNT, SPLIT_SCALE | no | - | split health = SPLIT_SCALE x scaled max |
| Ooze PUDDLE_SLOW 0.6, PUDDLE_TIME 6, PUDDLE_RADIUS | no (default) | - | status strength on the player; Q10 |
| Scorchling EMBER_HIT/LIFE, Gnawer HUNT_TIME, BITE_HEIGHT, separation etc. | no | - | AI and geometry |
| Enemy BURN_TICK, FLASH_TIME, statuses received | no | - | statuses the player puts on enemies follow player stats |
| Projectile and blob damage (Scorchling ember, Filth blob = attack_damage) | yes | dmg, x25 | through attack_damage |

### Stats that don't exist on enemies today

Armor, shields, mana, a cast rate separate from attack_cooldown, status chance and
duration on enemy attacks (only the ooze puddle slow exists), crit and accuracy: enemies
have none of these. If any is added in 0.3.2 or later, it must get a row in
`LevelScale.TABLE` (the coverage test below enforces that). The defaults if added:
- armor: res-style, additive with a cap.
- shield: hp curve.
- mana: fixed.
- status chance: `+0.2 %/level`, cap +10 %.
- status duration: fixed.
- crit chance: fixed.
- accuracy: fixed.

### Coverage test (fast tier): `tests/unit/test_level_scale_coverage.gd`

- Lists every script variable of `EnemyDef` (via `get_property_list()`, filtered on
  PROPERTY_USAGE_SCRIPT_VARIABLE).
- Lists every key in `RusherDef.RANGES` plus `kind`.
- Lists every numeric constant of each enemy subtype script (Elites, GoblinKing, Filth,
  Warden, Ooze, Scorchling, Gnawer, Heap, Enemy), via `get_script_constant_map()`.
- Fails, with the stat's name, if any of these has no entry in `LevelScale.TABLE`. Every
  entry is `{"scale": curve_id}` or `{"fixed": reason}`.
- Fails if a TABLE entry names an unknown curve or a stat that no longer exists, so
  nothing stale is left behind.
- Checks that every curve hits 1.0 at dL 0 and respects its cap at levels 1 and 50.

So a new stat added to any enemy without a scaling decision breaks the fast tier.

## 3. Damage, both ways

Key idea: the host keeps everything in **normalised units** (fractions of base), and
each peer converts at its own level.

- **Player -> enemy.** A peer's hit amount is computed locally as today, then divided by
  that peer's `hp_mult(eff_level(peer))` before it goes to the host
  (`"hit"` gets `amt_norm`). The host applies `amt_norm` to the base-scale enemy. So a
  level-30 player and a level-5 player each kill a same-level enemy in the same number of
  hits, as long as player damage scales with level by the same curve (§3 player term).
- **Player damage term.** Add `LevelScale.player_dmg_mult(level) = growth_hp^(level-1)` to
  spell damage (one place: `Damage.compute` / the caster's base damage). Without it a
  high-level player would be weaker than today against scaled foes. (Question Q2.)
- **Enemy -> player.** The host routes a bite with base `dmg`; the owner multiplies by
  `dmg_mult(eff_level(owner))` and its own player-level mitigation (`"hurt"` carries base
  damage plus a flag `norm: true`). The local solo path does the same.
- DoTs, chain/blast/orb hits (`MagicEffects.puppet_hits`) and heals on puppets go through
  the same normalise step.

## 4. Health and its sync model

Two options:

**A. Shared HP percentage (recommended, default D1).** The host holds one health pool in
base units (`def.max_health * health_scale`). Snapshots already carry health and max;
clients display `fraction * max_health_at(eff_level(me))`. Everyone sees the same bar
fraction; numbers above it are local-scale. Pros: one authority, no desync, the death is
one event, minimal net change (send fraction or keep sending base pair). Cons: a
low-level player's raw number contribution is "worth" the same share as a high one only
if damage is normalised as in §3 (it is).

**B. Per-peer HP.** Each peer has its own pool for the enemy; it dies separately for each
peer. Pros: fully independent. Cons: the enemy is dead for one player and alive for
another (Borderlands does not do this), puppets diverge, kills/loot timing gets messy,
snapshot size grows with party. Not recommended.

Co-op party scaling (+60 % per extra player) stays as a multiplier on the base pool.

## 5. XP and loot per player

- XP: each peer computes `xp(eff_level(me))` in `XpRewarder` from its own level. Resolve
  catch-up (step 70) then compares to the party's highest level as today; with scaling,
  the gap bonus can shrink or go (Q5).
- Loot: `LootDropper` uses `eff_level(me)` instead of `enemy.level()`. Drops are already
  per-peer instanced, so each player gets gear for their own level. Gold (3 x level)
  follows the same level.

## 6. Nameplate level

There is no enemy nameplate level today (party frames show player levels; the HUD boss
bar shows a name). Add "Lv N" to the boss bar and (when nameplates land) to enemy
plates, from `eff_level(local)`. Elite/boss offsets show as the higher number. Different
peers seeing different numbers is the intended behaviour.

## 7. Solo

Solo is the one-peer case: `eff_level = player_level + offset`. Open-world zones then
stop having a fixed difficulty. Option (Q3): keep a per-zone **floor** (minimum level)
and only scale up, so early zones stay easy for a high-level character but never under
the zone's band ("level floor" vs pure Borderlands "always your level").

## 8. Bosses and Labyrinth floors

- Bosses: offset +2 (Q4), plus any phase thresholds stay as fractions (warden PHASE_2_AT,
  filth, ooze split) so they work unchanged with scaled HP.
- Labyrinth: today `level_override` is the floor's item level band. Under scaling,
  replace it with an **offset by depth** (floor 1 +0 ... King +2) on top of the player's
  level, keeping the band as a minimum item level so Act I rewards are not below today.

## 9. Save compatibility

No save-format change and no `SaveGame.VERSION` bump. Player level is already saved;
enemy levels are never saved (they are resolved at spawn/hit time). `EnemyDef.level` keeps
its meaning as the base level `L0`. Old saves load as today.

## 10. Tests

Fast tier (unit):
- `test_level_scale.gd`: hp/dmg/xp curves, clamp 1..50, same-level hits-to-kill equals
  today's numbers at L0, offsets for elite/boss/floor.
- normalise round trip: a level-30 hit sent as `amt_norm` and shown back at level 30.
- `test_enemy.gd`: health/damage at L0 unchanged (golden numbers stay).
- loot/XP: `LootDropper` and `XpRewarder` use the local effective level.
- boss phase thresholds fire at the same fraction at levels 1, 25 and 50.
Co-op (full tier; not while QA runs co-op):
- two fake peers at levels 5 and 30 hit one enemy: one host pool, the same fraction on
  both screens, one death, each peer rolls its own loot level.
- a bite on each peer lands at that peer's scaled damage.
- old-protocol peer: reject with the existing compat check (bump the co-op protocol
  version, not the save version).

## 11. Scaling steps and estimates

| # | Step | Est. |
|---|------|------|
| S1 | `LevelScale` pure class + TABLE for every stat (2b) + coverage test + unit tests | 0.75 d |
| S2 | Effective level resolver per peer (solo, elite/boss/floor offsets) | 0.5 d |
| S3 | Enemy health/damage through `LevelScale` in solo (and player damage term) | 1 d |
| S4 | Co-op: normalised hits/bites/heals, client display at local level, protocol bump | 1.5 d |
| S5 | XP and loot at the local level; Resolve catch-up review | 0.5 d |
| S6 | Boss bar / nameplate "Lv N" | 0.25 d |
| S7 | Labyrinth: depth offsets + item level floor | 0.5 d |
| S8 | Balance pass with the playtest bot (hits-to-kill, time-to-die by level) + full tier and co-op run | 1 d |

About 6 days in total. Each step lands with a fast-tier run and the full tier at S4 and S8.

## 12. Scaling defaults and questions for ShobieShy

1. D1: shared HP percentage (§4 A)? Default yes.
2. Should player spell damage scale with level (needed for "same level feels the same")?
   Default yes, the same curve as enemy health.
3. Solo zones: pure "always your level", or keep a zone minimum level? Default: keep the
   zone minimum, scale up only.
4. Offsets: elite +1, boss +2, Labyrinth floor 1..King +0..+2? Default yes.
5. Keep Resolve catch-up XP once enemies scale? Default: keep it, but only for party level gaps.
6. Growth rates 1.09 HP / 1.07 damage per level? Default yes, tuned in S8.
7. Co-op party health bonus (+60 % per extra player) unchanged? Default yes.
8. Do level-1 players in a level-50 friend's game see level-1 enemies (pure Borderlands)?
   Default yes. That is the point of the feature.
9. Movement and AI timings (walk/sprint speed, turn rate, attack cooldown and windup,
   projectile speed, boss throw and enrage timings) stay fixed by level? Default yes: no
   scaling, so fights stay readable. If no, attack cooldown would be `0.99^dL`, floor x0.7.
10. Status effects enemies put on players (the ooze puddle slow and time) stay fixed?
    Default yes.
11. Resistances grow +0.5 % per level, under the 60 % applied cap? Default yes.
12. Caps at level 50: health x60, damage x25, XP x40, gold x20? Default yes, tuned in S8.

# Part B: co-op polish

## 13. What is rough today (from the code and the QA and build history)

1. **Joiner exit crash (rc 134).** The joiner aborts at engine teardown with
   "corrupted size vs. prev_size" or a double free, after its bot has PASSed. It has
   been seen since the open-world co-op work (a 05:03 core dump predates it) and in every
   full tier since rt30. `coop_playtest.sh` accepts rc 134 after PASS with a WARNING, and
   docs/TEST_TIERS.md documents that. The 0.0x "clean shutdown" work (PlaytestBot.finished,
   re-entrant Coop.end) did not fix it. The root cause is open. Also, 1 ObjectDB instance
   leaks at exit.
2. **Join and leave flow.** Per POLISH_0.3.1 L2, coop_menu works but has no join progress
   states, no "host is loading" feedback on the joiner, and a failure gives no message
   beyond the log. Leaving goes back to the menu with no in-game notice for the others.
3. **Desync and latency.** Remote players lerp toward the last pose (remote_player.gd:131)
   and puppets lerp (coop_world.gd:109), with no snapshot buffer, timestamps or
   extrapolation. Under jitter they stutter, and with loss they snap. A client's hits are
   predicted on the puppet, then the host's 20 Hz health overwrites them, so bars can
   flick back. The 400 m leash and host fast travel ("travel") teleport the joiner, which
   is the one place a teleport is intended.
4. **Party UI.** party_frames.gd shows the name, "Lv N", a health bar and "DOWN"/"dead" as
   text. There is no damage chip (L2), no shield or mana, no distance or direction, no
   off-screen marker, and no ping.
5. **Revive and downed.** The rules are LAST_STAND 15 s, REVIVE_RANGE 2.5 m, REVIVE_TIME
   3 s and REVIVE_HEALTH 0.3. The only feedback is the HUD text "Down! N s, a friend
   standing beside you revives you". There is no revive progress bar for either side, no
   world marker on a downed teammate, no interact prompt (reviving works by standing
   nearby), and no sound.
6. **Shared vs instanced loot.** Drops are instanced per peer (PLAN §30.2), so nobody
   steals. That is not communicated: players see different drops and don't know why.
   There is no way to give an item to a teammate, and chests (the Labyrinth boss chest)
   roll per peer too.
7. **Vote UX.** 0.3.1 P2 added the banner and QA r10 and r11 fixed it. Still missing: a
   way for a player to start or cancel the vote, a ready-up shortcut, and an in-world
   marker for "go to the stairs".
8. **Disconnect handling.** `server_disconnected` ends the session ("host left") and drops
   everyone to the menu. A client's disconnect frees its proxy. There is no reconnect
   window, no host-migration fallback (out of scope), the joiner's character is saved
   only on a normal exit (to check), and the host gets no toast.
9. Also: enemy health +60 % per extra player is not shown anywhere. Brand and status FX
   parity rides on fx_flags only. And co-op cannot run while QA runs co-op (shared ports),
   so the test runs need a port or seed per run.

## 14. Co-op polish items

| # | Item | Plan | Est. |
|---|------|------|------|
| C1 | Joiner exit crash | Reproduce with `--verbose` and an ASan or debug build of 4.7.2, bisect the teardown (NetSession/ENet free order, SafeLoad threads, RemotePlayer and puppet frees, Steam transport) and fix it. Then remove the rc 134 acceptance from `coop_playtest.sh` and TEST_TIERS. Also fix the ObjectDB leak. | 1.5 d (an investigation, so it may run over) |
| C2 | Join and leave flow | Joiner states: connecting, handshake/version, host loading, loading the world, in world, each with a timeout and a readable error ("version mismatch", "host full", "timed out"). Toasts for "X joined" and "X left". A leave confirmation. | 1 d |
| C3 | Latency smoothing | An interpolation buffer (about 100 ms behind, with timestamps in pose and snapshot), a short extrapolation cap, and a snap only past a threshold. Client health prediction is kept until the host acks a hit sequence. Run under link_conditioner at 150 ms and 5 % loss. | 1.5 d |
| C4 | Party UI | Chip bars (reuse HudFx.Chip), shield, distance and an arrow, an off-screen marker, a ping dot, and a "DOWN" timer ring. | 1 d |
| C5 | Revive and downed | A world marker with a bleed-out ring over a downed teammate. An optional hold-Interact revive, or keep proximity (Q-C2). A progress bar for both players, sounds, and a "revived by X" toast. | 1 d |
| C6 | Loot clarity | A "Your loot" note on the first co-op drop, a tooltip or icon on instanced drops, and an optional drop-to-share for items (a dropped item becomes visible to all; Q-C3). | 1 d |
| C7 | Vote UX | Start the vote by holding Interact at the stairs (exists). Add a cancel by walking away when you started it, a stairs ping marker, and a ready count on the party frames. | 0.5 d |
| C8 | Disconnect handling | A 30 s client reconnect window (the host keeps the proxy, shown as "reconnecting"). Save the joiner's character on any disconnect. If the host leaves, return to the menu with a reason and save. | 1 d |
| C9 | Party scaling shown | A "Party x2: enemies +60 % health" line in the pause menu or party frames. | 0.25 d |

## 15. Co-op tests

- Fast tier: unit tests for the interpolation buffer (jitter in, smooth out), the join
  state machine (every error path), the reconnect window, revive progress, and
  party-frame chips.
- Full tier: the co-op playtest with no rc 134 accepted, plus link_conditioner runs at
  150 ms with 5 % loss. These are a co-op run, so not while QA runs co-op.
- Ember QA manual list: join while the host is loading, kill the host, kill the joiner
  and rejoin within 30 s, revive under fire, a vote with a lagging joiner.

# 16. Combined 0.3.2 step list

| # | Steps | Est. |
|---|-------|------|
| Q1 | C1 joiner exit crash (first, so every later co-op run is clean) | 1.5 d |
| Q2 | S1-S3 scaling core (every stat, 2b), solo | 2.25 d |
| Q3 | S4 co-op normalised damage and protocol bump, plus C3 latency smoothing (the same messages) | 3 d |
| Q4 | S5-S7 XP and loot, nameplate, Labyrinth | 1.25 d |
| Q5 | C2, C8 join, leave and disconnect | 2 d |
| Q6 | C4, C5, C9 party UI, revive, scaling note | 2.25 d |
| Q7 | C6, C7 loot clarity, vote | 1.5 d |
| Q8 | S8 balance, full tier and co-op matrix, release prep (release only on ShobieShy's go) | 1 d |

About 14.75 days in total. Fast tier on every step, and the full tier at Q3 and Q8.

## 17. Co-op defaults and questions for ShobieShy

C1. Fix the rc 134 crash before any other 0.3.2 work? Default yes.
C2. Revive: keep proximity (stand 3 s) or switch to hold Interact? Default: hold Interact,
    since it matches the stairs.
C3. Loot stays instanced, plus an optional drop-to-share for items? Default yes.
C4. A reconnect window of 30 s? Default yes, with no host migration.
C5. A co-op protocol version bump in 0.3.2 (0.3.1 and 0.3.2 cannot play together)?
    Default yes. The save format is unchanged.
C6. Latency target: smooth at 150 ms and 5 % loss? Default yes.
