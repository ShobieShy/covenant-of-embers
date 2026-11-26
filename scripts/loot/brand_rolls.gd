class_name BrandRolls
extends RefCounted
## 0.11.5: one brand buff line, and sometimes one debuff line, from data/loot/brand_rolls.toml.
## The Magewar stat roll is unchanged. These lines use a second generator so an old seed
## still rebuilds the same base stats. Arcane (no brand) uses the even pool.

const PATH := "res://data/loot/brand_rolls.toml"
const DEBUFF_SCALE := 0.5

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = LevelToml.load_file(PATH)
	return _data


static func chance(rarity_id: String) -> float:
	return float(data().get("debuff_chance", {}).get(rarity_id, 0.0))


static func magnitude(stat: String) -> Vector2:
	var row: Array = data().get("magnitude", {}).get(stat, [0.0, 0.0])
	return Vector2(float(row[0]), float(row[1]))


static func pool(element: ElementTable.Element) -> Dictionary:
	var id := "arcane"
	var brand := BrandTable.for_element(element)
	if brand != null:
		id = brand.id
	for p in data().get("pool", []):
		if String(p.get("id", "")) == id:
			return p
	return {}


## [{stat, percent, debuff}]. percent is the displayed magnitude, always positive.
## A debuff's percent is half the buff range at this rarity.
static func lines(seed: int, rarity_id: String, element: ElementTable.Element) -> Array:
	var src := pool(element)
	if src.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5A17DEB
	var out: Array = []
	var buff := _pick(rng, src.get("buff", []))
	if buff != "":
		out.append({"stat": buff, "percent": _roll(rng, buff, rarity_id, false), "debuff": false})
	if rng.randf() < chance(rarity_id):
		var bad := _pick(rng, src.get("debuff", []))
		if bad != "":
			out.append({"stat": bad, "percent": _roll(rng, bad, rarity_id, true), "debuff": true})
	return out


static func stats_of(which: String, element: ElementTable.Element) -> PackedStringArray:
	var out := PackedStringArray()
	for row in pool(element).get(which, []):
		var stat := String(row.get("stat", ""))
		if stat != "" and not out.has(stat):
			out.append(stat)
	return out


## Signed percent. Mana cost up is negative. Everything else up is positive.
static func signed(line: Dictionary) -> float:
	var pct := float(line.get("percent", 0.0))
	var debuff := bool(line.get("debuff", false))
	var stat := String(line.get("stat", ""))
	var good := not debuff
	if stat == "mana_cost":
		good = not good
	return pct if good else -pct


static func score(rolled: Array) -> float:
	var total := 0.0
	for line in rolled:
		var v := signed(line)
		if String(line.get("stat", "")) == "mana_cost":
			total -= v
		else:
			total += v
	return total


static func _roll(rng: RandomNumberGenerator, stat: String, rarity_id: String, debuff: bool) -> float:
	var span := magnitude(stat)
	var mult := RarityTable.load_default().multiplier(rarity_id)
	var scale := DEBUFF_SCALE if debuff else 1.0
	return rng.randf_range(span.x * mult * scale, span.y * mult * scale)


static func _pick(rng: RandomNumberGenerator, rows: Array) -> String:
	var total := 0.0
	for row in rows:
		total += maxf(0.0, float(row.get("weight", 0.0)))
	if total <= 0.0:
		return ""
	var pick := rng.randf() * total
	var cum := 0.0
	var last := ""
	for row in rows:
		var w := maxf(0.0, float(row.get("weight", 0.0)))
		if w <= 0.0:
			continue
		last = String(row.get("stat", ""))
		cum += w
		if pick < cum:
			return last
	return last
