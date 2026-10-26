class_name TerrainZone
extends Node3D
## Phase W (step 152, TERRAIN_MAPS_PLAN sections 2-4): an open-zone heightfield around a
## level's greybox. Built by tools/toml_to_scene.py from a TOML `[terrain]` table.
##
## The heights are a pure function of the exported settings (FastNoiseLite with a fixed
## seed, flattened over `pads`, raised at the zone edge), so every peer builds the same
## bytes and `content_hash()` can be compared on co-op join. Pads are the footprints of
## the level's `ground` boxes: the old greybox content stays where it was, on flat ground
## just below the box tops, and the zone grows around it.
##
## Rendering, LOD and collision come from Terrain3D (addons/terrain_3d, MIT, v1.0.2).
## When the GDExtension is missing (a broken install), the zone still adds its edge walls
## and heights, and `terrain` stays null.

const LAYER_DIR := "res://assets/ambientcg/%s/"
const GEN_VERSION := 1  ## step 155: bump when height/splat generation changes (co-op hash)
const EDGE := 24.0  ## metres over which the zone edge rises to `rim`

@export var size := Vector2(200, 200)
@export var center := Vector2.ZERO
@export var height := 10.0
@export var noise_seed := 1
@export var spacing := 1.0
@export var rim := 16.0
@export var map_version := 1
@export var layers: PackedStringArray = ["Grass004", "Rock030", "Gravel022"]
@export var pads: Array[Rect2] = []
@export var pad_y := -0.02
@export var blend := 14.0
@export var build_on_ready := true

var terrain: Node3D = null  ## Terrain3D (typed loosely so this parses without the extension)
var _noise: FastNoiseLite = null
var _hash := 0


static func available() -> bool:
	return ClassDB.class_exists(&"Terrain3D")


const REGION_SIZE := 256  # Terrain3D default region_size (vertices)


func _ready() -> void:
	snap_level()
	if build_on_ready:
		build()


## Step 157: TOML props / anchors / waystones with `snap = true` keep their y as an offset
## above the heightfield (the generator does not know the noise), so they sit on the hills.
func snap_level() -> void:
	var lvl := get_parent()
	if lvl == null:
		return
	for holder in ["Props", "Anchors", "Waystones", "Pois", "Chests"]:
		var h := lvl.get_node_or_null(holder)
		if h == null:
			continue
		var stack: Array[Node] = h.get_children()
		while not stack.is_empty():
			var n := stack.pop_back() as Node
			if n is Node3D and n.get_meta(&"snap", false) and not n.get_meta(&"snapped", false):
				var p := (n as Node3D).position
				(n as Node3D).position.y = height_at(p.x, p.z) + p.y
				n.set_meta(&"snapped", true)
			if holder == "Pois":
				stack.append_array(n.get_children())


func noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = noise_seed
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.008
		_noise.fractal_octaves = 3
	return _noise


## Distance (m) from (x, z) to the nearest pad; 0 inside one, INF with no pads.
func pad_distance(x: float, z: float) -> float:
	var d := INF
	for r in pads:
		var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
		d = minf(d, sqrt(dx * dx + dz * dz))
	return d


## Distance (m) from (x, z) to the zone edge (negative outside).
func edge_distance(x: float, z: float) -> float:
	var h := size * 0.5
	return minf(minf(x - (center.x - h.x), center.x + h.x - x), minf(z - (center.y - h.y), center.y + h.y - z))


func height_at(x: float, z: float) -> float:
	var hill := (noise().get_noise_2d(x, z) * 0.5 + 0.5) * height
	var t := clampf(pad_distance(x, z) / blend, 0.0, 1.0)
	var h := pad_y + hill * t * t * (3.0 - 2.0 * t)
	var e := clampf(1.0 - edge_distance(x, z) / EDGE, 0.0, 1.0)
	return h + rim * e * e


func grid_size() -> Vector2i:
	var span := center + size * 0.5 - origin()
	return Vector2i(int(ceil(span.x / spacing)) + 1, int(ceil(span.y / spacing)) + 1)


## Image origin, snapped down to Terrain3D's region grid: import_images pastes the
## image at the corner of the region containing the given position, so the image
## has to start there for world positions to line up.
func origin() -> Vector2:
	var r := REGION_SIZE * spacing
	var o := center - size * 0.5
	return Vector2(floor(o.x / r) * r, floor(o.y / r) * r)


## The heightmap (FORMAT_RF, one pixel per vertex).
func height_image() -> Image:
	var g := grid_size()
	var o := origin()
	var data := PackedFloat32Array()
	data.resize(g.x * g.y)
	for j in g.y:
		var z := o.y + j * spacing
		for i in g.x:
			data[j * g.x + i] = height_at(o.x + i * spacing, z)
	return Image.create_from_data(g.x, g.y, false, Image.FORMAT_RF, data.to_byte_array())


## Terrain3D control map: pads are painted with layer 2 (paths); elsewhere the auto
## shader picks layer 0 (flat) or 1 (slopes). Navigation bit set everywhere.
func control_image() -> Image:
	var g := grid_size()
	var o := origin()
	var bytes := PackedByteArray()
	bytes.resize(g.x * g.y * 4)
	var path_id := mini(2, layers.size() - 1)
	for j in g.y:
		var z := o.y + j * spacing
		for i in g.x:
			var on_pad := pad_distance(o.x + i * spacing, z) < 2.0
			var c := (path_id << 27) | 2 if on_pad else 3  # bit 1 navigation, bit 0 auto
			bytes.encode_u32((j * g.x + i) * 4, c)
	return Image.create_from_data(g.x, g.y, false, Image.FORMAT_RF, bytes)


## Stable across peers and runs (the heightmap bytes plus the map version).
func content_hash() -> int:
	if _hash == 0:
		_hash = hash([map_version, height_image().get_data()])
	return _hash


func build() -> void:
	_add_edge_walls()
	if not available():
		push_warning("TerrainZone %s: Terrain3D extension missing; flat greybox only" % name)
		return
	var t: Node3D = ClassDB.instantiate(&"Terrain3D")
	t.name = "Terrain3D"
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or DisplayServer.get_name() == "headless":
		# Headless tests / servers: Terrain3D stops processing without a camera, and a
		# borrowed camera may be freed before the terrain (another test's scene).
		cam = Camera3D.new()
		cam.name = "TerrainFallbackCamera"
		cam.current = false
		add_child(cam)
	t.call(&"set_camera", cam)
	t.set(&"vertex_spacing", spacing)
	t.set(&"material", ClassDB.instantiate(&"Terrain3DMaterial"))
	t.set(&"assets", _assets())
	add_child(t)
	t.get(&"collision").set(&"mode", 3)  # FULL_GAME: static collision for the whole zone
	var o := origin()
	t.get(&"data").call(&"import_images", [height_image(), control_image(), null], Vector3(o.x, 0, o.y), 0.0, 1.0)
	var mat: Object = t.get(&"material")
	mat.set(&"auto_shader", true)
	mat.call(&"set_shader_param", &"auto_slope", 1.2)
	mat.call(&"set_shader_param", &"auto_base_texture", 0)
	mat.call(&"set_shader_param", &"auto_overlay_texture", mini(1, layers.size() - 1))
	t.get(&"collision").call(&"build")
	terrain = t


func _assets() -> Object:
	var a: Object = ClassDB.instantiate(&"Terrain3DAssets")
	var list := []
	for i in layers.size():
		var ta: Object = ClassDB.instantiate(&"Terrain3DTextureAsset")
		ta.set(&"name", layers[i])
		ta.set(&"id", i)
		var dir := LAYER_DIR % layers[i]
		if ResourceLoader.exists(dir + "terrain_alb_ht.png"):
			ta.set(&"albedo_texture", load(dir + "terrain_alb_ht.png"))
			ta.set(&"normal_texture", load(dir + "terrain_nrm_rgh.png"))
		ta.set(&"uv_scale", 0.15)
		list.append(ta)
	a.set(&"texture_list", list)
	return a


## Invisible walls just inside the zone edge (the rim slopes up to them).
func _add_edge_walls() -> void:
	var h := size * 0.5
	var wall_h := rim + height + 40.0
	for s in [
		[Vector3(center.x, 0, center.y - h.y), Vector3(size.x, wall_h, 1)],
		[Vector3(center.x, 0, center.y + h.y), Vector3(size.x, wall_h, 1)],
		[Vector3(center.x - h.x, 0, center.y), Vector3(1, wall_h, size.y)],
		[Vector3(center.x + h.x, 0, center.y), Vector3(1, wall_h, size.y)]
	]:
		var body := StaticBody3D.new()
		body.name = "EdgeWall%d" % get_child_count()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s[1]
		cs.shape = box
		body.position = s[0]
		body.add_child(cs)
		add_child(body)


## Step 152: terrain faces inside `aabb` for the level navmesh (LevelNavigation), so
## enemies path over the ground around the old greybox pads.
func add_nav_faces(data: NavigationMeshSourceGeometryData3D, aabb: AABB) -> void:
	# Built from height_at rather than Terrain3D.generate_nav_mesh_source_geometry,
	# which returned no faces right after import (and must match on every peer anyway).
	var lo := Vector2(maxf(aabb.position.x, center.x - size.x * 0.5), maxf(aabb.position.z, center.y - size.y * 0.5))
	var hi := Vector2(minf(aabb.end.x, center.x + size.x * 0.5), minf(aabb.end.z, center.y + size.y * 0.5))
	if hi.x <= lo.x or hi.y <= lo.y:
		return
	var o := origin()
	var i0 := int(floor((lo.x - o.x) / spacing))
	var j0 := int(floor((lo.y - o.y) / spacing))
	var i1 := int(ceil((hi.x - o.x) / spacing))
	var j1 := int(ceil((hi.y - o.y) / spacing))
	var faces := PackedVector3Array()
	for j in range(j0, j1):
		for i in range(i0, i1):
			var x0 := o.x + i * spacing
			var z0 := o.y + j * spacing
			var x1 := x0 + spacing
			var z1 := z0 + spacing
			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x1, height_at(x1, z0), z0)
			var c := Vector3(x0, height_at(x0, z1), z1)
			var d := Vector3(x1, height_at(x1, z1), z1)
			faces.append_array([a, b, c, b, d, c])
	if not faces.is_empty():
		data.add_faces(faces, Transform3D.IDENTITY)
