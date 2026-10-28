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
var travel: WorldTravel
var fog := WorldFog.new()  ## OW7; main.gd saves it under progress.fog from OW10
var pins := MapPins.new()
var map_screen: WorldMapScreen
var minimap: Minimap
var leash: CoopLeash
var _fog_t := 0.0
var info := {}
var story_flags: StoryFlags  ## main.gd sets it before adding the world (fast travel flags)
var _fallback_cam: Camera3D
var _terrain_cam: Camera3D
var first_loaded := false  ## OW10: the initial world load (loading screen) has run
signal first_load_done
signal host_space(interior: String)  ## OW11c: a joiner whose host is in another space


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
	interiors.streamer = streamer
	add_child(interiors)
	interiors.add_doors()
	travel = WorldTravel.new()  # OW6
	travel.name = "Travel"
	travel.streamer = streamer
	travel.height_fn = height_at
	travel.arrived.connect(func(_p: String) -> void: ground_now())
	if story_flags:  # the save's attunement and crystal (else a blank FastTravel)
		travel.fast_travel = FastTravel.new(story_flags)
	travel.deep_travel = _deep_travel  # Labyrinth L2
	travel.deep_world = func(_p: String) -> Vector3:
		return interiors.link_world(Interiors.LINKS["labyrinth"]["front"])
	travel.leave_interior = func() -> void:
		if interiors.current != "":
			interiors.leave()
	add_child(travel)
	var layer := CanvasLayer.new()
	layer.name = "MapLayer"
	layer.layer = 20
	add_child(layer)
	map_screen = WorldMapScreen.new()
	map_screen.fog = fog
	map_screen.pins = pins
	map_screen.travel = travel
	map_screen.players = _map_players
	layer.add_child(map_screen)
	leash = CoopLeash.new()  # OW9
	leash.name = "Leash"
	leash.height_fn = height_at
	leash.host_pos = _host_pos
	leash.hint = _hint
	add_child(leash)
	minimap = Minimap.new()  # OW8
	minimap.fog = fog
	minimap.pins = pins
	minimap.travel = travel
	minimap.players = _map_players
	minimap.lock_north = Settings.load_from().minimap_north
	layer.add_child(minimap)
	for w in travel.waystones.values():
		(w as Waystone).opened.connect(func(_p: String) -> void: map_screen.open())
	interiors.left.connect(_on_left_interior)
	var fader := InteriorFade.new()
	fader.name = "InteriorFade"
	fader.interiors = interiors
	fader.travel = travel  # 0.3.1 P1: fast-travel arrival fades in
	add_child(fader)


## Labyrinth L2: a deep waystone enters its floor.
func _deep_travel(point: String) -> void:
	await interiors.enter_floor(int(FastTravel.info(point).get("floor", 1)))


## OW10 (plan section 9): the one initial world load, behind the loading screen; later
## moves stream in the background as usual.
func first_load(dest: Vector3, level := "") -> void:
	if first_loaded:
		return
	first_loaded = true
	await travel.land_at(dest, level, func() -> void: await ShaderWarmup.run(get_tree()))
	first_load_done.emit()


## L5b: Terrain3D builds its Dynamic collision around its camera only, so that camera must be
## where the players are. The viewport camera is used when there is one (it follows the player);
## otherwise (headless, or before the player's camera exists) a fallback camera is kept on the
## local player. Before L5b the fallback stayed at the origin and the camera was picked once at
## build time, so the ground outside the Breach (which has no box pads) had no collision.
func _physics_process(_dt: float) -> void:
	_track_terrain_camera()


func _track_terrain_camera() -> void:
	if terrain == null or not is_instance_valid(terrain) or _fallback_cam == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or DisplayServer.get_name() == "headless" or not cam.is_inside_tree():
		cam = _fallback_cam
		var p := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
		if p and p.is_inside_tree() and (interiors == null or interiors.current == ""):
			_fallback_cam.global_position = p.global_position
	if cam != _terrain_cam:
		_terrain_cam = cam
		terrain.call(&"set_camera", cam)


## Builds the terrain collision around the players now (a party move: leaving an interior,
## fast travel), so nobody stands on a heightmap whose collision has not been built yet.
func ground_now() -> void:
	_track_terrain_camera()
	if terrain and is_instance_valid(terrain) and terrain.is_inside_tree():
		var c: Object = terrain.get(&"collision")
		if c and c.has_method(&"update"):
			c.call(&"update")


func _on_left_interior(_id: String) -> void:
	ground_now()
	if not first_loaded:  # a run that started indoors (the intro): its first look outside
		var p := interiors.party()
		if not p.is_empty():
			first_load((p[0] as Node3D).global_position, "town_square")


## Reveals fog around every player twice a second.
func _process(dt: float) -> void:
	_fog_t += dt
	if _fog_t < 0.5:
		return
	_fog_t = 0.0
	for p in _map_players():
		fog.reveal(p[0].x, p[0].z)
	if Coop.is_client():
		var hs: Variant = _host_interior()
		_sync_breach()
		if hs is String and hs != interiors.current and not interiors.busy and not travel.busy:
			host_space.emit(hs)  # OW11c: follow the host in or out of an interior
		elif interiors.current == "" and not interiors.busy and not travel.busy:
			leash.player = get_tree().get_first_node_in_group(Player.GROUP) as Node3D
			leash.check()
	if minimap:
		minimap.visible = not map_screen.visible


## [pos, yaw, name, colour, is_local] for the local player and every co-op partner (OW8).
func _map_players() -> Array:
	if not is_inside_tree() or (interiors and interiors.current != ""):
		return []
	return map_rows(get_tree())


## The host's proxy on a joiner (peer 1), or null.
func _host_pos() -> Variant:
	for n in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		if (n as RemotePlayer).peer == 1:
			return (n as Node3D).global_position
	return null


## OW11c: the joiner's Breach rooms open the gate and vault when the host's have (the levers
## and the boss are the host's; without this the joiner is walled in at the switch gate).
func _sync_breach() -> void:
	var br := interiors.breach if interiors else null
	if br == null or not is_instance_valid(br):
		return
	for n in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		var r := n as RemotePlayer
		if r.peer == 1:
			if r.breach_open & 1 and not br.gate_open:
				br.open_gate()
			if r.breach_open & 2 and not br.open:
				br.open_vault()


## The interior the host is in ("" outdoors), or null before its first pose.
func _host_interior() -> Variant:
	for n in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		var r := n as RemotePlayer
		if r.peer == 1 and r.poses > 0:
			return r.interior
	return null


func _hint(t: String) -> void:
	var hud := (
		get_tree().current_scene.get_node_or_null("Hud") if get_tree().current_scene else null
	)
	if hud and hud.has_method(&"show_hint"):
		hud.call(&"show_hint", t)


static func map_rows(tree: SceneTree) -> Array:
	var out: Array = []
	for n in tree.get_nodes_in_group(Player.GROUP):
		var p := n as Node3D
		var nm: Variant = p.get(&"character_name")
		var c: Variant = p.get(&"character_color")
		out.append(
			[
				p.global_position,
				p.global_rotation.y,
				String(nm) if nm != null else "",
				c if c is Color else Color(1, 0.8, 0.3),
				true
			]
		)
	for n in tree.get_nodes_in_group(RemotePlayer.GROUP):
		var r := n as RemotePlayer
		out.append([r.global_position, r.target_yaw, r.display_name, r.color, false])
	return out


static func load_info() -> Dictionary:
	var v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TERRAIN_DIR + "world_terrain.json")
	)
	return v if v is Dictionary else {}


func _build_terrain() -> void:
	var t: Node3D = ClassDB.instantiate(&"Terrain3D")
	t.name = "Terrain3D"
	_fallback_cam = Camera3D.new()
	_fallback_cam.name = "TerrainFallbackCamera"
	_fallback_cam.current = false
	add_child(_fallback_cam)
	terrain = t
	_track_terrain_camera()
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
