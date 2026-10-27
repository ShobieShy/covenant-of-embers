class_name SaveMigration
extends RefCounted
## OW10 (OPEN_WORLD_PLAN section 8): level saves to open-world saves. A save carries
## progress.world_pos [x, y, z] + progress.region; a 0.1.4 save only has progress.level_id,
## so it maps through the level's world_offset to the level's PlayerStart (its entrance;
## old saves never stored a local position). With a stored local position (`local_pos`)
## outdoors, that spot is kept. Interior / unknown levels land at the level entrance or the
## town gate. Visited levels seed the fog (progress.fog). Additive keys only: level_id stays,
## so builds that still play levels keep loading the migrated file.

const WORLD_V := 2
const FALLBACK_LEVEL := "town_square"
const SEED_HALF := 96.0  ## metres revealed around each visited level's entrance
const INTERIORS: PackedStringArray = ["mage_association"]

static var _spots := {}  ## level id -> world Vector3 of its PlayerStart (scene loads cached)


static func is_migrated(data: Dictionary) -> bool:
	return int((data.get("progress", {}) as Dictionary).get("world_v", 0)) >= WORLD_V


## World spot of `level`'s entrance (PlayerStart + world_offset), y = local start height.
static func entrance(level: String) -> Vector3:
	if _spots.has(level):
		return _spots[level]
	var path := GameFlow.level_scene(level)
	if not GameFlow.LEVELS.has(level) or not ResourceLoader.exists(path):
		return entrance(FALLBACK_LEVEL) if level != FALLBACK_LEVEL else Vector3.ZERO
	var lvl := (load(path) as PackedScene).instantiate() as Node3D
	var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
	var st := lvl.get_node_or_null(^"PlayerStart") as Node3D
	var p := st.position if st else Vector3.ZERO
	lvl.free()
	_spots[level] = Vector3(p.x + wo.x, p.y, p.z + wo.y)
	return _spots[level]


## Where a save at `level` (optionally with a level-local position) stands in the world.
static func world_spot(level: String, local: Variant = null) -> Vector3:
	var e := entrance(level)
	if local is Array and (local as Array).size() == 3 and not INTERIORS.has(level):
		var path := GameFlow.level_scene(level)
		if GameFlow.LEVELS.has(level) and ResourceLoader.exists(path):
			var lvl := (load(path) as PackedScene).instantiate() as Node3D
			var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
			lvl.free()
			var a: Array = local
			return Vector3(float(a[0]) + wo.x, float(a[1]), float(a[2]) + wo.y)
	return e


## Levels the save has been to: the current one plus each level of a visited region.
static func visited_levels(data: Dictionary) -> PackedStringArray:
	var pr: Dictionary = data.get("progress", {})
	var fl: Dictionary = pr.get("flags", {})
	var out := PackedStringArray()
	var here := String(pr.get("level_id", ""))
	if WorldMap.LEVEL_REGION.has(here):
		out.append(here)
	for l in WorldMap.LEVEL_REGION:
		var reg := String(WorldMap.LEVEL_REGION[l])
		if int(fl.get("region:" + reg, 0)) >= int(WorldMap.State.VISITED) and not out.has(l):
			out.append(l)
	return out


## Upgrades `data` in place; returns true when it changed. Safe to call on any save.
static func migrate(data: Dictionary) -> bool:
	if not data.get("progress") is Dictionary:
		return false  # co-op character files: no progress, no position
	if is_migrated(data):
		return false
	var pr: Dictionary = data["progress"]
	var lvl := String(pr.get("level_id", ""))
	if not GameFlow.LEVELS.has(lvl):
		lvl = FALLBACK_LEVEL
	var w := world_spot(lvl, pr.get("local_pos"))
	pr["world_pos"] = [w.x, w.y, w.z]
	pr["region"] = String(WorldMap.LEVEL_REGION.get(lvl, WorldMap.LEVEL_REGION[FALLBACK_LEVEL]))
	if not pr.has("fog"):
		var fog := WorldFog.new()
		for l in visited_levels(data):
			var c := entrance(l)
			var x := -SEED_HALF
			while x <= SEED_HALF:
				var z := -SEED_HALF
				while z <= SEED_HALF:
					fog.reveal(c.x + x, c.z + z)
					z += WorldFog.CELL
				x += WorldFog.CELL
		pr["fog"] = fog.to_save()
	pr["world_v"] = WORLD_V
	return true
