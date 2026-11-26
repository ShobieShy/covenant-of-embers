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
	_blossoms(slice)
	_door_frame(slice)
	_people(slice)
	_stand_bob_at_the_door(slice)
	_lanterns(slice)
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
	cam.global_position = Vector3(-6.4, 3.4, 22.0)
	cam.look_at(Vector3(-6.4, 2.4, 9.6))
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
	root.transparent_bg = true
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.sky = null
	for hide_name in ["Terrain", "Boxes"]:
		var hide := slice.get_node_or_null(hide_name) as Node3D
		if hide:
			hide.visible = false
	var dome := slice.get_node_or_null("Props/dome") as Node3D
	if dome:
		dome.visible = false
	_false_color(slice)
	await _frame()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 280.0
	cam.global_position = Vector3(20.0, 220.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _frame()
	await _frame()
	_save(out + "/topdown.png")
	quit(0)


func _blossoms(slice: Node3D) -> void:
	var oak := slice.get_node_or_null("Props/east_oak") as Node3D
	if oak == null:
		return
	var packed := load("res://assets/original/ember_art/town/blossom.glb") as PackedScene
	if packed == null:
		return
	var spawned := 0
	for n in oak.find_children("Flowers*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visible = false
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var step := maxi(1, verts.size() / 140)
		var i := 0
		while i < verts.size() and spawned < 160:
			var blossom := packed.instantiate() as Node3D
			oak.add_child(blossom)
			blossom.global_position = mi.global_transform * verts[i]
			blossom.scale = Vector3(0.55, 0.55, 0.55)
			spawned += 1
			i += step


func _door_frame(slice: Node3D) -> void:
	var door := _door(slice)
	if door == null:
		return
	var packed := load("res://assets/original/ember_art/town/door_frame.glb") as PackedScene
	if packed == null:
		return
	var frame := packed.instantiate() as Node3D
	slice.add_child(frame)
	frame.global_transform = door.global_transform
	_warm(slice, door.global_position + Vector3(0, 1.8, 0), 5.5, 1.6)


func _false_color(slice: Node3D) -> void:
	for mi in slice.find_children("*", "MeshInstance3D", true, false):
		var key := str(mi.get_path()).to_lower()
		var col := Color(0.55, 0.55, 0.55)
		if "wall" in key or "tower" in key:
			col = Color(0.15, 0.9, 1.0)
		elif "gate" in key:
			col = Color(1.0, 0.85, 0.15)
		elif "fountain" in key:
			col = Color(1.0, 0.45, 0.1)
		elif "stall" in key:
			col = Color(0.95, 0.2, 0.25)
		elif "plaza" in key or "path" in key:
			col = Color(0.95, 0.92, 0.45)
		elif "oak" in key or "blossom" in key or "door_frame" in key:
			col = Color(0.9, 0.25, 0.95)
		elif "crystal" in key:
			col = Color(0.6, 0.25, 1.0)
		elif "association" in key:
			col = Color(0.35, 0.5, 1.0)
		elif "flagon" in key:
			col = Color(0.55, 0.28, 0.12)
		elif "garden" in key or "hedge" in key or "tree" in key or "bed" in key:
			col = Color(0.2, 0.75, 0.3)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		mi.material_override = m


func _lanterns(slice: Node3D) -> void:
	var props := slice.get_node_or_null("Props")
	if props == null:
		return
	for n in props.get_children():
		var who := n as Node3D
		if who == null:
			continue
		var label := String(who.name)
		if not label.begins_with("lamp") and not label.begins_with("crystal") and label != "east_oak":
			continue
		if label.begins_with("crystal"):
			_warm(slice, who.global_position + Vector3(0, 3.2, 0), 8.0, 0.8, Color(0.65, 0.4, 1.0))
			continue
		if label == "east_oak":
			var door := _door(slice)
			if door == null:
				continue
			_warm(slice, door.global_position + Vector3(0, 1.2, 0), 6.0, 1.4)
			continue
		_warm(slice, who.global_position + Vector3(0, 2.4, 0), 9.0, 0.9)


func _warm(slice: Node3D, at: Vector3, radius: float, energy: float, color := Color(1.0, 0.72, 0.42)) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	slice.add_child(light)
	light.global_position = at


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
		for lab in npc.find_children("*", "Label3D", true, false):
			(lab as Node3D).visible = false


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
