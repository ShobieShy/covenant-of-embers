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
## Point id -> name + GameFlow level id (Magewar travel_points: location -> scene).
const POINTS := {
	"old_oak": {"name": "The Old Oak", "level": "old_oak"},
	"town_gate": {"name": "Eldoria - Town Gate", "level": "town_square"},
	"town_market": {"name": "Eldoria - Market", "level": "town_square"},  # step 158
	"landfill": {"name": "The Landfill", "level": "midden"},
	"landfill_camp": {"name": "The Landfill - Joe's Camp", "level": "midden"},  # step 161
	"landfill_overlook": {"name": "The Landfill - Overlook", "level": "midden"},
	"breach": {"name": "The Breach", "level": "breach"},
}
## Labyrinth L2 (plan section 7): waystones below ground, on boss floors (attuned once the
## boss is down). Same attunement flags; WorldTravel enters the floor instead of a spot.
const DEEP_POINTS := {
	"warrens_hall": {"name": "The Warrens - Goblin King's Hall", "level": "labyrinth", "floor": 5},
}
## GameFlow level id -> the waystone point in it.
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


func attune(point: String) -> bool:
	if not (POINTS.has(point) or DEEP_POINTS.has(point)) or attuned(point):
		return false
	flags.set_flag(PREFIX + point)
	return true


func attuned(point: String) -> bool:
	return flags.has(PREFIX + point)


## Attuned destinations, in POINTS order.
func destinations() -> PackedStringArray:
	var out := PackedStringArray()
	for p in POINTS:
		if attuned(p):
			out.append(p)
	for p in DEEP_POINTS:
		if attuned(p):
			out.append(p)
	return out


## A point's {name, level[, floor]}, outdoors or below ground ({} when unknown).
static func info(point: String) -> Dictionary:
	return POINTS.get(point, DEEP_POINTS.get(point, {}))


static func is_deep(point: String) -> bool:
	return DEEP_POINTS.has(point)


func can_travel(point: String) -> bool:
	last_error = ""
	if not has_crystal():
		last_error = "You have no Teleportation Crystal."
	elif not flags.has(TUTORIAL_DONE):
		last_error = "The crystal hasn't been activated yet."
	elif not attuned(point):
		last_error = "That place isn't attuned."
	return last_error.is_empty()


## Emits traveled(point, level) when allowed (main.gd travels on it); else false + last_error.
func travel(point: String) -> bool:
	if not can_travel(point):
		return false
	traveled.emit(point, String(info(point)["level"]))
	return true
