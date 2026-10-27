class_name WorldTravel
extends Node3D
## OW6: waystones and fast travel inside the open world. Places a Waystone at every point
## in res://world/markers.json (tools/bake_world_markers.gd), and travel_to(point) streams
## the destination cells under the loading screen, then moves the party there - no level
## change. Level [[exit]]s are plain roads here; exit_markers() hands them to the map (OW7).
## Free between attuned waystones, refused in combat (OPEN_WORLD_PLAN Q3); host only.

signal arrived(point: String)

const MARKERS := "res://world/markers.json"
const LAND := Vector3(0.0, 0.0, 2.5)  ## off the stone, like main.gd's spawn

var fast_travel: FastTravel
var streamer: WorldStreamer
var height_fn := Callable()
var in_combat := Callable()  ## -> bool; travel is refused while it is true
var party := Callable()  ## -> Array of Node3D to move; default: the Player group
var waystones := {}  ## point -> Waystone
var markers := {}
var busy := false
var last_error := ""


static func load_markers() -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(MARKERS))
	return v if v is Dictionary else {}


func _ready() -> void:
	if fast_travel == null:
		fast_travel = FastTravel.new()
	markers = load_markers()
	for p in markers.get("waystones", {}):
		var w := Waystone.new(String(p), fast_travel)
		w.name = "Waystone_" + String(p)
		add_child(w)
		w.global_position = point_world(String(p))
		waystones[String(p)] = w


## Waystones attune on the local player (Waystone.player).
func _physics_process(_dt: float) -> void:
	var p: Player = null
	for n in _party():
		if n is Player:
			p = n
			break
	for w in waystones.values():
		(w as Waystone).player = p


func ground(x: float, z: float) -> Vector3:
	var h: float = height_fn.call(x, z) if height_fn.is_valid() else NAN
	return Vector3(x, 0.0 if is_nan(h) else h, z)


func point_world(point: String) -> Vector3:
	var xz: Array = markers.get("waystones", {}).get(point, [0.0, 0.0])
	return ground(float(xz[0]), float(xz[1]))


## [{level, name, to, kind ("road" / "door"), pos: Vector3}] for the map screen.
func exit_markers() -> Array:
	var out: Array = []
	for e in markers.get("exits", []):
		var d: Dictionary = (e as Dictionary).duplicate()
		d["pos"] = ground(float(e["pos"][0]), float(e["pos"][1]))
		out.append(d)
	return out


func can_travel(point: String) -> bool:
	last_error = ""
	if busy:
		last_error = "Already travelling."
	elif not waystones.has(point):
		last_error = "That waystone isn't in the world."
	elif in_combat.is_valid() and in_combat.call():
		last_error = "You can't travel while fighting."
	elif not fast_travel.can_travel(point):
		last_error = fast_travel.last_error
	return last_error.is_empty()


## Streams the cells around `point` (LoadingScreen overlay with real progress), then moves
## the party. False + last_error when refused.
func travel_to(point: String) -> bool:
	if not can_travel(point):
		return false
	busy = true
	var dest := point_world(point) + LAND
	var screen := LoadingScreen.overlay(get_tree(), String(FastTravel.POINTS[point]["level"]))
	await _stream(dest, screen)
	var who := _party()
	var lead := (who[0] as Node3D).global_position if not who.is_empty() else dest
	for n in who:  # keep the party's spread around the leader
		var o := n as Node3D
		var off := o.global_position - lead
		var to := ground(dest.x + off.x, dest.z + off.z)
		if o.has_method("spawn"):
			o.call("spawn", to, o.rotation.y)
		else:
			o.global_position = to
	if is_instance_valid(screen):
		screen.done()
	busy = false
	arrived.emit(point)
	return true


## OW10 (plan section 9): streams the cells around `dest` behind the loading screen, then
## lands the party there; the first world load uses it (a fresh start or the Association's
## front door), waystones use travel_to.
func land_at(dest: Vector3, level := "") -> void:
	while busy and is_inside_tree():  # QA-2: queue behind a load in flight (a 2nd overlay freed the 1st)
		await get_tree().process_frame
	busy = true
	var screen := LoadingScreen.overlay(get_tree(), level)
	await _stream(dest, screen)
	for n in _party():
		var o := n as Node3D
		var to := ground(dest.x, dest.z)
		if o.has_method("spawn"):
			o.call("spawn", to, o.rotation.y)
		else:
			o.global_position = to
	if is_instance_valid(screen):
		screen.done()
	busy = false


func _party() -> Array:
	if party.is_valid():
		return party.call()
	return get_tree().get_nodes_in_group(Player.GROUP) if is_inside_tree() else []


func _stream(dest: Vector3, screen: LoadingScreen) -> void:
	if streamer == null:
		return
	var keep := streamer.viewer_override.duplicate()
	var pts: Array[Vector3] = [dest]
	streamer.viewer_override = pts
	var want := streamer.wanted(pts, WorldStreamer.RING)
	for i in 1200:  # 20 s at 60 fps, then go anyway
		streamer.step()
		var got := 0
		for k in want:
			got += 1 if streamer.loaded.has(k) else 0
		if is_instance_valid(screen):
			screen.advance(LoadingScreen.Stage.LEVEL, float(got) / maxf(1.0, want.size()))
		if got == want.size():
			if is_instance_valid(screen):
				screen.advance(LoadingScreen.Stage.NAV, 0.0)
			if not streamer.nav_pending(pts):
				break
		await get_tree().process_frame
	streamer.viewer_override = keep
