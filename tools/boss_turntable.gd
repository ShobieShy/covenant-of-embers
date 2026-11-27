extends SceneTree
## Turntable of each boss beside a 1.8 m figure, plus a flat front for the sheet overlay.
##
##   DISPLAY=:1 godot --path . --rendering-driver opengl3 \
##     -s res://tools/boss_turntable.gd -- /tmp/boss-shots

const IDS: Array[String] = [
	"the_filth",
	"breach_warden",
	"goblin_king",
	"blightmaw_matriarch",
	"forgemaw",
	"drowned_choir",
	"storm_warden",
]
const FIGURE := "res://assets/quaternius/bob/Adventurer_male.glb"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("boss_turntable: pass an output directory")
		quit(2)
		return
	_run.call_deferred(args[0])


func _run(out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 960)
	var table := EnemyTable.load_default()
	var only := OS.get_environment("BOSS_ONLY")
	for id in IDS:
		if only != "" and id != only:
			continue
		var d := table.find(id)
		if d == null:
			push_error("missing def " + id)
			continue
		var phases := _phases(id)
		for phase in phases:
			await _shoot(out, d, phase)
	print("[boss_turntable] wrote ", out)
	quit(0)


func _phases(id: String) -> Array[int]:
	var got: Array[int] = []
	var raw := OS.get_environment("BOSS_PHASES")
	if raw == "":
		got.append(1)
		got.append(2)
		if id == "the_filth" or id == "blightmaw_matriarch" or id == "forgemaw":
			got.append(3)
		return got
	for part in raw.split(","):
		if part != "":
			got.append(int(part))
	return got


func _shoot(out: String, d: EnemyDef, phase: int) -> void:
	var stage := _stage()
	var body := _body(d, phase)
	stage.add_child(body)
	await _frames(3)
	var height := _height(body)
	var span := _width(body)
	# Skinned imports sometimes report a huge bind box. The fitted body is the def height.
	if height < 0.2 or height > 18.0:
		height = d.size.y
		span = d.size.x
	await _grab(out, "%s_p%d_front" % [d.id, phase], stage, _ortho(height), true)
	var fig_x := -(span * 0.5 + 1.15)
	var figure := CharacterModel.make_sized(FIGURE, 1.8)
	if figure:
		stage.add_child(figure)
		figure.position = Vector3(fig_x, 0, 0)
	var aim_y := height * 0.46
	var dist := maxf(10.0, height * 3.1)
	var eye := Vector3(dist * 0.7, height * 0.5, -dist)
	await _grab(out, "%s_p%d_turntable" % [d.id, phase], stage, _persp(eye, Vector3(fig_x * 0.35, aim_y, 0)), false)
	await _grab(out, "%s_p%d_scale" % [d.id, phase], stage, _ortho_pair(height, span, fig_x), false)
	stage.free()


func _body(d: EnemyDef, phase: int) -> Node3D:
	var e := Enemy.create(d)
	e.auto_tick = false
	if "phase" in e:
		e.phase = phase
	elif d.id == "storm_warden" and phase >= 2:
		e.health = e.max_health() * 0.4
	return e


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -28, 0)
	key.light_energy = 1.15
	key.shadow_enabled = false
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	stage.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.38, 0.3)
	ground.material_override = mat
	stage.add_child(ground)
	return stage


func _env(magenta: bool) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(1, 0, 1) if magenta else Color(0.55, 0.48, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.6, 0.58)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 0.85
	e.fog_enabled = false
	return e


func _ortho(height: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = height * 1.12
	cam.environment = _env(true)
	var y := height * 0.5
	cam.look_at_from_position(Vector3(0, y, -maxf(4.0, height)), Vector3(0, y, 0))
	return cam


func _ortho_pair(height: float, span: float, figure_x: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aspect := 1280.0 / 960.0
	var half_w := maxf(span * 0.55, absf(figure_x) + 0.85)
	var size_w := (half_w * 2.1) / aspect
	cam.size = maxf(size_w, height * 1.22)
	cam.environment = _env(false)
	var look_x := figure_x * 0.42
	var y := height * 0.48
	cam.look_at_from_position(Vector3(look_x, y, -16.0), Vector3(look_x, y, 0.0))
	return cam


func _persp(eye: Vector3, at: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 22.0
	cam.environment = _env(false)
	cam.look_at_from_position(eye, at)
	return cam


func _grab(out: String, label: String, stage: Node3D, cam: Camera3D, _front: bool) -> void:
	stage.add_child(cam)
	cam.current = true
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, label])
	print("[boss_turntable] ", label)
	cam.queue_free()


func _height(body: Node3D) -> float:
	var box := _aabb(body)
	return box.size.y if box.size.y > 0.0 else 0.0


func _width(body: Node3D) -> float:
	var box := _aabb(body)
	return maxf(box.size.x, box.size.z)


func _aabb(body: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box if not first else AABB()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
