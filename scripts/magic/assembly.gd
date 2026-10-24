class_name Assembly
extends RefCounted
## Assembly rules + final stats (BUILD_PLAN step 17; PLAN §30.1/§30.3). Follows Magewar's
## MagicAssemblyStation + StaffWieldableItem directly (weapon system = Magewar design):
##  * Staff = Head + Exterior + Interior + Handle (+ optional Charm): 4-5 parts
##    (Magewar can_build_staff; Bible "Staffs are crafted using 4-5 parts").
##  * Wand = Head + Exterior (+ optional Handle): 2-3 parts (Magewar can_build_wand;
##    _parts_for_build drops Interior/Charm on a wand).
##  * Assembled rarity = floor(mean of the attached parts' tiers) (Magewar
##    _calculate_assembled_rarity: int sum / count; Basic when empty); it replaces the
##    base's rarity, so damage() = base x that multiplier + every part's damage_bonus.
##  * Element = the Head's when it has one (Magewar sets primary_element from it),
##    cooldown = base x Exterior x Charm >= 0.1 s, accuracy 50 + Head/Handle/Charm 0..100
##    (WieldableInstance getters, step 7).
##  * Name = "<Rarity> <Element> Staff|Wand" (Magewar _build_staff/_build_wand).
## Reinterpreted (plan design):
##  * Magewar silently drops parts that don't fit (Interior/Charm on a wand; a wand's Handle
##    whenever an Interior is also selected) and always duplicates one template
##    (starter_fire_staff / starter_arcane_wand) → check() rejects such builds with a
##    message, and the caller picks the base (PLAN: "the base staff/wand is the spell").
##  * handling (Magewar declares handling_bonus but never reads it) = sum of every attached
##    part's handling_bonus; it shortens the draw: draw_seconds(base, h) =
##    base x 100 / (100 + h), never under MIN_DRAW_SECONDS (Loadout.select).
##  * Wands keep the Head (PLAN; Magewar's comments say Head is staff only but its
##    can_build_wand requires one); a wand Head socket count is capped at 1 (Bible "Wands
##    have only 1"), a staff uses the Head's gem_slots (WieldableInstance.gem_slots()).
## The station (step 25) consumes/returns parts; this class only checks and builds, so it
## is also the preview (Magewar preview_staff/preview_wand).

const P := WieldablePart.PartType
const STAFF_REQUIRED: Array[WieldablePart.PartType] = [P.HEAD, P.EXTERIOR, P.INTERIOR, P.HANDLE]
const STAFF_OPTIONAL: Array[WieldablePart.PartType] = [P.CHARM]
const WAND_REQUIRED: Array[WieldablePart.PartType] = [P.HEAD, P.EXTERIOR]
const WAND_OPTIONAL: Array[WieldablePart.PartType] = [P.HANDLE]
const WAND_GEM_SLOTS := 1
const MIN_DRAW_SECONDS := 0.2
const TYPE_NAMES: PackedStringArray = ["Staff", "Wand"]  ## Magewar type_str


static func required_types(type: WieldableDef.Type) -> Array[WieldablePart.PartType]:
	return STAFF_REQUIRED if type == WieldableDef.Type.STAFF else WAND_REQUIRED


static func optional_types(type: WieldableDef.Type) -> Array[WieldablePart.PartType]:
	return STAFF_OPTIONAL if type == WieldableDef.Type.STAFF else WAND_OPTIONAL


static func allows(type: WieldableDef.Type, part_type: int) -> bool:
	return part_type in required_types(type) or part_type in optional_types(type)


## Part count range: staff 4..5, wand 2..3.
static func count_range(type: WieldableDef.Type) -> Vector2i:
	var n := required_types(type).size()
	return Vector2i(n, n + optional_types(type).size())


## Empty when `parts` make a legal build on `def`; else one message per problem.
static func check(def: WieldableDef, parts: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	if def == null:
		errs.append("no base staff/wand")
		return errs
	for e in def.validate():
		errs.append(e)
	var kind: String = TYPE_NAMES[def.type] if def.type >= 0 and def.type < TYPE_NAMES.size() else "?"
	var seen := {}
	for i in parts.size():
		var p := parts[i] as WieldablePart
		if p == null:
			errs.append("part %d is empty" % i)
			continue
		for e in p.validate():
			errs.append(e)
		var tname := p.part_type_name()
		if seen.has(p.part_type):
			errs.append("%s: two %s parts" % [kind, tname])
		seen[p.part_type] = true
		if not allows(def.type, p.part_type):
			errs.append("%s can't take a %s part" % [kind, tname])
	for t in required_types(def.type):
		if not seen.has(t):
			errs.append("%s needs a %s" % [kind, WieldablePart.PART_TYPE_NAMES[t]])
	var r := count_range(def.type)
	if parts.size() < r.x or parts.size() > r.y:
		errs.append("%s takes %d-%d parts (got %d)" % [kind, r.x, r.y, parts.size()])
	return errs


static func can_build(def: WieldableDef, parts: Array) -> bool:
	return check(def, parts).is_empty()


## Magewar _calculate_assembled_rarity: floor(mean part tier); Basic when empty. Unknown
## rarity ids count as Basic (check() rejects them anyway).
static func rarity_for(parts: Array) -> String:
	if parts.is_empty():
		return Rarity.IDS[Rarity.Tier.BASIC]
	var total := 0
	for p in parts:
		var part := p as WieldablePart
		total += maxi(0, Rarity.parse(part.rarity)) if part != null else 0
	return Rarity.IDS[clampi(floori(float(total) / parts.size()), 0, Rarity.COUNT - 1)]


## A new assembled WieldableInstance (parts sorted Head..Charm, the same part objects, not
## copies, so disassembling returns them), or null when check() fails. Nothing is consumed:
## this is also the preview.
static func assemble(def: WieldableDef, parts: Array) -> WieldableInstance:
	if not can_build(def, parts):
		return null
	var w := WieldableInstance.of(def)
	var sorted: Array[WieldablePart] = []
	for p in parts:
		sorted.append(p as WieldablePart)
	sorted.sort_custom(func(a: WieldablePart, b: WieldablePart) -> bool: return a.part_type < b.part_type)
	w.parts = sorted
	w.assembled = true
	return w


## The parts back out of an assembled wieldable (the step 25 station returns them).
static func disassemble(w: WieldableInstance) -> Array[WieldablePart]:
	var out: Array[WieldablePart] = []
	if w != null and w.assembled:
		out.assign(w.parts)
	return out


## Draw (swap-in) time for a wieldable with `handling`: base x 100 / (100 + handling),
## handling below 0 counts as 0, never under MIN_DRAW_SECONDS (and never longer than base).
static func draw_seconds(base_seconds: float, handling: float) -> float:
	if base_seconds <= 0.0:
		return 0.0
	var t := base_seconds * 100.0 / (100.0 + maxf(0.0, handling))
	return clampf(t, minf(MIN_DRAW_SECONDS, base_seconds), base_seconds)


## Magewar's assembled name: "<Rarity> <Element> Staff|Wand".
static func name_for(type: WieldableDef.Type, rarity_id: String, element: ElementTable.Element) -> String:
	return (
		"%s %s %s"
		% [
			RarityTable.load_default().display_name(rarity_id),
			ElementTable.load_default().display_name(element),
			TYPE_NAMES[type]
		]
	)
