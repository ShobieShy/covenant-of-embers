class_name BrandDps
extends RefCounted
## Step 143 (Brands B9): the brand DPS harness. Runs a Caster at 60 Hz for `seconds` with
## unlimited mana and a "good player" input policy per fire mode (hold to fire; Sigil Sauer
## holds to full charge then releases; Pyrowning vents on R when near overheat), and sums the
## damage of every bolt spawned. single = direct hits x the crit expectation (cursed orbs
## count as hitting the target); aoe adds one extra enemy nearby (blast at mid-radius,
## chain jump). Used by tests/unit/test_brand_balance.gd (each brand within +-15% of the
## unbranded build) and printable with:
##   godot --headless --path . -s res://tools/brand_dps_main.gd

const DT := 1.0 / 60.0
const E := ElementTable.Element
const P := WieldablePart.PartType


## A basic staff (or wand) whose Head is `e` (ARCANE = unbranded), same seed and rarity.
static func build(e: E, wand := false, rarity := "basic", seed := 99) -> WieldableInstance:
	var base := "swift_wind_wand" if wand else "apprentice_fire_staff"
	var parts: Array[WieldablePart] = [PartRoller.from_seed(seed, P.HEAD, rarity, e)]
	for id in ["basic_exterior"] if wand else ["basic_exterior", "basic_interior", "basic_handle"]:
		parts.append(WieldablePart.load_part(id))
	return Assembly.assemble(WieldableInstance.load_base(base).def, parts)


## {single, aoe, casts, bolts} damage per second.
static func measure(w: WieldableInstance, seconds := 30.0, skills: Skills = null) -> Dictionary:
	var c := Caster.new(w)
	c.skills = skills
	var bolts := SpellBolts.new()
	var aim := Caster.Aim.make(Vector3.ZERO, Vector3.FORWARD)
	var m := c.fire_mode()
	var charge_ticks := 0
	if m is ChargeMode:
		charge_ticks = ceili((m as ChargeMode).charge_time() / DT) + 1
	var held_for := 0
	var n := roundi(seconds / DT)
	for t in n:
		var held := true
		if charge_ticks > 0:
			held = held_for < charge_ticks
			held_for = 0 if not held else held_for + 1
		if m is HeatMode and m.meter() >= 0.9:
			c.reload(aim, bolts)
		c.tick(held, held, DT, aim, bolts)
	var single := 0.0
	var aoe := 0.0
	for b in bolts.live:
		var s: SpellBolts.Spawn = b.spawn
		var hit := s.damage * (1.0 + s.crit_chance * (s.crit_mult - 1.0))
		single += hit
		aoe += hit + s.damage * s.blast_fraction * (1.0 + s.blast_falloff) * 0.5
		if s.chain_targets > 0:
			aoe += s.damage * s.chain_fraction
	var out := {"single": single / seconds, "aoe": aoe / seconds, "casts": c.casts, "bolts": bolts.spawned}
	bolts.free()
	return out


## Every brand vs the unbranded build: [{brand, wand, single, aoe, base, ratio}].
static func table(wand := false, rarity := "basic") -> Array:
	var base: float = measure(build(E.ARCANE, wand, rarity)).single
	var rows: Array = []
	for b: Brand in BrandTable.load_default().brands:
		var r := measure(build(b.element, wand, rarity))
		rows.append(
			{"brand": b.id, "wand": wand, "single": r.single, "aoe": r.aoe, "base": base, "ratio": r.single / base}
		)
	return rows


## Step 151: a Skills with `points` spent in element tree `el` (cheapest tiers first, max ranks,
## no capstone): the --skills <tree>:<points> build.
static func skills_build(el: String, points: int) -> Skills:
	var sk := Skills.new()
	sk.tree = SkillTree.default_tree()
	var t := SkillTree.element_tree(el)
	if t == null:
		return sk
	var rows: Array = t.skills.values().filter(func(x): return not bool(x.get("capstone", false)))
	rows.sort_custom(func(a, b): return int(a["tier"]) < int(b["tier"]))
	var d := {}
	var left := points
	for r in rows:
		if left <= 0:
			break
		var n := mini(left, int(r["max_rank"]))
		d[r["id"]] = n
		left -= n
	sk.el_ranks[el] = d
	return sk


## Step 151: every element's staff with `points` in its own tree vs the mean:
## [{element, single, base, ratio}] (ratio = single / mean single at those points).
static func skills_table(points: int, wand := false) -> Array:
	var rows: Array = []
	var sum := 0.0
	for el in ElementTable.IDS:
		var e := ElementTable.parse(el) as E
		var w := build(e, wand)
		var base: float = measure(w).single
		var r: float = measure(build(e, wand), 30.0, skills_build(el, points)).single
		rows.append({"element": el, "single": r, "base": base, "gain": r / base})
		sum += r / base
	for row in rows:
		row["ratio"] = row["gain"] / (sum / rows.size())
	return rows
