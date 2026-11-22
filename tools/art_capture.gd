extends SceneTree
## 0.11.3 capture harness. Top-down shots use an orthographic camera and a fixed
## exposure, so a pale terrain does not blow out. Creatures and NPCs are shot from
## the front (the face is -Z) with their feet on y = 0. A frame with no visible mesh,
## or a frame whose pixels barely change, is a failure.
##
##   godot --headless --path . -s res://tools/art_capture.gd -- --self-test
##   DISPLAY=:99 godot --display-driver x11 --rendering-driver opengl3 --path . \
##     -s res://tools/art_capture.gd -- /opt/cursor/artifacts/v0.11.3-gate

var out := ""
var failures: PackedStringArray = []
var notes := []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--self-test"):
		quit(_self_test())
		return
	out = args[0] if args.size() > 0 else OS.get_environment("ART_OUT")
	if out == "":
		push_error("art_capture: pass an output directory")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	_run.call_deferred()


func _self_test() -> int:
	var blank := Node3D.new()
	if _has_mesh(blank):
		push_error("empty node looked solid")
		return 1
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	blank.add_child(box)
	if not _has_mesh(blank):
		push_error("a box was not a mesh")
		return 1
	var flat := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.55, 0.62, 0.72))
	if not _washed(flat):
		push_error("a flat frame was accepted")
		return 1
	for x in 16:
		for y in 32:
			flat.set_pixel(x, y, Color(0.05, 0.04, 0.03))
	if _washed(flat):
		push_error("a split frame was called empty")
		return 1
	print("[art_capture] self-test ok")
	return 0


func _run() -> void:
	for id in ["town_square", "midden", "mage_association", "old_oak", "bobs_lab", "breach"]:
		var scene := load(GameFlow.level_scene(id)) as PackedScene
		if scene == null:
			_reject("level_%s" % id, "scene missing")
			continue
		await _shoot_level("level_%s" % id, scene.instantiate() as Node3D)
	var state := LabyrinthState.fresh(42)
	await _shoot_level("level_act1", LabyrinthFloor.build(FloorGen.load_kit(), 1, state))
	await _shoot_level("level_act2", BlightcoilCavern.make(6, state))
	await _shoot_level("level_act3", SlagworksFloor.make(9, state))
	await _shoot_level("level_act4", SunkenFloor.make(14, state))
	await _shoot_level("level_act5", SpireFloor.make(19, state))
	for d in EnemyTable.load_default().defs:
		if d == null:
			continue
		await _shoot_body("creature_%s" % d.id, _creature(d), d.size.y)
	for speaker in CharacterModel.SPEAKERS:
		var model := CharacterModel.make_for_speaker(speaker)
		var body := Node3D.new()
		if model:
			body.add_child(model)
			CharacterModel.plant_feet(model)
		await _shoot_body("npc_%s" % speaker.replace(" ", "_").to_lower(), body, CharacterModel.HEIGHT)
	await _shoot_weapon(
		"weapon_staff_basic",
		"apprentice_fire_staff",
		["basic_handle", "basic_exterior", "basic_interior", "basic_fire_head"]
	)
	await _shoot_weapon(
		"weapon_staff_unique",
		"apprentice_fire_staff",
		[
			"uncommon_dark_handle",
			"mythic_water_exterior",
			"basic_fire_interior",
			"primordial_fire_head",
			"unique_void_charm"
		]
	)
	await _shoot_weapon("weapon_wand_basic", "novice_arcane_wand", ["basic_exterior", "basic_fire_head"])
	await _shoot_weapon("weapon_wand_unique", "swift_wind_wand", ["primordial_fire_head", "unique_void_charm"])
	await _shoot_ui()
	var file := FileAccess.open("%s/notes.json" % out, FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "shots": notes}, "\t"))
	print("[art_capture] %d shots, %d failures" % [notes.size(), failures.size()])
	quit(1 if failures.size() > 0 else 0)


func _creature(d: EnemyDef) -> Node3D:
	var body := Node3D.new()
	var model := EnemyModels.make(d.id, d.size.y)
	if model:
		body.add_child(model)
		CharacterModel.plant_feet(model)
		return body
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = d.size
	box.mesh = mesh
	box.position.y = d.size.y * 0.5
	body.add_child(box)
	return body


func _shoot_level(label: String, node: Node3D) -> void:
	var stage := _stage()
	stage.add_child(node)
	_tame(node)
	await _frames(4)
	if not _has_mesh(node):
		await _grab(label + "_top", stage, node, true)
		_clear(stage)
		return
	var box := _content_aabb(node)
	var centre := box.get_center()
	var span := maxf(box.size.x, box.size.z)
	await _save_cam(label + "_top", stage, node, _ortho(centre, span))
	var eyes: Array[Vector3] = [
		centre + Vector3(0, 1.7, span * 0.28),
		centre + Vector3(span * 0.22, 1.7, span * 0.08),
		centre + Vector3(-span * 0.16, 1.7, -span * 0.18),
	]
	var n := 1
	for eye in eyes:
		await _save_cam("%s_eye_%d" % [label, n], stage, node, _persp(eye, centre + Vector3(0, 1.2, 0)))
		n += 1
	_clear(stage)


func _shoot_body(label: String, body: Node3D, height: float) -> void:
	var stage := _stage()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.18)
	ground.material_override = mat
	stage.add_child(ground)
	stage.add_child(body)
	var pole := MeshInstance3D.new()
	var post := CylinderMesh.new()
	post.height = 1.8
	post.top_radius = 0.035
	post.bottom_radius = 0.035
	pole.mesh = post
	pole.position = Vector3(maxf(0.8, height * 0.55), 0.9, 0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.06)
	pole.material_override = dark
	stage.add_child(pole)
	await _frames(3)
	var dist := maxf(2.6, height * 1.7)
	var aim := Vector3(0, height * 0.42, 0)
	await _save_cam(label + "_front", stage, body, _persp(Vector3(0, height * 0.45, -dist), aim))
	await _save_cam(
		label + "_three_quarter", stage, body, _persp(Vector3(dist * 0.72, height * 0.55, -dist * 0.72), aim)
	)
	_clear(stage)


func _shoot_weapon(label: String, base: String, ids: Array) -> void:
	var stage := _stage()
	var vm := Viewmodel.new()
	stage.add_child(vm)
	var w := WieldableInstance.load_base(base)
	for id: String in ids:
		w.parts.append(load("res://resources/parts/%s.tres" % id) as WieldablePart)
	w.assembled = not ids.is_empty()
	vm.show_wieldable(w)
	for mi in vm.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1
	await _frames(2)
	await _save_cam(label + "_side", stage, vm, _persp(Vector3(1.5, 0.12, 0.05), Vector3(0, 0, 0)))
	await _save_cam(label + "_three_quarter", stage, vm, _persp(Vector3(0.85, 0.32, 0.95), Vector3(0, 0, 0)))
	_clear(stage)


func _shoot_ui() -> void:
	var stage := _stage()
	var hud := Hud.new()
	hud.add_to_group(&"hud")
	root.add_child(hud)
	await _frames(2)
	await _grab("ui_hud", stage, stage, false)
	var menu := EchoMenu.new()
	root.add_child(menu)
	menu.open("map")
	await _frames(3)
	var hidden: bool = not hud.visible
	await _grab("ui_scribe", stage, stage, false)
	if not hidden:
		_reject("ui_scribe", "hud still visible")
	menu.free()
	hud.free()
	_clear(stage)


func _stage() -> Node3D:
	var stage := Node3D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = false
	stage.add_child(sun)
	return stage


func _tame(node: Node) -> void:
	var sun := node.find_child("Sun", true, false) as DirectionalLight3D
	if sun:
		sun.light_energy = minf(sun.light_energy, 0.85)


func _env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.58, 0.68)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.64)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 0.7
	e.fog_enabled = false
	return e


func _ortho(centre: Vector3, span: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(span * 1.06, 4.0)
	cam.environment = _env()
	cam.look_at_from_position(centre + Vector3(0, maxf(30.0, span), 0.001), centre)
	return cam


func _persp(eye: Vector3, at: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.environment = _env()
	cam.look_at_from_position(eye, at)
	return cam


func _save_cam(label: String, stage: Node3D, subject: Node, cam: Camera3D) -> void:
	stage.add_child(cam)
	cam.current = true
	await _frames(2)
	await _grab(label, stage, subject, true)
	cam.queue_free()


func _grab(label: String, _stage: Node3D, subject: Node, require_mesh: bool) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, label])
	var empty := (require_mesh and not _has_mesh(subject)) or _washed(img)
	notes.append({"file": label + ".png", "empty": empty})
	if empty:
		_reject(label, "empty frame")
	else:
		print("[art_capture] ", label)


func _has_mesh(root_n: Node) -> bool:
	for n in root_n.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.visible and mi.mesh != null:
			return true
	return false


func _content_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null or _under(mi, "Terrain"):
			continue
		var a := mi.global_transform * mi.get_aabb()
		if maxf(a.size.x, a.size.z) > 280.0:
			continue
		box = a if first else box.merge(a)
		first = false
	return box if not first else AABB(Vector3(-16, 0, -16), Vector3(32, 4, 32))


func _under(n: Node, kind: String) -> bool:
	var cur := n.get_parent()
	while cur:
		if cur.name == kind:
			return true
		cur = cur.get_parent()
	return false


func _washed(img: Image) -> bool:
	var small := img.duplicate() as Image
	small.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var sum := 0.0
	var sum2 := 0.0
	var n: int = small.get_width() * small.get_height()
	for y in small.get_height():
		for x in small.get_width():
			var c: Color = small.get_pixel(x, y)
			var lum: float = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			sum += lum
			sum2 += lum * lum
	var mean: float = sum / float(n)
	var variance: float = sum2 / float(n) - mean * mean
	return variance < 0.0004


func _reject(label: String, why: String) -> void:
	failures.append("%s: %s" % [label, why])
	print("[art_capture] FAIL ", label, " ", why)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _clear(stage: Node) -> void:
	stage.free()
