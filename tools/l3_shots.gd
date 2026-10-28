extends SceneTree
## L3 art review: the goblins (hand props up close) and Labyrinth rooms, one PNG each.
## godot --display-driver wayland --path . -s tools/l3_shots.gd -- <out_dir>

const GOBLINS := ["goblin_grunt", "goblin_archer", "goblin_shaman", "goblin_king"]

var out := "user://shots/l3"
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _env(parent: Node, bright: float) -> void:
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.08, 0.07, 0.06)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.7, 0.62, 0.5)
	we.environment.ambient_light_energy = bright
	we.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	parent.add_child(sun)


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	cam.look_at_from_position(from, at)
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("[l3_shots] ", p)


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	# Goblins on a plain stage.
	var st := Node3D.new()
	root.add_child(st)
	_env(st, 0.9)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	st.add_child(fl)
	cam = Camera3D.new()
	st.add_child(cam)
	cam.current = true
	var t := EnemyTable.load_default()
	var line: Array[Enemy] = []
	for i in GOBLINS.size():
		var e := Enemy.create(
			t.find(GOBLINS[i]), Transform3D(Basis.IDENTITY, Vector3(i * 2.6 - 4.0, 0, 0))
		)
		e.auto_tick = false
		e.rotation.y = PI  # face the camera (+z)
		st.add_child(e)
		line.append(e)
	for _f in 30:
		await process_frame
	await _shot("goblins_lineup", Vector3(0, 2.0, 8.5), Vector3(0, 1.1, 0))
	for e in line:
		for o in line:
			o.visible = o == e
		var h := maxf(e.def.size.y, 1.2)
		h *= 1.5 if e.def.id == "goblin_grunt" else 1.0
		var p := e.position
		await _shot(
			"hand_%s_front" % e.def.id,
			p + Vector3(0.4, h * 0.6, h * 1.4),
			p + Vector3(0, h * 0.45, 0)
		)
		await _shot(
			"hand_%s_side" % e.def.id,
			p + Vector3(h * 1.4, h * 0.55, 0.2),
			p + Vector3(0, h * 0.45, 0)
		)
	st.queue_free()
	await process_frame
	# Labyrinth floor 1 (dressed) and floor 5 (throne hall + the King).
	var kit := FloorGen.load_kit()
	var ls := LabyrinthState.fresh(42)
	for n in [1, 5]:
		var f := LabyrinthFloor.build(kit, n, ls)
		root.add_child(f)
		_env(f, 0.35)
		cam = Camera3D.new()
		f.add_child(cam)
		cam.current = true
		var spawned := Enemy.spawn_at_markers(f, f, t)
		for e in spawned:
			e.auto_tick = false
		for _f in 30:
			await process_frame
		for r in f.rooms:
			var kind := String(r.get_meta(&"kind"))
			var c: Vector3 = r.global_position
			var sz := _size(f, kit, r)
			if kind in ["rest", "exit", "elite", "start"] or (kind == "normal" and r == f.rooms[1]):
				await _shot(
					"floor%d_%s_%s" % [n, kind, r.name],
					c + Vector3(sz.x / 2 - 1.2, 2.6, sz.y / 2 - 1.2),
					c + Vector3(-sz.x / 6, 0.4, -sz.y / 6)
				)
			if kind == "boss":
				await _shot("floor5_throne_hall", c + Vector3(0, 6, 15), c + Vector3(0, 1.5, -8))
				await _shot("floor5_king_close", c + Vector3(2, 3, -1), c + Vector3(0, 1.4, -8))
				await _shot("floor5_throne_hall_far_lod", c + Vector3(0, 30, 70), c)
		var sd := f.get_node_or_null("StairsDown") as Node3D
		if sd:
			var p := sd.global_position
			await _shot("floor%d_stair_down" % n, p + Vector3(1.5, 5.5, 5.5), p)
		f.queue_free()
		await process_frame
	quit()


## The room's footprint, as LabyrinthFloor._build_rooms sizes it (kit size, rotated).
func _size(f: LabyrinthFloor, kit: Dictionary, r: Node3D) -> Vector2:
	var i := f.rooms.find(r)
	if not f.layout.has("rooms"):
		return Vector2(12, 12)
	var rs: Array = f.layout["rooms"]
	if i < 0 or i >= rs.size():
		return Vector2(12, 12)
	var kr: Dictionary = f._kit_room(kit, String(rs[i]["room"]))
	var sz := Vector2(float(kr["size"][0]), float(kr["size"][1]))
	return Vector2(sz.y, sz.x) if int(rs[i]["rot"]) % 2 == 1 else sz
