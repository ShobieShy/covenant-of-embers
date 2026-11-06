extends TestCase
## BUILD_PLAN step 2: scenes/levels/midden.tscn is generated from
## data/levels/midden_greybox.toml (tools/toml_to_scene.py). Expected values follow the
## archived C++ test (archive/cpp-engine/tests/test_level.cpp).

const TOML_PATH := "res://data/levels/midden_greybox.toml"
const SCENE_PATH := "res://scenes/levels/midden.tscn"
const EPS := 1e-4


func _toml() -> Dictionary:
	var d := LevelToml.load_file(TOML_PATH)
	check(not d.has("error"), "TOML parses: %s" % d.get("error", ""))
	return d


func _boxes(d: Dictionary) -> Array:
	return d.get("box", [])


## Instantiates the level inside the runner's tree so physics queries work.
func _spawn() -> Node3D:
	var packed: PackedScene = load(SCENE_PATH)
	var level: Node3D = packed.instantiate()
	runner_tree.root.add_child(level)
	return level


func _ray(level: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return level.get_world_3d().direct_space_state.intersect_ray(q)


func _box_node(level: Node, name: String) -> StaticBody3D:
	return level.get_node_or_null("Boxes/" + name) as StaticBody3D


func test_toml_reader() -> void:
	var d := LevelToml.parse('[a]\nx = 1.5 # c\ns = "h#i"\n[[b]]\nv = [1, 2, 3]\n[[b]]\nok = true\n')
	check(not d.has("error"), "subset parses")
	check_near(float(d["a"]["x"]), 1.5, EPS, "number")
	check(d["a"]["s"] == "h#i", "# inside a string is not a comment")
	check((d["b"] as Array).size() == 2 and LevelToml.vec3(d["b"][0]["v"]) == Vector3(1, 2, 3), "array of tables")
	check(LevelToml.parse("x = [1,\n2]").has("error"), "multi-line arrays rejected")
	check(LevelToml.parse("x = 1\nx = 2").has("error"), "duplicate key rejected")


func test_boxes_match_toml() -> void:
	var d := _toml()
	var boxes := _boxes(d)
	var level: Node3D = (load(SCENE_PATH) as PackedScene).instantiate()
	var nodes := level.get_node("Boxes").get_children()
	check(nodes.size() == boxes.size(), "scene has %d boxes, TOML %d" % [nodes.size(), boxes.size()])
	var want: Dictionary = {}
	var got: Dictionary = {}
	for b in boxes:
		want[b["kind"]] = int(want.get(b["kind"], 0)) + 1
	for n in nodes:
		check(n is StaticBody3D, "%s is a StaticBody3D" % n.name)
		var k: String = n.get_meta("kind", "")
		got[k] = int(got.get(k, 0)) + 1
	check(want == got, "kind counts: TOML %s scene %s" % [want, got])
	check(int(want.get("wall", 0)) == 0, "the valley has no slate barrier ring")
	check(int(want.get("heap", 0)) >= 8 and int(want.get("ground", 0)) >= 3, "heaps and three floors: %s" % want)
	check(int(want.get("ramp", 0)) >= 4 and int(want.get("platform", 0)) >= 1, "ramps and the scrap ledge: %s" % want)
	for i in boxes.size():
		var n := level.get_node_or_null("Boxes/" + str(boxes[i]["name"]))
		check(
			n != null and n.get_index() == i and n.get_meta("kind") == boxes[i]["kind"],
			"box %s order/kind" % boxes[i]["name"]
		)
	level.free()


func test_box_sizes_rotations_colours() -> void:
	var level: Node3D = (load(SCENE_PATH) as PackedScene).instantiate()
	for b in _boxes(_toml()):
		var n := _box_node(level, b["name"])
		if n == null:
			fail("missing box " + str(b["name"]))
			continue
		var want := LevelToml.box_transform(b)
		check(n.transform.origin.distance_to(want.origin) < EPS, "%s centre" % n.name)
		for axis in 3:
			check(
				n.transform.basis[axis].distance_to(want.basis[axis]) < 1e-5,
				"%s rotation (Y-X-Z) axis %d" % [n.name, axis]
			)
		var size := LevelToml.vec3(b["size"])
		var shape := (n.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
		var mi := n.get_node("Mesh") as MeshInstance3D
		check(shape != null and shape.size.distance_to(size) < EPS, "%s shape size" % n.name)
		check((mi.mesh as BoxMesh).size.distance_to(size) < EPS, "%s mesh size" % n.name)
		var mat := mi.get_surface_override_material(0) as StandardMaterial3D
		var c := LevelToml.color(b["color"])
		if mat.albedo_texture != null:
			# Step 75: textured boxes keep the TOML hue as a tint (brightest channel 1, halfway to white).
			var s := c.linear_to_srgb()
			var m := maxf(maxf(s.r, s.g), maxf(s.b, 1e-4))
			var t := Vector3(0.5 + 0.5 * s.r / m, 0.5 + 0.5 * s.g / m, 0.5 + 0.5 * s.b / m)
			if b["kind"] == "ground":
				t *= 0.72  # Step 127 GROUND_TINT
			var a := mat.albedo_color
			check(Vector3(a.r, a.g, a.b).distance_to(t) < 2e-3, "%s tint (TOML hue)" % n.name)
			check(mat.normal_enabled and mat.normal_texture != null, "%s normal map" % n.name)
			check(mat.uv1_triplanar and mat.uv1_world_triplanar, "%s world triplanar" % n.name)
		else:
			var lin := mat.albedo_color.srgb_to_linear()
			check(Vector3(lin.r - c.r, lin.g - c.g, lin.b - c.b).length() < 1e-3, "%s colour (linear TOML)" % n.name)
	level.free()


func test_environment_palette_fog_sun() -> void:
	var d := _toml()
	var level: Node3D = (load(SCENE_PATH) as PackedScene).instantiate()
	var env := (level.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := LevelToml.color(d["environment"]["sky_color"])
	var amb := LevelToml.color(d["environment"]["ambient_color"])
	# Step 124: a level with `sky = true` draws a procedural sky whose horizon is sky_color.
	var has_sky: bool = d["environment"].get("sky", false)
	check(env.background_mode == (Environment.BG_SKY if has_sky else Environment.BG_COLOR), "background mode")
	if has_sky:
		var sm := env.sky.sky_material as ProceduralSkyMaterial
		var hz := sm.sky_horizon_color
		check(hz.is_equal_approx(sky) or _close(hz.srgb_to_linear(), sky), "sky horizon = sky_color")
	check(
		(
			env.background_color.srgb_to_linear().is_equal_approx(sky)
			or _close(env.background_color.srgb_to_linear(), sky)
		),
		"sky colour"
	)
	check(_close(env.ambient_light_color.srgb_to_linear(), amb), "ambient colour")
	check(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_EXPONENTIAL, "exponential fog")
	check_near(env.fog_density, float(d["environment"]["fog_density"]), 1e-6, "fog density")
	check(_close(env.fog_light_color.srgb_to_linear(), sky), "fog toward sky colour")
	var sun := level.get_node("Sun") as DirectionalLight3D
	var to_light := LevelToml.vec3(d["sun"]["to_light"]).normalized()
	check(
		sun.transform.basis.z.normalized().distance_to(to_light) < 1e-4, "sun +Z = to_light (light travels -to_light)"
	)
	check(_close(sun.light_color.srgb_to_linear(), LevelToml.color(d["sun"]["color"])), "sun colour")
	level.free()


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 1e-3 and absf(a.g - b.g) < 1e-3 and absf(a.b - b.b) < 1e-3


func test_player_start_and_eye() -> void:
	var level := _spawn()
	var start := level.get_node("PlayerStart") as Marker3D
	check(start.global_position.distance_to(Vector3(0, 0, 12.5)) < EPS, "start feet at (0, 0, 12.5)")
	check((-start.global_basis.z).distance_to(Vector3(0, 0, -1)) < EPS, "facing north (-Z)")
	var eye := start.get_node("Eye") as Marker3D
	check_near(eye.global_position.y, 1.5, EPS, "eye height")
	var hit := _ray(level, start.global_position + Vector3.UP, start.global_position + Vector3.DOWN)
	check(not hit.is_empty() and (hit["collider"] as Node).name == "ground", "feet on the ground")
	if not hit.is_empty():
		check_near((hit["position"] as Vector3).y, 0.0, 0.01, "ground top at y 0")
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, eye.global_position)
	check(level.get_world_3d().direct_space_state.intersect_shape(q).is_empty(), "eye clear of every box (0.5 m)")
	level.free()


func test_ramp_tops_meet_ledge() -> void:
	var level := _spawn()
	var ledge := _box_node(level, "scrap_ledge")
	var lsize := ((ledge.get_node("Shape") as CollisionShape3D).shape as BoxShape3D).size
	var ledge_top := ledge.position.y + lsize.y * 0.5
	var ledge_south := ledge.position.z + lsize.z * 0.5
	check_near(ledge_top, 1.5, EPS, "ledge 1.5 m up")
	for rname in ["ramp_west", "ramp_east"]:
		var r := _box_node(level, rname)
		var s := ((r.get_node("Shape") as CollisionShape3D).shape as BoxShape3D).size
		var high := r.transform * Vector3(0, s.y * 0.5, -s.z * 0.5)
		var low := r.transform * Vector3(0, s.y * 0.5, s.z * 0.5)
		check_near(high.y, ledge_top, 0.01, rname + " top meets ledge height")
		check_near(high.z, ledge_south, 0.01, rname + " top meets ledge south edge")
		check_near(low.y, 0.0, 0.01, rname + " foot on the floor")
		# Walk the ramp centreline with down-rays: the surface rises monotonically to the ledge.
		var prev := -1.0
		for i in 9:
			var z := lerpf(-5.2, -8.8, i / 8.0)
			var hit := _ray(level, Vector3(r.position.x, 5, z), Vector3(r.position.x, -1, z))
			check(not hit.is_empty() and (hit["collider"] as Node).name == rname, "%s surface at z %.2f" % [rname, z])
			if not hit.is_empty():
				var y: float = (hit["position"] as Vector3).y
				check(y > prev, "%s rises at z %.2f" % [rname, z])
				prev = y
		var past := _ray(level, Vector3(r.position.x, 5, -9.3), Vector3(r.position.x, -1, -9.3))
		check(
			(
				not past.is_empty()
				and (past["collider"] as Node).name == "scrap_ledge"
				and absf((past["position"] as Vector3).y - 1.5) < 0.01
			),
			rname + " continues onto the ledge"
		)
	level.free()


func test_valley_surfaces_face_up() -> void:
	var level := _spawn()
	var hits := 0
	var per_kind: Dictionary = {}
	var walkable := cos(deg_to_rad(45.0))
	# Centre lane, the scrap climb (inset from the ledge faces), the bowl, and heap tops.
	var samples: Array[Vector3] = []
	for z in [20, 16, 12, 8, 4, 0, -4, -8, -12, -16]:
		samples.append(Vector3(0, 12, z))
	for z in [-6, -7, -8, -10, -11, -12, -13, -16, -17]:
		samples.append(Vector3(-4.5, 8, z))
	for z in range(-24, -46, -2):
		samples.append(Vector3(3, 6, z))
	samples.append(Vector3(0, 8, -55))
	samples.append(Vector3(-13, 12, 16))
	samples.append(Vector3(13, 12, 10))
	for p in samples:
		var hit := _ray(level, p, p + Vector3(0, -20, 0))
		if hit.is_empty():
			fail("no hit at %s" % p)
			continue
		var n: Vector3 = hit["normal"]
		var body := hit["collider"] as Node3D
		if n.y < walkable or n.dot(body.global_basis.y.normalized()) < 0.999:
			fail("%s: hit %s normal %s is not its top face" % [p, body.name, n])
			continue
		hits += 1
		var k: String = body.get_meta("kind")
		per_kind[k] = int(per_kind.get(k, 0)) + 1
	check(hits == samples.size(), "up-facing hits %d/%d %s" % [hits, samples.size(), per_kind])
	check(
		per_kind.has("ground") and per_kind.has("ramp") and per_kind.has("platform") and per_kind.has("heap"),
		"floor, ramps, ledge, heaps: %s" % per_kind
	)
	level.free()


func test_walls_and_open_sky() -> void:
	var level := _spawn()
	check(_ray(level, Vector3(0, 10, 0), Vector3(0, 100, 0)).is_empty(), "open sky above the valley")
	var gap := _ray(level, Vector3(0, 1.5, 12.5), Vector3(0, 1.5, 30))
	check(gap.is_empty() or gap["collider"] is FlagGate, "the entry lane south stays open")
	var side := _ray(level, Vector3(0, 1.5, 16), Vector3(20, 1.5, 16))
	var side_name := "" if side.is_empty() else String((side["collider"] as Node).name)
	check(side_name.begins_with("heap_"), "a trash wall closes the east (%s)" % side_name)
	var cap := _ray(level, Vector3(0, 1.5, 20), Vector3(0, 1.5, 40))
	check(not cap.is_empty() and (cap["collider"] as Node).name == "south_cap", "the south lip is closed")
	level.free()


func test_enemy_spawns_from_toml() -> void:
	var d := _toml()
	var level: Node3D = (load(SCENE_PATH) as PackedScene).instantiate()
	var spawns := level.get_node("EnemySpawns").get_children()
	var enemies: Array = d.get("enemy", [])
	check(spawns.size() == enemies.size() and enemies.size() == 4, "4 enemy spawns (2 dummies, Gnawer, Heap)")
	for i in mini(spawns.size(), enemies.size()):
		var m := spawns[i] as Marker3D
		check(m.get_meta("enemy") == enemies[i]["enemy"], "spawn %d id" % i)
		check(m.position.distance_to(LevelToml.vec3(enemies[i]["position"])) < EPS, "spawn %d position" % i)
	level.free()
