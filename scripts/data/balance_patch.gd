class_name BalancePatch
extends RefCounted
## Hotfix-style JSON balance patches (BUILD_PLAN step 21, PLAN §31). A patch is one JSON
## object with "version": 1 and any of the sections "elements", "rarities", "drop_pools".
## apply() is all-or-nothing: every section is applied to a duplicate(true) copy, each copy
## must pass its validate(), and only then are the shared tables updated (Element/Rarity
## tables in place so cached references see the change, DropRoller._pools swapped).
## Any unknown key, wrong type or failed validate() rejects the whole patch and leaves every
## table exactly as it was.
## Ember Mark safety (step 20): item code index tables and the PartRoller/EquipmentRoller
## seed roll ranges/order are NOT patchable (a tuned range would change what every saved
## seed decodes to); "item_codes", "part_rolls", "equipment_rolls" are rejected by name.
##
## {"version": 1,
##  "elements": {"strong": 1.5, "weak": 0.5,
##               "<element id>": {"strong_against": [...], "weak_against": [...], "color": "#RRGGBB", "display_name": "..."}},
##  "rarities": {"luck_common_step": 5, "luck_rare_step": 2, "luck_common_floor": 1,
##               "<rarity id>": {"multiplier": 1.5, "drop_weight": 15, "color": "#RRGGBB"}},
##  "drop_pools": {"<pool id>": {"drop_chance": 0.3, "min_level": 1, "max_level": 50,
##                 "entries": {"<index>": {"weight": 1.0, "rarity": "rare"}}}},
##  "brands": {"<brand id>": {"wand_scale": 0.6, "params": {"<existing param>": 1.2}}},
##  "skills": {"<element tree id>": {"<skill id>": {"<existing effect>": 2.5}}}}
## Step 151: skill effects patch the cached element SkillTrees in place (per-rank values; only
## effects the skill already has, any finite number; reset() reloads the trees from disk).
## Step 143: brand params patch the shared Brand resources in place (FireModes read them
## live); only params the brand already has, as non-negative numbers.

const VERSION := 1
const LOCKED := ["item_codes", "part_rolls", "equipment_rolls"]
const ELEMENT_KEYS := ["strong_against", "weak_against", "color", "display_name"]
const RARITY_KEYS := ["multiplier", "drop_weight", "color"]
const RARITY_TABLE_KEYS := ["luck_common_step", "luck_rare_step", "luck_common_floor"]
const POOL_KEYS := ["drop_chance", "min_level", "max_level", "entries"]
const ENTRY_KEYS := ["weight", "rarity"]

## Patches applied since startup (ids), newest last.
static var applied: PackedStringArray = []


## Applies every *.json in `dir` in name order; returns the messages of rejected ones
## (a missing directory is fine: no patches).
static func apply_dir(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		if String(f).ends_with(".json"):
			out.append_array(apply_file(dir.path_join(f)))
	return out


## Reads and applies a JSON file. Empty result = applied.
static func apply_file(path: String) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return PackedStringArray(["%s: can't read or empty" % path])
	return apply_json(text, path.get_file())


static func apply_json(text: String, patch_id := "patch") -> PackedStringArray:
	var j := JSON.new()
	if j.parse(text) != OK:
		return PackedStringArray(["%s: JSON error line %d: %s" % [patch_id, j.get_error_line(), j.get_error_message()]])
	if not (j.data is Dictionary):
		return PackedStringArray(["%s: top level must be an object" % patch_id])
	return apply(j.data, patch_id)


static func apply(patch: Dictionary, patch_id := "patch") -> PackedStringArray:
	var errs := PackedStringArray()
	if not patch.has("version") or not _is_num(patch["version"]) or int(patch["version"]) != VERSION:
		errs.append("version must be %d" % VERSION)
	var el: ElementTable = null
	var ra: RarityTable = null
	var dp: DropTable = null
	var br := {}  ## brand id -> {wand_scale?, params}
	var sk := {}  ## step 151: tree id -> {skill id -> {effect: value}}
	for key in patch:
		match key:
			"version":
				pass
			"elements":
				el = ElementTable.load_default().duplicate(true) as ElementTable
				_patch_elements(el, patch[key], errs)
			"rarities":
				ra = RarityTable.load_default().duplicate(true) as RarityTable
				_patch_rarities(ra, patch[key], errs)
			"drop_pools":
				dp = DropRoller.default_pools().duplicate(true) as DropTable
				_patch_pools(dp, patch[key], errs)
			"brands":
				br = _patch_brands(patch[key], errs)
			"skills":
				sk = _patch_skills(patch[key], errs)
			_:
				if LOCKED.has(key):
					(
						errs
						. append(
							(
								"'%s' can't be patched: it changes what existing Ember Mark codes decode to (needs a new code version)"
								% key
							)
						)
					)
				else:
					errs.append("unknown key '%s'" % key)
	if errs.is_empty() and el != null:
		el.rebuild()
		errs.append_array(_tag("elements", el.validate()))
	if errs.is_empty() and ra != null:
		errs.append_array(_tag("rarities", ra.validate()))
	if errs.is_empty() and dp != null:
		errs.append_array(_tag("drop_pools", dp.validate()))
	if not errs.is_empty():
		return _tag(patch_id, errs)
	if el != null:
		var shared := ElementTable.load_default()
		shared.strong = el.strong
		shared.weak = el.weak
		shared.elements = el.elements
		shared.rebuild()
	if ra != null:
		var shared_r := RarityTable.load_default()
		shared_r.rarities = ra.rarities
		for k in RARITY_TABLE_KEYS:
			shared_r.set(k, ra.get(k))
		shared_r.rebuild()
	if dp != null:
		DropRoller._pools = dp
	for id in br:
		var b := BrandTable.by_id(id)
		if br[id].has("wand_scale"):
			b.wand_scale = float(br[id]["wand_scale"])
		for k in br[id]["params"]:
			b.params[k] = float(br[id]["params"][k])
	for eid in sk:
		var t := SkillTree.element_tree(eid)
		for sid in sk[eid]:
			for k in sk[eid][sid]:
				t.skills[sid]["effects"][k] = float(sk[eid][sid][k])
	applied.append(patch_id)
	return errs


## Restores every patchable table from disk (tests, "reset balance").
static func reset() -> void:
	var el := ResourceLoader.load(ElementTable.PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as ElementTable
	var shared := ElementTable.load_default()
	shared.strong = el.strong
	shared.weak = el.weak
	shared.elements = el.elements
	shared.rebuild()
	var ra := ResourceLoader.load(RarityTable.PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as RarityTable
	var shared_r := RarityTable.load_default()
	shared_r.rarities = ra.rarities
	for k in RARITY_TABLE_KEYS:
		shared_r.set(k, ra.get(k))
	shared_r.rebuild()
	DropRoller._pools = null
	for b: Brand in BrandTable.load_default().brands:
		var disk := (
			ResourceLoader.load("res://resources/brands/%s.tres" % b.id, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			as Brand
		)
		if disk != null:
			b.params = disk.params.duplicate()
			b.wand_scale = disk.wand_scale
	SkillTree._elements.clear()  # step 151: element trees reload from disk
	applied.clear()


## Step 151: validates the "skills" section; returns {tree: {skill: {effect: value}}} to apply.
static func _patch_skills(sec: Variant, errs: PackedStringArray) -> Dictionary:
	var out := {}
	if not (sec is Dictionary):
		errs.append("skills: must be an object")
		return out
	for el in sec:
		var t := SkillTree.element_tree(String(el))
		if t == null:
			errs.append("skills.%s: unknown element tree" % el)
			continue
		if not (sec[el] is Dictionary):
			errs.append("skills.%s: must be an object" % el)
			continue
		out[String(el)] = {}
		for sid in sec[el]:
			var where := "skills.%s.%s" % [el, sid]
			var s := t.skill(String(sid))
			if s.is_empty():
				errs.append("%s: unknown skill" % where)
				continue
			if not (sec[el][sid] is Dictionary):
				errs.append("%s: must be an object" % where)
				continue
			var row := {}
			for k in sec[el][sid]:
				var v: Variant = sec[el][sid][k]
				if not s["effects"].has(k):
					errs.append("%s.%s: the skill has no such effect" % [where, k])
				elif not _is_num(v) or is_nan(float(v)) or is_inf(float(v)):
					errs.append("%s.%s: must be a number" % [where, k])
				else:
					row[String(k)] = float(v)
			out[String(el)][String(sid)] = row
	return out


## Step 143: validates the "brands" section; returns {id: {wand_scale?, params}} to apply.
static func _patch_brands(sec: Variant, errs: PackedStringArray) -> Dictionary:
	var out := {}
	if not (sec is Dictionary):
		errs.append("brands: must be an object")
		return out
	for id in sec:
		var b := BrandTable.by_id(String(id))
		var where := "brands.%s" % id
		if b == null:
			errs.append("%s: unknown brand" % where)
			continue
		if not (sec[id] is Dictionary):
			errs.append("%s: must be an object" % where)
			continue
		var row := {"params": {}}
		for k in sec[id]:
			var v: Variant = sec[id][k]
			match k:
				"wand_scale":
					if not _is_num(v) or float(v) <= 0.0 or float(v) > 1.0:
						errs.append("%s.wand_scale: must be in (0, 1]" % where)
					else:
						row["wand_scale"] = v
				"params":
					if not (v is Dictionary):
						errs.append("%s.params: must be an object" % where)
						continue
					for pk in v:
						if not b.params.has(pk):
							errs.append("%s.params: unknown param '%s'" % [where, pk])
						elif not _is_num(v[pk]) or float(v[pk]) < 0.0:
							errs.append("%s.params.%s: must be a number >= 0" % [where, pk])
						else:
							row["params"][pk] = v[pk]
				_:
					errs.append("%s: unknown key '%s'" % [where, k])
		out[String(id)] = row
	return out


static func _tag(prefix: String, errs: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for e in errs:
		out.append("%s: %s" % [prefix, e])
	return out


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _color(v: Variant, where: String, errs: PackedStringArray) -> Variant:
	if typeof(v) != TYPE_STRING or not Color.html_is_valid(v):
		errs.append('%s: color must be "#RRGGBB"' % where)
		return null
	return Color.html(v)


static func _ids(v: Variant, where: String, errs: PackedStringArray) -> Variant:
	if not (v is Array):
		errs.append("%s: must be a list of element ids" % where)
		return null
	var out := PackedStringArray()
	for x in v:
		if typeof(x) != TYPE_STRING:
			errs.append("%s: must be a list of element ids" % where)
			return null
		out.append(x)
	return out


static func _patch_elements(t: ElementTable, sec: Variant, errs: PackedStringArray) -> void:
	if not (sec is Dictionary):
		errs.append("elements: must be an object")
		return
	for key in sec:
		var v: Variant = sec[key]
		if key == "strong" or key == "weak":
			if _is_num(v):
				t.set(key, float(v))
			else:
				errs.append("elements.%s: must be a number" % key)
			continue
		var e := ElementTable.parse(key)
		var d: ElementDef = null
		for x in t.elements:
			if x != null and x.id == key:
				d = x
		if e < 0 or d == null:
			errs.append("elements: unknown key '%s'" % key)
			continue
		if not (v is Dictionary):
			errs.append("elements.%s: must be an object" % key)
			continue
		for f in v:
			var w := "elements.%s.%s" % [key, f]
			if not ELEMENT_KEYS.has(f):
				errs.append("elements.%s: unknown key '%s'" % [key, f])
			elif f == "color":
				var c: Variant = _color(v[f], w, errs)
				if c != null:
					d.color = c
			elif f == "display_name":
				if typeof(v[f]) == TYPE_STRING:
					d.display_name = v[f]
				else:
					errs.append("%s: must be a string" % w)
			else:
				var ids: Variant = _ids(v[f], w, errs)
				if ids != null:
					d.set(f, ids)


static func _patch_rarities(t: RarityTable, sec: Variant, errs: PackedStringArray) -> void:
	if not (sec is Dictionary):
		errs.append("rarities: must be an object")
		return
	for key in sec:
		var v: Variant = sec[key]
		if RARITY_TABLE_KEYS.has(key):
			if _is_num(v):
				t.set(key, float(v))
			else:
				errs.append("rarities.%s: must be a number" % key)
			continue
		var r: Rarity = null
		for x in t.rarities:
			if x != null and x.id == key:
				r = x
		if r == null:
			errs.append("rarities: unknown key '%s'" % key)
			continue
		if not (v is Dictionary):
			errs.append("rarities.%s: must be an object" % key)
			continue
		for f in v:
			var w := "rarities.%s.%s" % [key, f]
			if not RARITY_KEYS.has(f):
				errs.append("rarities.%s: unknown key '%s'" % [key, f])
			elif f == "color":
				var c: Variant = _color(v[f], w, errs)
				if c != null:
					r.color = c
			elif _is_num(v[f]):
				r.set(f, float(v[f]))
			else:
				errs.append("%s: must be a number" % w)


static func _patch_pools(t: DropTable, sec: Variant, errs: PackedStringArray) -> void:
	if not (sec is Dictionary):
		errs.append("drop_pools: must be an object")
		return
	for key in sec:
		var p := t.find(key)
		var v: Variant = sec[key]
		if p == null:
			errs.append("drop_pools: unknown pool '%s'" % key)
			continue
		if not (v is Dictionary):
			errs.append("drop_pools.%s: must be an object" % key)
			continue
		for f in v:
			var w := "drop_pools.%s.%s" % [key, f]
			if not POOL_KEYS.has(f):
				errs.append("drop_pools.%s: unknown key '%s'" % [key, f])
			elif f == "entries":
				_patch_entries(p, v[f], w, errs)
			elif not _is_num(v[f]):
				errs.append("%s: must be a number" % w)
			elif f == "drop_chance":
				p.drop_chance = float(v[f])
			else:
				if float(v[f]) != floorf(float(v[f])):
					errs.append("%s: must be a whole number" % w)
				p.set(f, int(v[f]))


static func _patch_entries(p: DropPool, sec: Variant, where: String, errs: PackedStringArray) -> void:
	if not (sec is Dictionary):
		errs.append("%s: must be an object keyed by entry index" % where)
		return
	for key in sec:
		var i := int(key) if String(key).is_valid_int() else -1
		if i < 0 or i >= p.entries.size():
			errs.append("%s: no entry '%s'" % [where, key])
			continue
		var v: Variant = sec[key]
		if not (v is Dictionary):
			errs.append("%s.%s: must be an object" % [where, key])
			continue
		for f in v:
			var w := "%s.%s.%s" % [where, key, f]
			if not ENTRY_KEYS.has(f):
				errs.append("%s.%s: unknown key '%s'" % [where, key, f])
			elif f == "rarity":
				if typeof(v[f]) == TYPE_STRING:
					p.entries[i].rarity = v[f]
				else:
					errs.append("%s: must be a rarity id string" % w)
			elif _is_num(v[f]):
				p.entries[i].weight = float(v[f])
			else:
				errs.append("%s: must be a number" % w)
