class_name OpenWorld
extends Node3D
## OW3b: the open-world root. Loads the saved world Terrain3DData (res://world/terrain/,
## tools/build_world.sh) instead of generating terrain, with Dynamic collision around the
## viewers, and streams the static content cells with a WorldStreamer. Gameplay content
## still comes from the levels until OW4-OW6; main.gd keeps using levels until OW10.

const TERRAIN_DIR := "res://world/terrain/"

var terrain: Node3D
var streamer: WorldStreamer
var interiors: Interiors
var info := {}


func _ready() -> void:
	info = load_info()
	if TerrainZone.available() and not info.is_empty():
		_build_terrain()
	streamer = WorldStreamer.new()
	streamer.name = "Cells"
	add_child(streamer)
	var sleeper := EnemySleep.new()
	sleeper.name = "EnemySleep"
	add_child(sleeper)
	interiors = Interiors.new()
	interiors.name = "Interiors"
	interiors.height_fn = height_at
	add_child(interiors)
	interiors.add_doors()


static func load_info() -> Dictionary:
	var v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TERRAIN_DIR + "world_terrain.json")
	)
	return v if v is Dictionary else {}


func _build_terrain() -> void:
	var t: Node3D = ClassDB.instantiate(&"Terrain3D")
	t.name = "Terrain3D"
	var cam := get_viewport().get_camera_3d()
	if cam == null or DisplayServer.get_name() == "headless":
		cam = Camera3D.new()
		cam.name = "TerrainFallbackCamera"
		cam.current = false
		add_child(cam)
	t.call(&"set_camera", cam)
	t.set(&"vertex_spacing", float(info.get("spacing", 1.0)))
	t.set(&"material", ClassDB.instantiate(&"Terrain3DMaterial"))
	t.set(&"data_directory", TERRAIN_DIR)
	add_child(t)
	t.set(&"assets", TerrainZone.make_assets(PackedStringArray(info.get("layers", []))))
	t.get(&"material").set(&"show_checkered", false)
	t.get(&"material").set(&"auto_shader", false)  # build_world.py paints every vertex
	t.get(&"collision").set(&"mode", 1)  # DYNAMIC_GAME: collision around the camera only
	terrain = t


## World height at (x, z), or NAN outside the saved regions.
func height_at(x: float, z: float) -> float:
	if terrain == null:
		return NAN
	return terrain.get(&"data").call(&"get_height", Vector3(x, 0, z))
