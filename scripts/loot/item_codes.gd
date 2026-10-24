class_name ItemCodes
extends RefCounted
## Ember Marks: compact, versioned, plain-text item codes for saving and sharing (BUILD_PLAN
## step 20; PLAN §31.5). Code = "EM1-" + Crockford base32 of (bit-packed payload + CRC-16),
## grouped in fives with "-" for reading aloud ("EM1-0G4R8-...") — decode ignores the
## grouping, case, and Crockford's O/I/L look-alikes.
##
## Payload v1 (MSB first; fields are fixed-width unsigned ints):
##   header: version 6 b (= index-table version) | kind 3 b | flags 3 b (none defined in v1;
##           non-zero is rejected so a later flag can't be silently dropped)
##   WIELDABLE           base index | rarity tier 3 b (a pool's rarity override survives)
##   ASSEMBLED           base index | rarity tier 3 b | part count 3 b | count × part record
##   PART                part type 3 b | rarity tier 3 b | element 3 b | roll_seed 32 b
##   PART_HANDMADE       part index
##   EQUIPMENT           slot 3 b | rarity tier 3 b | element 3 b | roll_seed 32 b
##   EQUIPMENT_TEMPLATE  equipment index
##   POTION              consumable index | count 7 b (1..stack_size)
##   part record = rolled 1 b, then the PART fields (rolled) or a part index (hand-made)
##   GEM (step 44)       element 3 b
##   v2 extras (step 44): flag FLAG_EXTRAS set (and prefix "EM2-") when an item carries
##   socketed gems or a consecration. Then every part record (loose or inside an assembled
##   wieldable) is followed by: gem count 2 b | count × element 3 b, and an EQUIPMENT /
##   EQUIPMENT_TEMPLATE record by: consecration 3 b (0 none, else Consecrations.IDS index + 1).
##   Items without extras still encode as the exact same EM1 code (old codes keep decoding).
##   then CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) over the payload bytes.
## Indices point into the version's append-only index tables (TABLES); their bit width is
## bits_for(table size) of that version, so a frozen version always decodes the same way.
## New content = a new TABLES version that starts with the old list; old codes keep decoding.
##
## Nothing derived is stored: rolled parts/equipment come back exactly from
## PartRoller.from_seed / EquipmentRoller.from_seed (same floats, names, ids), assembled
## wieldables from Assembly.assemble (rarity, name and stats recomputed); a code whose parts
## fail Assembly.check is rejected. encode() refuses items a code can't reproduce exactly
## (an edited hand-made part or base, a rolled part that no longer matches its seed, loose
## parts on an unassembled base, a potion stack outside 1..stack_size): it returns "" and
## encode_error() says why. Codes are plain, not obfuscated (open-source game; the CRC only
## catches typos; co-op hosts re-validate shared items, step 22+).
## Magewar (magewar_instanced_loot_service serialize_drop) sends dictionaries with every
## rolled stat and a resource path for anything else, and can't send assembled staffs;
## ours is seed-based and covers every item kind (reinterpreted, PLAN §31.5).

enum Kind { WIELDABLE, ASSEMBLED, PART, PART_HANDMADE, EQUIPMENT, EQUIPMENT_TEMPLATE, POTION, GEM }

const PREFIX := "EM1-"
const PREFIX_V2 := "EM2-"  ## step 44: codes with FLAG_EXTRAS or a GEM
const FLAG_EXTRAS := 1
const GEM_COUNT_BITS := 2
const CONSECRATION_BITS := 3
const VERSION := 1  ## current index-table version (written by encode)
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  ## Crockford base32
const GROUP := 5  ## characters per "-" group
const VERSION_BITS := 6
const KIND_BITS := 3
const FLAGS_BITS := 3
const TIER_BITS := 3
const ELEMENT_BITS := 3
const PART_TYPE_BITS := 3
const SLOT_BITS := 3
const SEED_BITS := 32
const PART_COUNT_BITS := 3
const COUNT_BITS := 7

## Append-only index tables per version (ids of resources/wieldables, parts, equipment,
## consumables). NEVER reorder or remove an entry; add a new version instead.
const TABLES := {
	1:
	{
		"wieldables":
		["apprentice_fire_staff", "earthward_battlestaff", "novice_arcane_wand", "swift_wind_wand"],
		"parts":
		[
			"basic_earth_interior",
			"basic_exterior",
			"basic_fire_head",
			"basic_fire_interior",
			"basic_handle",
			"basic_interior",
			"mythic_water_exterior",
			"primordial_fire_head",
			"rare_air_handle",
			"rare_light_charm",
			"rare_water_head",
			"uncommon_air_exterior",
			"uncommon_dark_handle",
			"uncommon_earth_charm",
			"uncommon_fire_head",
			"unique_void_charm"
		],
		"equipment":
		["apprentice_hat", "basic_robes", "leather_belt", "novice_grimoire", "traveler_shoes"],
		"consumables": ["health_potion", "mana_potion"],
	},
}


## Bits needed for an index into a table of `n` entries (at least 1).
static func bits_for(n: int) -> int:
	var b := 1
	while (1 << b) < n:
		b += 1
	return b


static func table(category: String, version := VERSION) -> Array:
	return TABLES.get(version, {}).get(category, [])


## The Ember Mark of `item` (WieldableInstance, WieldablePart, EquipmentItem, ConsumableItem
## with `count`, or a LootDrop's item); "" when it can't be encoded exactly (encode_error()).
static func encode(item: Variant, count := 1) -> String:
	return _encode(item, count)[0]


## Why encode() refuses `item` ("" when it encodes).
static func encode_error(item: Variant, count := 1) -> String:
	return _encode(item, count)[1]


static func _encode(item: Variant, count: int) -> Array:
	if item is LootDrop:
		item = (item as LootDrop).item
	var w := BitStream.new()
	var err := ""
	var ex := has_extras(item)
	if item is ElementGem:
		write_header(w, Kind.GEM)
		w.write((item as ElementGem).element, ELEMENT_BITS)
		return [seal(w.to_bytes(), PREFIX_V2), ""]
	if item is WieldableInstance:
		err = _write_wieldable(w, item, ex)
	elif item is WieldablePart:
		var p := item as WieldablePart
		err = _check_part(p)
		if err.is_empty():
			var fl := FLAG_EXTRAS if ex else 0
			if p.roll_seed >= 0:
				write_header(w, Kind.PART, VERSION, fl)
			else:
				write_header(w, Kind.PART_HANDMADE, VERSION, fl)
			_write_part_fields(w, p, ex)
	elif item is EquipmentItem:
		err = _write_equipment(w, item, ex)
	elif item is ConsumableItem:
		err = _write_potion(w, item, count)
	else:
		err = "not an item"
	if not err.is_empty():
		return ["", err]
	return [seal(w.to_bytes(), PREFIX_V2 if ex else PREFIX), ""]


## Step 44: true when `item` needs the v2 extras (socketed gems or a consecration).
static func has_extras(item: Variant) -> bool:
	if item is WieldablePart:
		return not (item as WieldablePart).gems.is_empty()
	if item is EquipmentItem:
		return not (item as EquipmentItem).consecration.is_empty()
	if item is WieldableInstance:
		for p in (item as WieldableInstance).parts:
			if p != null and not p.gems.is_empty():
				return true
	return false


static func write_header(w: BitStream, kind: int, version := VERSION, flags := 0) -> void:
	w.write(version, VERSION_BITS)
	w.write(kind, KIND_BITS)
	w.write(flags, FLAGS_BITS)


static func _write_wieldable(w: BitStream, wi: WieldableInstance, ex := false) -> String:
	if wi.def == null:
		return "wieldable has no base"
	var ids := table("wieldables")
	var idx := ids.find(wi.def.id)
	if idx < 0:
		return "base '%s' is not in the index table" % wi.def.id
	var shared := WieldableInstance.load_base(wi.def.id).def
	if not _props_equal(wi.def, shared, ["base_rarity"]):
		return "base '%s' was edited (only its rarity can differ)" % wi.def.id
	var tier := Rarity.parse(wi.def.base_rarity)
	if tier < 0:
		return "unknown rarity '%s'" % wi.def.base_rarity
	if wi.assembled:
		var problems := Assembly.check(wi.def, wi.parts)
		if not problems.is_empty():
			return "illegal build: " + "; ".join(problems)
		for p in wi.parts:
			var e := _check_part(p)
			if not e.is_empty():
				return e
		write_header(w, Kind.ASSEMBLED, VERSION, FLAG_EXTRAS if ex else 0)
		w.write(idx, bits_for(ids.size()))
		w.write(tier, TIER_BITS)
		w.write(wi.parts.size(), PART_COUNT_BITS)
		for p in wi.parts:
			w.write(1 if p.roll_seed >= 0 else 0, 1)
			_write_part_fields(w, p, ex)
		return ""
	if not wi.parts.is_empty():
		return "loose parts on an unassembled base (assemble it first)"
	write_header(w, Kind.WIELDABLE)
	w.write(idx, bits_for(ids.size()))
	w.write(tier, TIER_BITS)
	return ""


## A part a code reproduces exactly: rolled = regenerates from its seed, hand-made = an
## unedited index-table resource.
static func _check_part(p: WieldablePart) -> String:
	if p == null:
		return "empty part"
	if p.roll_seed >= 0:
		if p.roll_seed >= (1 << SEED_BITS):
			return "part '%s': roll_seed out of range" % p.id
		var again := PartRoller.regenerate(p)
		if again == null or not _props_equal(p, again, ["gems"]):
			return "part '%s' doesn't match its roll seed (edited?)" % p.id
		return ""
	if table("parts").find(p.id) < 0:
		return "hand-made part '%s' is not in the index table" % p.id
	if not _props_equal(p, WieldablePart.load_part(p.id), ["gems"]):
		return "hand-made part '%s' was edited" % p.id
	if p.gems.size() > (1 << GEM_COUNT_BITS) - 1:
		return "part '%s': too many gems" % p.id
	return ""


static func _write_part_fields(w: BitStream, p: WieldablePart, ex := false) -> void:
	if p.roll_seed >= 0:
		w.write(p.part_type, PART_TYPE_BITS)
		w.write(Rarity.parse(p.rarity), TIER_BITS)
		w.write(p.element, ELEMENT_BITS)
		w.write(p.roll_seed, SEED_BITS)
	else:
		var ids := table("parts")
		w.write(ids.find(p.id), bits_for(ids.size()))
	if ex:
		w.write(p.gems.size(), GEM_COUNT_BITS)
		for g in p.gems:
			w.write(g.element, ELEMENT_BITS)


static func _write_consecration(w: BitStream, e: EquipmentItem, ex: bool) -> void:
	if ex:
		w.write(Consecrations.IDS.find(e.consecration) + 1, CONSECRATION_BITS)


static func _write_equipment(w: BitStream, e: EquipmentItem, ex := false) -> String:
	if not e.consecration.is_empty() and Consecrations.IDS.find(e.consecration) < 0:
		return "unknown consecration '%s'" % e.consecration
	var fl := FLAG_EXTRAS if ex else 0
	if e.roll_seed >= 0:
		if e.roll_seed >= (1 << SEED_BITS):
			return "equipment '%s': roll_seed out of range" % e.id
		var again := EquipmentRoller.regenerate(e)
		if again == null or not _props_equal(e, again, ["consecration"]):
			return "equipment '%s' doesn't match its roll seed (edited?)" % e.id
		write_header(w, Kind.EQUIPMENT, VERSION, fl)
		w.write(e.slot, SLOT_BITS)
		w.write(Rarity.parse(e.rarity), TIER_BITS)
		w.write(e.element_affinity, ELEMENT_BITS)
		w.write(e.roll_seed, SEED_BITS)
		_write_consecration(w, e, ex)
		return ""
	var ids := table("equipment")
	var idx := ids.find(e.id)
	if idx < 0:
		return "equipment '%s' is not in the index table" % e.id
	if not _props_equal(e, EquipmentItem.load_item(e.id), ["consecration"]):
		return "equipment '%s' was edited" % e.id
	write_header(w, Kind.EQUIPMENT_TEMPLATE, VERSION, fl)
	w.write(idx, bits_for(ids.size()))
	_write_consecration(w, e, ex)
	return ""


static func _write_potion(w: BitStream, c: ConsumableItem, count: int) -> String:
	var ids := table("consumables")
	var idx := ids.find(c.id)
	if idx < 0:
		return "consumable '%s' is not in the index table" % c.id
	if not _props_equal(c, ConsumableItem.load_item(c.id)):
		return "consumable '%s' was edited" % c.id
	if count < 1 or count > c.stack_size:
		return "potion count %d outside 1..%d" % [count, c.stack_size]
	write_header(w, Kind.POTION)
	w.write(idx, bits_for(ids.size()))
	w.write(count, COUNT_BITS)
	return ""


## "EM1-" + grouped base32 of payload + CRC-16 (public so tests can craft raw payloads).
static func seal(payload: PackedByteArray, prefix := PREFIX) -> String:
	var bytes := payload.duplicate()
	var crc := crc16(payload)
	bytes.append((crc >> 8) & 0xFF)
	bytes.append(crc & 0xFF)
	var body := base32_encode(bytes)
	var groups := PackedStringArray()
	for i in range(0, body.length(), GROUP):
		groups.append(body.substr(i, GROUP))
	return prefix + "-".join(groups)


## CRC-16/CCITT-FALSE (check value of "123456789" = 0x29B1).
static func crc16(bytes: PackedByteArray) -> int:
	var crc := 0xFFFF
	for b in bytes:
		crc ^= b << 8
		for i in 8:
			crc = ((crc << 1) ^ 0x1021) if (crc & 0x8000) != 0 else (crc << 1)
			crc &= 0xFFFF
	return crc


static func base32_encode(bytes: PackedByteArray) -> String:
	var s := BitStream.new()
	s.load_bytes(bytes)
	var out := ""
	while s.remaining() > 0:
		var take := mini(5, s.remaining())
		out += ALPHABET[s.read(take) << (5 - take)]
	return out


## {"bytes": PackedByteArray} or {"error": String}. Case-insensitive, O = 0, I/L = 1; the
## leftover bits after the last whole byte must be fewer than 5 and all 0.
static func base32_decode(text: String) -> Dictionary:
	var s := BitStream.new()
	for ch in text.to_upper():
		var c := ch
		if c == "O":
			c = "0"
		elif c == "I" or c == "L":
			c = "1"
		var v := ALPHABET.find(c)
		if v < 0:
			return {"error": "invalid character '%s'" % ch}
		s.write(v, 5)
	var n := s.bits.size() >> 3
	if s.bits.size() - n * 8 >= 5:
		return {"error": "bad length (truncated?)"}
	var bytes := PackedByteArray()
	for i in n:
		bytes.append(s.read(8))
	if not s.rest_is_zero():
		return {"error": "bad padding (truncated?)"}
	return {"bytes": bytes}


## Rebuilds the item of an Ember Mark; check result.ok() / result.error.
static func decode(code: String) -> EmberMark:
	var m := EmberMark.new()
	var s := code.strip_edges()
	var v2 := s.to_upper().begins_with(PREFIX_V2)
	if not v2 and not s.to_upper().begins_with(PREFIX):
		m.error = "bad prefix (expected %s or %s)" % [PREFIX, PREFIX_V2]
		return m
	var body := s.substr(PREFIX.length()).replace("-", "").replace(" ", "")
	if body.is_empty():
		m.error = "empty code"
		return m
	var dec := base32_decode(body)
	if dec.has("error"):
		m.error = dec["error"]
		return m
	var bytes: PackedByteArray = dec["bytes"]
	if bytes.size() < 3:
		m.error = "truncated code"
		return m
	var payload := bytes.slice(0, bytes.size() - 2)
	var crc := (bytes[bytes.size() - 2] << 8) | bytes[bytes.size() - 1]
	if crc16(payload) != crc:
		m.error = "bad checksum (typo or truncated)"
		return m
	var r := BitStream.new()
	r.load_bytes(payload)
	m.version = r.read(VERSION_BITS)
	m.kind = r.read(KIND_BITS)
	var flags := r.read(FLAGS_BITS)
	if not TABLES.has(m.version):
		m.error = "unknown version %d" % m.version
		return m
	if flags & ~FLAG_EXTRAS:
		m.error = "unknown flags %d" % flags
		return m
	var ex := (flags & FLAG_EXTRAS) != 0
	if ex != v2 and m.kind != Kind.GEM or (m.kind == Kind.GEM and not v2):
		m.error = "prefix doesn't match the code's kind/flags"
		return m
	var res: Array = _read_item(r, m.kind, m.version, ex)
	if r.overrun:
		m.error = "truncated payload"
		return m
	if not res[1].is_empty():
		m.error = res[1]
		return m
	if r.remaining() >= 8 or not r.rest_is_zero():
		m.error = "trailing data"
		return m
	m.item = res[0]
	m.count = res[2]
	return m


## [item, error, count]
static func _read_item(r: BitStream, kind: int, version: int, ex := false) -> Array:
	match kind:
		Kind.GEM:
			var el := r.read(ELEMENT_BITS)
			if r.overrun:
				return [null, "", 1]
			if el >= ElementTable.COUNT:
				return [null, "unknown element %d" % el, 1]
			return [ElementGem.make(el as ElementTable.Element), "", 1]
		Kind.WIELDABLE, Kind.ASSEMBLED:
			var ids := table("wieldables", version)
			var idx := r.read(bits_for(ids.size()))
			var tier := r.read(TIER_BITS)
			if r.overrun:
				return [null, "", 1]
			if idx >= ids.size():
				return [null, "unknown wieldable index %d" % idx, 1]
			if tier >= Rarity.COUNT:
				return [null, "unknown rarity tier %d" % tier, 1]
			var def := WieldableInstance.load_base(ids[idx]).def
			if Rarity.IDS[tier] != def.base_rarity:
				def = def.duplicate() as WieldableDef  # the shared base is never edited (DropEntry.make)
				def.base_rarity = Rarity.IDS[tier]
			if kind == Kind.WIELDABLE:
				return [WieldableInstance.of(def), "", 1]
			var n := r.read(PART_COUNT_BITS)
			var parts: Array[WieldablePart] = []
			for i in n:
				var rolled := r.read(1) == 1
				var pr := _read_part(r, rolled, version, ex)
				if r.overrun:
					return [null, "", 1]
				if not pr[1].is_empty():
					return [null, "part %d: %s" % [i, pr[1]], 1]
				parts.append(pr[0])
			var w := Assembly.assemble(def, parts)
			if w == null:
				return [null, "assembly fails: " + "; ".join(Assembly.check(def, parts)), 1]
			return [w, "", 1]
		Kind.PART:
			var pr := _read_part(r, true, version, ex)
			return [pr[0], pr[1], 1]
		Kind.PART_HANDMADE:
			var pr := _read_part(r, false, version, ex)
			return [pr[0], pr[1], 1]
		Kind.EQUIPMENT:
			var slot := r.read(SLOT_BITS)
			var tier := r.read(TIER_BITS)
			var el := r.read(ELEMENT_BITS)
			var seed := r.read(SEED_BITS)
			if r.overrun:
				return [null, "", 1]
			if slot >= EquipmentItem.SLOT_COUNT:
				return [null, "unknown equipment slot %d" % slot, 1]
			if tier >= Rarity.COUNT:
				return [null, "unknown rarity tier %d" % tier, 1]
			if el >= ElementTable.COUNT:
				return [null, "unknown element %d" % el, 1]
			var e := EquipmentRoller.from_seed(seed, slot, Rarity.IDS[tier], el)
			if e == null:
				return [null, "equipment roll failed", 1]
			return [e, _read_consecration(r, e, ex), 1]
		Kind.EQUIPMENT_TEMPLATE:
			var ids := table("equipment", version)
			var idx := r.read(bits_for(ids.size()))
			if r.overrun:
				return [null, "", 1]
			if idx >= ids.size():
				return [null, "unknown equipment index %d" % idx, 1]
			var t := EquipmentItem.load_item(ids[idx]).duplicate() as EquipmentItem
			return [t, _read_consecration(r, t, ex), 1]
		Kind.POTION:
			var ids := table("consumables", version)
			var idx := r.read(bits_for(ids.size()))
			var count := r.read(COUNT_BITS)
			if r.overrun:
				return [null, "", 1]
			if idx >= ids.size():
				return [null, "unknown consumable index %d" % idx, 1]
			var c := ConsumableItem.load_item(ids[idx])
			if count < 1 or count > c.stack_size:
				return [null, "potion count %d outside 1..%d" % [count, c.stack_size], 1]
			return [c, "", count]
	return [null, "unknown item kind %d" % kind, 1]


static func _read_consecration(r: BitStream, e: EquipmentItem, ex: bool) -> String:
	if not ex:
		return ""
	var c := r.read(CONSECRATION_BITS)
	if r.overrun:
		return ""
	if c > Consecrations.IDS.size():
		return "unknown consecration %d" % c
	e.consecration = Consecrations.IDS[c - 1] if c > 0 else ""
	return ""


static func _read_gems(r: BitStream, p: WieldablePart, ex: bool) -> String:
	if not ex or p == null:
		return ""
	var n := r.read(GEM_COUNT_BITS)
	var a: Array[ElementGem] = []
	for i in n:
		var el := r.read(ELEMENT_BITS)
		if r.overrun:
			return ""
		if el >= ElementTable.COUNT:
			return "unknown gem element %d" % el
		a.append(ElementGem.make(el as ElementTable.Element))
	p.gems = a
	return ""


## [part, error]
static func _read_part(r: BitStream, rolled: bool, version: int, ex := false) -> Array:
	var res := _read_part_base(r, rolled, version)
	if res[0] != null:
		var e := _read_gems(r, res[0], ex)
		if not e.is_empty():
			return [null, e]
	return res


static func _read_part_base(r: BitStream, rolled: bool, version: int) -> Array:
	if rolled:
		var type := r.read(PART_TYPE_BITS)
		var tier := r.read(TIER_BITS)
		var el := r.read(ELEMENT_BITS)
		var seed := r.read(SEED_BITS)
		if r.overrun:
			return [null, ""]
		if type >= WieldablePart.PART_TYPE_NAMES.size():
			return [null, "unknown part type %d" % type]
		if tier >= Rarity.COUNT:
			return [null, "unknown rarity tier %d" % tier]
		if el >= ElementTable.COUNT:
			return [null, "unknown element %d" % el]
		var p := PartRoller.from_seed(seed, type as WieldablePart.PartType, Rarity.IDS[tier], el)
		return [p, "" if p != null else "part roll failed"]
	var ids := table("parts", version)
	var idx := r.read(bits_for(ids.size()))
	if r.overrun:
		return [null, ""]
	if idx >= ids.size():
		return [null, "unknown part index %d" % idx]
	return [WieldablePart.load_part(ids[idx]).duplicate(), ""]


## Deep equality of two items: same class, every script property equal (Resources compared
## recursively, arrays element-wise). Used by encode() and the round-trip tests.
static func same_item(a: Variant, b: Variant) -> bool:
	return _values_equal(a, b)


static func _props_equal(a: Object, b: Object, skip: Array = []) -> bool:
	if a == null or b == null:
		return a == b
	if a.get_script() != b.get_script():
		return false
	for prop in a.get_property_list():
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name: String = prop["name"]
		if name.begins_with("_") or name in skip:
			continue
		if not _values_equal(a.get(name), b.get(name)):
			return false
	return true


static func _values_equal(x: Variant, y: Variant) -> bool:
	if x is Object or y is Object:
		if x == y:
			return true
		if not (x is Object and y is Object):
			return false
		return _props_equal(x, y)
	if (x is Array) and (y is Array):
		if x.size() != y.size():
			return false
		for i in x.size():
			if not _values_equal(x[i], y[i]):
				return false
		return true
	if typeof(x) != typeof(y):
		return false
	return x == y
