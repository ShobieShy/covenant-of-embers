class_name FastTravel
extends RefCounted
## Fast Travel Teleportation Crystal + waystones (BUILD_PLAN step 68; Magewar
## fast_travel_crystal.gd + npc_bob.gd). The crystal is a unique key item, kept as story
## flag CRYSTAL (Bob crafts it from Joe's discards - step 67 sets it); like Magewar's
## `is_activated` it only works once the tutorial is over (flag TUTORIAL_DONE). Waystones
## are attuned by walking up to them (flag "waystone:<id>", so attunement saves with the
## story flags); the map screen (FastTravelUI) lists the attuned points.

signal traveled(point: String, level: String)

const CRYSTAL := "fast_travel_crystal"
const TUTORIAL_DONE := "tutorial_done"
const PREFIX := "waystone:"
## Travel list for closed levels: the hub, the Breach, and Act-boss floors (DEEP_POINTS).
## Landfill and market sub-points merge; the Old Oak and Landfill stones stay on their
## levels (LOCAL) but are not destinations. A boss-floor stone lists the hub, which is
## the road back (LINEAR_LEVELS_PLAN decisions 2 and 5).
const POINTS := {
	"town_gate": {"name": "Eldoria", "level": "town_square"},
	"breach": {"name": "The Breach", "level": "breach"},
}
## Stones that attune in place. Travel from the map does not offer them.
const LOCAL := {
	"old_oak": {"name": "The Old Oak", "level": "old_oak"},
	"landfill": {"name": "The Landfill", "level": "midden"},
}
## Old attunement ids written by 0.3.x. canon() folds them into the stone that remains.
const MERGED := {
	"town_market": "town_gate",
	"landfill_camp": "landfill",
	"landfill_overlook": "landfill",
}
## Labyrinth L2: waystones on Act boss floors. In closed levels, picking one loads that
## floor; picking the hub on the same map returns the party to Town Square.
const DEEP_POINTS := {
	"warrens_hall": {"name": "The Warrens - Goblin King's Hall", "level": "labyrinth", "floor": 5},
}
## GameFlow level id -> the waystone point that stands in it (spawn anchor).
const LEVEL_POINT := {
	"old_oak": "old_oak", "town_square": "town_gate", "midden": "landfill", "breach": "breach"
}

var flags: StoryFlags
var last_error := ""


func _init(f: StoryFlags = null) -> void:
	flags = f if f else StoryFlags.new()


func has_crystal() -> bool:
	return flags.has(CRYSTAL)


func unlocked() -> bool:
	return has_crystal() and flags.has(TUTORIAL_DONE)


## Alias ids (town_market, landfill_camp, ...) become the stone that replaced them.
static func canon(point: String) -> String:
	return String(MERGED.get(point, point))


static func known(point: String) -> bool:
	var id := canon(point)
	return POINTS.has(id) or LOCAL.has(id) or DEEP_POINTS.has(id)


static func is_local(point: String) -> bool:
	return LOCAL.has(canon(point))


func attune(point: String) -> bool:
	var id := canon(point)
	if not known(id) or attuned(id):
		return false
	flags.set_flag(PREFIX + id)
	return true


func attuned(point: String) -> bool:
	return flags.has(PREFIX + canon(point))


## Attuned destinations, in POINTS then boss-floor order. Local stones are not listed.
func destinations() -> PackedStringArray:
	var out := PackedStringArray()
	for p in POINTS:
		if attuned(p):
			out.append(p)
	for p in DEEP_POINTS:
		if attuned(p):
			out.append(p)
	return out


## A point's {name, level[, floor]} ({} when unknown). Aliases resolve first.
static func info(point: String) -> Dictionary:
	var id := canon(point)
	if POINTS.has(id):
		return POINTS[id]
	if LOCAL.has(id):
		return LOCAL[id]
	return DEEP_POINTS.get(id, {})


static func is_deep(point: String) -> bool:
	return DEEP_POINTS.has(canon(point))


func can_travel(point: String) -> bool:
	point = canon(point)
	last_error = ""
	if not has_crystal():
		last_error = "You have no Teleportation Crystal."
	elif not flags.has(TUTORIAL_DONE):
		last_error = "The crystal hasn't been activated yet."
	elif not attuned(point):
		last_error = "That place isn't attuned."
	return last_error.is_empty()


## Emits traveled(point, level) when allowed (main.gd travels on it); else false + last_error.
## An alias travels as the stone it merged into.
func travel(point: String) -> bool:
	var id := canon(point)
	if not can_travel(id):
		return false
	traveled.emit(id, String(info(id)["level"]))
	return true
