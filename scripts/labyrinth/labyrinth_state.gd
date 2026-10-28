class_name LabyrinthState
extends RefCounted
## Labyrinth step L2a (LABYRINTH_PLAN section 10): the save's progress.labyrinth block.
## deepest floor reached, cleared floors, per-floor state (remix count, opened chests,
## dead elites), bosses defeated and open shortcut gates. The save seed is rolled once per
## save, so each floor's layout (FloorGen.floor_seed) is the same when you come back.
## Old saves (no block) get a fresh one; a save that visited the Breach starts with floor 1
## reached, since the Breach crater is the Labyrinth gate (plan section 2).

const V := 1
const KIT := "warrens"

var save_seed := 1
var deepest := 0
var cleared: Array[int] = []
var floors := {}  ## str(floor) -> {"remix": int, "chests": [ids], "elites": [ids]}
var bosses: Array[String] = []
var shortcuts: Array[String] = []
## L2: the floor the party is on (0 = not in the Labyrinth); a save made on a floor
## resumes at that floor's start (plan section 7).
var current := 0


static func fresh(seed_value: int = -1) -> LabyrinthState:
	var s := LabyrinthState.new()
	s.save_seed = seed_value if seed_value > 0 else (randi() & 0x7FFFFFFF) + 1
	return s


## The block from a whole save dictionary, migrating saves that predate it.
static func from_save(data: Dictionary) -> LabyrinthState:
	var pr: Variant = data.get("progress", {})
	if not pr is Dictionary:
		return fresh()
	var blk: Variant = (pr as Dictionary).get("labyrinth")
	if blk is Dictionary:
		return from_dict(blk)
	var s := fresh()
	if SaveMigration.visited_levels(data).has("breach"):
		s.deepest = 1
	return s


static func from_dict(d: Dictionary) -> LabyrinthState:
	var s := LabyrinthState.new()
	s.save_seed = maxi(1, int(d.get("save_seed", 1)))
	s.deepest = maxi(0, int(d.get("deepest", 0)))
	for f: Variant in d.get("cleared", []):
		if int(f) > 0 and not s.cleared.has(int(f)):
			s.cleared.append(int(f))
	s.cleared.sort()
	var fl: Variant = d.get("floors", {})
	if fl is Dictionary:
		for k: Variant in fl:
			var e: Variant = fl[k]
			if e is Dictionary and str(k).is_valid_int() and int(k) > 0:
				s.floors[str(int(k))] = {
					"remix": maxi(0, int(e.get("remix", 0))),
					"chests": _strings(e.get("chests", [])),
					"elites": _strings(e.get("elites", [])),
				}
	for b: String in _strings(d.get("bosses", [])):
		s.bosses.append(b)
	for g: String in _strings(d.get("shortcuts", [])):
		s.shortcuts.append(g)
	s.current = maxi(0, int(d.get("current", 0)))
	return s


static func _strings(v: Variant) -> Array:
	var out := []
	if v is Array:
		for x: Variant in v:
			if not out.has(str(x)):
				out.append(str(x))
	return out


func to_dict() -> Dictionary:
	return {
		"v": V,
		"save_seed": save_seed,
		"deepest": deepest,
		"cleared": cleared.duplicate(),
		"floors": floors.duplicate(true),
		"bosses": bosses.duplicate(),
		"shortcuts": shortcuts.duplicate(),
		"current": current,
	}


func _floor(n: int) -> Dictionary:
	var k := str(n)
	if not floors.has(k):
		floors[k] = {"remix": 0, "chests": [], "elites": []}
	return floors[k]


func remix_of(n: int) -> int:
	return int(floors.get(str(n), {}).get("remix", 0))


func floor_seed(n: int) -> int:
	return FloorGen.floor_seed(save_seed, KIT, n, remix_of(n))


func reach(n: int) -> void:
	deepest = maxi(deepest, n)


func clear_floor(n: int) -> void:
	reach(n)
	if not cleared.has(n):
		cleared.append(n)
		cleared.sort()


## Re-rolls a cleared floor (plan section 6 "remix"): new layout, its chests and elites back.
func remix(n: int) -> bool:
	if not cleared.has(n):
		return false
	var f := _floor(n)
	f["remix"] = int(f["remix"]) + 1
	f["chests"] = []
	f["elites"] = []
	return true


func open_chest(n: int, id: String) -> void:
	var c: Array = _floor(n)["chests"]
	if not c.has(id):
		c.append(id)


func chest_open(n: int, id: String) -> bool:
	return (floors.get(str(n), {}).get("chests", []) as Array).has(id)


func kill_elite(n: int, id: String) -> void:
	var e: Array = _floor(n)["elites"]
	if not e.has(id):
		e.append(id)


func elite_dead(n: int, id: String) -> bool:
	return (floors.get(str(n), {}).get("elites", []) as Array).has(id)


func defeat_boss(id: String) -> void:
	if not bosses.has(id):
		bosses.append(id)


func open_shortcut(id: String) -> void:
	if not shortcuts.has(id):
		shortcuts.append(id)
