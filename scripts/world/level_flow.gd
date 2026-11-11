class_name LevelFlow
extends RefCounted
## 0.4.0 closed levels (LINEAR_LEVELS_PLAN section 2). One scene per level. Forward
## travel is gated by story flags; the road back to Town Square, the hub, stays open.
## A headless slice with no story flags keeps every gate open (the greybox flow).

const HUB := "town_square"
## Campaign order. The Association is an interior of the hub, not its own step.
const ORDER: PackedStringArray = ["old_oak", "town_square", "midden", "breach", "labyrinth"]
## here -> target -> [flag that opens it, locked text]. Absent means the gate is open.
const FORWARD := {
	"old_oak":
	{
		"town_square": ["home_unlocked", "Rest in the grove first. The road to town is shut."],
	},
	"town_square":
	{
		"midden": ["landfill_route_open", "Bob has not sent you to the Landfill yet."],
	},
	"mage_association":
	{
		"midden": ["landfill_route_open", "Staff only. By order of the Elders."],
	},
	"midden":
	{
		"breach": ["filth_defeated", "The crater is sealed until the Landfill is dealt with."],
	},
	"breach":
	{
		"labyrinth": ["filth_defeated", "The crater portal is dark."],
	},
}


static func story_started(flags: StoryFlags) -> bool:
	if flags == null:
		return false
	for id in ["intro_beat", "intro_done", "permit_given", "home_unlocked", "landfill_route_open"]:
		if flags.has(id):
			return true
	return false


## [flag, text] when `target` is a forward gate. A road back to the hub is open unless
## this level's FORWARD row names it (the Old Oak finale is the first trip to town).
static func rule(here: String, target: String) -> PackedStringArray:
	var row: Dictionary = FORWARD.get(here, {})
	if row.has(target):
		var r: Array = row[target]
		return PackedStringArray([String(r[0]), String(r[1])])
	return PackedStringArray()


## A world save may stand in a level the story flags have not opened. The hub is safe.
static func gates_allow(level: String, flags: Dictionary, vault_open := false) -> bool:
	if level == "old_oak" or level == "town_square" or level == "mage_association":
		return true
	if level == "midden":
		return _on(flags, "landfill_route_open") or _on(flags, "filth_defeated") or _on(flags, "tutorial_done")
	if level == "breach" or level == "labyrinth":
		return vault_open or _on(flags, "filth_defeated") or _on(flags, "tutorial_done")
	return false


static func _on(flags: Dictionary, id: String) -> bool:
	return int(flags.get(id, 0)) != 0


## Locks forward gates. No-op until the story has started, so a flagless slice still travels.
static func apply(gates: Array, here: String, flags: StoryFlags) -> void:
	if not story_started(flags):
		return
	for g in gates:
		var gate := g as LevelGate
		if gate == null:
			continue
		var r := rule(here, gate.target)
		if r.is_empty():
			if gate.target == HUB:
				gate.requires = ""
				gate.flags = flags
			continue
		gate.requires = r[0]
		gate.locked_text = r[1]
		gate.flags = flags
