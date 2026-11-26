extends SceneTree
## 0.12.0 golden-slice frames. Real meshes only. Not a score.
##
##   DISPLAY=:1 godot --display-driver x11 --rendering-driver opengl3 --path . \
##     -s res://tools/town_slice_shot.gd -- /opt/cursor/artifacts/v0.12.0-town


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/town-slice"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	_go.call_deferred(out)


func _go(out: String) -> void:
	var slice: Node3D = (load("res://scenes/levels/town_golden_slice.tscn") as PackedScene).instantiate()
	root.add_child(slice)
	for _i in 16:
		await process_frame
	OldOakLandmark.prepare(slice)
	_people(slice)
	_stand_bob_at_the_door(slice)
	for _i in 8:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.current = true
	root.add_child(cam)
	var env := (slice.get_node("WorldEnvironment") as WorldEnvironment).environment
	cam.environment = env
	# South of the arch, looking north through the gate at the fountain.
	cam.global_position = Vector3(-6.4, 4.4, 108.0)
	cam.look_at(Vector3(-6.4, 3.2, 9.6))
	await _frame()
	_save(out + "/gate.png")
	# Plaza, eye height, fountain in front, stalls to either side.
	cam.global_position = Vector3(-6.4, 3.6, 28.0)
	cam.look_at(Vector3(-6.4, 2.6, 9.6))
	await _frame()
	_save(out + "/square.png")
	var door := _door(slice)
	var oak := slice.get_node("Props/east_oak") as Node3D
	var aim := door.global_position if door else oak.global_position + Vector3(0, 8, 0)
	var out_dir := oak.global_transform.basis * Vector3(0, 0, -1)
	cam.global_position = aim + out_dir * 16.0 + Vector3(0, 2.2, 0)
	cam.look_at(aim + Vector3(0, 1.5, 0))
	await _frame()
	_save(out + "/oak.png")
	await _face(cam, slice, "guard_gate", out + "/npc_guard.png")
	await _face(cam, slice, "merchant", out + "/npc_market.png")
	await _bob(cam, slice, out + "/npc_bob.png")
	root.size = Vector2i(1024, 1024)
	await _frame()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 280.0
	cam.global_position = Vector3(20.0, 220.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _frame()
	await _frame()
	_save(out + "/topdown.png")
	quit(0)


func _people(slice: Node3D) -> void:
	var marks := slice.get_node_or_null("NPCs")
	if marks == null:
		return
	var terrain := slice.get_node_or_null("Terrain") as TerrainZone
	for m in marks.get_children():
		var who := m as Node3D
		if who == null:
			continue
		var speaker := String(who.get_meta(&"speaker", ""))
		var npc := Npc.new(speaker)
		npc.name = "Npc_" + who.name
		slice.add_child(npc)
		var at := who.global_position
		if terrain:
			at.y = terrain.height_at(at.x, at.z)
		npc.global_position = at
		npc.rotation_degrees.y = float(who.get_meta(&"yaw_deg", 0.0))


func _stand_bob_at_the_door(slice: Node3D) -> void:
	var door := _door(slice)
	var bob := slice.get_node_or_null("Npc_bob") as Node3D
	var oak := slice.get_node_or_null("Props/east_oak") as Node3D
	if door == null or bob == null or oak == null:
		return
	var fwd := oak.global_transform.basis * Vector3(0, 0, -1)
	var terrain := slice.get_node_or_null("Terrain") as TerrainZone
	var at := door.global_position + fwd * 6.0
	at.y = terrain.height_at(at.x, at.z) if terrain else door.global_position.y
	bob.global_position = at
	bob.look_at(Vector3(door.global_position.x, bob.global_position.y, door.global_position.z), Vector3.UP)


func _bob(cam: Camera3D, slice: Node3D, path: String) -> void:
	var npc := slice.get_node_or_null("Npc_bob") as Node3D
	if npc == null:
		push_error("missing bob")
		return
	for n in npc.find_children("*", "Label3D", true, false):
		(n as Node3D).visible = false
	var oak := slice.get_node("Props/east_oak") as Node3D
	var fwd := oak.global_transform.basis * Vector3(0, 0, -1)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 42.0
	cam.global_position = npc.global_position + fwd * 8.0 + Vector3(0, 1.5, 0)
	cam.look_at(npc.global_position + Vector3(0, 1.3, 0))
	await _frame()
	_save(path)


func _face(cam: Camera3D, slice: Node3D, marker: String, path: String) -> void:
	var npc := slice.get_node_or_null("Npc_" + marker) as Node3D
	if npc == null:
		push_error("missing " + marker)
		return
	for n in npc.find_children("*", "Label3D", true, false):
		(n as Node3D).visible = false
	var ahead := npc.global_transform.basis * Vector3(0, 0, -1)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 38.0
	cam.global_position = npc.global_position + ahead * 3.2 + Vector3(0, 1.45, 0)
	cam.look_at(npc.global_position + Vector3(0, 1.35, 0))
	await _frame()
	_save(path)


func _door(slice: Node3D) -> Node3D:
	var oak := slice.get_node_or_null("Props/east_oak") as Node3D
	if oak == null:
		return null
	return oak.find_child("Door", true, false) as Node3D


func _frame() -> void:
	await process_frame
	await process_frame


func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
