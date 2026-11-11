class_name RareSpawns
extends RefCounted
## 0.8.5 named rares (issue #38). One or two per shipped area, built from an
## existing enemy type: a new name, a stat boost, and a unique of their own.
## No new AI. The appearance roll is a fraction in 0..1 so tests can force it;
## the world derives that fraction from the marker name.

const APPEAR := 0.12
const HEALTH := 1.6
const DAMAGE := 1.25

const ENTRIES := [
	{
		"id": "pit_warden",
		"area": "midden",
		"base": "gnawer",
		"name": "The Pit Warden",
		"unique": "gnawers_vow",
	},
	{
		"id": "old_heap",
		"area": "midden",
		"base": "heap",
		"name": "Old Heap",
		"unique": "last_coal",
	},
	{
		"id": "pale_husk",
		"area": "blightcoil",
		"base": "spore_husk",
		"name": "The Pale Husk",
		"unique": "sump_lantern",
	},
	{
		"id": "crown_treant",
		"area": "blightcoil",
		"base": "mossbound_treant",
		"name": "The Crown Treant",
		"unique": "canopy_antler",
	},
	{
		"id": "walking_brand",
		"area": "slagworks",
		"base": "branded_troll",
		"name": "The Walking Brand",
		"unique": "brand_iron",
	},
	{
		"id": "unfinished_construct",
		"area": "slagworks",
		"base": "forge_construct",
		"name": "The Unfinished Construct",
		"unique": "cinderspine",
	},
]


static func for_base(base_id: String) -> Dictionary:
	for e in ENTRIES:
		if String(e["base"]) == base_id:
			return e
	return {}


static func roll_of(key: String) -> float:
	return (absi(hash(key)) % 10000) / 10000.0


## `roll` in 0..1. Below APPEAR, a named copy; otherwise the same def.
static func decorate(def: EnemyDef, roll: float) -> EnemyDef:
	if def == null:
		return def
	var entry := for_base(def.id)
	if entry.is_empty() or roll >= APPEAR:
		return def
	var e := def.duplicate(true) as EnemyDef
	e.display_name = String(entry["name"])
	e.max_health = def.max_health * HEALTH
	e.xp_reward = int(round(float(def.xp_reward) * 2.0))
	e.color = def.color.lerp(NamedUniques.COLOR, 0.55)
	var ai: Dictionary = e.ai.duplicate(true)
	if ai.has("attack_damage"):
		ai["attack_damage"] = float(ai["attack_damage"]) * DAMAGE
	e.ai = ai
	e.set_meta(&"rare_id", String(entry["id"]))
	e.set_meta(&"unique_id", String(entry["unique"]))
	return e


static func source_of(def: EnemyDef) -> String:
	if def == null:
		return ""
	var rare := String(def.get_meta(&"rare_id", ""))
	return rare if rare != "" else def.id
