class_name WorldMap
extends RefCounted
## The Elyria map (BUILD_PLAN step 69; Magewar storyline / Bible). Barrier-protected towns
## (Eldoria, Luminar, Willowbrook, Stonehaven) and the wild land between them (~60 % of
## Elyria); areas such as the Whispering Woods, Shattered Peaks and Crimson Sea start
## locked. Each region has a state LOCKED / KNOWN / VISITED kept as story flag
## "region:<id>" (so it saves with the flags); visiting a level marks its region visited.

enum State { LOCKED, KNOWN, VISITED }

const PREFIX := "region:"
const STATE_NAMES := ["Locked", "Known", "Visited"]
## id -> name, barrier (town under an arcane barrier) or wild, start state, map share.
const REGIONS := {
	"eldoria": {"name": "Eldoria", "barrier": true, "start": State.KNOWN, "share": 0.1},
	"luminar": {"name": "Luminar", "barrier": true, "start": State.KNOWN, "share": 0.1},
	"willowbrook": {"name": "Willowbrook", "barrier": true, "start": State.KNOWN, "share": 0.1},
	"stonehaven": {"name": "Stonehaven", "barrier": true, "start": State.KNOWN, "share": 0.1},
	"landfill": {"name": "The Landfill", "barrier": false, "start": State.KNOWN, "share": 0.05},
	"breach": {"name": "The Breach", "barrier": false, "start": State.LOCKED, "share": 0.0},
	"whispering_woods": {"name": "Whispering Woods", "barrier": false, "start": State.LOCKED, "share": 0.2},
	"shattered_peaks": {"name": "Shattered Peaks", "barrier": false, "start": State.LOCKED, "share": 0.2},
	"crimson_sea": {"name": "Crimson Sea", "barrier": false, "start": State.LOCKED, "share": 0.15},
}
## GameFlow level id -> region.
const LEVEL_REGION := {
	"town_square": "eldoria",
	"mage_association": "eldoria",
	"old_oak": "eldoria",
	"midden": "landfill",
	"breach": "breach",
	"labyrinth": "breach",
}
## Closed-level map: one name per scene. The full-screen sheet is this list, not Elyria.
const LEVEL_NAMES := {
	"old_oak": "The Old Oak",
	"town_square": "Eldoria, Town Square",
	"mage_association": "Mage Association",
	"midden": "The Landfill",
	"breach": "The Breach",
	"labyrinth": "The Breach Labyrinth",
}
const SEEN := "seen:"

var flags: StoryFlags


func _init(f: StoryFlags = null) -> void:
	flags = f if f else StoryFlags.new()


func state(id: String) -> int:
	if not REGIONS.has(id):
		return State.LOCKED
	var v := flags.value(PREFIX + id)
	return v - 1 if v > 0 else int(REGIONS[id]["start"])


## Raises a region's state (never lowers it); true when it changed.
func set_state(id: String, s: int) -> bool:
	if not REGIONS.has(id) or s <= state(id):
		return false
	flags.set_flag(PREFIX + id, s + 1)
	return true


func discover(id: String) -> bool:
	return set_state(id, State.KNOWN)


func visit_level(level_id: String) -> bool:
	if LEVEL_NAMES.has(level_id):
		flags.set_flag(SEEN + level_id)
	return set_state(String(LEVEL_REGION.get(level_id, "")), State.VISITED)


static func level_name(level_id: String) -> String:
	return String(LEVEL_NAMES.get(level_id, level_id))


## True when this run has loaded `level_id` (flag "seen:<id>").
func seen(level_id: String) -> bool:
	return flags.has(SEEN + level_id)


## Per-level sheet: this level, then the campaign with Here / Visited / Unseen.
func level_lines(level_id: String, seen_ids: Array = []) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(level_name(level_id))
	var point := String(FastTravel.LEVEL_POINT.get(level_id, ""))
	if not point.is_empty():
		out.append("Waystone: " + String(FastTravel.info(point).get("name", point)))
	for id in LevelFlow.ORDER:
		var mark := "Unseen"
		if id == level_id:
			mark = "Here"
		elif seen(id) or seen_ids.has(id):
			mark = "Visited"
		out.append("%s: %s" % [level_name(id), mark])
	return out


func wild_share() -> float:
	var t := 0.0
	for id in REGIONS:
		if not REGIONS[id]["barrier"]:
			t += float(REGIONS[id]["share"])
	return t


## One line per region: "Eldoria (barrier town): Visited".
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for id in REGIONS:
		var r: Dictionary = REGIONS[id]
		out.append("%s (%s): %s" % [r["name"], "barrier town" if r["barrier"] else "wild land", STATE_NAMES[state(id)]])
	return out
