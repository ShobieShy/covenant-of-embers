extends TestCase
## Step 15 done check: the Rarity resource + the Magewar part model.
##  - resources/loot/rarities.tres = PLAN §30.2 (names, hex colours, multipliers, weights)
##    = Magewar ItemRarity (item_rarity.gd consts, transcribed independently here: the
##    Magewar scripts aren't copied into the project);
##  - lookups by id, Magewar fallbacks, bad tables rejected, the shared table untouched by
##    a patched copy;
##  - WieldableInstance damage uses Rarity.multiplier for all six tiers (step 7's temporary
##    lookup is gone, WieldableDef accepts every tier);
##  - Magewar's roll_rarity luck rule and a seeded, deterministic roll;
##  - resources/parts/*.tres = the 16 Magewar part .tres copies (assets/magewar), Head gem
##    slots follow PLAN's 1 / +1 Rare / +1 Primordial, ignored stats, Magewar-style
##    descriptions, assembled-staff stats from real Magewar parts; bad parts rejected.

const EPS := 1e-9
const E := ElementTable.Element
const P := WieldablePart.PartType
const MAGEWAR_PARTS := "res://assets/magewar/resources/items/parts"

## PLAN §30.2 table, transcribed.
const PLAN := [
	["basic", "Basic", "B3B3B3", 1.0, 50.0], ["uncommon", "Uncommon", "33CC33", 1.25, 25.0],
	["rare", "Rare", "3366FF", 1.5, 15.0], ["mythic", "Mythic", "991AE6", 2.0, 7.0],
	["primordial", "Primordial", "FF9900", 2.75, 2.0], ["unique", "Unique", "FFD900", 3.0, 1.0],
]
## Magewar item_rarity.gd RARITY_COLORS, transcribed.
const MAGEWAR_COLORS := [
	Color(0.7, 0.7, 0.7), Color(0.2, 0.8, 0.2), Color(0.2, 0.4, 1.0),
	Color(0.6, 0.1, 0.9), Color(1.0, 0.6, 0.0), Color(1.0, 0.85, 0.0),
]

func _table() -> RarityTable:
	return RarityTable.load_default()

## Magewar .tres: `key = value` lines of the [resource] section (strings unquoted).
func _magewar_tres(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		fail("open " + path)
		return out
	var in_res := false
	for line in f.get_as_text().split("\n"):
		if line.begins_with("["):
			in_res = line.strip_edges() == "[resource]"
			continue
		var eq := line.find(" = ")
		if in_res and eq > 0:
			out[line.substr(0, eq)] = line.substr(eq + 3).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return out

# --- Rarity table ---------------------------------------------------------------------

func test_table_matches_plan_and_magewar() -> void:
	var t := _table()
	check(t != null and t.validate().is_empty(), "rarities.tres valid: %s" % ("; ".join(t.validate()) if t else "null"))
	check(t.rarities.size() == 6, "6 tiers")
	var line := []
	for i in PLAN.size():
		var row: Array = PLAN[i]
		var r := t.tier(i)
		check(r != null and r.id == row[0] and r.tier() == i, "tier %d = %s" % [i, row[0]])
		if r == null:
			continue
		check(r.display_name == row[1], "%s name %s" % [r.id, r.display_name])
		check(r.multiplier == row[3], "%s x%s" % [r.id, r.multiplier])
		check(r.drop_weight == row[4], "%s weight %s" % [r.id, r.drop_weight])
		# Magewar's floats exactly; PLAN's hex is them rounded to 8 bits (+-0.5/255).
		check(r.color.is_equal_approx(MAGEWAR_COLORS[i]), "%s colour = Magewar %s (%s)" % [r.id, MAGEWAR_COLORS[i], r.color])
		var hex := Color.html(row[2])
		for c in 3:
			check(absf(r.color[c] - hex[c]) <= 0.5 / 255.0 + 1e-6, "%s channel %d vs #%s" % [r.id, c, row[2]])
		check(r.color.to_html(false).to_upper() == row[2], "%s hex %s" % [r.id, r.color.to_html(false)])
		line.append("%s #%s x%s w%d" % [r.display_name, r.color.to_html(false).to_upper(), r.multiplier, int(r.drop_weight)])
	print("    rarities: %s" % ", ".join(line))

func test_ids_and_lookups() -> void:
	var t := _table()
	check(Rarity.IDS == WieldableDef.RARITY_IDS, "WieldableDef.RARITY_IDS = Rarity.IDS")
	check(Rarity.COUNT == Rarity.IDS.size() and Rarity.Tier.UNIQUE == 5, "Magewar enum order, 6 tiers")
	check(Rarity.parse("mythic") == Rarity.Tier.MYTHIC and Rarity.parse("epic") == -1, "parse")
	check(Rarity.id_of(Rarity.Tier.PRIMORDIAL) == "primordial", "id_of")
	check(Rarity.of("rare") == t.find("rare") and Rarity.of("rare").multiplier == 1.5, "Rarity.of = shared table")
	check(t.find("legendary") == null and not t.has("legendary") and t.has("unique"), "unknown id -> null")
	# Magewar fallbacks: get_multiplier 1.0, rarity_color WHITE, rarity_name "Unknown".
	check(t.multiplier("legendary") == 1.0 and t.color("x") == Color.WHITE and t.display_name("x") == "Unknown", "fallbacks")
	check(t.tier(-1) == null and t.tier(6) == null, "tier out of range -> null")

func test_bad_tables_rejected() -> void:
	var base: RarityTable = _table().duplicate(true)
	check(base.validate().is_empty(), "copy valid")
	var cases := [
		[func(t: RarityTable) -> void: t.rarities[2].id = "epic", "unknown id"],
		[func(t: RarityTable) -> void: t.rarities[1].id = "basic", "duplicate"],
		[func(t: RarityTable) -> void: t.rarities.remove_at(5), "'unique' missing"],
		[func(t: RarityTable) -> void: t.rarities[0].display_name = "", "display_name is empty"],
		[func(t: RarityTable) -> void: t.rarities[3].multiplier = 0.0, "multiplier must be in"],
		[func(t: RarityTable) -> void: t.rarities[4].multiplier = 1.1, "below the previous tier"],
		[func(t: RarityTable) -> void: t.rarities[0].drop_weight = -1.0, "drop_weight must be >= 0"],
		[func(t: RarityTable) -> void: t.rarities[2].color = Color(1.5, 0, 0), "colour channel"],
		[func(t: RarityTable) -> void: t.luck_rare_step = -2.0, "luck steps"],
		[func(t: RarityTable) -> void: t.rarities.append(null), "null rarity"],
		[func(t: RarityTable) -> void:
			for r in t.rarities:
				r.drop_weight = 0.0, "sum to 0"],
	]
	for c in cases:
		var t: RarityTable = base.duplicate(true)
		(c[0] as Callable).call(t)
		var errs := " | ".join(t.validate())
		check(errs.contains(c[1]), "expected '%s' (got '%s')" % [c[1], errs])
	var patched: RarityTable = base.duplicate(true)
	patched.rarities[5].multiplier = 4.0
	check(patched.validate().is_empty() and patched.multiplier("unique") == 4.0, "patched copy x4")
	check(_table().multiplier("unique") == 3.0, "shared table untouched")

# --- Damage -------------------------------------------------------------------------

func test_rarity_multiplier_drives_wieldable_damage() -> void:
	var consts: Dictionary = (WieldableInstance as Script).get_script_constant_map()
	check(not consts.has("TEMP_RARITY_MULTIPLIER"), "step 7's temporary lookup removed")
	var fire := load("res://resources/wieldables/apprentice_fire_staff.tres") as WieldableDef
	var want := [10.0, 12.5, 15.0, 20.0, 27.5, 30.0]
	var got := []
	for i in Rarity.COUNT:
		var d := fire.duplicate() as WieldableDef
		d.base_rarity = Rarity.IDS[i]
		check(d.validate().is_empty(), "%s base valid" % d.base_rarity)
		var w := WieldableInstance.of(d)
		check(w.rarity() == _table().tier(i), "%s instance rarity" % d.base_rarity)
		check(w.rarity_color() == _table().tier(i).color, "%s colour" % d.base_rarity)
		check_near(w.damage(), want[i], EPS, "Fire staff 10 as %s" % d.base_rarity)
		check_near(WieldableInstance.rarity_multiplier(d.base_rarity) * 10.0, want[i], EPS, "rarity_multiplier %s" % d.base_rarity)
		got.append(w.damage())
	# Parts add flat after the multiplier (Magewar get_final_damage): Mythic 20 + 2 + 3.
	var d2 := fire.duplicate() as WieldableDef
	d2.base_rarity = "mythic"
	var mw := WieldableInstance.of(d2)
	mw.parts.append(WieldablePart.load_part("basic_fire_head"))
	mw.parts.append(WieldablePart.load_part("basic_interior"))
	check_near(mw.damage(), 25.0, EPS, "mythic 20 + head 2 + interior 3")
	check(WieldableInstance.load_base("earthward_battlestaff").rarity().display_name == "Uncommon", "Earthward is Uncommon")
	print("    Fire staff by rarity: %s" % ", ".join(got.map(func(x: float) -> String: return String.num(x, 2))))

# --- Rolls --------------------------------------------------------------------------

func test_luck_weights_and_seeded_roll() -> void:
	var t := _table()
	check(Array(t.weights()) == [50.0, 25.0, 15.0, 7.0, 2.0, 1.0], "luck 0: %s" % t.weights())
	# Magewar roll_rarity: Basic/Uncommon max(1, w - 5 luck), Rare+ w + 2 luck.
	check(Array(t.weights(3.0)) == [35.0, 10.0, 21.0, 13.0, 8.0, 7.0], "luck 3: %s" % t.weights(3.0))
	check(Array(t.weights(10.0)) == [1.0, 1.0, 35.0, 27.0, 22.0, 21.0], "luck 10: %s" % t.weights(10.0))
	# Negative luck: Magewar would give Primordial/Unique negative weights; ours stop at 0.
	check(Array(t.weights(-2.0)) == [60.0, 35.0, 11.0, 3.0, 0.0, 0.0], "luck -2: %s" % t.weights(-2.0))
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 1234
	b.seed = 1234
	var same := true
	var counts := [0, 0, 0, 0, 0, 0]
	var n := 20000
	for i in n:
		var ra := t.roll(a)
		same = same and ra == t.roll(b)
		counts[ra.tier()] += 1
	check(same, "same seed -> same rolls")
	var w := t.weights()
	var shares := []
	for i in 6:
		var share := float(counts[i]) / n
		check(absf(share - w[i] / 100.0) <= 0.02, "%s share %.4f vs %.2f" % [Rarity.IDS[i], share, w[i] / 100.0])
		shares.append("%.3f" % share)
	var c := RandomNumberGenerator.new()
	c.seed = 7
	var rare_hits := 0
	for i in 5000:
		var r := t.roll(c, -2.0)
		if r.tier() >= Rarity.Tier.PRIMORDIAL:
			rare_hits += 1
	check(rare_hits == 0, "zero-weight tiers never rolled (%d)" % rare_hits)
	var d := RandomNumberGenerator.new()
	d.seed = 99
	var s0 := d.state
	t.roll(d)
	d.state = s0
	d.randf()
	var one_draw := d.state
	d.state = s0
	t.roll(d)
	check(d.state == one_draw, "one roll = one randf draw")
	print("    20000 rolls seed 1234: %s" % ", ".join(shares))

# --- Parts --------------------------------------------------------------------------

func test_parts_match_magewar() -> void:
	var ids := WieldablePart.list_ids()
	var files := PackedStringArray()
	for f in DirAccess.get_files_at(MAGEWAR_PARTS):
		if f.ends_with(".tres"):
			files.append(f.get_basename())
	files.sort()
	check(ids.size() == 16 and ids == files, "16 parts = Magewar files (%s)" % ", ".join(ids))
	var by_rarity := [0, 0, 0, 0, 0, 0]
	var by_type := [0, 0, 0, 0, 0]
	for id in ids:
		var p := WieldablePart.load_part(id)
		check(p != null and p.id == id, "%s loads" % id)
		if p == null:
			continue
		check(p.validate().is_empty(), "%s valid: %s" % [id, "; ".join(p.validate())])
		var m := _magewar_tres("%s/%s.tres" % [MAGEWAR_PARTS, id])
		check(m.get("name") == p.display_name, "%s name" % id)
		check(m.get("description") == p.description, "%s description" % id)
		check(int(m.get("part_type", -1)) == p.part_type, "%s part_type" % id)
		check(Rarity.IDS[int(m.get("rarity", 0))] == p.rarity, "%s rarity" % id)
		check(int(m.get("element", -1)) == p.element, "%s element" % id)
		check(int(m.get("gem_slots", -1)) == p.gem_slots, "%s gem_slots" % id)
		for k in ["damage_bonus", "fire_rate_modifier", "accuracy_bonus", "handling_bonus"]:
			check(float(m.get(k, -999)) == float(p.get(k)), "%s %s %s vs %s" % [id, k, m.get(k), p.get(k)])
		check(id.begins_with(p.rarity + "_"), "%s file prefix = rarity" % id)
		by_rarity[Rarity.parse(p.rarity)] += 1
		by_type[p.part_type] += 1
		if p.part_type == P.HEAD:
			# PLAN §30.2: 1 gem slot, +1 at Rare+, +1 at Primordial+ (Magewar's heads agree).
			var t := p.rarity_def().tier()
			var want := 1 + int(t >= Rarity.Tier.RARE) + int(t >= Rarity.Tier.PRIMORDIAL)
			check(p.gem_slots == want, "%s gem slots %d (plan %d)" % [id, p.gem_slots, want])
		else:
			check(p.gem_slots == 0, "%s non-Head has no gem slots" % id)
	check(by_rarity == [6, 4, 3, 1, 1, 1], "per rarity %s" % [by_rarity])
	check(by_type == [4, 3, 3, 3, 3], "per type %s" % [by_type])
	print("    parts: 16 = Magewar, per rarity %s, per type %s" % [by_rarity, by_type])

func test_part_helpers() -> void:
	var head := WieldablePart.load_part("rare_water_head")
	check(head.part_type_name() == "Head" and head.rarity_def().id == "rare", "Head / Rare")
	check(head.rarity_color() == Color(0.2, 0.4, 1.0), "rare blue")
	check(WieldablePart.load_part("nope") == null, "missing part -> null")
	var ignored := {
		"basic_fire_interior": ["fire_rate_modifier", "accuracy_bonus"],
		"basic_earth_interior": ["accuracy_bonus"],
		"rare_water_head": ["fire_rate_modifier"],
		"rare_air_handle": ["fire_rate_modifier"],
		"mythic_water_exterior": ["accuracy_bonus"],
		"uncommon_air_exterior": ["accuracy_bonus"],
		"basic_handle": [], "unique_void_charm": [], "primordial_fire_head": [], "rare_light_charm": [],
	}
	for id in ignored:
		var got := Array(WieldablePart.load_part(id).ignored_stats())
		check(got == ignored[id], "%s ignored %s (got %s)" % [id, ignored[id], got])
	var lone := WieldablePart.make(P.EXTERIOR)
	lone.gem_slots = 1
	check(Array(lone.ignored_stats()) == ["gem_slots"], "a gem slot on an Exterior is inert")
	check(WieldablePart.make(P.EXTERIOR).gem_slots == 0 and WieldablePart.make(P.HEAD).gem_slots == 1,
		"make(): Head 1 gem slot, non-Heads 0 (step 16 fix)")
	var desc := head.full_description()
	check(desc == "[Rare] Head\nElement: Water\nDamage: +6\nAccuracy: +12\nHandling: +1\nGem Slots: 2", "description:\n%s" % desc)
	var charm := WieldablePart.load_part("unique_void_charm").full_description()
	check(charm == "[Unique] Charm\nElement: Dark\nDamage: +8\nFire Rate: x0.85\nAccuracy: +12\nHandling: +5", "charm:\n%s" % charm)
	check(WieldablePart.load_part("basic_exterior").full_description() == "[Basic] Exterior", "plain exterior")

func test_magewar_parts_assemble_stats() -> void:
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	for id in ["basic_fire_head", "basic_exterior", "basic_interior", "basic_handle"]:
		staff.parts.append(WieldablePart.load_part(id))
	check_near(staff.damage(), 15.0, EPS, "10 + 2 + 0 + 3 + 0")
	check(staff.accuracy() == 65.0 and staff.element() == E.FIRE, "accuracy 50 + 5 + 10, Fire")
	check_near(staff.cooldown(), 0.4, EPS, "basic exterior x1.0")
	staff.parts.append(WieldablePart.load_part("rare_light_charm"))
	check_near(staff.damage(), 17.5, EPS, "+ charm 2.5")
	check_near(staff.cooldown(), 0.36, EPS, "charm x0.9")
	check(staff.accuracy() == 75.0, "charm +10")
	var big := WieldableInstance.load_base("earthward_battlestaff")
	for id in ["primordial_fire_head", "mythic_water_exterior", "basic_earth_interior", "rare_air_handle", "unique_void_charm"]:
		big.parts.append(WieldablePart.load_part(id))
	# 14 x 1.25 + 12 + 1.5 + 3.5 + 0 + 8; 0.55 x 0.55 x 0.85 (handle/interior rates ignored);
	# 50 + 15 + 22 + 12 = 99 (exterior/interior accuracy ignored).
	check_near(big.damage(), 42.5, EPS, "Earthward with top parts")
	check_near(big.cooldown(), 0.55 * 0.55 * 0.85, EPS, "Earthward cooldown")
	check(big.accuracy() == 99.0 and big.element() == E.FIRE, "accuracy 99, Head Fire overrides Earth")
	print("    assembled: Fire staff 17.5 / %.2f s / 75 %%, Earthward %.1f / %.4f s / %.0f %%" % [staff.cooldown(), big.damage(), big.cooldown(), big.accuracy()])

func test_bad_parts_rejected() -> void:
	var ok := WieldablePart.load_part("rare_water_head")
	var cases := [
		["id", "Bad Id", "lower_snake_case"], ["display_name", "", "name is empty"],
		["rarity", "epic", "unknown rarity"], ["part_type", 7, "unknown part_type"],
		["element", 9, "unknown element"], ["fire_rate_modifier", 0.0, "fire_rate_modifier must be in"],
		["damage_bonus", 500.0, "damage_bonus must be in"], ["accuracy_bonus", -101.0, "accuracy_bonus must be in"],
		["handling_bonus", 1000.0, "handling_bonus must be in"], ["gem_slots", 4, "gem_slots must be in"],
	]
	for c in cases:
		var p := ok.duplicate() as WieldablePart
		p.set(c[0], c[1])
		var errs := " | ".join(p.validate())
		check(errs.contains(c[2]), "%s = %s -> '%s' (got '%s')" % [c[0], c[1], c[2], errs])
	check(ok.validate().is_empty(), "shared part untouched")
