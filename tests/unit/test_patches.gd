extends TestCase
## Step 21 done check: BalancePatch (JSON hotfix patches over the element, rarity and
## drop-pool tables). A valid patch applies to the shared tables; any unknown key, wrong
## type, failed validate() or locked Ember Mark section rejects the whole patch and leaves
## every table untouched. Every test resets the tables from disk afterwards.

const E := ElementTable.Element


func _snapshot() -> Array:
	var el := ElementTable.load_default()
	var ra := RarityTable.load_default()
	var dp := DropRoller.default_pools()
	var mid := dp.find("midden_gnawer")
	return [
		el.strong,
		el.weak,
		el.effectiveness(E.FIRE, E.EARTH),
		el.color(E.FIRE),
		ra.find("rare").drop_weight,
		ra.find("rare").multiplier,
		ra.luck_rare_step,
		mid.drop_chance,
		mid.entries[0].weight,
		mid.entries[0].rarity,
		dp
	]


func test_example_patch_applies() -> void:
	BalancePatch.reset()
	var errs := BalancePatch.apply_file("res://data/patches/example_hotfix.json")
	check(errs.is_empty(), "example patch: %s" % "; ".join(errs))
	var el := ElementTable.load_default()
	check_near(el.effectiveness(E.FIRE, E.EARTH), 1.6, 1e-9, "fire>earth")
	check_near(el.effectiveness(E.EARTH, E.FIRE), 0.5, 1e-9, "weak (earth vs fire) unchanged")
	check_near(el.effectiveness(E.WATER, E.FIRE), 1.6, 1e-9, "water>fire")
	check(el.color(E.FIRE).is_equal_approx(Color.html("#FF4010")), "fire colour")
	var ra := RarityTable.load_default()
	check_near(ra.find("rare").drop_weight, 18.0, 1e-9, "rare weight")
	check_near(ra.luck_rare_step, 2.5, 1e-9, "luck_rare_step")
	check_near(ra.weights(0.0)[Rarity.Tier.RARE], 18.0, 1e-9, "weights() sees the patch")
	var mid := DropRoller.default_pools().find("midden_gnawer")
	check_near(mid.drop_chance, 0.35, 1e-9, "pool chance")
	check_near(mid.entries[3].weight, 12.0, 1e-9, "entry weight")
	check(BalancePatch.applied.has("example_hotfix.json"), "logged")
	BalancePatch.reset()
	check_near(ElementTable.load_default().effectiveness(E.FIRE, E.EARTH), 1.5, 1e-9, "reset elements")
	check_near(RarityTable.load_default().find("rare").drop_weight, 15.0, 1e-9, "reset rarity")
	check_near(DropRoller.default_pools().find("midden_gnawer").drop_chance, 0.3, 1e-9, "reset pools")


func test_pool_rolls_follow_patch() -> void:
	BalancePatch.reset()
	var p := {"version": 1, "drop_pools": {"midden_gnawer": {"drop_chance": 1.0}}}
	check(BalancePatch.apply(p).is_empty(), "chance 1.0")
	var rng := RandomNumberGenerator.new()
	var hits := 0
	for i in 200:
		rng.seed = i
		var drops: Array = DropRoller.roll_kill(rng, "gnawer", 1)
		for d in drops:
			if d.kind == LootDrop.Kind.WIELDABLE:
				hits += 1
				break
	check(hits == 200, "every gnawer kill drops a pool item at chance 1.0 (got %d)" % hits)
	BalancePatch.reset()


func _rejected(patch: Variant, why: String) -> void:
	var before := _snapshot()
	var errs: PackedStringArray
	if patch is String:
		errs = BalancePatch.apply_json(patch)
	else:
		errs = BalancePatch.apply(patch)
	check(not errs.is_empty(), "%s should be rejected" % why)
	var after := _snapshot()
	for i in before.size():
		if before[i] is Color:
			check(before[i].is_equal_approx(after[i]), "%s changed field %d" % [why, i])
		else:
			check(before[i] == after[i], "%s changed field %d (%s -> %s)" % [why, i, before[i], after[i]])


func test_invalid_patches_rejected() -> void:
	BalancePatch.reset()
	_rejected("{not json", "bad JSON")
	_rejected("[1,2]", "top-level array")
	_rejected({"elements": {"strong": 2.0}}, "missing version")
	_rejected({"version": 2, "elements": {"strong": 2.0}}, "wrong version")
	_rejected({"version": 1, "weapons": {}}, "unknown section")
	_rejected({"version": 1, "elements": {"plasma": {"color": "#FFFFFF"}}}, "unknown element")
	_rejected({"version": 1, "elements": {"fire": {"damage": 3}}}, "unknown element key")
	_rejected({"version": 1, "elements": {"strong": "big"}}, "wrong type")
	_rejected({"version": 1, "elements": {"strong": 0.9}}, "strong <= 1 fails validate")
	_rejected({"version": 1, "elements": {"fire": {"strong_against": ["fire"]}}}, "self in strong_against")
	_rejected({"version": 1, "elements": {"fire": {"color": "red-ish"}}}, "bad colour")
	_rejected({"version": 1, "rarities": {"legendary": {"multiplier": 4}}}, "unknown rarity")
	_rejected({"version": 1, "rarities": {"rare": {"multiplier": 0.5}}}, "multiplier below lower tier")
	_rejected({"version": 1, "rarities": {"rare": {"name": "x"}}}, "unknown rarity key")
	_rejected({"version": 1, "drop_pools": {"nowhere": {"drop_chance": 0.1}}}, "unknown pool")
	_rejected({"version": 1, "drop_pools": {"midden_gnawer": {"drop_chance": 1.5}}}, "chance > 1")
	_rejected({"version": 1, "drop_pools": {"midden_gnawer": {"entries": {"99": {"weight": 1}}}}}, "missing entry")
	_rejected({"version": 1, "drop_pools": {"midden_gnawer": {"entries": {"0": {"weight": 0}}}}}, "zero weight")
	_rejected(
		{"version": 1, "drop_pools": {"midden_gnawer": {"entries": {"0": {"rarity": "epic"}}}}}, "unknown entry rarity"
	)
	_rejected({"version": 1, "drop_pools": {"midden_gnawer": {"min_level": 1.5}}}, "fractional level")
	for locked in BalancePatch.LOCKED:
		_rejected({"version": 1, locked: {}}, "locked section " + locked)
	# All-or-nothing: a good section next to a bad one changes nothing.
	_rejected({"version": 1, "elements": {"strong": 2.0}, "rarities": {"rare": {"bogus": 1}}}, "mixed good+bad")
	check(BalancePatch.applied.is_empty(), "nothing logged")
	BalancePatch.reset()


func test_codes_unchanged_by_patch() -> void:
	BalancePatch.reset()
	var code := "EM1-0J2D7-608F0-VHC"
	var before := ItemCodes.decode(code)
	check(before.ok(), "worked example decodes")
	var errs := BalancePatch.apply({"version": 1, "rarities": {"rare": {"drop_weight": 1}}})
	check(errs.is_empty(), "weight-only patch ok")
	var after := ItemCodes.decode(code)
	check(
		after.ok() and ItemCodes.same_item(before.item, after.item),
		"Ember Mark decodes to the same item after a weight patch"
	)
	BalancePatch.reset()


func test_apply_dir() -> void:
	BalancePatch.reset()
	var dir := "user://test_patches_tmp"
	DirAccess.make_dir_recursive_absolute(dir)
	var a := FileAccess.open(dir.path_join("a.json"), FileAccess.WRITE)
	a.store_string('{"version": 1, "rarities": {"rare": {"drop_weight": 20}}}')
	a.close()
	var b := FileAccess.open(dir.path_join("b.json"), FileAccess.WRITE)
	b.store_string('{"version": 1, "rarities": {"rare": {"drop_weight": -1}}}')
	b.close()
	var errs := BalancePatch.apply_dir(dir)
	check(errs.size() >= 1 and errs[0].begins_with("b.json"), "b.json rejected: %s" % "; ".join(errs))
	check_near(RarityTable.load_default().find("rare").drop_weight, 20.0, 1e-9, "a.json applied, b.json didn't undo it")
	check(BalancePatch.apply_dir("user://no_such_dir_xyz").is_empty(), "missing dir = no patches")
	DirAccess.remove_absolute(dir.path_join("a.json"))
	DirAccess.remove_absolute(dir.path_join("b.json"))
	DirAccess.remove_absolute(dir)
	BalancePatch.reset()
