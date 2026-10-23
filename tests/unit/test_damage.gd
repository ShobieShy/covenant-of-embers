extends TestCase
## Step 6 done check (port of the archived test_damage.cpp, old step 20): Magewar elements
## (resources/magic/elements.tres) and the damage formula (scripts/combat/damage.gd).
##  - the full 7x7 chart equals Magewar's get_effectiveness (transcribed independently
##    below, not read from the .tres): 6 strong cells, 4 weak, same/Arcane x1.0;
##  - names/colours are Magewar's ELEMENT_NAMES/ELEMENT_COLORS (= PLAN §30.4 hex) and
##    the .tres matches data/magic/elements.toml (the C++ engine's validated data);
##  - validate() refuses tables that break the code rules;
##  - base x rarity + sum of part bonuses; resist per element capped at 0.6 (0.8 -> 0.6);
##    weak point x2; worked example 12 x 1.5 x 0.7 x 2 = 25.2.

const E := ElementTable.Element
const EPS := 1e-9

## Magewar MagicElement.get_effectiveness (scripts/magic/magic_element.gd), transcribed.
static func _magewar(a: int, d: int) -> float:
	if a == d or a == E.ARCANE or d == E.ARCANE:
		return 1.0
	match a:
		E.FIRE:
			if d == E.EARTH: return 1.5
			if d == E.WATER: return 0.5
		E.WATER:
			if d == E.FIRE: return 1.5
			if d == E.AIR: return 0.5
		E.EARTH:
			if d == E.AIR: return 1.5
			if d == E.FIRE: return 0.5
		E.AIR:
			if d == E.WATER: return 1.5
			if d == E.EARTH: return 0.5
		E.LIGHT:
			if d == E.DARK: return 1.5
		E.DARK:
			if d == E.LIGHT: return 1.5
	return 1.0

func _table() -> ElementTable:
	var t := ElementTable.load_default()
	check(t != null, "elements.tres loads as ElementTable")
	check(t.validate().is_empty(), "elements.tres valid: %s" % "; ".join(t.validate()))
	return t

func test_full_chart_matches_magewar() -> void:
	var t := _table()
	var strong := 0
	var weak := 0
	for a in ElementTable.COUNT:
		for d in ElementTable.COUNT:
			var got := t.effectiveness(a as E, d as E)
			check(got == _magewar(a, d), "%s -> %s: %s, Magewar %s" % [ElementTable.IDS[a], ElementTable.IDS[d], got, _magewar(a, d)])
			if got > 1.0: strong += 1
			if got < 1.0: weak += 1
	check(strong == 6, "6 strong cells (4-cycle + Light/Dark both ways), got %d" % strong)
	check(weak == 4, "4 weak cells (cycle backwards; Light/Dark never weak), got %d" % weak)
	# The plan's words: Fire > Earth > Air > Water > Fire, Light <-> Dark.
	check(t.effectiveness(E.FIRE, E.EARTH) == 1.5 and t.effectiveness(E.EARTH, E.AIR) == 1.5, "Fire>Earth>Air")
	check(t.effectiveness(E.AIR, E.WATER) == 1.5 and t.effectiveness(E.WATER, E.FIRE) == 1.5, "Air>Water>Fire")
	check(t.effectiveness(E.FIRE, E.WATER) == 0.5 and t.effectiveness(E.EARTH, E.FIRE) == 0.5, "backwards x0.5")
	check(t.effectiveness(E.LIGHT, E.DARK) == 1.5 and t.effectiveness(E.DARK, E.LIGHT) == 1.5, "Light<->Dark")
	check(t.effectiveness(E.FIRE, E.LIGHT) == 1.0 and t.effectiveness(E.DARK, E.AIR) == 1.0, "unrelated x1.0")
	print("    damage: 49/49 cells = Magewar get_effectiveness (%d strong, %d weak)" % [strong, weak])

func test_same_and_arcane_always_neutral() -> void:
	var t := _table()
	for e in ElementTable.COUNT:
		check(t.effectiveness(e as E, e as E) == 1.0, "%s vs itself" % ElementTable.IDS[e])
		check(t.effectiveness(E.ARCANE, e as E) == 1.0, "arcane -> %s" % ElementTable.IDS[e])
		check(t.effectiveness(e as E, E.ARCANE) == 1.0, "%s -> arcane" % ElementTable.IDS[e])
	var empty := ElementTable.new()   # no data: neutral everywhere
	for a in ElementTable.COUNT:
		for d in ElementTable.COUNT:
			check(empty.effectiveness(a as E, d as E) == 1.0, "empty table neutral")

func test_names_and_colours_are_magewars() -> void:
	var t := _table()
	# Magewar ELEMENT_NAMES / ELEMENT_COLORS, and the PLAN §30.4 hex of each.
	var want := [
		["arcane", "Arcane", Color(0.7, 0.7, 0.7), "#B3B3B3"],
		["fire", "Fire", Color(1.0, 0.3, 0.1), "#FF4D1A"],
		["water", "Water", Color(0.1, 0.4, 1.0), "#1A66FF"],
		["earth", "Earth", Color(0.5, 0.35, 0.1), "#80591A"],
		["air", "Air", Color(0.8, 0.95, 1.0), "#CCF2FF"],
		["light", "Light", Color(1.0, 0.95, 0.7), "#FFF2B3"],
		["dark", "Dark", Color(0.3, 0.0, 0.5), "#4D0080"],
	]
	for e in ElementTable.COUNT:
		var w: Array = want[e]
		check(ElementTable.id_of(e as E) == w[0] and ElementTable.parse(w[0]) == e, "id %s" % w[0])
		check(t.display_name(e as E) == w[1], "name %s: %s" % [w[0], t.display_name(e as E)])
		check(t.color(e as E).is_equal_approx(w[2]), "colour %s = Magewar %s" % [w[0], t.color(e as E)])
		var hex := Color.html(w[3])
		for c in 3:
			check(absf(t.color(e as E)[c] - hex[c]) <= 0.5 / 255.0 + 1e-6, "%s channel %d ~ %s" % [w[0], c, w[3]])
	check(ElementTable.parse("none") == -1 and ElementTable.parse("wind") == -1, "unknown ids")
	check(t.strong == 1.5 and t.weak == 0.5, "x1.5 / x0.5")

func test_tres_matches_cpp_elements_toml() -> void:
	var t := _table()
	var d := LevelToml.load_file("res://data/magic/elements.toml")
	check(not d.has("error"), "elements.toml parses: %s" % d.get("error", ""))
	var eff: Dictionary = d.get("effectiveness", {})
	check(float(eff.get("strong", 0)) == t.strong and float(eff.get("weak", 0)) == t.weak, "multipliers")
	var rows: Array = d.get("element", [])
	check(rows.size() == ElementTable.COUNT, "7 TOML elements")
	for row in rows:
		var e := ElementTable.parse(row["id"])
		check(e >= 0, "TOML id %s" % row["id"])
		if e < 0:
			continue
		var def := t.def(e as E)
		check(def.display_name == row["name"], "%s name" % row["id"])
		check(def.color.is_equal_approx(LevelToml.color(row["color"])), "%s colour" % row["id"])
		check(Array(def.strong_against) == row["strong_against"], "%s strong_against" % row["id"])
		check(Array(def.weak_against) == row["weak_against"], "%s weak_against" % row["id"])

func _bad(edit: Callable, expect: String) -> void:
	var t: ElementTable = ElementTable.load_default().duplicate(true)
	edit.call(t)
	t.rebuild()
	var errs := "; ".join(t.validate())
	check(errs.contains(expect), "expected '%s', got '%s'" % [expect, errs])

func test_validate_rejects_bad_tables() -> void:
	check(ElementTable.load_default().duplicate(true).validate().is_empty(), "deep copy valid")
	_bad(func(t: ElementTable) -> void: t.strong = 1.0, "strong must be in (1, 10]")
	_bad(func(t: ElementTable) -> void: t.weak = 1.0, "weak must be in [0, 1)")
	_bad(func(t: ElementTable) -> void: t.elements[1].id = "plasma", "element #2: unknown element 'plasma'")
	_bad(func(t: ElementTable) -> void: t.elements[1].id = "arcane", "duplicate element 'arcane'")
	_bad(func(t: ElementTable) -> void: t.elements[1].id = "arcane", "missing element 'fire'")
	_bad(func(t: ElementTable) -> void: t.elements.pop_back(), "missing element 'dark'")
	_bad(func(t: ElementTable) -> void: t.elements[1].strong_against = PackedStringArray(["wood"]), "unknown element 'wood' in strong_against")
	_bad(func(t: ElementTable) -> void: t.elements[1].strong_against = PackedStringArray(["fire"]), "strong_against can't list itself")
	_bad(func(t: ElementTable) -> void: t.elements[1].weak_against = PackedStringArray(["arcane"]), "weak_against can't list arcane")
	_bad(func(t: ElementTable) -> void: t.elements[1].strong_against = PackedStringArray(["water"]), "'water' is in both")
	_bad(func(t: ElementTable) -> void: t.elements[1].strong_against = PackedStringArray(["earth", "earth"]), "'earth' listed twice")
	_bad(func(t: ElementTable) -> void: t.elements[0].strong_against = PackedStringArray(["fire"]), "arcane is neutral")
	_bad(func(t: ElementTable) -> void: t.elements[1].color = Color(2, 0.3, 0.1), "'fire': color must be in 0..1")
	_bad(func(t: ElementTable) -> void: t.elements[1].display_name = "", "'fire': display_name is empty")

func test_patched_chart_rebuilds() -> void:
	var t: ElementTable = ElementTable.load_default().duplicate(true)
	t.strong = 2.0
	t.rebuild()
	check(t.effectiveness(E.FIRE, E.EARTH) == 2.0, "patched strong x2.0")
	check(ElementTable.load_default().effectiveness(E.FIRE, E.EARTH) == 1.5, "shared table untouched")

func test_rarity_multiplier_and_part_bonuses() -> void:
	# Magewar item_rarity.gd multipliers (Rarity resource comes in step 15).
	var mults := [1.0, 1.25, 1.5, 2.0, 2.75, 3.0]
	for m in mults:
		check_near(Damage.wieldable_damage(10.0, m), 10.0 * m, EPS, "10 x %s" % m)
	# get_final_damage: wieldable x rarity + head + exterior + interior + handle + charm.
	var bonuses := PackedFloat64Array([2.0, 1.5, 0.5, 1.0, 3.0])
	check_near(Damage.wieldable_damage(14.0, 1.25, bonuses), 14.0 * 1.25 + 8.0, EPS, "bonuses not multiplied")
	# The four Magewar bases with no parts (base rarity basic/uncommon): 10, 17.5, 7, 7.5.
	check_near(Damage.wieldable_damage(10.0, 1.0), 10.0, EPS, "Apprentice Fire Staff")
	check_near(Damage.wieldable_damage(14.0, 1.25), 17.5, EPS, "Earthward Battlestaff")
	check_near(Damage.wieldable_damage(7.0, 1.0), 7.0, EPS, "Novice Arcane Wand")
	check_near(Damage.wieldable_damage(6.0, 1.25), 7.5, EPS, "Swift Wind Wand")

func test_resist_capped_at_60_percent_per_element() -> void:
	var t := _table()
	check(Damage.RESIST_CAP == 0.6, "cap 0.6 (kept decision, not Magewar's 0.9)")
	var target := Damage.Target.new().set_resist(E.FIRE, 0.25)
	var r := Damage.resolve_hit(100.0, E.FIRE, target, t)
	check(r.resist == 0.25 and absf(r.amount - 75.0) <= EPS, "25 %% -> 75 (%f)" % r.amount)
	target.set_resist(E.FIRE, 0.8)
	r = Damage.resolve_hit(100.0, E.FIRE, target, t)
	check(r.resist == 0.6, "0.8 -> 0.6 (%f)" % r.resist)
	check_near(r.amount, 40.0, EPS, "0.8 resist -> 40")
	target.set_resist(E.FIRE, 0.9)   # Magewar's cap would let 10 through
	check_near(Damage.resolve_hit(100.0, E.FIRE, target, t).amount, 40.0, EPS, "0.9 -> still 0.6")
	target.set_resist(E.FIRE, -0.5)
	check_near(Damage.resolve_hit(100.0, E.FIRE, target, t).amount, 100.0, EPS, "negative resist -> 0")
	target.set_resist(E.FIRE, 0.8)
	r = Damage.resolve_hit(100.0, E.WATER, target, t)
	check(r.resist == 0.0 and absf(r.amount - 100.0) <= EPS, "fire resist doesn't stop water")
	check(Damage.clamp_resist(0.8) == 0.6 and Damage.clamp_resist(0.3) == 0.3, "clamp_resist")

func test_weak_point_is_x2() -> void:
	var t := _table()
	var body := Damage.Target.new()
	var seam := Damage.Target.new()
	seam.weak_point = true
	var a := Damage.resolve_hit(12.0, E.ARCANE, body, t)
	var b := Damage.resolve_hit(12.0, E.ARCANE, seam, t)
	check(a.crit == 1.0 and b.crit == 2.0, "crit 1 / 2")
	check_near(a.amount, 12.0, EPS, "body 12")
	check_near(b.amount, 24.0, EPS, "weak point 24")

func test_effectiveness_per_hit_vs_affinity() -> void:
	var t := _table()
	var earth := Damage.Target.new(E.EARTH)
	var s := Damage.resolve_hit(10.0, E.FIRE, earth, t)
	check(s.effectiveness == 1.5 and s.strong() and not s.weak(), "fire vs earth strong")
	check_near(s.amount, 15.0, EPS, "Fire staff vs Earth = 15 (step 11 dummy)")
	var w := Damage.resolve_hit(10.0, E.AIR, earth, t)
	check(w.weak() and not w.strong(), "air vs earth weak")
	check_near(w.amount, 5.0, EPS, "air vs earth 5")
	var n := Damage.resolve_hit(10.0, E.EARTH, earth, t)
	check(not n.strong() and not n.weak() and n.amount == 10.0, "earth vs earth neutral")
	check(Damage.resolve_hit(-5.0, E.FIRE, earth, t).amount == 0.0, "negative damage never heals")
	check_near(Damage.resolve_hit(10.0, E.FIRE, earth).amount, 15.0, EPS, "default table used when none given")

func test_worked_example_25_2() -> void:
	# Apprentice Fire Staff (base 10, basic x1.0) + a Head with damage_bonus 2 = 12 per bolt,
	# into an Earth-affinity target (x1.5) with 30 % fire resist, on its weak point (x2).
	var t := _table()
	var dmg := Damage.wieldable_damage(10.0, 1.0, PackedFloat64Array([2.0]))
	check_near(dmg, 12.0, EPS, "12 per bolt")
	var heap := Damage.Target.new(E.EARTH).set_resist(E.FIRE, 0.3)
	heap.weak_point = true
	var r := Damage.resolve_hit(dmg, E.FIRE, heap, t)
	print("    damage: 12 x %.1f x %.1f x %.0f = %.4f" % [r.effectiveness, 1.0 - r.resist, r.crit, r.amount])
	check_near(r.amount, 12.0 * 1.5 * 0.7 * 2.0, EPS, "12 x 1.5 x 0.7 x 2")
	check_near(r.amount, 25.2, 1e-9, "= 25.2")
	# Same hit with resist over the cap, off the seam: 12 x 1.5 x 0.4 = 7.2.
	heap.set_resist(E.FIRE, 0.75)
	heap.weak_point = false
	check_near(Damage.resolve_hit(dmg, E.FIRE, heap, t).amount, 7.2, 1e-9, "capped, body: 7.2")
