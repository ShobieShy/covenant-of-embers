extends SceneTree
## 0.1.4 release shots: map overviews with the Ember Art dressing, the Landfill junk mountain,
## the Breach crater rim, the batch 06 chests / waystones, and the world map paintings.
## godot --display-driver wayland --path . -s tools/release_shots.gd -- <out_dir>

const VIEWS := [
	["overview_town_square", "town_square", Vector3(0, 120, 140), Vector3(0, 0, 0)],
	["overview_old_oak", "old_oak", Vector3(0, 70, 90), Vector3(0, 0, -5)],
	["overview_midden", "midden", Vector3(0, 260, 420), Vector3(0, 0, 150)],
	["overview_breach", "breach", Vector3(0, 160, 300), Vector3(0, 0, 80)],
	["landfill_junk_mountain", "midden", Vector3(30, 12, 150), Vector3(0, 20, 300)],
	["landfill_dump_camp", "midden", Vector3(18, 6, 120), Vector3(0, 1, 92)],
	["breach_crater_rim", "breach", Vector3(0, 30, 200), Vector3(0, 0, 125)],
	["association_spire", "mage_association", Vector3(0, 8, 40), Vector3(0, 20, -15)],
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	for v: Array in VIEWS:
		var lvl: Node3D = (load("res://scenes/levels/%s.tscn" % v[1]) as PackedScene).instantiate()
		root.add_child(lvl)
		EmberArt.dress(lvl, v[1])
		if String(v[0]).begins_with("overview"):
			_thin_fog(lvl)  # shots only: the cameras sit 150-400 m out, gameplay fog hides the map
		var cam := Camera3D.new()
		cam.far = 2000.0
		lvl.add_child(cam)
		cam.look_at_from_position(v[2], v[3])
		cam.current = true
		await _snap(out, v[0], 30)
		lvl.queue_free()
		await process_frame
	await _props(out)
	await _map(out)
	quit()


func _thin_fog(n: Node) -> void:
	for we in n.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = (we as WorldEnvironment).environment
		if e:
			e = e.duplicate()
			e.fog_density = minf(e.fog_density, 0.0008)
			e.fog_aerial_perspective = 0.0
			e.volumetric_fog_enabled = false
			(we as WorldEnvironment).environment = e
			print("[shots] thinned fog on %s" % we.get_path())


func _snap(out: String, name: String, frames: int) -> void:
	for _f in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _props(out: String) -> void:
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.12, 0.16)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	w.add_child(sun)
	sun.rotation_degrees = Vector3(-50, 30, 0)
	var x := -4.5
	for t in ["normal", "hidden", "vault"]:
		var c := VaultChest.new()
		c.set_meta(&"tier", t)
		w.add_child(c)
		c.position = Vector3(x, 0, 0)
		if t == "vault":
			c.open_chest_quiet()
		x += 1.8
	for p in ["town_square", "landfill", "old_oak", "breach"]:
		var s := Waystone.new(p)
		w.add_child(s)
		s.position = Vector3(x, 0, 0)
		x += 1.8
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.look_at_from_position(Vector3(1, 3, 7.5), Vector3(1, 0.8, 0))
	cam.current = true
	await _snap(out, "chests_and_waystones", 20)
	w.queue_free()
	await process_frame


func _map(out: String) -> void:
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(20, 40)
	cl.add_child(grid)
	for r in WorldMap.REGIONS:
		var box := VBoxContainer.new()
		var pic := TextureRect.new()
		pic.texture = EmberArt.texture("map_" + String(r))
		pic.custom_minimum_size = Vector2(300, 176)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		box.add_child(pic)
		var l := Label.new()
		l.text = String(WorldMap.REGIONS[r]["name"])
		box.add_child(l)
		grid.add_child(box)
	await _snap(out, "world_map_paintings", 10)
	cl.queue_free()
