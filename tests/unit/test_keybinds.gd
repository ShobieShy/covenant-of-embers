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
	check(evs.size() == 1 and (evs[0] as InputEventKey).physical_keycode == KEY_J, "InputMap updated")
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
	check(l.invert_y and l.focus_toggle and is_equal_approx(l.hip_fov, 90.0) and is_equal_approx(l.head_bob, 0.1), "options round-trip")
	check(is_equal_approx(l.aim_sensitivity, Settings.RAW_LOOK), "sensitivity")
	check(l.bindings.get(&"jump", []) == [{"key": KEY_J}], "binding round-trip %s" % [l.bindings])
	# restore project defaults then re-apply the loaded file
	InputMap.action_erase_events(&"jump")
	for e in before:
		InputMap.action_add_event(&"jump", e)
	l.apply_input_map()
	check((InputMap.action_get_events(&"jump")[0] as InputEventKey).physical_keycode == KEY_J, "apply_input_map")
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
