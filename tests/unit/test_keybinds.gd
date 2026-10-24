extends TestCase
## Step 32 done check: settings save/load round-trip, a rebind applies to the InputMap,
## options reach the player, toggle modes latch.

const PATH := "user://test_keybinds.cfg"
const DT := 1.0 / 60.0


func _player() -> Player:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 400, 2100), 0.0)
	return p


func test_round_trip_and_rebind() -> void:
	var before := InputMap.action_get_events(&"jump").duplicate()
	var s := Settings.new()
	var k := InputEventKey.new()
	k.physical_keycode = KEY_J
	check(s.rebind(&"jump", k), "rebind")
	var evs := InputMap.action_get_events(&"jump")
	var kevs := evs.filter(func(e): return not Gamepad.is_pad(e))
	check(kevs.size() == 1 and (kevs[0] as InputEventKey).physical_keycode == KEY_J, "InputMap updated")
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_XBUTTON1
	check(s.rebind(&"quickslot_next_wieldable", m), "mouse button rebind")
	check(not s.rebind(&"no_such_action", k), "unknown action refused")
	s.invert_y = true
	s.hip_fov = 90.0
	s.focus_toggle = true
	s.head_bob = 0.1
	s.aim_sensitivity = Settings.RAW_LOOK
	check(s.save(PATH) == OK, "saved")
	var l := Settings.load_from(PATH)
	check(
		l.invert_y and l.focus_toggle and is_equal_approx(l.hip_fov, 90.0) and is_equal_approx(l.head_bob, 0.1),
		"options round-trip"
	)
	check(is_equal_approx(l.aim_sensitivity, Settings.RAW_LOOK), "sensitivity")
	var kb: Array = l.bindings.get(&"jump", []).filter(func(d): return d.has("key"))
	check(kb == [{"key": KEY_J}], "binding round-trip %s" % [l.bindings])
	# restore project defaults then re-apply the loaded file
	InputMap.action_erase_events(&"jump")
	for e in before:
		InputMap.action_add_event(&"jump", e)
	l.apply_input_map()
	check((InputMap.action_get_events(&"jump")[0] as InputEventKey).physical_keycode == KEY_J, "apply_input_map")
	check(Gamepad.has_pad_event(&"jump"), "pad event survives a key rebind")
	InputMap.action_erase_events(&"jump")
	for e in before:
		InputMap.action_add_event(&"jump", e)
	InputMap.load_from_project_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	check(Settings.load_from("user://missing.cfg").hip_fov == 75.0, "missing file = defaults")


func test_apply_to_player_and_toggles() -> void:
	var p := _player()
	var s := Settings.new()
	s.invert_y = true
	s.hip_fov = 95.0
	s.focus_toggle = true
	s.crouch_toggle = true
	s.apply_to(p)
	check(is_equal_approx(p.camera.fov, 95.0) and is_equal_approx(p.focus.hip_fov, 95.0), "hip fov")
	var pitch0 := p.pitch
	p.add_look(0, 10)
	check(p.pitch > pitch0, "invert-Y: mouse down looks up")
	var inp := PlayerInput.hold([], ["crouch"])
	p.tick(inp, DT)
	var later := PlayerInput.hold()
	p.tick(later, DT)
	check(later.down(&"crouch"), "crouch toggle stays held")
	var again := PlayerInput.hold([], ["crouch"])
	p.tick(again, DT)
	check(not again.down(&"crouch"), "second press releases")
	p.queue_free()


func test_settings_ui_capture() -> void:
	var ui := SettingsUi.new()
	ui.path = PATH
	runner_tree.root.add_child(ui)
	var s := Settings.new()
	ui.setup(s)
	ui.open()
	ui.listen(&"dash")
	check(ui.action_buttons[&"dash"].text == "Press a key...", "listening")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_Q
	check(ui.capture(k), "captured")
	check(ui.action_buttons[&"dash"].text == "Q", "label '%s'" % ui.action_buttons[&"dash"].text)
	check(Settings.load_from(PATH).bindings.has(&"dash"), "saved on change")
	InputMap.load_from_project_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	ui.queue_free()


# --- step 77: controller support ---


func test_every_action_has_joypad_event() -> void:
	InputMap.load_from_project_settings()
	Gamepad.install()
	for a in Gamepad.actions():
		check(Gamepad.has_pad_event(a), "%s has a joypad event" % a)
		var keys := InputMap.action_get_events(a).filter(func(e): return not Gamepad.is_pad(e))
		check(not keys.is_empty(), "%s keeps its keyboard/mouse event" % a)
	Gamepad.install()
	var n := InputMap.action_get_events(&"jump").filter(func(e): return Gamepad.is_pad(e)).size()
	check(n == 1, "install is idempotent")
	var j := InputEventJoypadButton.new()
	j.button_index = JOY_BUTTON_A
	j.pressed = true
	check(InputMap.event_is_action(j, &"jump"), "pad A = jump")
	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_LEFT_Y
	m.axis_value = -1.0
	check(m.is_action_pressed(&"forward") and not m.is_action_pressed(&"back"), "stick up = forward")
	InputMap.load_from_project_settings()


func test_controller_rebind_round_trip() -> void:
	InputMap.load_from_project_settings()
	Gamepad.install()
	var s := Settings.new()
	var j := InputEventJoypadButton.new()
	j.button_index = JOY_BUTTON_Y
	check(s.rebind(&"dash", j), "pad rebind accepted")
	var ev := InputMap.action_get_events(&"dash")
	check(ev.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y), "pad Y bound")
	check(not ev.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B), "old pad B gone")
	check(ev.any(func(e): return e is InputEventKey), "keyboard dash kept")
	var ax := InputEventJoypadMotion.new()
	ax.axis = JOY_AXIS_TRIGGER_LEFT
	ax.axis_value = 1.0
	check(s.rebind(&"crouch", ax), "axis rebind accepted")
	check(s.save(PATH) == OK, "saved")
	InputMap.load_from_project_settings()
	var l := Settings.load_from(PATH)
	l.apply_input_map()
	ev = InputMap.action_get_events(&"dash")
	check(ev.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y), "pad Y loaded")
	check(ev.any(func(e): return e is InputEventKey), "key loaded too")
	var c := InputMap.action_get_events(&"crouch")
	check(c.any(func(e): return e is InputEventJoypadMotion and e.axis == JOY_AXIS_TRIGGER_LEFT), "axis loaded")
	check(Gamepad.has_pad_event(&"jump"), "un-rebound actions keep defaults")
	check(Settings.event_label(j) == "Pad 3" and Settings.event_label(ax) == "Axis 4+", "pad labels")
	InputMap.load_from_project_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_stick_deadzone_and_look() -> void:
	check(Gamepad.deadzone(Vector2(0.1, 0.1)) == Vector2.ZERO, "inside dead zone")
	check_near(Gamepad.deadzone(Vector2(1, 0)).x, 1.0, 1e-6, "full tilt")
	check_near(Gamepad.deadzone(Vector2(0.6, 0)).x, 0.5, 1e-6, "rescaled")
	var p := _player()
	var y0 := p.yaw
	p.add_look_degrees(Vector2(90.0, 0.0))
	check_near(rad_to_deg(wrapf(y0 - p.yaw, -PI, PI)), 90.0, 1e-3, "stick right turns right 90 deg")
	p.queue_free()


func _focused(n: Node) -> bool:
	var f := n.get_viewport().gui_get_focus_owner() if n.is_inside_tree() else null
	return f != null and n.is_ancestor_of(f)


func test_ui_focus_chain() -> void:
	var su := SettingsUi.new()
	su.path = PATH
	runner_tree.root.add_child(su)
	su.setup(Settings.new())
	su.open()
	check(_focused(su), "settings focused")
	su.close()
	su.queue_free()
	var inv := InventoryUi.new()
	runner_tree.root.add_child(inv)
	inv.open()
	check(_focused(inv), "inventory focused")
	inv.queue_free()
	var p := _player()
	var st := StationUi.new()
	runner_tree.root.add_child(st)
	st.bind(p)
	st.open(null)
	check(_focused(st), "station focused")
	st.close()
	st.queue_free()
	var ft := FastTravel.new()
	ft.flags.set_flag(FastTravel.CRYSTAL)
	ft.flags.set_flag("tutorial_done")
	ft.attune("old_oak")
	ft.attune("landfill")
	var fu := FastTravelUI.new()
	runner_tree.root.add_child(fu)
	fu.show_map(ft, "old_oak")
	check(_focused(fu), "fast travel focused")
	fu.queue_free()
	var pm := PauseMenu.new()
	runner_tree.root.add_child(pm)
	pm.open()
	check(_focused(pm), "pause focused")
	runner_tree.paused = false
	pm.queue_free()
	p.queue_free()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
