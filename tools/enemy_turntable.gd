extends SceneTree
## Turntable of one regular enemy beside a 1.8 m figure.
## godot --path . -s tools/enemy_turntable.gd -- <out_dir>

const IDS := [
	"goblin_grunt", "goblin_archer", "goblin_shaman", "gnawer",
	"heap", "scorchling", "ooze", "earth_training_dummy", "water_training_dummy",
	"spore_husk", "mossbound_treant", "spore_beast",
	"branded_troll", "forge_construct", "drowned_cultist", "harpy", "storm_elemental",
]
const FIGURE := "res://assets/quaternius/bob/Adventurer_male.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/enemy_turntable"
	var only := ""
	if args.size() > 1:
		only = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var table := EnemyTable.load_default()
	for id in IDS:
		if only != "" and id != only:
			continue
		var d := table.find(id)
		if d == null:
			push_error("missing " + id)
			continue
		await _shoot(out, d)
	print("[turntable] wrote ", out)
	quit()


func _shoot(out: String, d: EnemyDef) -> void:
	var stage := _stage()
	var enemy := Enemy.create(d)
	stage.add_child(enemy)
	var figure := CharacterModel.make_sized(FIGURE, 1.8)
	stage.add_child(figure)
	for _i in 8:
		await process_frame
	var box := _aabb(enemy)
	var tall: float = maxf(box.size.y, 1.8)
	var wide: float = box.size.x
	var gap: float = maxf(0.55, tall * 0.22)
	var fig_x: float = -(wide * 0.5 + gap + 0.35)
	var enemy_x: float = box.get_center().x
	# Shift both so the pair is centred. enemy is already at the origin.
	var pair_mid: float = (fig_x + enemy_x) * 0.5
	figure.position = Vector3(fig_x - pair_mid, 0, 0)
	enemy.position = Vector3(-pair_mid, 0, 0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18, 18)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.45, 0.36, 0.24)
	gmat.roughness = 1.0
	ground.material_override = gmat
	stage.add_child(ground)
	var centre := Vector3(0, tall * 0.42, 0)
	var need_h: float = (wide + 1.6 + gap) * (720.0 / 1280.0)
	var cam_size: float = maxf(tall * 1.35, need_h)
	var views := [
		["front", 0.0],
		["right", 90.0],
		["back", 180.0],
		["left", 270.0],
	]
	for view in views:
		enemy.rotation.y = deg_to_rad(float(view[1]))
		await _save(out, "%s_%s" % [d.id, view[0]], stage, centre, cam_size, 0.0)
	enemy.rotation.y = 0.0
	figure.visible = false
	await _save(out, "%s_solo" % d.id, stage, Vector3(-pair_mid, tall * 0.45, 0) + enemy.position * 0.0, maxf(box.size.y, box.size.x) * 1.2, -pair_mid)
	stage.free()


func _save(out: String, label: String, stage: Node3D, at: Vector3, cam_size: float, look_x: float) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.environment = _env()
	var aim := Vector3(look_x, at.y, 0)
	cam.look_at_from_position(aim + Vector3(0, 0, -12), aim)
	stage.add_child(cam)
	cam.current = true
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, label])
	print("[turntable] ", label, " size ", cam_size)
	cam.free()


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var we := WorldEnvironment.new()
	we.environment = _env()
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 140, 0)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	stage.add_child(fill)
	return stage


func _env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.78, 0.67, 0.48)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.64, 0.52)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.05
	return e


func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first:
		return AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, 1.6, 0.8))
	return box
