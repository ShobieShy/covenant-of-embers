class_name QuestWaypoint
extends RefCounted
## 0.11.5: where the tracked step is, in the level the player is standing in.
## A kill or a pickup in this level marks that spot. A later labyrinth floor marks
## the downward stair. Another level marks the gate that leads toward it. A finished
## step and a step with no exit here mark nothing. Never the first waystone.

const BOSS_FLOOR := {
	"goblin_king": 5,
	"blightmaw_matriarch": 8,
	"forgemaw": 13,
	"drowned_choir": 18,
	"storm_warden": 23,
}
## Objective target -> the level that holds it.
const LEVEL_OF := {
	"old_oak": "old_oak",
	"bobs_lab": "bobs_lab",
	"landfill": "midden",
	"midden": "midden",
	"breach": "breach",
	"labyrinth": "labyrinth",
	"gnawer": "midden",
	"the_filth": "midden",
	"joes_discards": "midden",
	"breach_warden": "breach",
	"Bob": "old_oak",
	"goblin_king": "labyrinth",
	"joe_mark": "labyrinth",
	"blightmaw_matriarch": "labyrinth",
	"forgemaw": "labyrinth",
	"slag_seal": "labyrinth",
	"drowned_choir": "labyrinth",
	"storm_warden": "labyrinth",
}
## here -> destination level -> the LevelGate target that is the next hop.
const HOP := {
	"town_square":
	{
		"old_oak": "old_oak",
		"bobs_lab": "bobs_lab",
		"midden": "midden",
		"breach": "midden",
		"labyrinth": "midden",
	},
	"mage_association":
	{
		"town_square": "town_square",
		"old_oak": "town_square",
		"bobs_lab": "town_square",
		"midden": "midden",
		"breach": "midden",
		"labyrinth": "midden",
	},
	"old_oak":
	{
		"town_square": "town_square",
		"bobs_lab": "town_square",
		"midden": "town_square",
		"breach": "town_square",
		"labyrinth": "town_square",
	},
	"bobs_lab":
	{
		"town_square": "town_square",
		"old_oak": "town_square",
		"midden": "town_square",
		"breach": "town_square",
		"labyrinth": "town_square",
	},
	"midden":
	{
		"town_square": "town_square",
		"old_oak": "town_square",
		"bobs_lab": "town_square",
		"breach": "breach",
		"labyrinth": "breach",
	},
	"breach":
	{
		"midden": "midden",
		"town_square": "midden",
		"old_oak": "midden",
		"bobs_lab": "midden",
		"labyrinth": "labyrinth",
	},
}


## gates: [{target, at}]. stairs_down / stairs_up: Vector3 or missing.
## points: [{id, at}] for an Npc speaker, a pickup item id, an enemy id, or boss_dais.
static func resolve(kind: String, target: String, here: String, floor: int, survey: Dictionary) -> Variant:
	var spot: Variant = _local(kind, target, here, floor, survey)
	if spot != null:
		return spot
	var dest := String(LEVEL_OF.get(target, ""))
	if dest == "" or dest == here:
		return null
	if kind == "reach" and target == "old_oak":
		var door: Variant = _gate(survey, "bobs_lab")
		if door != null:
			return door
	return _gate(survey, String(HOP.get(here, {}).get(dest, "")))


static func _local(kind: String, target: String, here: String, floor: int, survey: Dictionary) -> Variant:
	var want := target
	if kind == "kill" and target == "breach_warden":
		want = "boss_dais"
	for p in survey.get("points", []):
		if String(p.get("id", "")) == want or String(p.get("id", "")) == target:
			return p.get("at")
	var dest := String(LEVEL_OF.get(target, ""))
	if dest != here:
		return null
	var boss_floor := int(BOSS_FLOOR.get(target, -1))
	if boss_floor < 0:
		return null
	if floor > 0 and floor < boss_floor and survey.get("stairs_down") is Vector3:
		return survey["stairs_down"]
	if floor > boss_floor and survey.get("stairs_up") is Vector3:
		return survey["stairs_up"]
	return null


static func _gate(survey: Dictionary, target: String) -> Variant:
	if target == "":
		return null
	for g in survey.get("gates", []):
		if String(g.get("target", "")) == target:
			return g.get("at")
	return null


## Live scene. Gates live on the game. A labyrinth floor is surveyed for the boss and the stairs.
static func survey(main: Node) -> Dictionary:
	var gates: Array = []
	var raw: Variant = main.get("gates")
	if raw is Array:
		for g in raw:
			if g is LevelGate:
				gates.append({"target": (g as LevelGate).target, "at": (g as Node3D).global_position})
	var root: Node = main
	var floor := 0
	var lin := main.get_node_or_null("LinearInteriors")
	if lin and String(lin.get("current")) == "labyrinth":
		root = lin.get("interior") if lin.get("interior") != null else lin
		floor = int(lin.get("floor_no"))
	elif main.get_node_or_null("Level") != null:
		root = main.get_node("Level")
	return {
		"gates": gates,
		"points": _points(root),
		"stairs_down": _stair(root, true),
		"stairs_up": _stair(root, false),
		"floor": floor,
	}


static func _points(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "Node", true, false))
	for n in nodes:
		if n is Npc:
			out.append({"id": String(n.get("speaker")), "at": (n as Node3D).global_position})
		elif n is QuestPickup:
			out.append({"id": (n as QuestPickup).item_id, "at": (n as Node3D).global_position})
		elif n is Node3D:
			var id := ""
			if n.has_meta(&"lab_boss"):
				id = String(n.get_meta(&"lab_boss"))
			elif n.has_meta(&"boss"):
				id = String(n.get_meta(&"boss"))
			elif n.has_meta(&"enemy"):
				id = String(n.get_meta(&"enemy"))
			elif String(n.name) == "boss_dais" or String(n.name) == "BossSpawn":
				id = "boss_dais" if String(n.name) == "boss_dais" else String(n.get_meta(&"boss", "BossSpawn"))
			if id != "":
				out.append({"id": id, "at": (n as Node3D).global_position})
	return out


static func _stair(root: Node, down: bool) -> Variant:
	if root == null:
		return null
	for n in root.find_children("*", "LabyrinthStairs", true, false):
		var s := n as LabyrinthStairs
		if (down and s.dir == LabyrinthStairs.DOWN) or (not down and s.dir == LabyrinthStairs.UP):
			return s.global_position
	return null
