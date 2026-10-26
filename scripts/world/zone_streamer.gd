class_name ZoneStreamer
extends Node3D
## Phase W2 (step 153, TERRAIN_MAPS_PLAN section 5): streams an open zone's points of
## interest. The level's `Pois` node (generated from TOML [[poi]] tables) holds one Node3D
## per POI (metadata center + radius) whose children are that POI's props and dressing.
## A POI's content is in the tree while any player is within LOAD_RADIUS[quality] of its
## edge and leaves the tree (kept in memory, so re-entry is instant and deterministic)
## once every player is UNLOAD_EXTRA further out: the hysteresis stops thrash at the line.
## Gameplay nodes (camps, chests, waystones, exits) never live under a POI, so streaming
## is purely visual and co-op peers never disagree about the world.
##
## apply_ranges() sets per-quality visibility ranges (HLOD-style fade) on every prop mesh,
## and occlusion culling is on for Medium/High (QualityPresets.apply_level calls both).

const LOAD_RADIUS := [150.0, 200.0, 250.0]  ## Low (Steam Deck) / Medium / High
const UNLOAD_EXTRA := 50.0
const VIS_END := [90.0, 140.0, 220.0]  ## prop mesh visibility_range_end per quality
const TICK_S := 0.25

var loaded := {}  ## poi name -> true while its content is in the tree
var _held := {}  ## poi name -> Array[Node] detached content
var _t := 0.0


func _ready() -> void:
	for p in get_children():
		loaded[String(p.name)] = true
	update_now()


static func load_radius() -> float:
	return LOAD_RADIUS[QualityPresets.level]


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= TICK_S:
		_t = 0.0
		update_now()


## Positions the streamer measures from: every local player plus co-op avatars.
func viewers() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_inside_tree():
		return out
	for g in [Player.GROUP, &"coop_avatars", &"stream_viewers"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and (n as Node3D).is_inside_tree():
				out.append((n as Node3D).global_position)
	return out


func update_now(at: Array[Vector3] = []) -> void:
	var pts := at if not at.is_empty() else viewers()
	if pts.is_empty():
		return  # no one to stream for (editor preview, tools): leave everything in
	var r := load_radius()
	for p in get_children():
		var id := String(p.name)
		if not loaded.has(id):
			loaded[id] = true
		var c: Vector3 = p.get_meta(&"center", Vector3.ZERO)
		var edge := float(p.get_meta(&"radius", 30.0))
		var d := INF
		for v in pts:
			d = minf(d, Vector2(v.x - c.x, v.z - c.z).length() - edge)
		if loaded.get(id, true) and d > r + UNLOAD_EXTRA:
			_unload(p)
		elif not loaded.get(id, true) and d <= r:
			_load(p)


func _unload(p: Node) -> void:
	var kids: Array[Node] = []
	for k in p.get_children():
		p.remove_child(k)
		kids.append(k)
	_held[String(p.name)] = kids
	loaded[String(p.name)] = false


func _load(p: Node) -> void:
	for k in _held.get(String(p.name), []):
		p.add_child(k)
	_held.erase(String(p.name))
	loaded[String(p.name)] = true


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for id in _held:  # detached nodes are ours to free
		for k in _held[id]:
			(k as Node).free()
	_held.clear()


static func apply_ranges(lvl: Node) -> void:
	var end: float = VIS_END[QualityPresets.level]
	for holder in [lvl.get_node_or_null(^"Props"), lvl.get_node_or_null(^"Pois")]:
		if holder == null:
			continue
		for g in (holder as Node).find_children("*", "GeometryInstance3D", true, false):
			var gi := g as GeometryInstance3D
			gi.visibility_range_end = end
			gi.visibility_range_end_margin = 10.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
