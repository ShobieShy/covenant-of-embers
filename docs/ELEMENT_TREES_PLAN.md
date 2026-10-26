# Element skill trees — plan (Phase V, WAITING ON USER GO)

> **t70u answers (2026-10-26):** structure (b); trees **uncapped** (Q48); **21 skills per element
> tree**; an element capstone **locks all other element capstones** until respec (§4.8); every other
> question takes its default (Q49–Q56). Still plan only: the build waits for the user's go.

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
  (brand/fire-mode synergy). It has **21 skills** over 6 tiers (gates at 0/5/10/15/20 points in
  that tree, not per branch, so that 2 branches stay flexible). The capstone sits alone on T5, needs
  25 points in the tree, and is exclusive across element trees (§4.8).
- **Points:** one shared pool (unchanged). **Element trees are uncapped** (t70u, Q48). Any number of points can go into one tree, and
  spending is free across trees. 20 ranked skills = 50 ranks per tree > 49 points at level 50.
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

## 4. Element trees: 21 skills each (t70u; placeholder numbers, per rank)

Shape of every element tree (t70u): **21 skills = 20 ranked skills + 1 capstone**. There are
6 tiers. Tiers 0–4 each hold 4 skills (2 **Attunement**: element and status; 2 **Craft**: brand
and fire-mode synergy). Tier 5 holds only the capstone. Tier gates count points spent **in that
tree**: 0/5/10/15/20 for T0–T4, and the capstone needs **25** points in the tree plus 1 skill
taken in T4. The tree is **uncapped** (Q48): all 20 ranked skills total 50 ranks, so at level 50
(49 points) nobody can max a tree. Specialising comes from the point budget.

Format: Tier – name (ranks) – effect. [A] = Attunement, [C] = Craft (brand synergy, wand-scaled).
★ = capstone (1 rank, **exclusive**, see §4.8). "Status" means the element's status from
ElementTable. Every number is a placeholder, to be balanced by the DPS harness (±15% band per
element at equal points).

### 4.1 Arcane – "Pure Focus" (unbranded semi; synergy = gems, accuracy, mana)
- T0 [A] Clean Lines (5) – +3% Arcane damage. [A] Measured Breath (3) – Arcane casts cost −4% mana. [C] Steady Hand (3) – +4 accuracy. [C] Trigger Discipline (2) – semi-auto cooldown −4%.
- T1 [A] Resonant Gem (3) – a gem bolt's status lasts +10% on an Arcane staff. [A] Thin Veil (2) – Arcane bolts pierce +1 enemy at 50%. [C] Quick Study (2) – focus FOV-in time −10%. [C] Bloom Control (3) – spread bloom per cast −10%.
- T2 [A] Echo (3) – every 8th Arcane bolt fires a free copy at 40%. [A] Mana Lens (3) – +1% damage per 10% mana missing (max +5%/rank). [C] Gem Socket Sense (2) – gem bolts on Arcane staffs +6% damage. [C] Long Sight (2) – range +8%.
- T3 [A] Overflow (2) – Arcane kills refund 3 mana. [A] Prism (1) – Arcane hits apply 25% of a random element's status. [C] Focused Fire (3) – while focusing, +4% damage. [C] Weak Point Study (2) – weak-point damage +8%.
- T4 [A] Attuned Pool (2) – mana regen delay −0.2 s after an Arcane kill. [A] Refraction (2) – Prism picks the element the target is weakest to. [C] Clockwork (2) – every 10th semi cast has no cooldown. [C] Gem Harmony (1) – gem bolts also get the Arcane damage % from this tree.
- ★ T5 **Convergence** – every 5th Arcane hit on one target triggers the statuses of every element tree you have put a point into.

### 4.2 Fire – "Kindling" (burn; synergy = Pyrowning heat, vent and crystal reload)
- T0 [A] Hot Coals (5) – +3% Fire damage. [A] Long Burn (3) – burn lasts +0.5 s. [C] Heat Sink (3) – Pyrowning heat per shot −6%. [C] Cool Hands (2) – heat decay +10%.
- T1 [A] Searing (3) – burn deals +10% of the hit (fraction 0.30 → max 0.60). [A] Tinder (2) – the first hit on an unburnt enemy +8%. [C] Quick Vent (3) – vent time −10%. [C] Efficient Crystal (2) – crystal reload mana cost −5% of max (from 50%, floor 35%).
- T2 [A] Flashpoint (3) – +5% damage to burning enemies. [A] Spread Fire (2) – a burning enemy that dies passes 50% of its burn to 1 enemy within 4 m. [C] Red Line (2) – while heat ≥ 70%, +6% Fire damage. [C] Short Fuse (2) – overheat lockout −0.1 s.
- T3 [A] Wildfire Kin (2) – burn ticks have a 5% chance to refresh themselves. [A] Ember Ward (2) – −4% damage taken from burning enemies. [C] Hot Swap (2) – the crystal reload ejects a 2 m fire puff (30% of one shot). [C] Overclock (3) – heat ≥ 90%: cooldown −5%.
- T4 [A] Inferno Heart (2) – burn damage +10%. [A] Kindred Flame (1) – your burns don't stack-limit with allies' burns. [C] Fresh Crystal (2) – after a crystal reload, the next 5 shots add −50% heat. [C] Thermal Bank (1) – a crystal reload refunds 10% of max mana if heat was ≥ 95%.
- ★ T5 **Backdraft** – venting (R) at ≥ 80% heat releases a 4 m fire burst for 120% of one shot and resets the burn on everything it hits.

### 4.3 Water – "Tidecaller" (slow, **Soaked**; synergy = Sigil Sauer charge + chain)
- T0 [A] Cold Current (5) – +3% Water damage. [A] Undertow (3) – slow lasts +0.4 s. [C] Patient Draw (3) – Sigil charge time −6%. [C] Steady Pour (2) – charge isn't lost for 0.3 s after a holster.
- T1 [A] Heavy Water (3) – slow factor 0.60, −0.04 per rank (floor 0.45). [A] Riptide (3) – +6% damage to slowed enemies. [C] Overflowing Charge (2) – a full charge chains to +1 target. [C] Pressure (2) – partial charges deal +5% more.
- T2 [A] Drench (2) – slow also applies −5% enemy move speed after it ends (2 s). [A] Calm Pool (3) – +1 mana regen while charging. [C] Brimming (2) – full-charge window +0.15 s. [C] Ripple (2) – the full-charge chain range +1 m.
- T3 [A] Soak (2) – Water hits apply **Soaked** (4 s): the next Air chain or Earth stagger on them is +50%. [A] Deep Cold (2) – slowed enemies deal −4% damage. [C] Tide Turn (2) – a full charge on a Soaked enemy refunds 20% of the charge time. [C] Wave Crest (2) – charged-shot damage +6%.
- T4 [A] Saturation (2) – Soaked lasts +1 s and spreads to 1 enemy within 3 m on a kill. [A] Still Water (1) – standing still for 1 s: +8% Water damage. [C] Riverbed (2) – chain jumps don't lose damage on Soaked targets. [C] Hydraulic (2) – a full charge refunds 5 mana.
- ★ T5 **Tidal Hold** – a full Sigil charge freezes its first target for 1.2 s (stagger-strength; bosses are slowed ×0.4 instead).

### 4.4 Earth – "Bedrock" (stagger; synergy = Moss & Berg explosive boulders)
- T0 [A] Stoneskin (5) – +3% Earth damage. [A] Bulk (3) – +2% damage resist with an Earth staff out. [C] Wide Blast (3) – splash radius +8%. [C] Heavy Shot (2) – boulder speed +10%.
- T1 [A] Quake (3) – stagger +0.1 s. [A] Crumble (3) – +6% damage to staggered enemies. [C] Rubble (2) – a blast leaves 2 s of rubble (×0.7 slow). [C] Packed Load (2) – blast falloff −10%.
- T2 [A] Grounded (2) – no knockback, +5% max health with an Earth staff out. [A] Bedrock Pulse (2) – a stagger also staggers 1 enemy within 2 m at half time. [C] Aftershock (2) – a second, smaller blast (30%) 0.5 s later. [C] Shrapnel (3) – a blast hit +4%.
- T3 [A] Tremor (2) – staggering a Soaked enemy doubles that stagger (Soaked synergy). [A] Stone Will (2) – while staggering something, −5% damage taken. [C] Cluster (2) – blast self-damage −25%. [C] Seismic Charge (2) – direct boulder hits +8%.
- T4 [A] Landslide (2) – stagger duration +10% per staggered enemy nearby (max 3). [A] Mountain (1) – +10 max health. [C] Detonator (2) – boulders that miss explode at range end. [C] Bigger Rocks (2) – boulder head size and splash +5%.
- ★ T5 **Fault Line** – every 4th boulder splits into 3 on impact (each 40%), each able to stagger.

### 4.5 Air – "Gale" (chain; synergy = Windchester spin-up)
- T0 [A] Tailwind (5) – +3% Air damage. [A] Light Feet (3) – +2% move speed with an Air staff out. [C] Spool (3) – spin-up time −8% (the 0.1 s cooldown clamp stays). [C] Momentum (2) – spin starts at 10%.
- T1 [A] Long Arc (3) – chain range +1 m. [A] Gust (2) – chain hits +5%. [C] Keep Spinning (3) – spin decays 15% slower after release. [C] Whirl Guard (2) – at full spin, −4% damage taken.
- T2 [A] Forked (2) – the chain jumps to +1 enemy (each jump at 50% of the last). [A] Conductive (2) – chains on Soaked enemies +25% (Soaked synergy). [C] Static (3) – +4% damage per chained enemy hit in the last 2 s (max 3 stacks). [C] Overspin (2) – spin can overfill to 110% (+5% fire rate).
- T3 [A] Updraft (2) – chain hits push enemies 1 m. [A] Slipstream (2) – a kill gives +6% move speed for 2 s. [C] Feathered (2) – spread at full spin −15%. [C] Cyclic (2) – full spin refunds 1 mana per 10 hits.
- T4 [A] Storm Eye (2) – chains prefer the lowest-health target. [A] Jetstream (1) – an air dash recharges 20% faster with an Air staff out. [C] Gyro (2) – swapping weapons keeps 50% spin for 1 s. [C] Thunderhead (2) – every 20th spin shot chains to all enemies within 3 m.
- ★ T5 **Cyclone** – at full spin for 2 s, bolts chain to every enemy within 6 m (each 35%), on a 6 s cooldown.

### 4.6 Light – "Dawnward" (heals, allies; synergy = Coltara Halo burst/semi + accuracy ramp)
- T0 [A] Bright Hands (5) – ally/self heals +5%. [A] Clear Sight (3) – +3% Light damage (the 0.9× rule stays). [C] Choir (3) – burst accuracy ramp +15%. [C] Quick Toggle (2) – burst/semi toggle instant.
- T1 [A] Lasting Glow (3) – the LightSummon lasts +5 s. [A] Mend Bond (3) – healing an ally heals you 20% of it. [C] Halo Step (2) – a full burst gives +6% move speed for 2 s. [C] Tight Burst (2) – burst spread −10%.
- T2 [A] Sanctuary (2) – the summon heals nearby allies 2 HP/s. [A] Radiance (2) – Light hits weaken enemies (−5% damage dealt, 3 s). [C] Ramp Memory (2) – the accuracy ramp holds 0.5 s longer. [C] Fourth Note (2) – 10% chance per burst of a 4th shot.
- T3 [A] Beacon (2) – the summon's light reveals enemies (outline, 8 m). [A] Gentle (2) – heals overflow into shield (max 10). [C] Measured Semi (2) – semi shots at full ramp +8%. [C] Halo Recall (2) – a burst that lands every shot refunds 3 mana.
- T4 [A] Martyr (2) – reviving an ally restores +10% more health. [A] Purify (1) – your heals clear burn and slow on allies. [C] Chorus Line (2) – burst cooldown −6%. [C] Hallowed (2) – Radiance lasts +1 s.
- ★ T5 **Dawnchorus** – a full 3-shot burst that lands heals every ally within 6 m for 15% of their max health (8 s cooldown; co-op through "heal").

### 4.7 Dark – "Gloam" (turn, **Hex**; synergy = Hexler & Koch crit + cursed orb reload)
- T0 [A] Shadow Touch (5) – +3% Dark damage. [A] Whisper (3) – turn chance +0.5% (still capped at 15%). [C] Weak Spots (3) – crit damage +8%. [C] Keen Eye (2) – crit chance +2%.
- T1 [A] Long Night (3) – corrupted allies last +5 s. [A] Thrall Bond (2) – corrupted allies deal +15% and heal you 2 HP on a kill. [C] Cursed Load (2) – cursed orb reload damage +15%. [C] Misfortune (2) – misses refund 25% of the miss penalty.
- T2 [A] Hex (3) – Dark hits apply **Hex** (5 s): your hits on it +3% per rank. [A] Dread (2) – Hexed enemies move −5% slower. [C] Orb Radius (2) – orb blast radius +10%. [C] Lucky Streak (2) – a crit gives +3% crit chance for 2 s (max 3 stacks).
- T3 [A] Contagion (2) – Hex spreads to 1 enemy within 3 m on death. [A] Dark Pact (2) – while you have a corrupted ally, +5% Dark damage. [C] Deadeye (2) – crit on a weak point +10%. [C] Quick Curse (2) – orb reload time −8%.
- T4 [A] Soul Tithe (2) – killing a Hexed enemy heals 3 HP. [A] Legion (1) – up to 2 corrupted allies at once (bosses excluded). [C] Executioner (2) – crit damage +10% vs enemies below 30% health. [C] Black Orb (2) – an orb hit applies Hex.
- ★ T5 **Eclipse** – a crit on a Hexed enemy below 30% health turns it (normal turn rules, not bosses; may ignore the 15% cap once every 20 s, Q55).

### 4.8 Exclusive capstones (t70u)

- Taking **any** element capstone (the T5 skill) **locks every other element tree's capstone**,
  so a character owns at most **one** element capstone. Core's capstone (Wildfire) isn't affected.
- Rule in data: each element tree's capstone has `exclusive_group = "element_capstone"`.
  `Skills.can_rank_up()` refuses a skill whose group already has a taken skill in another tree
  (reason `capstone_locked`, naming the tree that holds it).
- **Respec** (Old Oak, everything together) refunds the capstone and **unlocks all of them**.
  There is no partial unlock.
- **Saves:** on load, if a save has more than one element capstone (an edited save or a bug), the
  first in tree order (Arcane, Fire, Water, Earth, Air, Light, Dark) is kept and the others are
  refunded as free points. Logged once.
- **Co-op:** ranks travel in the character file, so the host and peers apply the same rule. A
  client never sends capstone procs for a tree it can't hold.
- **UI (skills screen, K):**
  - The **owned** capstone gets a gold frame and a small crown pip, and its tab gets a crown badge.
  - Every **locked** capstone node is drawn greyed (desaturated, 40% alpha) with a **padlock icon**
    over it and the element colour kept as a thin outline only. The button is disabled.
  - The tooltip on a locked capstone says: "Locked – you hold **Backdraft** (Fire). Only one element
    capstone per character. Respec at the Old Oak to choose again."
  - Before the confirm when taking a capstone: a dialog "Taking Cyclone locks the other 6 element
    capstones until you respec. Continue?" [Take] [Cancel]. On gamepad, A confirms and B cancels.
  - A capstone that is unreachable only by points (under 25 in the tree) keeps the normal
    "needs 25 points in this tree" look, not the padlock. The padlock means exclusivity only.
  - The element tab strip shows a tiny padlock on tabs whose capstone is locked.

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
  pool refunded in full, now counted across all trees). The capstone exclusivity rule (§4.8) is also enforced on load (keep the first in tree order, refund the rest).
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
- The header shows "Skill points: N (level L)" and "This tree: x points (capstone at 25)". Each tab shows a dot when
  points can be spent there.
- Tooltips say "Only while casting Fire" and name the brand for Craft-branch skills. The current
  wieldable's element tab is highlighted.
- Gamepad: LB/RB switch tabs, as the inventory tabs already do. The intro lock on K stays.
- The item card for a staff gets one line: "Your Fire skills: +x% damage, burn +y" (optional, Q52).

## 9. Tests (all headless; must stay in run_tests.sh)

- `test_skill_trees_multi.gd`: load all 8 trees; 21 skills per element tree (20 + capstone); tier gating per tree; no per-tree cap (49 points in one tree is allowed); the shared pool; capstone gating at 25.
- `test_capstone_lock.gd`: taking one element capstone locks the other 6 (`capstone_locked` reason); Core capstone unaffected; respec unlocks all; a save with 2 capstones keeps the first and refunds the other; the UI shows the padlock state and the confirm dialog.
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
  (21 skills each, §4) + shared pool, uncapped, exclusive capstone group + lock, save v2 + migration. No behaviour change for Core.
- **145 V2** ElementSkillMods: resolve per-element mods; hook +damage%/accuracy/mana into Caster;
  status knobs into MagicEffects (burn/slow/stagger/chain, Light heal, Dark chance/duration).
- **146 V3** Brand synergies: FireMode reads mods (heat per shot, vent time, charge time, splash,
  spin-up/decay, burst ramp, crit/orb), wand-scaled.
- **147 V4** Marks and conditionals: Soaked, Hex, Red Line, Riptide, Crumble, Static, Mana Lens,
  Tremor, Conductive, Contagion, and the rest of the T1–T3 conditionals (Enemy timers, conditional_bonus).
- **148 V5** Capstones (7), with cooldowns and boss rules; the T4 skills (28) that need runtime hooks.
- **149 V6** Skills UI tabs (21-node element layout: 5 rows of 4 + capstone), tooltips, gamepad, card line, **locked-capstone look** (padlock, greyed, tooltip naming the owned capstone, take-confirm dialog, tab badges, §4.8); screenshots.
- **150 V7** Co-op: "hit" status-mod dictionary, capstone area hits/heals, PROTOCOL 3, coop tests.
- **151 V8** Balance: DPS harness with skills, BalancePatch "skills" section, bot spends element
  points, docs; then release 0.1.4 on request.

## 11. Questions (answered t70u: Q48 uncapped; all others take their defaults)

- Q47 Structure: (a) pick 3 of 7, (b) Core + 7 element trees, (c) archetype element branches? **ANSWERED (t70u, default): (b).**
- Q48 Per-element-tree point cap? **ANSWERED (t70u): uncapped.** Also t70u: 21 skills per element tree; one element capstone per character (locks the others until respec).
- Q49 Element skills apply only while casting that element (planned) or always at half strength? **ANSWERED (t70u, default): only that element.**
- Q50 Respec: everything together (planned), or per-tree at half price as well? **ANSWERED (t70u, default): all together only.**
- Q51 Archetype flavour: leave Core shared (planned), or give each archetype its own Core branch later? **ANSWERED (t70u, default): shared now; revisit after V8.**
- Q52 Staff card line showing your skill mods? **ANSWERED (t70u, default): yes, one line.**
- Q53 Gem bolts: does a Fire gem on a Water staff use Fire skills for its bolts? **ANSWERED (t70u, default): yes, per bolt element.**
- Q54 New marks (Soaked, Hex), or only tune existing statuses? **ANSWERED (t70u, default): add those two, capstone/T3 only.**
- Q55 Dark Eclipse may bypass the 15% cap (once / 20 s, not bosses)? **ANSWERED (t70u, default): yes.**
- Q56 Co-op PROTOCOL 3 (older builds can't join)? **ANSWERED (t70u, default): yes.**
