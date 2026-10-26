# Element skill trees — plan (Phase V, WAITING ON USER GO)

Request t67u (2026-10-26): "Make skill trees also based on magic types, applying new bonuses and
effects that work with each magic type." This is a plan only. No gameplay code until the user says go.
Like Phase U, it uses Borderlands-style design patterns only (branches, tiers opened by points,
ranked skills, capstones). No Borderlands content. Every name and number below is a placeholder.

## 1. What exists today (studied 2026-10-26)

- `scripts/player/skill_tree.gd` (SkillTree): reads one TOML tree. A tree has branches, tiers
  (tier t opens at t × `POINTS_PER_TIER` = 5 points spent in that branch), ranked skills, and one
  1-rank capstone on the last tier. Effects are flat per-rank stats from a fixed `STATS` list:
  max_health, max_mana, mana_regen, max_breath, spell_damage, speed_pct, resist_all, kill_mana,
  kill_health, kill_frenzy, cast_refund.
- `scripts/player/skills.gd` (Skills): ranks per character. You get 1 point per level from level 2,
  so level 50 gives 49 points. `respec()` refunds everything (Old Oak, gold price rises each time,
  capped). `from_dict` drops unknown skills, clamps ranks and refunds over-spent saves.
- `data/skills/ember_path.toml`: **one** shared placeholder tree, "Path of Embers", with 3
  branches: Hearth (survival), Pyre (damage), Ash (mana). It has 4 tiers and one capstone
  (Wildfire, kill_frenzy). **Note:** every archetype uses this same tree. There are no per-archetype trees.
  `Archetype` (Nerd/Gal/Buff/Loli) only adds one small perk.
- `SkillProcs`: kill procs plus the capstone frenzy. `Player.apply_bonuses()` sums skills + gear +
  archetype (no +=/-=). `SkillsUi` (K): one column per branch, a button per skill, plus respec.
- Co-op: ranks travel in the portable character save (CharacterSave). The bonuses are local, and
  clients send already-scaled hit damage plus the Dark bonus with their "hit". The host rolls
  Dark and applies statuses.
- Element hooks a tree can use: Light 0.9× damage and ally heals; Dark 1% turn chance (cap 15%);
  Fire burn 30% over 3 s; Water slow ×0.6 for 2.5 s; Earth stagger 0.4 s; Air chain 50% to one
  enemy within 6 m. Brands: Pyrowning heat/vent, Sigil Sauer charge plus a chain on full charge,
  Moss & Berg explosive boulders, Windchester spin-up, Coltara Halo burst/semi plus an accuracy ramp,
  Hexler & Koch crit plus cursed orb reload. Arcane is unbranded (semi).

## 2. Structure options

**(a) Replace with 7 element trees and pick 3.** At creation (or the first Old Oak visit) the
player picks 3 of 7 element trees, and only those can take points. This is the clearest identity,
but it throws away the current Hearth/Pyre/Ash survival and mana skills (or spreads them across 7
trees), locks builds early, and turns a pick into a respec-plus-repick. It also needs a picker UI
and a migration that refunds every save.

**(b) Keep a core tree and add 7 element trees (recommended).** The current tree becomes the
**Core** tree for every character: Hearth / Pyre / Ash, later archetype-flavoured (Q51). Seven
element trees are added beside it, all open, all drawing on the same point pool. Element skills
only work while the active wieldable casts that element (Head element; a gem's element also counts
for its bolts). They make the element and its brand stronger and change how its status works.
With 49 points at level 50, a player can go deep in about one element tree plus some Core, or
reach two mid-tier element nodes, so specialising comes from the point budget instead of a lock.
Existing saves keep their ranks (the tree ids don't change), so no refund is forced.

**(c) Archetype trees with element-themed branches.** Each archetype gets its own 3-branch tree,
and the branches are elements (for example Nerd: Arcane/Water/Air, Buff: Earth/Fire/Light,
Gal: Light/Water/Dark, Loli: Air/Fire/Dark). This has the strongest archetype identity. But an
archetype can then never specialise in some elements, it needs 12 element branches (4 × 3), and it
ties loot (any element) to classes. It also makes archetypes far more than "a look plus one perk",
which is a bigger design change than t67u asked for.

**Recommendation: (b).** It answers "trees based on magic types" directly, keeps today's tree and
saves, fits the staff-swap loot game (any staff can be good), and adds per-element data without
new class systems. If the user wants more archetype identity later, (c)-style flavour can go into
the Core tree branches (Q51).

## 3. Rules for option (b)

- **Trees:** `core` (ember_path, renamed in the UI only) plus `arcane, fire, water, earth, air,
  light, dark`. Each element tree has 2 branches: **Attunement** (element/status) and **Craft**
  (brand/fire-mode synergy). It has 5 tiers (gates at 0/5/10/15/20 points in that tree, not per
  branch, so that 2 branches stay flexible) and one capstone on tier 4 that needs 20 points in the tree.
- **Points:** one shared pool (unchanged). **Element trees cap at 25 points spent each** (Q48), so
  one tree can't take the whole pool, and spending is free across trees.
- **When it applies:** an element skill counts only when the bolt or meter belongs to that element
  ("active element" = the bolt's element. Fire-mode effects read the active wieldable's brand
  element). Passive non-combat bonuses (max mana and similar) are left out of element trees so they
  don't stack across trees. They stay in Core.
- **Wands:** brand-synergy effects scale by `wand_scale` (Q46 → wands are lighter), the same as brands.
- **Effects schema:** keys become `stat` (global, as today) or `element.stat`, for example
  `fire.burn_fraction`, `water.slow_seconds`, `fire.heat_per_shot_pct`. A new `ElementSkillMods`
  resolves them into a per-element dictionary that MagicEffects, Caster and FireMode read
  (pure static lookup, like BalancePatch, and never written into constants).
- **Statuses:** this phase adds no new statuses, only tuning of the existing four (burn, slow,
  stagger, chain) plus Light/Dark knobs. Two new light-weight marks are proposed for capstones
  only: **Soaked** (Water) and **Hex** (Dark), both plain timers on Enemy.

## 4. Element tree concepts (placeholder numbers, per rank)

Format: name (ranks) – effect. T = tier. ★ = capstone (1 rank). Every number is a placeholder,
to be balanced by the DPS harness (±15% target band per element at equal points).

### Arcane – "Pure Focus": the unbranded generalist. Rewards steady semi-auto and gem play.
- T0 Clean Lines (5) – +3% Arcane damage. Measured Breath (3) – Arcane casts cost −4% mana.
- T1 Resonant Gem (3) – a gem bolt's element status lasts +10% on an Arcane staff. Steady Hand (3) – +4 accuracy.
- T2 Echo (3) – every 8th Arcane bolt fires a free copy at 40% damage. Mana Lens (3) – +1% damage per 10% mana missing (max +5%/rank).
- T3 Overflow (2) – kills with Arcane refund 3 mana. Prism (1) – Arcane hits apply 25% of a random element's status.
- ★ T4 **Convergence** – every 5th Arcane hit on one target triggers the statuses of every element you have put a point into.

### Fire – "Kindling": burn stacking plus Pyrowning heat play.
- T0 Hot Coals (5) – +3% Fire damage. Long Burn (3) – burn lasts +0.5 s.
- T1 Searing (3) – burn deals +10% of the hit (fraction 0.30 → 0.60 max). Heat Sink (3) – Pyrowning heat per shot −6%.
- T2 Flashpoint (3) – hitting a burning enemy deals +5% damage. Quick Vent (3) – vent time −10%.
- T3 Red Line (2) – while heat ≥ 70%, +6% Fire damage. Spread Fire (2) – a burning enemy that dies passes 50% of its burn to 1 enemy within 4 m.
- ★ T4 **Backdraft** – venting (R) at ≥ 80% heat releases a 4 m fire burst for 120% of one shot and resets the burn on everything it hits.

### Water – "Tidecaller": control through slow, plus Sigil Sauer charge.
- T0 Cold Current (5) – +3% Water damage. Undertow (3) – slow lasts +0.4 s.
- T1 Heavy Water (3) – slow factor 0.60 → −0.04 per rank (floor 0.45). Patient Draw (3) – Sigil charge time −6%.
- T2 Riptide (3) – +6% damage to slowed enemies. Overflowing Charge (2) – a full charge chains to +1 extra target.
- T3 Soak (2) – Water hits apply **Soaked** (4 s): the next Air chain or Earth stagger on them is +50%. Calm Pool (3) – +1 mana regen while charging.
- ★ T4 **Tidal Hold** – a full Sigil charge freezes its first target for 1.2 s (stagger-strength, not on bosses: bosses are slowed ×0.4 instead).

### Earth – "Bedrock": stagger, toughness, Moss & Berg splash.
- T0 Stoneskin (5) – +3% Earth damage. Bulk (3) – +2% damage resist while holding an Earth staff.
- T1 Quake (3) – stagger +0.1 s. Wide Blast (3) – Moss & Berg splash radius +8%.
- T2 Crumble (3) – staggered enemies take +6% damage. Rubble (2) – a boulder blast leaves 2 s rubble (×0.7 slow).
- T3 Aftershock (2) – a second, smaller blast (30%) 0.5 s later. Grounded (2) – no knockback, +5% max health while on an Earth staff.
- ★ T4 **Fault Line** – every 4th boulder splits into 3 on impact (each 40%), and each one can stagger.

### Air – "Gale": chains, speed, Windchester spin.
- T0 Tailwind (5) – +3% Air damage. Light Feet (3) – +2% move speed with an Air staff out.
- T1 Long Arc (3) – chain range +1 m. Spool (3) – Windchester spin-up time −8% (still clamped at 0.1 s cooldown).
- T2 Forked (2) – chain jumps to +1 extra enemy (each jump at 50% of the last). Keep Spinning (3) – spin decays 15% slower after release.
- T3 Updraft (2) – chain hits push enemies 1 m. Static (3) – +4% damage per chained enemy hit in the last 2 s (max 3 stacks).
- ★ T4 **Cyclone** – at full spin for 2 s, bolts chain to every enemy within 6 m (each 35%), on a 6 s cooldown.

### Light – "Dawnward": healing, allies, Coltara burst.
- T0 Bright Hands (5) – ally/self heal +5%. Clear Sight (3) – +3% Light damage (the 0.9× rule stays).
- T1 Choir (3) – Coltara burst accuracy ramp +15%. Lasting Glow (3) – LightSummon lasts +5 s.
- T2 Mend Bond (3) – healing an ally also heals you for 20% of it. Halo Step (2) – a full burst gives +6% move speed for 2 s.
- T3 Sanctuary (2) – the summon heals nearby allies 2 HP/s. Radiance (2) – Light hits on an enemy weaken it (−5% damage dealt, 3 s).
- ★ T4 **Dawnchorus** – a full 3-shot burst that lands on allies or enemies heals every ally within 6 m for 15% of their max health (8 s cooldown); in co-op this goes out through the existing "heal".

### Dark – "Gloam": corruption, curses, Hexler & Koch crits.
- T0 Shadow Touch (5) – +3% Dark damage. Whisper (3) – turn chance +0.5% (still capped at 15%).
- T1 Long Night (3) – corrupted allies last +5 s. Weak Spots (3) – Hexler crit damage +8%.
- T2 Hex (3) – Dark hits apply **Hex** (5 s): your hits on it +3% damage per rank. Cursed Load (2) – cursed orb reload damage +15%.
- T3 Thrall Bond (2) – corrupted allies deal +15% damage and heal you 2 HP when they kill. Misfortune (2) – misses with Hexler refund 25% of the miss penalty.
- ★ T4 **Eclipse** – a crit on a Hexed enemy below 30% health turns it (normal turn rules, not bosses, ignores the 15% cap once every 20 s).

## 5. Respec

- Respec stays at the Old Oak with the same rising gold price, and now resets **Core + all element
  trees** together (one button). We could add a per-tree respec at half price later (Q50).
- `Skills` becomes multi-tree: `trees: Dictionary` id → SkillTree, and `ranks` keyed
  `"<tree>/<skill>"` internally. Core skill ids stay unprefixed in saves for compatibility (Section 6).

## 6. Save migration

- The character and save JSON keep `"skills": {"tree": "ember_path", "ranks": {...}, "respecs": n}`
  and gain `"elements": {"fire": {...ranks}, ...}` plus `"skills_version": 2`. A save without
  `skills_version` loads its ranks into Core unchanged, and its element trees start empty.
- The existing sanitise rules apply per tree (unknown skills dropped, ranks clamped, an over-spent
  pool refunded in full, now counted across all trees). The 25-point per-tree cap is also enforced on load.
- Old builds reading a v2 save ignore `"elements"` (the extra key is harmless). Points spent there
  show up as free points in the old build, which is acceptable for a pre-alpha.

## 7. Co-op sync

- Ranks already travel in the portable character file. The element mods are computed locally and
  sent in the data that already crosses the wire:
  - damage-type mods (+% damage, crit) are already inside the client's hit amount;
  - status mods (burn fraction/seconds, slow, stagger, chain jumps, Soaked/Hex, the turn-chance
    bonus) must reach the **host**, which applies statuses. Extend the client "hit" message with a
    small `sm` dictionary of non-default status mods (the same pattern as the Dark bonus);
  - capstone area hits (Backdraft, Fault Line, Cyclone) go through the step 142 puppet-hit path;
  - Dawnchorus heals use the existing "heal" message.
- Bump **PROTOCOL to 3** (0.1.3 builds can't join), as in step 142. Pose `bf` doesn't change.

## 8. UI

- The skills screen (K) gets a **tab row**: Core | Arcane | Fire | Water | Earth | Air | Light | Dark.
  Tabs use the element colours and icons. Each tab shows its tree in the existing column layout
  (2 branch columns, tier rows, capstone at the bottom).
- The header shows "Skill points: N (level L)" and "This tree: x/25". Each tab shows a dot when
  points can be spent there.
- Tooltips say "Only while casting Fire" and name the brand for Craft-branch skills. The current
  wieldable's element tab is highlighted.
- Gamepad: LB/RB switch tabs, as the inventory tabs already do. The intro lock on K stays.
- The item card for a staff gets one line: "Your Fire skills: +x% damage, burn +y" (optional, Q52).

## 9. Tests (all headless; must stay in run_tests.sh)

- `test_skill_trees_multi.gd`: load all 8 trees; tier gating per tree; 25-point cap; the shared pool; capstone gating.
- `test_skill_migration.gd`: a v1 save loads into Core unchanged; v2 round-trip; over-spent pool refund; unknown element ids dropped.
- `test_element_mods.gd`: each `element.stat` key changes only its element (for example a Fire burn mod doesn't change a Water bolt); wand scaling.
- One test per capstone (7): trigger conditions, cooldowns, boss exclusions, Dark cap override timing.
- `test_coop.gd`: a client with Fire Searing applies its longer burn on the host; Backdraft area hits; Dawnchorus heal; PROTOCOL 3.
- Balance: extend `tools/brand_dps.gd` with `--skills <tree>:<points>`. At 20 points in each element
  tree, single-target DPS stays within ±15% across elements (Light counts its healing as 0.5 damage
  per heal point), and Core-only builds stay unchanged (parity).
- The playtest bot spends points: Core first to 10, then its rotation brand's element tree. The
  PASS line lists the trees used.

## 10. Build steps (all WAITING ON USER GO)

- **144 V1** Multi-tree data: SkillTree element keys (`element.stat`), 7 placeholder TOML trees
  (Section 4 names, effects stubbed to the existing global stats where possible), Skills multi-tree
  + shared pool + 25 cap, save v2 + migration. No behaviour change for Core.
- **145 V2** ElementSkillMods: resolve per-element mods; hook +damage%/accuracy/mana into Caster;
  status knobs into MagicEffects (burn/slow/stagger/chain, Light heal, Dark chance/duration).
- **146 V3** Brand synergies: FireMode reads mods (heat per shot, vent time, charge time, splash,
  spin-up/decay, burst ramp, crit/orb), wand-scaled.
- **147 V4** Marks and conditionals: Soaked, Hex, Red Line, Riptide, Crumble, Static, Mana Lens,
  and so on (Enemy timers, conditional_bonus).
- **148 V5** Capstones (7), with cooldowns and boss rules.
- **149 V6** Skills UI tabs, tooltips, gamepad, card line; screenshots.
- **150 V7** Co-op: "hit" status-mod dictionary, capstone area hits/heals, PROTOCOL 3, coop tests.
- **151 V8** Balance: DPS harness with skills, BalancePatch "skills" section, bot spends element
  points, docs; then release 0.1.4 on request.

## 11. Open questions (defaults are used unless the user says otherwise)

- Q47 Structure: (a) pick 3 of 7, (b) Core + 7 element trees, (c) archetype element branches? **Default: (b).**
- Q48 Per-element-tree point cap? **Default: 25** (so a level-50 player can't put everything in one element).
- Q49 Element skills apply only while casting that element (planned) or always at half strength? **Default: only that element.**
- Q50 Respec: everything together (planned), or per-tree at half price as well? **Default: all together only.**
- Q51 Archetype flavour: leave Core shared (planned), or give each archetype its own Core branch later? **Default: shared now; revisit after V8.**
- Q52 Staff card line showing your skill mods? **Default: yes, one line.**
- Q53 Gem bolts: does a Fire gem on a Water staff use Fire skills for its bolts? **Default: yes, per bolt element.**
- Q54 New marks (Soaked, Hex), or only tune existing statuses? **Default: add those two, capstone/T3 only.**
- Q55 Dark Eclipse may bypass the 15% cap (once / 20 s, not bosses)? **Default: yes.**
- Q56 Co-op PROTOCOL 3 (older builds can't join)? **Default: yes.**
