class_name ActLoot
extends RefCounted
## Labyrinth L4: loot per Act (LABYRINTH_PLAN section 9) and co-op party scaling (section 8).
##  - item level = the floor's depth band (Act I 5-12: floors 1-4 at 5 / 7 / 9 / 10, the
##    King's floor 12); a floor's enemies drop at that level (Enemy.level_override);
##  - each Act has a brand element: an Act enemy's procedural drops take it ELEMENT_SHARE
##    of the time (else its own affinity);
##  - rarity luck rises per Act (Act I 0);
##  - the Act boss leaves a chest: Unique floor on the first clear, Rare on repeats;
##  - party: each extra player adds PARTY_BONUS to a pool's drop chance (enemies have +60 %
##    health each, CoopWorld.HP_PER_EXTRA_PLAYER; loot stays per-player instanced).

const PARTY_BONUS := 0.25
const ELEMENT_SHARE := 0.5
const ACTS := {
	1:
	{
		"name": "Goblin Warrens",
		"floors": [1, 5],
		"levels": [5, 7, 9, 10, 12],
		"chests": ["basic", "basic", "uncommon", "uncommon", "rare"],
		"element": ElementTable.Element.EARTH,
		"luck": 0.0,
		"boss_first": "unique",
		"boss_repeat": "rare",
	},
}


static func act_of(floor_no: int) -> int:
	for a: int in ACTS:
		var f: Array = ACTS[a]["floors"]
		if floor_no >= int(f[0]) and floor_no <= int(f[1]):
			return a
	return 0


static func item_level(floor_no: int) -> int:
	var a := act_of(floor_no)
	if a == 0:
		return 0
	var lv: Array = ACTS[a]["levels"]
	return int(lv[clampi(floor_no - int(ACTS[a]["floors"][0]), 0, lv.size() - 1)])


static func element(floor_no: int) -> int:
	var a := act_of(floor_no)
	return int(ACTS[a]["element"]) if a != 0 else -1


static func luck(floor_no: int) -> float:
	var a := act_of(floor_no)
	return float(ACTS[a]["luck"]) if a != 0 else 0.0


static func boss_rarity(floor_no: int, first_clear: bool) -> String:
	var a := act_of(floor_no)
	if a == 0:
		return VaultChest.DEFAULT_FLOOR
	return String(ACTS[a]["boss_first" if first_clear else "boss_repeat"])


## A floor's chest rarity floor; secret rooms hold chests one tier above it (plan section 9).
static func chest_rarity(floor_no: int, secret := false) -> String:
	var a := act_of(floor_no)
	if a == 0:
		return "basic"
	var cs: Array = ACTS[a]["chests"]
	var t := Rarity.parse(
		String(cs[clampi(floor_no - int(ACTS[a]["floors"][0]), 0, cs.size() - 1)])
	)
	if secret:
		t = mini(t + 1, Rarity.parse("primordial"))
	return Rarity.IDS[t]


static func party_chance(base: float, players: int) -> float:
	return clampf(base * (1.0 + PARTY_BONUS * maxf(0.0, players - 1)), 0.0, 1.0)


## Tags a Labyrinth enemy for its floor (LootDropper reads these).
static func tag(e: Enemy, floor_no: int) -> void:
	var lv := item_level(floor_no)
	if lv > 0:
		e.level_override = lv
	if element(floor_no) >= 0:
		e.set_meta(&"act_element", element(floor_no))
		e.set_meta(&"act_luck", luck(floor_no))
