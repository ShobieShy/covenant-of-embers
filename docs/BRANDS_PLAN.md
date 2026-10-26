# Staff/wand part brands (Phase U, planned 2026-10-26, WAITING ON USER GO)

The user approved six part makers, one per element, in the style of Borderlands 3 / Wonderlands
manufacturers. We copy the *design pattern* only (a maker that changes how a gun fires); no
Borderlands names, logos, text or assets. Arcane stays the unbranded neutral base.

| Element | Brand | Casting behaviour | Pattern borrowed |
|---|---|---|---|
| Fire | **Pyrowning Arms** | No reload/no mana per shot while hot: heat builds, overheat locks and vents | heat-sink overheat |
| Water | **Sigil Sauer** | Hold to charge; a full charge chains to nearby enemies | charge-up / alt-mode |
| Earth | **Moss & Berg** | Slow semi-auto boulders that explode, high damage, slow bolt | explosive slow launcher |
| Air | **Windchester** | Full auto; fire rate spins up while held | spin-up high fire rate |
| Light | **Coltara Halo** | Select fire burst/semi; accuracy tightens with sustained fire | select fire + accuracy ramp |
| Dark | **Hexler & Koch** | Precise semi-auto, crit bonus; spent charge thrown as a cursed orb on reload | precision crit + thrown reload |

## 1. Current code (what the brands plug into)
- `WieldableInstance` (scripts/magic/wieldable_instance.gd): stat getters `damage()`,
  `cooldown()` (>= 0.1 s), `accuracy()`, `element()` (first Head gem > Head element > base),
  `mana_cost()`, `projectile_speed()`, `range_m()`, `dark_chance_bonus()`.
- `WieldablePart` (scripts/magic/wieldable_part.gd): HEAD/EXTERIOR/INTERIOR/HANDLE/CHARM,
  `element`, `rarity`, `roll_seed`, gems on the Head.
- `Assembly` (scripts/magic/assembly.gd): legal builds, rarity = floor(mean part tier),
  `name_for()` = "<Rarity> <Element> Staff|Wand".
- `Caster` (scripts/magic/caster.gd): one press = one bolt (semi-auto, Magewar), optional
  `hold_to_repeat`; cooldown then `mana_spender(cost)`; damage = `damage()` + flat
  `damage_bonus` + Consecration bonuses, x0.9 for Light; sets `dark_bonus`.
- `Spread` (scripts/magic/spread.gd): accuracy -> cone, bloom per cast, seeded PCG32.
- `SpellBolts` / `MagicEffects`: burn (Fire), slow (Water), stagger (Earth), chain (Air,
  CHAIN_RANGE 6 m, 0.5x), Light heal, Dark turn (1 % base + part bonus, cap 15 %, 30 s).
- `PartRoller` (scripts/loot/part_roller.gd) seeded part rolls; `ItemCodes` v1 Ember Marks
  (append-only tables); `CoopWorld` snapshots with `net_fx` bits; `NetSession.PROTOCOL = 1`.

## 2. Data model
- New `scripts/magic/brand.gd` (`class_name Brand`, Resource): `id`, `display_name`,
  `element`, `fire_mode` (enum SEMI, HEAT, CHARGE, AUTO_SPINUP, SELECT_BURST, PRECISION),
  `logo` (Texture2D path), `color`, `tagline`, and a `params: Dictionary` of tunables.
- Data in `resources/brands/<id>.tres` + `resources/brands/brands.tres` (`BrandTable`,
  `validate()`, `load_default()`, `for_element(e) -> Brand or null`). Arcane -> null.
- **Brand is derived, not stored:** `WieldablePart.brand()` = `BrandTable.for_element(element)`
  for any part; `WieldableInstance.brand()` = the **Head part's** brand (Head element, NOT a
  socketed gem's element; see Q1). No Head / Arcane Head = unbranded = today's behaviour.
  Because it is derived from data already in the Ember Mark, **no ItemCodes version bump**
  and old saves gain brands automatically.
- New `scripts/magic/fire_mode.gd` (`class_name FireMode`, RefCounted, one subclass per mode)
  owned by `Caster`. Caster.tick asks `mode.wants_cast(pressed, held, released, dt)`,
  `mode.cost()`, `mode.modify(spawn)` and `mode.after_cast()`; unbranded = `SemiMode`, which
  must reproduce today's Caster exactly (tests pin it). State (heat, charge, spin, burst
  count, ramp) lives on the mode, per slot, and resets on equip() except heat (keeps cooling
  while holstered, like `cool()`).

## 3. Casting per brand (all numbers are tunable placeholders, see section 8)
**Reload equivalent:** we have no magazines. "Reload" = a short *vent* action (`reload` input,
default R) that only some brands use; others ignore it.
- **Pyrowning Arms (HEAT):** semi or hold-repeat at base cooldown x0.8. **No mana per cast**;
  each cast adds `heat_per_cast`. Heat decays `heat_decay/s` after `vent_delay`. At 100 %:
  overheat -> locked for `overheat_seconds`, emits `overheated` (steam SFX), small self-burn?
  (Q4). R = manual vent (dumps heat over `vent_seconds`, no cast). Mana spent instead as a
  one-off `mana_cost x overheat_mana` on overheat? (Q3; default: no mana at all).
- **Sigil Sauer (CHARGE):** press starts charging, release casts. Charge 0..1 over
  `charge_seconds`; damage x lerp(`min_mult`, `max_mult`, charge); mana scales with charge;
  a full charge (>= `chain_threshold`) chains to `chain_targets` enemies within `chain_range`
  using the Air chain code (MagicEffects chain helper generalised). Tap = weak quick shot.
  Focus does not cancel the charge. R does nothing.
- **Moss & Berg (SEMI explosive):** cooldown x`cooldown_mult` (slower), damage x`damage_mult`,
  projectile speed x`speed_mult`, small drop (gravity) optional (Q5); impact = radius
  `blast_radius` AoE falloff (new SpellBolts impact hook), stagger still applies. Self-damage
  off. Mana x`mana_mult`.
- **Windchester (AUTO_SPINUP):** forced hold-to-repeat. Cooldown x lerp(`spin_start`,
  `spin_end`, spin) where spin rises over `spin_seconds` held, falls `spin_down/s` released.
  Damage x`damage_mult` (< 1), bloom x`bloom_mult`. Mana per cast as normal (mana is the ammo).
- **Coltara Halo (SELECT_BURST):** R toggles burst <-> semi (shown on HUD). Burst = `burst_count`
  bolts `burst_gap` s apart for one press, one mana charge x`burst_mana`, then cooldown.
  Accuracy ramp: each cast within `ramp_window` adds `ramp_per_cast` accuracy (cap
  `ramp_max`), i.e. Spread bloom is *negative* for this brand. (Q6: Hyperion-style shield
  skipped.)
- **Hexler & Koch (PRECISION):** semi only, accuracy +`accuracy_add`, damage x`damage_mult`,
  **crit**: hits on the enemy head/weak-point collider (new `weak_point` group; body-only
  enemies use a `crit_chance` roll) deal x`crit_mult`. Has a "charge pool" of `pool_casts`
  casts; R (or empty pool) throws the spent charge as a **cursed orb** (lobbed, explodes for
  `orb_damage_per_charge x casts spent`, applies the Dark turn roll once), then refills after
  `refill_seconds`. Pool replaces nothing about mana: casts still cost mana.

## 4. Interplay with existing rules
- **Light heal / 0.9x:** stays in Caster after the brand modifies damage; every bolt of a
  Coltara burst heals allies per bolt (ally heal is per hit; LIGHT_ALLY_FRACTION unchanged).
  Burst heals are tuned via `burst_count` not a new heal rule.
- **Dark turn chance:** rolled per Dark hit as today, capped at 15 %. Hexler crits roll
  once (no extra chance from crit; Q7). The cursed orb rolls once per enemy hit.
- **Flat spell damage bonus (gear, Consecration):** added **before** brand multipliers? No:
  it stays a flat add *after* multipliers so a charged/boulder shot does not multiply gear
  (keeps the "added flat to every cast" decision literal). Exception: each burst bolt and each
  Windchester bolt get it once each (it is "every cast"). Q2 asks whether that is OK given
  Windchester's high cast rate (alternative: per-press bonus).
- **Rarity cap at Primordial:** brands don't change rarity; Dust upgrades still stop at
  Primordial; brand params may scale with rarity via `params.rarity_scale` (e.g. heat per
  cast down at higher tiers) but rarity rules themselves untouched.
- **Elemental status effects** (burn/slow/stagger/chain) keep firing per hit; Sigil Sauer's
  chain reuses Air's chain helper but deals Water damage + slow (Q8 overlap with Air).
- **Gems:** a gem changes the bolt element (today's rule) but not the brand (Q1).

## 5. UI
- Item cards / CompareCard / station / vendor / tooltips: brand line under the name
  ("Pyrowning Arms" in brand colour + 16 px logo), fire-mode line ("Heat: no mana while
  cool"), brand stats (heat/cast, charge time, spin-up, burst) next to existing stats.
- Logos: our own simple pixel glyphs (flame-gear, wave-sigil, mossy boulder, windmill, haloed
  star, hex eye) drawn in the pixel theme; no BL-style shapes. Stored in `assets/ui/brands/`.
- Naming: "<Rarity> <Brand> <Element> Staff" (e.g. "Rare Pyrowning Fire Staff")? or
  "<Rarity> <Brand> Staff" since brand implies element (Q9; default keeps element).
- HUD: one meter under the crosshair, per active brand: heat bar (orange, flashes + "VENT"
  on overheat), charge ring (blue), spin gauge (white), burst/semi pip (gold), Hexler pool
  pips (purple). Hidden for unbranded/semi. Respects ui_theme and the Low preset.

## 6. Loot rolls and naming
- No new roll: Head element already rolls (`ELEMENT_WEIGHTS` 2/1/1/1/1/0.5/0.5) so brand odds
  follow it. Arcane Heads (weight 2) stay unbranded.
- Part display names gain the brand on the Head only: "Brilliant Pyrowning Head". Other parts
  keep Magewar names (Q10: brand all elemental parts?).
- Optional: per-brand flavour lines on Rare+ (`tagline`), our own text.
- Vendors list brand; Ember Marks unchanged (brand derived).

## 7. VFX / SFX hooks
- `Caster` signals: `heat_changed(f)`, `overheated`, `vented`, `charge_changed(f)`,
  `charge_released(f)`, `spin_changed(f)`, `mode_toggled(mode)`, `orb_thrown`.
- FX: heat shimmer + red glow on the Head, steam burst on vent; charge glow growing on the
  Head, chain arcs (reuse chain FX in Water colour); boulder mesh bolt + dust explosion;
  spinning Head ring; burst triple tracer; cursed orb (dark sphere + trail) and pop.
- SFX: overheat hiss, vent, charge hum (pitch with charge), boulder thud, spin whine, burst
  click, mode toggle, orb throw. CC0 sources as before, credited in CREDITS.md.
- All FX obey quality presets (particle caps from step 134).

## 8. Co-op sync
- Brand is derived from the wieldable, which is already replicated -> nothing new to send.
- Casts are client-authoritative for their own bolts today; brand state (heat, charge, spin)
  stays local. Remote players see FX via a new 2-bit-per-meter `brand_fx` field in the player
  snapshot (heat high / overheated / charging / spinning) and existing bolt replication.
- New payloads: Moss & Berg blast hits and the cursed orb are sent as "hit" lists like chain
  (host applies damage); Sigil chain uses the existing chain path.
- **PROTOCOL 1 -> 2** (snapshot layout changes); version gate rejects mixed builds.

## 9. Balance placeholders (resources/brands/*.tres, patchable via BalancePatch v2)
| Brand | Key params |
|---|---|
| Pyrowning | cooldown_mult 0.8, heat_per_cast 0.12, heat_decay 0.6/s, vent_delay 0.4 s, overheat_seconds 2.0, vent_seconds 1.0, mana 0 |
| Sigil Sauer | charge_seconds 1.0, min_mult 0.6, max_mult 1.8, chain_threshold 0.95, chain_targets 2, chain_range 6 m, chain_fraction 0.5, mana x lerp(0.5,1.5) |
| Moss & Berg | cooldown_mult 1.8, damage_mult 2.2, speed_mult 0.6, blast_radius 3 m, falloff 0.5 at edge, mana_mult 1.6 |
| Windchester | spin_start 1.4, spin_end 0.45 (cooldown x), spin_seconds 1.5, spin_down 1.5/s, damage_mult 0.6, bloom_mult 0.6, still >= 0.1 s min cooldown? (Q45: yes, clamped at 0.1 s) |
| Coltara Halo | burst_count 3, burst_gap 0.07 s, burst_mana 2.0, ramp_per_cast +4 acc, ramp_max +20, ramp_window 0.6 s |
| Hexler & Koch | accuracy_add +15, damage_mult 1.15, crit_mult 2.0, crit_chance 0.1 (no weak point), pool_casts 6, orb_damage_per_charge 0.4x damage, refill_seconds 1.5 |
Target: DPS within +/-15 % of unbranded semi at equal rarity over a 10 s dummy test.

## 10. Tests (tools/run_tests.sh stays green)
- test_brands.gd: table validates; every element but Arcane has exactly one brand; brand
  comes from Head element, not gem; Arcane/no Head -> null; old Ember Marks decode with brand.
- test_fire_modes.gd (deterministic 60 Hz ticks): SemiMode == old Caster (cast counts/
  cooldowns pinned); heat build/overheat/vent timings; charge damage curve + release; spin-up
  cooldown curve; burst count/gap/mana; accuracy ramp; Hexler pool + orb + crit mult.
- Interplay: Light 0.9x after brand mult, flat bonus added once per bolt, Dark cap 15 %,
  rarity names; Spread negative bloom clamps.
- DPS harness `tools/brand_dps.gd` prints per brand/rarity table, asserts the +/-15 % band.
- UI: cards show brand + logo; HUD meter visibility per brand (ui_shots additions).
- Co-op: snapshot round-trip of brand_fx; PROTOCOL 2 gate; coop playtest with branded staves.
- Playtest bot: rotates through one branded staff per element.

## 11. Ordered build steps (each waiting on user go)
- **135 Brands B1** Brand/BrandTable data + six .tres, `brand()` getters, names, tests (no behaviour change).
- **136 Brands B2** FireMode refactor of Caster: SemiMode identical to today, reload/vent input, signals; tests pin old behaviour.
- **137 Brands B3** Pyrowning HEAT + Windchester AUTO_SPINUP modes + tests.
- **138 Brands B4** Sigil Sauer CHARGE (+ generalised chain) + Moss & Berg explosive boulders (AoE impact hook) + tests.
- **139 Brands B5** Coltara Halo SELECT_BURST + accuracy ramp (Spread hook) + Hexler & Koch PRECISION (weak points, crit, pool, cursed orb) + tests.
- **140 Brands B6** UI: card/tooltip brand line + logos, HUD heat/charge/spin/burst/pool meter, settings for reload key.
- **141 Brands B7** VFX/SFX hooks and assets, quality-preset caps, credits.
- **142 Brands B8** Co-op: brand_fx snapshot bits, blast/orb hit lists, PROTOCOL 2; coop test.
- **143 Brands B9** Balance pass with DPS harness, BalancePatch support for brand params, playtest bot rotation, docs.

## 12. Open questions (all answered 2026-10-26: user accepted the defaults)
- ~~**Q35** Gems: brand follows the Head's own element (planned) or the socketed gem's element?~~ **Answered 2026-10-26:** Head element (gems don't change brand).
- ~~**Q36** Flat gear/Consecration bonus: once per bolt (planned; strong on Windchester/bursts) or once per trigger press?~~ **Answered 2026-10-26:** Per bolt.
- ~~**Q37** Pyrowning mana: zero mana (planned) or a mana charge on overheat/vent?~~ **Answered 2026-10-26:** No mana.
- ~~**Q38** Overheat penalty: lockout only (planned) or also a small self-burn?~~ **Answered 2026-10-26:** Lockout only.
- ~~**Q39** Moss & Berg boulders: straight (planned) or arcing with gravity?~~ **Answered 2026-10-26:** Straight.
- ~~**Q40** Coltara Halo: select fire toggle on R (planned) or a separate key; any Hyperion-style shield on focus?~~ **Answered 2026-10-26:** R toggles; no shield.
- ~~**Q41** Hexler crit: real weak-point hitboxes on enemies (planned, plus chance fallback) or chance only?~~ **Answered 2026-10-26:** Weak-point hitboxes with chance fallback.
- ~~**Q42** Sigil Sauer chain vs Air's chain status: keep both (Water chain only on full charge), or give Water something else?~~ **Answered 2026-10-26:** Keep; Water chain on full charge only.
- ~~**Q43** Naming: "Rare Pyrowning Fire Staff" (planned) or drop the element ("Rare Pyrowning Staff")?~~ **Answered 2026-10-26:** Keep element in names.
- ~~**Q44** Brand only the Head (planned) or every elemental part, with a set bonus for matching brands?~~ **Answered 2026-10-26:** Head only.
- ~~**Q45** Windchester: keep the 0.1 s global minimum cooldown or let spin-up go lower?~~ **Answered 2026-10-26:** Windchester spin-up clamps at the existing 0.1 s minimum cooldown.
- ~~**Q46** Wands: same brand behaviour as staves, or a lighter version (e.g. no burst/orb)?~~ **Answered 2026-10-26:** Wands get a lighter version (scaled-down brand effects).

## 13. Wands (Q46)
Wands use the same brand modes with scaled-down effects: a per-brand `wand_scale` param (placeholder 0.6) shrinks heat/charge multipliers, blast radius, burst count (2), spin range, accuracy ramp, crit mult and orb damage toward the unbranded baseline.
