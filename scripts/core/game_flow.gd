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
	"town_square": "res://scenes/levels/town_square.tscn",  # step 65
	"mage_association": "res://scenes/levels/mage_association.tscn",
	"old_oak": "res://scenes/levels/old_oak.tscn",  # step 66
}
const LEVEL_IDS := {
	"midden_greybox": "midden",
	"breach_slice": "breach",
	"town_square": "town_square",
	"mage_association": "mage_association",
	"old_oak": "old_oak",
}

static var level_id := "midden"
static var load_save := false
static var spawn_anchor := ""  ## step 155: co-op join at the host's waystone
static var save_path := SaveGame.PATH
static var slot := 1
## Tests: when set, select_slot keeps this path (the real slot saves stay untouched and unread).
static var path_override := ""
static var dry_run := false
static var last_request := ""
static var requests := 0
## Step 73: the new character's pick from the menu ({archetype, name, color}); applied to a
## fresh run (and to a co-op client with no character file yet).
static var new_identity := {}
## Step 109: how the next fresh game starts (consumed by main.gd): INTRO_PLAY runs the intro
## from the Association, INTRO_SKIP starts at the Old Oak with the intro's end state.
const INTRO_PLAY := "play"
const INTRO_SKIP := "skip"
static var intro_mode := ""


## Step 109: --skip-intro on the command line skips the prologue.
static func intro_mode_from_args(args: PackedStringArray) -> String:
	return INTRO_SKIP if args.has("--skip-intro") else INTRO_PLAY  # step 118: the bot plays it


## Step 73: --archetype <id> / --char-name <name> / --color <#hex> (playtests, scripts).
static func identity_from_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for i in args.size() - 1:
		match args[i]:
			"--archetype":
				out["archetype"] = Archetype.valid(args[i + 1])
			"--char-name":
				out["name"] = args[i + 1]
			"--color":
				out["color"] = Color.from_string(args[i + 1], Color.WHITE)
	return out


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
	LoadingScreen.start(tree, path, level_id if path == GAME else "")  # threaded load, staged bar


## Step 109: a new game starts the intro in the Mage Association (or skips it to the Old Oak).
static func new_run(tree: SceneTree, mode := INTRO_PLAY) -> void:
	intro_mode = mode
	level_id = "old_oak" if mode == INTRO_SKIP else "mage_association"
	load_save = false
	_change(tree, GAME)


## Continue: the saved level, state loaded. False (nothing happens) without a valid save.
static func continue_run(tree: SceneTree) -> bool:
	if SaveGame.migrate_intro(save_path) == SaveGame.INTRO_ASK:
		SaveGame.answer_intro(save_path, false)  # step 118: unasked (scripted --continue): keep playing
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


## Step 49: picks save slot 1..SaveGame.SLOTS; New Run / Continue / autosaves then use it.
static func select_slot(n: int) -> void:
	slot = clampi(n, 1, SaveGame.SLOTS)
	save_path = path_override if path_override != "" else SaveGame.slot_path(slot)


static func slot_has_save(n: int) -> bool:
	return not SaveGame.read(SaveGame.slot_path(n)).has("error")
