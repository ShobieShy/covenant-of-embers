class_name RarityTable
extends Resource
## The six rarity tiers (BUILD_PLAN step 15; PLAN §30.2) = Magewar ItemRarity, as data:
## resources/loot/rarities.tres. Lookups by id never fail hard (Magewar's getters fall back
## to x1.0 / white / "Unknown"); validate() catches bad data at load instead.
## roll() is Magewar's roll_rarity (weights + luck shift) on a seeded
## RandomNumberGenerator, so drops are deterministic (PLAN §30.2: the host rolls, clients
## regenerate). Step 18 builds drop pools on it, step 28 shifts weights per Vigil tier.

const PATH := "res://resources/loot/rarities.tres"

@export var rarities: Array[Rarity] = []  ## one per Rarity.IDS, any order
@export var luck_common_step := 5.0  ## Magewar: -5 weight per luck point on Basic/Uncommon
@export var luck_rare_step := 2.0  ## Magewar: +2 per point on Rare and above
@export var luck_common_floor := 1.0  ## Magewar: max(1, w - luck * 5)

var _rows: Array[Rarity] = []  ## indexed by Rarity.Tier

static var _default: RarityTable


## The shared table from resources/loot/rarities.tres (loaded and validated once).
static func load_default() -> RarityTable:
	if _default == null:
		_default = load(PATH) as RarityTable
		var errs := _default.validate()
		if not errs.is_empty():
			push_error("%s: %s" % [PATH, "; ".join(errs)])
	return _default


func find(rarity_id: String) -> Rarity:
	var t := Rarity.parse(rarity_id)
	return tier(t) if t >= 0 else null


func tier(t: int) -> Rarity:
	_ensure_built()
	return _rows[t] if t >= 0 and t < _rows.size() else null


func has(rarity_id: String) -> bool:
	return find(rarity_id) != null


func multiplier(rarity_id: String) -> float:
	var r := find(rarity_id)
	return r.multiplier if r != null else 1.0


func color(rarity_id: String) -> Color:
	var r := find(rarity_id)
	return Accessibility.rarity_color(rarity_id, r.color if r != null else Color.WHITE)  # step 76


func display_name(rarity_id: String) -> String:
	var r := find(rarity_id)
	return r.display_name if r != null else "Unknown"


## Drop weights by tier after the luck shift (Magewar roll_rarity).
func weights(luck := 0.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for t in Rarity.COUNT:
		var r := tier(t)
		out.append(r.weight_with_luck(luck, luck_common_step, luck_rare_step, luck_common_floor) if r != null else 0.0)
	return out


## One weighted roll = exactly one rng.randf() draw. A zero-weight tier is never chosen.
func roll(rng: RandomNumberGenerator, luck := 0.0) -> Rarity:
	var w := weights(luck)
	var total := 0.0
	for x in w:
		total += x
	var pick := rng.randf() * total
	var cum := 0.0
	var last := -1
	for t in Rarity.COUNT:
		if w[t] <= 0.0:
			continue
		last = t
		cum += w[t]
		if pick < cum:
			return tier(t)
	return tier(last) if last >= 0 else tier(Rarity.Tier.BASIC)


## Re-index `rarities` (after a patch, step 21).
func rebuild() -> void:
	_rows.clear()
	_rows.resize(Rarity.COUNT)
	for r in rarities:
		var t := Rarity.parse(r.id) if r != null else -1
		if t >= 0:
			_rows[t] = r


func _ensure_built() -> void:
	if _rows.size() != Rarity.COUNT:
		rebuild()


## Empty when usable; else one message per problem.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var seen := {}
	for r in rarities:
		if r == null:
			errs.append("null rarity entry")
			continue
		var tag := "rarity '%s'" % r.id
		if Rarity.parse(r.id) < 0:
			errs.append("%s: unknown id (expected %s)" % [tag, ", ".join(Rarity.IDS)])
			continue
		if seen.has(r.id):
			errs.append("%s: duplicate" % tag)
		seen[r.id] = r
		if r.display_name.is_empty():
			errs.append("%s: display_name is empty" % tag)
		if not (r.multiplier > 0.0 and r.multiplier <= 100.0):
			errs.append("%s: multiplier must be in (0, 100] (got %s)" % [tag, r.multiplier])
		if not (r.drop_weight >= 0.0):
			errs.append("%s: drop_weight must be >= 0 (got %s)" % [tag, r.drop_weight])
		for c in [r.color.r, r.color.g, r.color.b, r.color.a]:
			if c < 0.0 or c > 1.0:
				errs.append("%s: colour channel out of 0..1" % tag)
				break
	for rid in Rarity.IDS:
		if not seen.has(rid):
			errs.append("rarity '%s' missing" % rid)
	# Higher tiers never scale worse (Magewar's multipliers rise with the tier).
	var prev := 0.0
	for rid in Rarity.IDS:
		if seen.has(rid):
			var m: float = seen[rid].multiplier
			if m < prev:
				errs.append("rarity '%s': multiplier %s below the previous tier's %s" % [rid, m, prev])
			prev = maxf(prev, m)
	var total := 0.0
	for rid in seen:
		total += maxf(0.0, seen[rid].drop_weight)
	if seen.size() > 0 and total <= 0.0:
		errs.append("drop weights sum to 0")
	if luck_common_step < 0.0 or luck_rare_step < 0.0 or luck_common_floor < 0.0:
		errs.append("luck steps/floor must be >= 0")
	if errs.is_empty():
		rebuild()
	return errs
