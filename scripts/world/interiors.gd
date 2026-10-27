class_name Interiors
extends Node3D
## OW5a (OPEN_WORLD_PLAN section 4): instanced interiors in the open world. A door
## trigger (InteriorDoor) fades and loads the interior scene far below the world
## (DEPTH) so the outside stays streamed, moves the party to the interior's matching
## exit, and leaving through an interior exit moves the party back out to the linked
## marker in the world. Loads run on a thread; `slow_load` fires when one takes over
## SLOW_MS (the loading-screen hook), `fade` asks the UI for the 0.3 s fade.
## OW5b: the Breach rooms are the breach level's greybox complex, instanced from the
## breach scene with its crater parts (STRIP) dropped (the crater is seamless world
## terrain); the portal is the complex's entrance road, and a Breach node runs the rooms.

signal fade(seconds: float)
signal slow_load(id: String)
signal entered(id: String)
signal left(id: String)

const DEPTH := -2000.0
const SLOW_MS := 250
const FADE := 0.3
const INSET := 2.5  ## landings sit this far inside a door, clear of its trigger
## interior id -> front door [level, Exits marker], and where each interior exit
## (its Exits marker metadata/to) lands outside [level, Exits marker]. The back door to
## the Landfill opens at Eldoria's Landfill edge (the town's to_landfill road).
const LINKS := {
	"mage_association":
	{
		"scene": "mage_association",
		"inside": "town_square",
		"front": ["town_square", "to_association"],
		"exits":
		{
			"town_square": ["town_square", "to_association"],
			"midden": ["town_square", "to_landfill"],
		},
	},
	"breach_rooms":
	{
		"scene": "breach",
		"inside": "midden",
		"front": ["breach", "to_midden"],
		"exits": {"midden": ["breach", "to_midden"]},
		"strip": ["Terrain", "Props", "Pois"],
		"logic": "breach",
	},
}

## OW5b: level groups that live in an instanced interior, so tools/build_cells.gd keeps
## them out of the world cells.
const CELL_SKIP := {"breach": ["Boxes"]}

var current := ""
var interior: Node3D
var height_fn: Callable  ## (x, z) -> world height; OpenWorld.height_at
var busy := false
var breach: Breach  ## OW5b: the rooms' logic while breach_rooms is entered


## World position of a level's Exits marker (at the level's world_offset), on the ground.
func marker_world(level: String, marker: String) -> Vector3:
	var lvl := (load(GameFlow.level_scene(level)) as PackedScene).instantiate() as Node3D
	var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
	var m := lvl.get_node_or_null(NodePath("Exits/" + marker)) as Node3D
	var p := m.position if m else Vector3.ZERO
	lvl.free()
	var w := Vector3(p.x + wo.x, 0.0, p.z + wo.y)
	var h: float = height_fn.call(w.x, w.z) if height_fn.is_valid() else NAN
	w.y = 0.0 if is_nan(h) else h
	return w


## Toward the level's centre by INSET, so a landing never sits on its own trigger.
func _inset(p: Vector3, centre: Vector3) -> Vector3:
	var d := Vector3(centre.x - p.x, 0, centre.z - p.z)
	return p + (d.normalized() * INSET if d.length() > 0.01 else Vector3(0, 0, INSET))


## Adds an InteriorDoor at every front door.
func add_doors() -> void:
	for id in LINKS:
		var f: Array = LINKS[id]["front"]
		var d := InteriorDoor.new()
		d.name = "Door_" + id
		d.interior = id
		d.interiors = self
		d.position = marker_world(f[0], f[1])
		add_child(d)


func party() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for g in [Player.GROUP, &"coop_avatars"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D:
				out.append(n)
	return out


func _move_party(p: Vector3) -> void:
	var i := 0
	for n in party():
		n.global_position = p + Vector3(i * 0.8, 0.5, 0)
		if n is CharacterBody3D:
			(n as CharacterBody3D).velocity = Vector3.ZERO
		i += 1


static func nav_cache(id: String) -> String:
	return "res://scenes/levels/nav/interior_%s.res" % id


## Drops the interior's sky, sun and STRIP parts, and gives its LevelNavigation the
## offline mesh (tools/bake_interior_nav.gd) so entering never bakes on the main thread.
static func prepare(n: Node3D, id: String, use_cache := true) -> void:
	var strip: Array = ["WorldEnvironment", "Sun"] + LINKS[id].get("strip", [])
	for s in strip:  # the world's sky and sun stay
		var e := n.get_node_or_null(NodePath(s))
		if e:
			n.remove_child(e)
			e.free()
	var nav := n.get_node_or_null("Navigation") as LevelNavigation
	if nav and use_cache and ResourceLoader.exists(nav_cache(id)):
		nav.bake_on_ready = false
		nav.navigation_mesh = load(nav_cache(id)) as NavigationMesh
	elif nav and use_cache:
		push_warning("Interiors: no nav cache for %s (run tools/bake_interior_nav.gd)" % id)


## The interior scene still loading on a thread ("" when none).
var _loading := ""


## Freed mid-enter (a test, a quit): collect the threaded load so it is not left stale.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _loading != "":
		ResourceLoader.load_threaded_get(_loading)
		_loading = ""


## Enters `id` from `from_level` (the side of the front door). Returns the landing.
func enter(id: String, from_level := "") -> Vector3:
	if busy or current != "" or not LINKS.has(id):
		return Vector3.INF
	var link: Dictionary = LINKS[id]
	if from_level == "":
		from_level = link["inside"]
	busy = true
	fade.emit(FADE)
	var path := GameFlow.level_scene(link["scene"])
	var t0 := Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(path, "PackedScene")
	_loading = path
	var slow := false
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not slow and Time.get_ticks_msec() - t0 > SLOW_MS:
			slow = true
			slow_load.emit(id)
		await get_tree().process_frame
	var ps := ResourceLoader.load_threaded_get(path) as PackedScene
	_loading = ""
	interior = ps.instantiate() as Node3D
	prepare(interior, id)
	interior.name = "Interior"
	interior.position = Vector3(0, DEPTH, 0)
	add_child(interior)
	current = id
	var m := interior.get_node_or_null(NodePath("Exits")) as Node3D
	var land := interior.global_position + Vector3(0, 0.5, 0)
	if m:
		for e in m.get_children():
			if String(e.get_meta(&"to", "")) == from_level:
				land = _inset((e as Node3D).global_position, interior.global_position)
	_move_party(land)
	if link.get("logic", "") == "breach":
		breach = Breach.new()
		breach.name = "Breach"
		interior.add_child(breach)
		var ps_party := party()
		breach.setup(interior, ps_party[0] as Player if not ps_party.is_empty() else null)
	busy = false
	entered.emit(id)
	return land


## Leaves the interior through its exit to `to_level`. Returns the world landing.
func leave(to_level := "town_square") -> Vector3:
	if current == "" or busy:
		return Vector3.INF
	var ex: Dictionary = LINKS[current]["exits"]
	var link: Array = ex.get(to_level, LINKS[current]["front"])
	fade.emit(FADE)
	var p := marker_world(link[0], link[1])
	var lvl := (load(GameFlow.level_scene(link[0])) as PackedScene).instantiate() as Node3D
	var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
	lvl.free()
	var land := _inset(p, Vector3(wo.x, p.y, wo.y))
	_move_party(land)
	var id := current
	interior.queue_free()
	interior = null
	breach = null
	current = ""
	left.emit(id)
	return land
