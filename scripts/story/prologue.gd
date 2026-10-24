class_name Prologue
extends RefCounted
## Prologue: the summoning (BUILD_PLAN step 64; Magewar magewar_prologue_scene_driver beats
## "Prologue: The Summoning" / "Welcome to Town" / "A New Home"). A beat sequencer over
## StoryFlags + DialogueRunner:
##   1 summoning   (Mage Association grand hall) talk to Crazy Joe (dialogue joe_summoning)
##   2 expulsion   narration: the Association expels Joe
##   3 grant       narration: the government grants 50 gold, basic clothes and the Old Oak
##                 (flags gold = 50, basic_clothes, permit_given)
##   4 welcome_to_town  reach the Town Square
##   5 a_new_home  reach the Old Oak -> home_unlocked, prologue_done
## Beats fire strictly in order: an event for a later beat does nothing.

signal beat_started(index: int, id: String, title: String)
signal finished

const BEATS: Array[Dictionary] = [
	{"id": "summoning", "title": "Prologue: The Summoning", "kind": "talk", "target": "Crazy Joe"},
	{
		"id": "expulsion",
		"title": "Prologue: The Summoning",
		"kind": "narrate",
		"lines":
		[
			"The Mage Association does not forgive forbidden rituals. Crazy Joe is stripped of his staff and expelled.",
		],
	},
	{
		"id": "grant",
		"title": "Prologue: The Summoning",
		"kind": "narrate",
		"lines":
		[
			"The government, embarrassed, grants the Summoned 50 gold, basic clothes and the deed to the Old Oak.",
		],
	},
	{"id": "welcome_to_town", "title": "Welcome to Town", "kind": "reach", "target": "town_square"},
	{"id": "a_new_home", "title": "A New Home", "kind": "reach", "target": "old_oak"},
]
const GRANT_GOLD := 50

var flags: StoryFlags
var index := -1
var fired: PackedStringArray = []  ## beat ids in the order they completed
var narration := ""


func _init(f: StoryFlags = null) -> void:
	flags = f if f else StoryFlags.new()


func begin() -> void:
	if index < 0 and not flags.has("prologue_done"):
		_go(0)


func done() -> bool:
	return flags.has("prologue_done")


func current() -> Dictionary:
	return BEATS[index] if index >= 0 and index < BEATS.size() else {}


func bind_dialogue(r: DialogueRunner) -> void:
	var db := r.db  # not `r`: a lambda holding r on r's own signal would be a ref cycle
	r.ended.connect(
		func(id: String) -> void:
			on_dialogue_ended(db.entries.filter(func(e: Dictionary) -> bool: return e["id"] == id))
	)


func on_dialogue_ended(entries: Array) -> void:
	var b := current()
	if b.get("kind") == "talk" and not entries.is_empty() and entries[0]["speaker"] == b["target"]:
		_complete()


func on_talked(speaker: String) -> void:
	var b := current()
	if b.get("kind") == "talk" and b["target"] == speaker:
		_complete()


func on_reached(area: String) -> void:
	var b := current()
	if b.get("kind") == "reach" and b["target"] == area:
		_complete()


## Dismiss the current narration card.
func advance() -> void:
	if current().get("kind") == "narrate":
		_complete()


func _complete() -> void:
	var b := current()
	fired.append(b["id"])
	match b["id"]:
		"summoning":
			flags.set_flag("joe_met")
		"expulsion":
			flags.set_flag("joe_expelled")
		"grant":
			flags.set_flag("gold", flags.value("gold") + GRANT_GOLD)
			flags.set_flag("basic_clothes")
			flags.set_flag("permit_given")
		"welcome_to_town":
			flags.set_flag("town_visited")
		"a_new_home":
			flags.set_flag("home_unlocked")
			flags.set_flag("prologue_done")
	if index + 1 < BEATS.size():
		_go(index + 1)
	else:
		index = BEATS.size()
		narration = ""
		finished.emit()


func _go(i: int) -> void:
	index = i
	var b := BEATS[i]
	narration = "\n".join(b.get("lines", []))
	beat_started.emit(i, b["id"], b["title"])
