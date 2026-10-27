extends TestCase
## OW8: minimap (rotation, north lock, rim clamp) and co-op partner markers.


func test_minimap_orientation() -> void:
	var m := Minimap.new()
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.size = Vector2(Minimap.SIZE, Minimap.SIZE)
	var mid := m.size * 0.5
	m.center = Vector2(10, 20)
	m.lock_north = true
	check(m.world_to_mini(Vector3(10, 0, 20)).distance_to(mid) < 0.01, "player at the centre")
	var n := m.world_to_mini(Vector3(10, 0, 0))  # 20 m north (-z)
	check(n.y < mid.y and absf(n.x - mid.x) < 0.01, "north is up when locked")
	m.lock_north = false
	m.yaw = PI / 2.0  # camera looks west (-x)
	var w := m.world_to_mini(Vector3(-10, 0, 20))
	check(w.y < mid.y and absf(w.x - mid.x) < 0.01, "camera forward is up when rotating")
	var far := m.clamp_rim(m.world_to_mini(Vector3(5000, 0, 20)))
	check(far.distance_to(mid) <= mid.x, "far markers clamp to the rim")
	m.free()


func test_settings_option() -> void:
	var s := Settings.new()
	check(not s.minimap_north, "rotates by default")
	check("minimap_north" in s._options(), "saved with the other options")
	var p := "user://test_minimap_settings.cfg"
	var c := ConfigFile.new()
	c.set_value("options", "hip_fov", 80.0)  # an old settings file without the key
	c.save(p)
	check(not Settings.load_from(p).minimap_north, "old settings files load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_partner_rows_and_draw() -> void:
	var r := RemotePlayer.new()
	r.display_name = "Pal"
	r.color = Color.RED
	runner_tree.root.add_child(r)
	r.global_position = Vector3(30, 0, 40)
	var rows: Array = OpenWorld.map_rows(runner_tree)
	var pal: Array = rows.filter(func(x: Array) -> bool: return x[2] == "Pal")
	check(
		pal.size() == 1 and not pal[0][4] and pal[0][3] == Color.RED,
		"partner row with name and colour"
	)
	var m := Minimap.new()
	m.fog = WorldFog.new()
	m.pins = MapPins.new()
	m.pins.add(0, 0)
	m.players = func() -> Array: return rows
	runner_tree.root.add_child(m)
	await runner_tree.process_frame  # one draw pass without errors
	await runner_tree.process_frame
	check(m.tex != null, "uses the world map texture")
	m.free()
	r.free()
