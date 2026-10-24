class_name GameFlow
extends RefCounted
## Scene flow (BUILD_PLAN step 39): main menu -> Midden -> Breach -> back.
## The game scene (scenes/main.tscn) reads `level_id` / `load_save` in its _ready and
## swaps in that level; travelling autosaves and reloads the game scene with load_save on,
## so the player carries health, items and level through (SaveGame, step 38).
## `dry_run` (tests) records the request instead of changing scenes.

const MENU := "res://scenes/menu.tscn"
const GAME := "res://scenes/main.tscn"
const LEVELS := {
	"midden": "res://scenes/levels/midden.tscn",
	"breach": "res://scenes/levels/breach.tscn",
}
const LEVEL_IDS := {"midden_greybox": "midden", "breach_slice": "breach"}

static var level_id := "midden"
static var load_save := false
static var save_path := SaveGame.PATH
static var dry_run := false
static var last_request := ""
static var requests := 0


static func level_scene(id: String) -> String:
	return LEVELS.get(id, LEVELS["midden"])


## Flow id ("midden"/"breach") of a level root's level_id meta.
static func id_of(level: Node) -> String:
	return LEVEL_IDS.get(String(level.get_meta("level_id", "")), "midden") if level else "midden"


static func _change(tree: SceneTree, path: String) -> void:
	last_request = path
	requests += 1
	if dry_run or tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file.call_deferred(path)


static func new_run(tree: SceneTree) -> void:
	level_id = "midden"
	load_save = false
	_change(tree, GAME)


## Continue: the saved level, state loaded. False (nothing happens) without a valid save.
static func continue_run(tree: SceneTree) -> bool:
	var r := SaveGame.read(save_path)
	if r.has("error"):
		return false
	level_id = String((r["data"] as Dictionary).get("progress", {}).get("level_id", "midden"))
	if not LEVELS.has(level_id):
		level_id = "midden"
	load_save = true
	_change(tree, GAME)
	return true


static func travel(tree: SceneTree, to_level: String) -> void:
	level_id = to_level if LEVELS.has(to_level) else "midden"
	load_save = true
	_change(tree, GAME)


static func to_menu(tree: SceneTree) -> void:
	load_save = false
	_change(tree, MENU)


static func has_save() -> bool:
	return not SaveGame.read(save_path).has("error")
