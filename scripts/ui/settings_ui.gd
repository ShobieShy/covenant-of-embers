class_name SettingsUi
extends CanvasLayer
## Settings screen (BUILD_PLAN step 32; opened from the pause/main menu in step 39):
## one row per rebindable action (click, then press a key or mouse button), and the look /
## accessibility options. Every change saves user://keybinds.cfg and re-applies.

signal closed

var settings: Settings
var player: Player
var path := Settings.PATH
var listening: StringName = &""
var action_buttons := {}  ## StringName -> Button
var root: PanelContainer
var controls := {}  ## option name -> Control


func _init() -> void:
	layer = 4
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var scroll := ScrollContainer.new()
	root.add_child(scroll)
	var h := HBoxContainer.new()
	scroll.add_child(h)
	var keys := GridContainer.new()
	keys.columns = 2
	h.add_child(keys)
	for a in Settings.rebindable():
		var l := Label.new()
		l.text = String(a).capitalize()
		keys.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 0)
		b.pressed.connect(func(): listen(a))
		keys.add_child(b)
		action_buttons[a] = b
	var opts := VBoxContainer.new()
	h.add_child(opts)
	for o in ["invert_y", "focus_toggle", "crouch_toggle", "reduced_motion", "subtitles"]:
		var c := CheckBox.new()
		c.text = o.capitalize()
		c.toggled.connect(func(v): set_option(o, v))
		opts.add_child(c)
		controls[o] = c
	for o in [
		["hip_fov", 60.0, 110.0, 1.0],
		["aim_sensitivity", 0.1, 5.0, 0.05],
		["head_bob", 0.0, 1.0, 0.1],
		["master_volume", 0.0, 1.0, 0.05],
		["sfx_volume", 0.0, 1.0, 0.05],
		["music_volume", 0.0, 1.0, 0.05],
		["subtitle_scale", 0.75, 2.0, 0.25],
		["ui_scale", 0.0, 2.0, 0.25]
	]:
		var l := Label.new()
		l.text = String(o[0]).capitalize()
		opts.add_child(l)
		var sl := HSlider.new()
		sl.min_value = o[1]
		sl.max_value = o[2]
		sl.step = o[3]
		sl.custom_minimum_size = Vector2(240, 0)
		sl.value_changed.connect(func(v): set_option(o[0], v))
		opts.add_child(sl)
		controls[o[0]] = sl
	var cb := OptionButton.new()  # step 76
	for n in Accessibility.MODE_NAMES:
		cb.add_item("Colour-blind: " + n)
	cb.item_selected.connect(func(i): set_option("colorblind", i))
	opts.add_child(cb)
	controls["colorblind"] = cb
	var wm := OptionButton.new()  # step 86
	for n in PlatformDisplay.WINDOW_MODES:
		wm.add_item(n)
	wm.item_selected.connect(func(i): set_option("window_mode", i))
	opts.add_child(wm)
	controls["window_mode"] = wm
	var q := OptionButton.new()  # step 134
	q.add_item("Graphics: Auto")
	for n in QualityPresets.NAMES:
		q.add_item("Graphics: " + n)
	q.item_selected.connect(func(i): set_option("quality", i - 1))
	opts.add_child(q)
	controls["quality"] = q
	var rd := OptionButton.new()
	for n in PlatformDisplay.renderers_for(OS.get_name()):
		rd.add_item("Renderer: " + n + " (restart)")
	rd.item_selected.connect(func(i): set_option("renderer", PlatformDisplay.renderers_for(OS.get_name())[i]))
	opts.add_child(rd)
	controls["renderer"] = rd
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(close)
	opts.add_child(back)


func setup(s: Settings, p: Player = null) -> void:
	settings = s
	player = p
	refresh()


func open() -> void:
	visible = true
	refresh()
	Gamepad.focus_first(self)  # step 77


func close() -> void:
	visible = false
	listening = &""
	closed.emit()


func refresh() -> void:
	if settings == null:
		return
	for a in action_buttons:
		action_buttons[a].text = "Press a key..." if a == listening else Settings.action_label(a)
		action_buttons[a].tooltip_text = "Controller: " + Settings.action_label(a, true)
	for o in controls:
		var c: Control = controls[o]
		if c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(settings.get(o))
		elif c is OptionButton and o == "renderer":
			(c as OptionButton).select(maxi(0, PlatformDisplay.renderers_for(OS.get_name()).find(settings.renderer)))
		elif c is OptionButton and o == "quality":
			(c as OptionButton).select(int(settings.quality) + 1)
		elif c is OptionButton:
			(c as OptionButton).select(settings.get(o))
		else:
			(c as Range).set_value_no_signal(settings.get(o))


func listen(a: StringName) -> void:
	listening = a
	refresh()


func set_option(o: String, v: Variant) -> void:
	settings.set(o, v)
	_commit()


func _commit() -> void:
	settings.save(path)
	settings.apply_to(player)
	refresh()


func _input(event: InputEvent) -> void:
	if not visible or listening == &"":
		return
	var pad_axis := event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6
	if (
		(
			(event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton)
			and event.is_pressed()
		)
		or pad_axis
	):
		get_viewport().set_input_as_handled()
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			listening = &""
			refresh()
			return
		capture(event)


## The key/mouse event for the action being rebound.
func capture(e: InputEvent) -> bool:
	if listening == &"":
		return false
	var ok := settings.rebind(listening, e)
	listening = &""
	_commit()
	return ok
