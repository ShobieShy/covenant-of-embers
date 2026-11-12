class_name Bounties
extends RefCounted
## Repeatable combat tasks against enemies that already ship. Pay is gold. No new scenes.

const ROWS := [
	{"id": "gnawer", "need": 3, "gold": 12},
	{"id": "heap", "need": 2, "gold": 18},
	{"id": "spore_husk", "need": 2, "gold": 18},
]

var counts := {}


func note(enemy_id: String) -> void:
	counts[enemy_id] = int(counts.get(enemy_id, 0)) + 1


func from_dict(d: Dictionary) -> void:
	counts = {}
	for k in d:
		counts[String(k)] = int(d[k])


func to_dict() -> Dictionary:
	return counts.duplicate()


func claim(p: Player, enemy_id: String) -> bool:
	var row := {}
	for r in ROWS:
		if String(r["id"]) == enemy_id:
			row = r
			break
	if row.is_empty():
		return false
	var need := int(row["need"])
	if int(counts.get(enemy_id, 0)) < need:
		return false
	counts[enemy_id] = int(counts[enemy_id]) - need
	p.inventory.add_gold(int(row["gold"]))
	return true
