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
## Read from the packed scene's state. Instantiating the level just to read a marker
## and then free()ing it, while the open world is already up, corrupts the heap
## (joiner rc 134 at process exit).
static func entrance(level: String) -> Vector3:
	if _spots.has(level):
		return _spots[level]
	var path := GameFlow.level_scene(level)
	if not GameFlow.LEVELS.has(level) or not ResourceLoader.exists(path):
		return entrance(FALLBACK_LEVEL) if level != FALLBACK_LEVEL else Vector3.ZERO
	var wo := world_offset(level)
	var p := marker_origin(level, "./PlayerStart")
	_spots[level] = Vector3(p.x + wo.x, p.y, p.z + wo.y)
	return _spots[level]


## OW11c: `level`'s world_offset (cached; zero for an unknown level).
static var _offsets := {}


static func world_offset(level: String) -> Vector2:
	if _offsets.has(level):
		return _offsets[level]
	var wo := Vector2.ZERO
	var v: Variant = _node_prop(level, ".", "metadata/world_offset")
	if v is Vector2:
		wo = v
	_offsets[level] = wo
	return wo


## Local origin of a node in `level`'s packed scene (`./PlayerStart`, `./Exits/to_town`).
static func marker_origin(level: String, node_path: String) -> Vector3:
	var v: Variant = _node_prop(level, node_path, "transform")
	return (v as Transform3D).origin if v is Transform3D else Vector3.ZERO


static func _node_prop(level: String, node_path: String, prop: String) -> Variant:
	var path := GameFlow.level_scene(level)
	if not GameFlow.LEVELS.has(level) or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var st := ps.get_state()
	var want := NodePath(node_path)
	for i in st.get_node_count():
		if st.get_node_path(i) != want:
			continue
		for p in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, p)) == prop:
				return st.get_node_property_value(i, p)
		return null
	return null


## Where a save at `level` (optionally with a level-local position) stands in the world.
static func world_spot(level: String, local: Variant = null) -> Vector3:
	var e := entrance(level)
	if local is Array and (local as Array).size() == 3 and not INTERIORS.has(level):
		var wo := world_offset(level)
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


# --- 0.4.0: world saves to closed levels (LINEAR_LEVELS_PLAN section 4) ------------------
const LINEAR_V := 3
const FLOW := "linear"


static func is_linear(data: Dictionary) -> bool:
	return int((data.get("progress", {}) as Dictionary).get("linear_v", 0)) >= LINEAR_V


## `user://save.json` -> slot1, `save_2.json` -> slot2. Empty when `path` is not a slot
## (tests). The copy is the file as it was before the first linear write.
static func pre_linear_path(path: String) -> String:
	for n in range(1, SaveGame.SLOTS + 1):
		if path == SaveGame.slot_path(n):
			return "user://slot%d.pre_linear.json" % n
	return ""


## Maps a world save onto a closed level. Additive: world_pos, region and fog stay so a
## 0.3.x build can still read the file. The Labyrinth block is not touched, so the floor
## is kept. Returns true when `data` changed. Character files (no progress) are skipped.
static func migrate_linear(data: Dictionary) -> bool:
	if not data.get("progress") is Dictionary or is_linear(data):
		return false
	var pr: Dictionary = data["progress"]
	var flags: Dictionary = pr.get("flags", {})
	var from_world := int(pr.get("world_v", 0)) >= WORLD_V or pr.has("world_pos")
	var lvl := String(pr.get("level_id", ""))
	if from_world:
		var wp: Variant = pr.get("world_pos", [])
		if wp is Array and (wp as Array).size() == 3:
			var a: Array = wp
			lvl = WorldSession.nearest_level(Vector3(float(a[0]), float(a[1]), float(a[2])))
		elif not GameFlow.LEVELS.has(lvl):
			lvl = FALLBACK_LEVEL
		if not LevelFlow.gates_allow(lvl, flags, bool(pr.get("vault_open", false))):
			lvl = FALLBACK_LEVEL
	elif not GameFlow.LEVELS.has(lvl):
		lvl = FALLBACK_LEVEL
	pr["level_id"] = lvl
	pr["flow"] = FLOW
	pr["linear_v"] = LINEAR_V
	_remap_waystones(pr)
	if not pr.has("level_seen"):
		var seen: Array = []
		for l in visited_levels(data):
			if not seen.has(l):
				seen.append(l)
		if GameFlow.LEVELS.has(lvl) and not seen.has(lvl):
			seen.append(lvl)
		pr["level_seen"] = seen
		for l in seen:
			if int(flags.get(WorldMap.SEEN + String(l), 0)) == 0:
				flags[WorldMap.SEEN + String(l)] = 1
		pr["flags"] = flags
	return true


## Copies the slot once, then writes the migrated save. No-op when already linear.
static func store_linear(data: Dictionary, path: String) -> bool:
	if not migrate_linear(data):
		return false
	var bak := pre_linear_path(path)
	if bak != "" and not FileAccess.file_exists(bak) and FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bak))
		print("[save] backed up %s -> %s" % [path, bak])
	var err := SaveGame.write(data, path)
	if err != OK:
		push_warning("[save] linear migration write failed: %s" % error_string(err))
	return true


static func _remap_waystones(pr: Dictionary) -> void:
	var fl: Variant = pr.get("flags", {})
	if not fl is Dictionary:
		return
	var flags: Dictionary = fl
	var map := {
		"waystone:town_market": "waystone:town_gate",
		"waystone:landfill_camp": "waystone:landfill",
		"waystone:landfill_overlook": "waystone:landfill",
	}
	var changed := false
	for src in map:
		if int(flags.get(src, 0)) != 0 and int(flags.get(map[src], 0)) == 0:
			flags[map[src]] = 1
			changed = true
	if changed:
		pr["flags"] = flags
