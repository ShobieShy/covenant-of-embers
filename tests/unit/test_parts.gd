extends TestCase
## Step 16 done check: seeded part stat rolls, gem slots, generated names (PartRoller =
## Magewar MagewarLootGenerator.generate_staff_part_with_rng, seeded).
##  - deterministic per seed (same seed = same part, field by field; roll() takes exactly one
##    draw from the caller's rng; the global RNG is never used; regenerate() round-trips);
##  - ranges per type × rarity = Magewar's (× rarity multiplier, fire rates unscaled;
##    Exterior ×0.7–1.3 below Rare, ×0.5–1.0 at Rare+), and the rolls fill them;
##  - Head gem slots 1/1/2/2/3/3, non-Heads 0; template stats kept; nothing ignored rolled;
##  - Magewar name ladders; element weights; rolled parts validate and assemble.

const EPS := 1e-9
const P := WieldablePart.PartType
const E := ElementTable.Element
const TYPES := [P.HEAD, P.EXTERIOR, P.INTERIOR, P.HANDLE, P.CHARM]
const FIELDS := ["id", "display_name", "description", "part_type", "rarity", "element", "damage_bonus",
	"fire_rate_modifier", "accuracy_bonus", "handling_bonus", "gem_slots", "roll_seed"]

## Magewar loot_generator.gd ranges, transcribed independently: [stat, lo, hi, scaled].
const MAGEWAR := {
	P.HEAD: [["damage_bonus", 1.0, 5.0, true], ["accuracy_bonus", 0.0, 10.0, true]],
	P.EXTERIOR: [["fire_rate_modifier", 0.7, 1.3, false]],
	P.INTERIOR: [["damage_bonus", 2.0, 8.0, true]],
	P.HANDLE: [["accuracy_bonus", 5.0, 20.0, true], ["handling_bonus", 2.0, 10.0, true]],
	P.CHARM: [["damage_bonus", 0.0, 3.0, true], ["fire_rate_modifier", 0.85, 1.0, false], ["accuracy_bonus", 0.0, 8.0, true]],
}
const MULT := {"basic": 1.0, "uncommon": 1.25, "rare": 1.5, "mythic": 2.0, "primordial": 2.75, "unique": 3.0}

func _same(a: WieldablePart, b: WieldablePart) -> bool:
	for f in FIELDS:
		if a.get(f) != b.get(f):
			return false
	return true

func _seeded(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng

func test_deterministic_per_seed() -> void:
	for t in TYPES:
		for r in Rarity.IDS:
			var a := PartRoller.from_seed(1234567, t, r)
			var b := PartRoller.from_seed(1234567, t, r)
			check(a != null and _same(a, b), "seed 1234567 %s %s identical" % [t, r])
			check(_same(PartRoller.regenerate(a), a), "regenerate %s %s" % [t, r])
	# Different seeds give different numbers.
	var heads := {}
	for s in 50:
		heads[PartRoller.from_seed(s, P.HEAD, "rare").damage_bonus] = true
	check(heads.size() == 50, "50 seeds, 50 distinct Head damages (got %d)" % heads.size())
	# roll(): exactly one draw from the caller's rng, whatever the type.
	for t in TYPES:
		var rng := _seeded(99)
		var ref := _seeded(99)
		var p := PartRoller.roll(rng, t, "mythic")
		var s := ref.randi()
		check(p.roll_seed == s and rng.state == ref.state, "roll() type %d takes one rng draw" % t)
		check(_same(p, PartRoller.from_seed(s, t, "mythic")), "roll() = from_seed(drawn seed)")
	# Same caller seed -> same drop sequence; the global RNG doesn't matter.
	var seq := func(global_seed: int) -> Array:
		seed(global_seed)
		var rng := _seeded(2026)
		var out := []
		for i in 20:
			out.append(PartRoller.roll(rng, TYPES[i % 5], Rarity.IDS[i % 6]))
		return out
	var x: Array = seq.call(1)
	var y: Array = seq.call(777)
	var all_same := true
	for i in x.size():
		all_same = all_same and _same(x[i], y[i])
	check(all_same, "20-part sequence from seed 2026 identical under different global seeds")
	# An explicit element doesn't change the stat draws; regenerate keeps the element.
	var fire := PartRoller.from_seed(42, P.INTERIOR, "rare", E.FIRE)
	var dark := PartRoller.from_seed(42, P.INTERIOR, "rare", E.DARK)
	check(fire.damage_bonus == dark.damage_bonus and fire.element == E.FIRE and dark.element == E.DARK, "element independent of stats")
	check(PartRoller.regenerate(WieldablePart.load_part("basic_handle")) == null, "hand-made parts aren't regenerated")
	check(PartRoller.from_seed(1, P.HEAD, "epic") == null, "unknown rarity -> null")
	print("    seed 1234567 rare Head: %s, %.3f dmg, %.3f acc" % [PartRoller.from_seed(1234567, P.HEAD, "rare").display_name,
		PartRoller.from_seed(1234567, P.HEAD, "rare").damage_bonus, PartRoller.from_seed(1234567, P.HEAD, "rare").accuracy_bonus])

func test_ranges_per_rarity() -> void:
	var n := 300
	var line := []
	for t in TYPES:
		for r in Rarity.IDS:
			for row in MAGEWAR[t]:
				var stat: String = row[0]
				var m: float = MULT[r] if row[3] else 1.0
				var lo: float = row[1] * m
				var hi: float = row[2] * m
				if t == P.EXTERIOR and Rarity.parse(r) >= Rarity.Tier.RARE:
					lo = 0.5
					hi = 1.0
				var want := Vector2(lo, hi)
				var got := PartRoller.stat_range(t, r, stat)
				check(got.is_equal_approx(want), "%d %s %s range %s (got %s)" % [t, r, stat, want, got])
				var mn := INF
				var mx := -INF
				for s in n:
					var v: float = PartRoller.from_seed(s * 7919 + 3, t, r).get(stat)
					mn = minf(mn, v)
					mx = maxf(mx, v)
				check(mn >= lo - EPS and mx <= hi + EPS, "%d %s %s in [%f, %f] (got %f..%f)" % [t, r, stat, lo, hi, mn, mx])
				check(mn - lo < 0.05 * (hi - lo) and hi - mx < 0.05 * (hi - lo), "%d %s %s fills the range (%f..%f)" % [t, r, stat, mn, mx])
		line.append("%s %s" % [WieldablePart.PART_TYPE_NAMES[t], ",".join(PartRoller.rolled_stats(t))])
	# Fire rates never scale with rarity; Basic/Uncommon Exteriors can be slower than x1.0.
	check(PartRoller.stat_range(P.EXTERIOR, "basic", "fire_rate_modifier").is_equal_approx(Vector2(0.7, 1.3)), "basic exterior 0.7-1.3")
	check(PartRoller.stat_range(P.EXTERIOR, "uncommon", "fire_rate_modifier").is_equal_approx(Vector2(0.7, 1.3)), "uncommon exterior 0.7-1.3")
	check(PartRoller.stat_range(P.CHARM, "unique", "fire_rate_modifier").is_equal_approx(Vector2(0.85, 1.0)), "charm rate unscaled")
	check(PartRoller.stat_range(P.EXTERIOR, "rare", "damage_bonus") == Vector2.ZERO, "exterior rolls no damage")
	print("    rolls: " + "; ".join(line))

func test_gem_slots_templates_and_ignored_stats() -> void:
	var heads := []
	for r in Rarity.IDS:
		heads.append(PartRoller.from_seed(5, P.HEAD, r).gem_slots)
		for t in [P.EXTERIOR, P.INTERIOR, P.HANDLE, P.CHARM]:
			check(PartRoller.from_seed(5, t, r).gem_slots == 0, "%d %s: no gem slots" % [t, r])
			check(PartRoller.gem_slots_for(t, r) == 0, "gem_slots_for non-Head")
	check(heads == [1, 1, 2, 2, 3, 3], "Head gem slots by tier %s" % [heads])
	for s in 40:
		for t in TYPES:
			var p := PartRoller.from_seed(s, t, Rarity.IDS[s % 6])
			check(p.validate().is_empty(), "rolled part valid: %s" % "; ".join(p.validate()))
			check(p.ignored_stats().is_empty(), "%s rolls nothing its type ignores (%s)" % [p.id, p.ignored_stats()])
			for stat in PartRoller.rolled_stats(t):
				if stat == "fire_rate_modifier":
					check(t in WieldablePart.FIRE_RATE_TYPES, "fire rate only on Exterior/Charm")
				if stat == "accuracy_bonus":
					check(t in WieldablePart.ACCURACY_TYPES, "accuracy only on Head/Handle/Charm")
	# Unrolled stats come from Magewar's template part.
	var charm := PartRoller.from_seed(8, P.CHARM, "rare")
	check(charm.handling_bonus == 4.0, "Charm keeps the Rootward template's handling 4")
	var handle := PartRoller.from_seed(8, P.HANDLE, "mythic")
	check(handle.damage_bonus == 0.0 and handle.fire_rate_modifier == 1.0, "Handle: no damage, x1.0")
	var ext := PartRoller.from_seed(8, P.EXTERIOR, "primordial")
	check(ext.damage_bonus == 0.0 and ext.accuracy_bonus == 0.0 and ext.handling_bonus == 0.0, "Exterior: rate only")
	var head := PartRoller.from_seed(8, P.HEAD, "basic")
	check(head.fire_rate_modifier == 1.0 and head.handling_bonus == 0.0, "Head: no rate/handling")
	check(WieldablePart.load_part("uncommon_earth_charm").display_name == "Rootward Talisman", "template untouched")

func test_names_and_descriptions() -> void:
	var want := {
		P.HEAD: ["Rough Fire Crystal Head", "Polished Fire Crystal Head", "Brilliant Fire Crystal Head",
			"Ethereal Fire Crystal Head", "Ancient Fire Crystal Head", "Legendary Fire Crystal Head"],
		P.EXTERIOR: ["Oak Exterior", "Ash Exterior", "Ironwood Exterior", "Darkwood Exterior", "Starwood Exterior", "Worldtree Exterior"],
		P.INTERIOR: ["Fire Mana Core", "Fire Arcane Conduit", "Fire Ley Channel", "Fire Void Heart", "Fire Prism Core", "Fire Soul Engine"],
		P.HANDLE: ["Leather-Wrapped Handle", "Silk-Wrapped Handle", "Chain-Wrapped Handle", "Rune-etched-Wrapped Handle",
			"Crystalweave-Wrapped Handle", "Dragonhide-Wrapped Handle"],
		P.CHARM: ["Fire Charm", "Fire Talisman", "Fire Sigil", "Fire Ward", "Fire Relic", "Fire Artifact"],
	}
	for t in TYPES:
		for i in 6:
			var p := PartRoller.from_seed(11, t, Rarity.IDS[i], E.FIRE)
			check(p.display_name == want[t][i], "name %s (got %s)" % [want[t][i], p.display_name])
			check(p.description == p.full_description(), "description = full_description")
	check(PartRoller.from_seed(3, P.INTERIOR, "basic", E.ARCANE).display_name == "Arcane Mana Core", "Magewar NONE reads Arcane")
	check(PartRoller.from_seed(3, P.CHARM, "rare", E.WATER).display_name == "Water Sigil", "Water Sigil")
	var p := PartRoller.from_seed(0xBEEF, P.HEAD, "rare", E.WATER)
	check(p.id == "rare_water_head_0000beef", "id %s" % p.id)
	check(p.description.begins_with("[Rare] Head\nElement: Water\nDamage: +") and p.description.ends_with("Gem Slots: 2"), "desc:\n%s" % p.description)
	print("    e.g. %s / %s / %s" % [p.display_name, PartRoller.from_seed(7, P.HANDLE, "unique").display_name,
		PartRoller.from_seed(7, P.EXTERIOR, "mythic").display_name])

func test_element_rolls() -> void:
	var rng := _seeded(31337)
	var counts := PackedInt32Array()
	counts.resize(ElementTable.COUNT)
	var n := 20000
	for i in n:
		counts[PartRoller.roll_element(rng)] += 1
	var w := PartRoller.ELEMENT_WEIGHTS
	var total := 0.0
	for x in w:
		total += x
	check(total == 7.0 and w[E.ARCANE] == 2.0 and w[E.LIGHT] == 0.5 and w[E.DARK] == 0.5, "Magewar element_weights")
	for e in ElementTable.COUNT:
		check(absf(counts[e] / float(n) - w[e] / total) < 0.02, "element %d %.3f vs %.3f" % [e, counts[e] / float(n), w[e] / total])
	var only_fire := PackedFloat64Array([0, 1, 0, 0, 0, 0, 0])
	check(PartRoller.roll_element(rng, only_fire) == E.FIRE, "zero weights never chosen")
	# An explicit element is kept on every part type (Magewar assigns the caller's element).
	for t in TYPES:
		check(PartRoller.from_seed(9, t, "uncommon", E.EARTH).element == E.EARTH, "explicit element on type %d" % t)
	print("    elements /20000: %s" % [Array(counts)])

func test_rolled_parts_assemble() -> void:
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	var parts := [PartRoller.from_seed(1, P.HEAD, "rare", E.WATER), PartRoller.from_seed(2, P.EXTERIOR, "rare"),
		PartRoller.from_seed(3, P.INTERIOR, "rare"), PartRoller.from_seed(4, P.HANDLE, "rare"), PartRoller.from_seed(5, P.CHARM, "rare")]
	var dmg := 10.0
	for p in parts:
		staff.parts.append(p)
		dmg += p.damage_bonus
	check_near(staff.damage(), dmg, 1e-6, "10 + rolled damage bonuses")
	check_near(staff.cooldown(), maxf(0.1, 0.4 * parts[1].fire_rate_modifier * parts[4].fire_rate_modifier), 1e-6, "cooldown x exterior x charm")
	check_near(staff.accuracy(), minf(100.0, 50.0 + parts[0].accuracy_bonus + parts[3].accuracy_bonus + parts[4].accuracy_bonus), 1e-6, "accuracy")
	check(staff.element() == E.WATER, "rolled Head element overrides Fire")
	print("    rare roll staff: %.2f dmg / %.3f s / %.1f %%" % [staff.damage(), staff.cooldown(), staff.accuracy()])
