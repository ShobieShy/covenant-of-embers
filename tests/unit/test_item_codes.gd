extends TestCase
## Step 20 done check: Ember Mark item codes (ItemCodes / EmberMark / BitStream; PLAN §31.5):
##  - CRC-16/CCITT-FALSE check value, Crockford base32 round trip and look-alike letters;
##  - 1000 random items (DropRoller.roll_enemy kills, PartRoller/EquipmentRoller rolls,
##    assembled staffs/wands from rolled + hand-made parts, bare bases with rarity overrides,
##    hand-made parts, equipment templates, potion stacks) round-trip: decode(encode(x)) is
##    the same item (every property, exact floats) and re-encodes to the same code;
##  - assembled wieldables come back through Assembly.assemble (worked example 3: 46 dmg,
##    "Rare Fire Staff"), golden codes keep the v1 format frozen;
##  - bad codes rejected: bad prefix, bad characters, bad checksum (every position), truncated,
##    trailing data, unknown version/kind/flags/ids/tiers/elements/slots, bad potion counts,
##    builds failing Assembly.check;
##  - encode refuses what a code can't reproduce (edited parts/bases, loose parts, illegal
##    builds, bad stacks);
##  - index tables are append-only and cover every shipped resource id.

const P := WieldablePart.PartType
const E := ElementTable.Element
const K := ItemCodes.Kind

## Golden v1 codes: if one of these changes, old saves/shared codes break → add a version.
const GOLDEN_PART := "EM1-0M08G-1G7ZX-R7FX8"
const GOLDEN_EQUIP := "EM1-0R18G-00002-CFKSR"
const GOLDEN_STAFF := "EM1-0J042-1MB00-000AH-075AG"
const GOLDEN_POTION := "EM1-0W431-XQP"


func _rarity(rng: RandomNumberGenerator) -> String:
	return Rarity.IDS[rng.randi_range(0, Rarity.COUNT - 1)]


func _element(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(-1, ElementTable.COUNT - 1)  # -1 = rolled


func _handmade_of(t: int) -> Array[WieldablePart]:
	var out: Array[WieldablePart] = []
	for id in ItemCodes.table("parts"):
		var p := WieldablePart.load_part(id)
		if p.part_type == t:
			out.append(p)
	return out


func _random_part(rng: RandomNumberGenerator, t: int) -> WieldablePart:
	var hand := _handmade_of(t)
	if not hand.is_empty() and rng.randf() < 0.3:
		return hand[rng.randi_range(0, hand.size() - 1)]
	return PartRoller.roll(rng, t as WieldablePart.PartType, _rarity(rng), _element(rng))


func _random_base(rng: RandomNumberGenerator) -> WieldableInstance:
	var ids := ItemCodes.table("wieldables")
	var w := WieldableInstance.load_base(ids[rng.randi_range(0, ids.size() - 1)])
	if rng.randf() < 0.5:
		var d := w.def.duplicate() as WieldableDef
		d.base_rarity = _rarity(rng)
		w = WieldableInstance.of(d)
	return w


func _random_assembled(rng: RandomNumberGenerator) -> WieldableInstance:
	var base := _random_base(rng)
	var parts: Array = []
	for t in Assembly.required_types(base.def.type):
		parts.append(_random_part(rng, t))
	for t in Assembly.optional_types(base.def.type):
		if rng.randf() < 0.5:
			parts.append(_random_part(rng, t))
	parts.shuffle()  # assemble() sorts them
	return Assembly.assemble(base.def, parts)


## [item, count] pairs, mixed kinds, deterministic.
func _random_items(n: int, s: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	seed(s)  # parts.shuffle() uses the global RNG
	var enemies := [EnemyTable.load_default().find("gnawer"), EnemyTable.load_default().find("heap")]
	var out: Array = []
	while out.size() < n:
		match rng.randi_range(0, 7):
			0, 1:
				for d in DropRoller.roll_enemy(rng, enemies[rng.randi_range(0, 1)], rng.randf_range(0.0, 5.0)):
					out.append([d.item, 1])
			2:
				out.append(
					[
						PartRoller.roll(
							rng, rng.randi_range(0, 4) as WieldablePart.PartType, _rarity(rng), _element(rng)
						),
						1
					]
				)
			3:
				out.append([EquipmentRoller.roll(rng, rng.randi_range(0, 4), _rarity(rng), _element(rng)), 1])
			4, 5:
				out.append([_random_assembled(rng), 1])
			6:
				out.append([_random_base(rng), 1])
			7:
				match rng.randi_range(0, 2):
					0:
						var ids := ItemCodes.table("parts")
						out.append([WieldablePart.load_part(ids[rng.randi_range(0, ids.size() - 1)]), 1])
					1:
						var ids := ItemCodes.table("equipment")
						out.append([EquipmentItem.load_item(ids[rng.randi_range(0, ids.size() - 1)]), 1])
					2:
						var ids := ItemCodes.table("consumables")
						var c := ConsumableItem.load_item(ids[rng.randi_range(0, ids.size() - 1)])
						out.append([c, rng.randi_range(1, c.stack_size)])
	out.resize(n)
	return out


func test_crc_and_base32() -> void:
	check(ItemCodes.crc16("123456789".to_ascii_buffer()) == 0x29B1, "CRC-16/CCITT-FALSE check value")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001
	for n in range(0, 40):
		var b := PackedByteArray()
		for i in n:
			b.append(rng.randi_range(0, 255))
		var s := ItemCodes.base32_encode(b)
		check(s.length() == ceili(n * 8 / 5.0), "length %d bytes -> %d chars" % [n, s.length()])
		var d := ItemCodes.base32_decode(s)
		check(d.has("bytes") and d["bytes"] == b, "base32 round trip %d bytes" % n)
		check(ItemCodes.base32_decode(s.to_lower()).get("bytes") == b, "lower case accepted")
	# Crockford look-alikes: O = 0, I = L = 1; U is not in the alphabet.
	check(ItemCodes.base32_decode("O1").get("bytes") == ItemCodes.base32_decode("01").get("bytes"), "O = 0")
	check(ItemCodes.base32_decode("0I").get("bytes") == ItemCodes.base32_decode("01").get("bytes"), "I = 1")
	check(ItemCodes.base32_decode("0L").get("bytes") == ItemCodes.base32_decode("01").get("bytes"), "L = 1")
	check(ItemCodes.base32_decode("0U").has("error"), "U rejected")
	var bs := BitStream.new()
	bs.write(5, 3)
	bs.write(0xFFFFFFFF, 32)
	bs.write(1, 1)
	var r := BitStream.new()
	r.load_bytes(bs.to_bytes())
	check(r.read(3) == 5 and r.read(32) == 0xFFFFFFFF and r.read(1) == 1 and r.rest_is_zero(), "bit stream")
	r.read(16)
	check(r.overrun, "reading past the end sets overrun")


func test_round_trip_1000_random_items() -> void:
	var items := _random_items(1000, 20)
	var kinds := {}
	var longest := 0
	var bad := 0
	for pair in items:
		var item: Resource = pair[0]
		var count: int = pair[1]
		var code := ItemCodes.encode(item, count)
		if code.is_empty():
			bad += 1
			if bad <= 5:
				fail("encode refused %s: %s" % [item, ItemCodes.encode_error(item, count)])
			continue
		longest = maxi(longest, code.length())
		var m := ItemCodes.decode(code)
		if not m.ok():
			bad += 1
			if bad <= 5:
				fail("decode failed %s: %s" % [code, m.error])
			continue
		kinds[m.kind] = kinds.get(m.kind, 0) + 1
		if not ItemCodes.same_item(item, m.item) or m.count != count:
			bad += 1
			if bad <= 5:
				fail("round trip differs for %s" % code)
			continue
		var again := ItemCodes.encode(m.item, m.count)
		if again != code:
			bad += 1
			if bad <= 5:
				fail("re-encode differs: %s vs %s" % [code, again])
		if m.item is WieldableInstance:
			var a := item as WieldableInstance
			var b := m.item as WieldableInstance
			if (
				a.damage() != b.damage()
				or a.cooldown() != b.cooldown()
				or a.accuracy() != b.accuracy()
				or a.display_name() != b.display_name()
				or a.rarity_id() != b.rarity_id()
				or a.element() != b.element()
			):
				bad += 1
				fail("wieldable stats differ for %s" % code)
	check(bad == 0, "%d of 1000 items failed the round trip" % bad)
	for k in ItemCodes.Kind.values():
		if k == ItemCodes.Kind.GEM:
			continue  # v2 kind, covered by test_item_codes_v2.gd (step 44)
		check(kinds.get(k, 0) >= 10, "kind %s covered (%d)" % [ItemCodes.Kind.keys()[k], kinds.get(k, 0)])
	check(longest <= 64, "longest code %d chars" % longest)
	print("    round trip: 1000 items, kinds %s, longest code %d chars" % [kinds, longest])


func test_decoded_items_are_fresh_and_assembled() -> void:
	# Worked example 3 (PLAN §30.3): Earthward + 5 Magewar parts -> Rare Fire Staff, 46 dmg.
	var parts: Array = []
	for id in [
		"primordial_fire_head", "mythic_water_exterior", "basic_earth_interior", "rare_air_handle", "unique_void_charm"
	]:
		parts.append(WieldablePart.load_part(id))
	var w := Assembly.assemble(WieldableInstance.load_base("earthward_battlestaff").def, parts)
	var m := ItemCodes.decode(ItemCodes.encode(w))
	check(m.ok() and m.kind == K.ASSEMBLED, "assembled decodes: %s" % m.error)
	var d := m.item as WieldableInstance
	check(d.assembled and d.display_name() == "Rare Fire Staff", "name %s" % d.display_name())
	check_near(d.damage(), 46.0, 1e-9, "damage")
	check_near(d.cooldown(), 0.55 * 0.55 * 0.85, 1e-9, "cooldown")
	check(d.gem_slots() == 3, "gem slots")
	check(d.parts[0] != parts[0] and ItemCodes.same_item(d.parts[0], parts[0]), "hand-made parts come back as copies")
	check(
		WieldablePart.load_part("primordial_fire_head").damage_bonus == parts[0].damage_bonus, "shared part untouched"
	)
	# Rarity override on a bare base: copy, shared base stays Basic.
	var base := WieldableInstance.load_base("apprentice_fire_staff")
	var dup := base.def.duplicate() as WieldableDef
	dup.base_rarity = "mythic"
	var mb := ItemCodes.decode(ItemCodes.encode(WieldableInstance.of(dup)))
	check(mb.ok() and (mb.item as WieldableInstance).rarity_id() == "mythic", "override kept")
	check_near((mb.item as WieldableInstance).damage(), 20.0, 1e-9, "mythic staff 10 x 2")
	check(base.def.base_rarity == "basic", "shared base still basic")
	# Formatting tolerance: case, spaces, look-alikes, missing group dashes.
	var code := ItemCodes.encode(PartRoller.from_seed(123456, P.HEAD, "rare", E.FIRE))
	check(ItemCodes.decode(code.to_lower()).ok(), "lower case")
	check(ItemCodes.decode("  " + code + "\n").ok(), "surrounding whitespace")
	check(ItemCodes.decode("EM1-" + code.substr(4).replace("-", "")).ok(), "no group dashes")
	check(ItemCodes.decode(code.replace("0", "O")).ok(), "O for 0")


func test_golden_codes() -> void:
	var part := PartRoller.from_seed(0xC0FFEE, P.HEAD, "rare", E.FIRE)
	var equip := EquipmentRoller.from_seed(19, EquipmentItem.Slot.CLOTHES, "rare", E.FIRE)
	var parts: Array = [
		WieldablePart.load_part("basic_fire_head"),
		WieldablePart.load_part("basic_exterior"),
		PartRoller.from_seed(42, P.INTERIOR, "uncommon", E.EARTH),
		WieldablePart.load_part("basic_handle")
	]
	var staff := Assembly.assemble(WieldableInstance.load_base("apprentice_fire_staff").def, parts)
	var codes := [
		ItemCodes.encode(part),
		ItemCodes.encode(equip),
		ItemCodes.encode(staff),
		ItemCodes.encode(ConsumableItem.load_item("mana_potion"), 3)
	]
	print("    golden: %s" % [codes])
	check(codes[0] == GOLDEN_PART, "part code %s" % codes[0])
	check(codes[1] == GOLDEN_EQUIP, "equipment code %s" % codes[1])
	check(codes[2] == GOLDEN_STAFF, "staff code %s" % codes[2])
	check(codes[3] == GOLDEN_POTION, "potion code %s" % codes[3])


func _raw(build: Callable) -> String:
	var w := BitStream.new()
	build.call(w)
	return ItemCodes.seal(w.to_bytes())


func _rejects(code: String, needle: String, what: String) -> void:
	var m := ItemCodes.decode(code)
	check(not m.ok() and m.item == null, "%s accepted" % what)
	check(needle.is_empty() or m.error.contains(needle), "%s: error '%s' lacks '%s'" % [what, m.error, needle])


func test_bad_codes_rejected() -> void:
	var good := ItemCodes.encode(PartRoller.from_seed(777, P.CHARM, "unique", E.DARK))
	check(ItemCodes.decode(good).ok(), "good code decodes")
	# Prefix
	for s in ["", "EM2" + good.substr(3), "XX1" + good.substr(3), "EM1" + good.substr(4), good.substr(4)]:
		_rejects(s, "prefix", "bad prefix '%s'" % s)
	_rejects("EM1-", "empty", "empty body")
	_rejects(good.replace(good[6], "U"), "character", "bad character")
	# Checksum: change every character (except the padded last one) to another symbol.
	var body := good.substr(4)
	for i in body.length() - 1:
		if body[i] == "-":
			continue
		var c := ItemCodes.ALPHABET[(ItemCodes.ALPHABET.find(body[i]) + 7) % 32]
		_rejects(good.substr(0, 4 + i) + c + good.substr(5 + i), "checksum", "typo at %d" % i)
	# Swapped neighbours.
	var swapped := good.substr(0, 4) + body[1] + body[0] + body.substr(2)
	if swapped != good:
		_rejects(swapped, "", "swapped characters")
	# Truncated: every shorter prefix of the body.
	var plain := body.replace("-", "")
	for n in range(0, plain.length()):
		_rejects("EM1-" + plain.substr(0, n), "", "truncated to %d chars" % n)
	# Extra data after a valid payload (CRC recomputed): rejected, not ignored.
	var m0 := ItemCodes.decode(good)
	var w0 := BitStream.new()
	ItemCodes.write_header(w0, K.PART)
	w0.write(P.CHARM, 3)
	w0.write(5, 3)
	w0.write(E.DARK, 3)
	w0.write(777, 32)
	check(ItemCodes.seal(w0.to_bytes()) == good, "raw builder matches encode (%s)" % m0.error)
	w0.write(0xAB, 8)
	_rejects(ItemCodes.seal(w0.to_bytes()), "trailing", "trailing byte")
	# Header problems.
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.WIELDABLE, 2)
				w.write(0, 5)
		),
		"version",
		"unknown version 2"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.WIELDABLE, 0)
				w.write(0, 5)
		),
		"version",
		"version 0"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, 7)
				w.write(0, 8)
		),
		"kind",
		"unknown kind 7"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.WIELDABLE, 1, 2)
				w.write(0, 5)
		),
		"flags",
		"unknown flags"
	)
	# Unknown ids / out-of-range fields.
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.EQUIPMENT_TEMPLATE)
				w.write(7, 3)
		),
		"unknown equipment index",
		"equipment index 7"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.EQUIPMENT_TEMPLATE)
				w.write(5, 3)
		),
		"unknown equipment index",
		"equipment index 5"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.WIELDABLE)
				w.write(0, 2)
				w.write(6, 3)
		),
		"rarity tier",
		"rarity tier 6"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.PART)
				w.write(5, 3)
				w.write(0, 3)
				w.write(0, 3)
				w.write(1, 32)
		),
		"part type",
		"part type 5"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.PART)
				w.write(0, 3)
				w.write(7, 3)
				w.write(0, 3)
				w.write(1, 32)
		),
		"rarity tier",
		"part tier 7"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.PART)
				w.write(0, 3)
				w.write(0, 3)
				w.write(7, 3)
				w.write(1, 32)
		),
		"element",
		"element 7"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.EQUIPMENT)
				w.write(5, 3)
				w.write(0, 3)
				w.write(0, 3)
				w.write(1, 32)
		),
		"slot",
		"slot 5"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.EQUIPMENT)
				w.write(0, 3)
				w.write(0, 3)
				w.write(7, 3)
				w.write(1, 32)
		),
		"element",
		"equipment element 7"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.POTION)
				w.write(1, 1)
				w.write(0, 7)
		),
		"count",
		"potion count 0"
	)
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.POTION)
				w.write(1, 1)
				w.write(6, 7)
		),
		"count",
		"potion count 6"
	)
	_rejects(_raw(func(w: BitStream) -> void: ItemCodes.write_header(w, K.PART)), "truncated", "header only")
	_rejects(
		_raw(
			func(w: BitStream) -> void:
				ItemCodes.write_header(w, K.PART)
				w.write(0, 3)
				w.write(0, 3)
				w.write(0, 3)
				w.write(1, 20)
		),
		"truncated",
		"short seed"
	)


## An ASSEMBLED payload: base index, tier, then [rolled?, fields...] records.
func _assembled_code(base_idx: int, records: Array) -> String:
	return _raw(
		func(w: BitStream) -> void:
			ItemCodes.write_header(w, K.ASSEMBLED)
			w.write(base_idx, 2)
			w.write(0, 3)
			w.write(records.size(), 3)
			for rec in records:
				if rec is int:  # hand-made part index
					w.write(0, 1)
					w.write(rec, 4)
				else:  # [type, tier, element, seed]
					w.write(1, 1)
					w.write(rec[0], 3)
					w.write(rec[1], 3)
					w.write(rec[2], 3)
					w.write(rec[3], 32)
	)


func test_failing_assembly_rejected() -> void:
	var ids := ItemCodes.table("parts")
	var head := ids.find("basic_fire_head")
	var ext := ids.find("basic_exterior")
	var inter := ids.find("basic_interior")
	var handle := ids.find("basic_handle")
	var staff := ItemCodes.table("wieldables").find("apprentice_fire_staff")
	var wand := ItemCodes.table("wieldables").find("novice_arcane_wand")
	var ok := ItemCodes.decode(_assembled_code(staff, [head, ext, inter, handle]))
	check(
		ok.ok() and (ok.item as WieldableInstance).damage() == 15.0,
		"legal staff decodes (worked example 1): %s" % ok.error
	)
	var ok2 := ItemCodes.decode(_assembled_code(wand, [head, [P.EXTERIOR, 2, 0, 99]]))
	check(ok2.ok(), "legal wand decodes: %s" % ok2.error)
	_rejects(_assembled_code(wand, [head]), "needs a Exterior", "wand without Exterior")
	_rejects(_assembled_code(wand, [head, ext, inter]), "can't take a Interior", "wand with an Interior")
	_rejects(_assembled_code(staff, [head, head, ext, inter, handle]), "two Head", "staff with two Heads")
	_rejects(_assembled_code(staff, [head, ext, inter]), "needs a Handle", "staff missing a Handle")
	_rejects(_assembled_code(staff, []), "assembly fails", "staff with no parts")
	_rejects(
		_assembled_code(staff, [head, ext, inter, handle, [P.HEAD, 0, 0, 5], [P.CHARM, 0, 0, 6]]),
		"assembly fails",
		"6 parts"
	)
	_rejects(
		_assembled_code(staff, [head, ext, inter, handle, [P.HEAD, 6, 0, 1]]),
		"rarity tier",
		"bad part inside an assembly"
	)


func test_encode_refuses_unreproducible_items() -> void:
	check(ItemCodes.encode(null) == "" and ItemCodes.encode_error(null) == "not an item", "null")
	var edited := WieldablePart.load_part("basic_fire_head").duplicate() as WieldablePart
	edited.damage_bonus += 1.0
	check(ItemCodes.encode(edited) == "" and ItemCodes.encode_error(edited).contains("edited"), "edited hand-made part")
	var rolled := PartRoller.from_seed(5, P.HEAD, "rare", E.FIRE)
	rolled.accuracy_bonus = 99.0
	check(ItemCodes.encode(rolled) == "" and ItemCodes.encode_error(rolled).contains("seed"), "edited rolled part")
	var big := PartRoller.from_seed(5, P.HEAD, "rare", E.FIRE)
	big.roll_seed = 1 << 32
	check(ItemCodes.encode(big) == "", "seed out of range")
	var unknown := WieldablePart.load_part("basic_handle").duplicate() as WieldablePart
	unknown.id = "custom_handle"
	check(ItemCodes.encode_error(unknown).contains("index table"), "unknown hand-made id")
	var loose := WieldableInstance.load_base("apprentice_fire_staff")
	loose.parts = [WieldablePart.load_part("basic_fire_head")]
	check(ItemCodes.encode_error(loose).contains("unassembled"), "loose parts")
	var illegal := WieldableInstance.load_base("novice_arcane_wand")
	illegal.parts = [WieldablePart.load_part("basic_fire_head")]
	illegal.assembled = true
	check(ItemCodes.encode_error(illegal).contains("illegal build"), "assembled flag on an illegal build")
	var custom := WieldableInstance.load_base("apprentice_fire_staff").def.duplicate() as WieldableDef
	custom.damage = 99.0
	check(ItemCodes.encode_error(WieldableInstance.of(custom)).contains("edited"), "edited base")
	custom.id = "homebrew_staff"
	check(ItemCodes.encode_error(WieldableInstance.of(custom)).contains("index table"), "unknown base")
	var potion := ConsumableItem.load_item("health_potion")
	check(ItemCodes.encode(potion, 0) == "" and ItemCodes.encode(potion, 6) == "", "potion stack 0 / 6")
	check(ItemCodes.decode(ItemCodes.encode(potion, 5)).count == 5, "stack of 5")
	var robe := EquipmentRoller.from_seed(3, EquipmentItem.Slot.CLOTHES, "rare", E.WATER)
	robe.elemental_resistance = 0.9
	check(ItemCodes.encode_error(robe).contains("seed"), "edited rolled equipment")
	var hat := EquipmentItem.load_item("apprentice_hat").duplicate() as EquipmentItem
	hat.mana_bonus = 50.0
	check(ItemCodes.encode_error(hat).contains("edited"), "edited template")


func test_index_tables_append_only_and_complete() -> void:
	var dirs := {
		"wieldables": "res://resources/wieldables",
		"parts": WieldablePart.DIR,
		"equipment": EquipmentItem.DIR,
		"consumables": ConsumableItem.DIR
	}
	var versions := ItemCodes.TABLES.keys()
	versions.sort()
	check(versions[-1] == ItemCodes.VERSION, "VERSION is the newest table")
	check(ItemCodes.VERSION < (1 << ItemCodes.VERSION_BITS), "version fits")
	for cat in dirs:
		var latest := ItemCodes.table(cat)
		# Every shipped resource has an index (new content -> append + new version).
		for f in ResourceLoader.list_directory(dirs[cat]):
			if f.ends_with(".tres"):
				check(latest.has(f.get_basename()), "%s/%s missing from index table v%d" % [cat, f, ItemCodes.VERSION])
		var seen := {}
		for id in latest:
			check(not seen.has(id), "%s: duplicate %s" % [cat, id])
			seen[id] = true
			check(ResourceLoader.exists("%s/%s.tres" % [dirs[cat], id]), "%s: %s has no resource" % [cat, id])
		# Append-only: each older version is a prefix of every newer one.
		for i in range(1, versions.size()):
			var old := ItemCodes.table(cat, versions[i - 1])
			var new := ItemCodes.table(cat, versions[i])
			check(
				new.slice(0, old.size()) == old, "%s: v%d isn't a prefix of v%d" % [cat, versions[i - 1], versions[i]]
			)
	check(ItemCodes.table("parts").size() <= (1 << 4), "hand-made part index fits 4 bits")
