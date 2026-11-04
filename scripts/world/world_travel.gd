class_name WorldTravel
extends Node3D
## Waystones from res://world/markers.json. travel_to(point) moves the party there under
## the loading screen. Closed levels load a new scene for a different level; this node
## still places the markers and handles deep Labyrinth points. Level [[exit]]s are plain
## roads here; exit_markers() hands them to the map. Free between attuned waystones,
## refused in combat.

signal arrived(point: String)

const MARKERS := "res://world/markers.json"
const LAND := Vector3(0.0, 0.0, 2.5)  ## off the stone, like main.gd's spawn

var fast_travel: FastTravel
var height_fn := Callable()
var in_combat := Callable()  ## -> bool; travel is refused while it is true
var party := Callable()  ## -> Array of Node3D to move; default: the Player group
var waystones := {}  ## point -> Waystone
## Labyrinth L2: deep waystones (FastTravel.DEEP_POINTS) have no world marker. The caller
## sets deep_travel (point -> enter its floor, awaitable), deep_world (point -> the map spot:
## the crater gate) and leave_interior (outdoor travel from inside an interior).
var deep_travel := Callable()
var deep_world := Callable()
var leave_interior := Callable()
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
	if FastTravel.is_deep(point):
		return deep_world.call(point) if deep_world.is_valid() else Vector3.ZERO
	var xz: Array = markers.get("waystones", {}).get(point, [0.0, 0.0])
	return ground(float(xz[0]), float(xz[1]))


## Every waystone on the map: the world's, then the deep ones.
func points() -> Array:
	var out: Array = waystones.keys()
	for p in FastTravel.DEEP_POINTS:
		out.append(p)
	return out


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
	elif not waystones.has(point) and not (FastTravel.is_deep(point) and deep_travel.is_valid()):
		last_error = "That waystone isn't in the world."
	elif in_combat.is_valid() and in_combat.call():
		last_error = "You can't travel while fighting."
	elif not fast_travel.can_travel(point):
		last_error = fast_travel.last_error
	return last_error.is_empty()


## Moves the party to `point` under the loading screen. False + last_error when refused.
func travel_to(point: String) -> bool:
	if not can_travel(point):
		return false
	if FastTravel.is_deep(point):
		busy = true
		await deep_travel.call(point)
		busy = false
		arrived.emit(point)
		return true
	busy = true
	if leave_interior.is_valid():
		leave_interior.call()
	var dest := point_world(point) + LAND
	var screen := LoadingScreen.overlay(get_tree(), String(FastTravel.info(point)["level"]))
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


## Lands the party at `dest` under the loading screen. Waystones use travel_to.
## `warm` (awaited) runs with the party in place, just before the loading screen goes.
func land_at(dest: Vector3, level := "", warm := Callable()) -> void:
	while busy and is_inside_tree():  # queue behind a load in flight (a 2nd overlay freed the 1st)
		await get_tree().process_frame
	busy = true
	var screen := LoadingScreen.overlay(get_tree(), level)
	for n in _party():
		var o := n as Node3D
		var to := ground(dest.x, dest.z)
		if o.has_method("spawn"):
			o.call("spawn", to, o.rotation.y)
		else:
			o.global_position = to
	if warm.is_valid():
		await warm.call()
	if is_instance_valid(screen):
		screen.done()
	busy = false


func _party() -> Array:
	if party.is_valid():
		return party.call()
	return get_tree().get_nodes_in_group(Player.GROUP) if is_inside_tree() else []
