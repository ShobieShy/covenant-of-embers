class_name PauseMenu
extends CanvasLayer
## Pause menu (step 39) on the `menu` action (Esc, Magewar's name): pauses the tree and
## frees the mouse; Resume / Settings / Save / Main menu / Quit. Ignored while another
## screen (inventory, station) is open: Esc closes that one first.

signal save_requested

var player: Player
var settings_ui: SettingsUi
var panel: PanelContainer
var buttons := {}
var status: Label
var center: CenterContainer


func _init() -> void:
	layer = 3
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c := CenterContainer.new()
	center = c
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	panel = PanelContainer.new()
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(260, 0)
	panel.add_child(v)
	var t := Label.new()
	t.text = "Paused"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for id in ["resume", "settings", "save", "main_menu", "quit"]:
		var b := Button.new()
		b.text = id.capitalize()
		b.pressed.connect(press.bind(id))
		v.add_child(b)
		buttons[id] = b
	status = Label.new()
	v.add_child(status)


func bind(p: Player, s: SettingsUi) -> void:
	player = p
	settings_ui = s


func open() -> void:
	if Cinematic.playing:  # step 110: Esc held during a cinematic skips it instead
		return
	visible = true
	# Anchors set in _init (before entering the tree) resolve against a zero rect; re-apply
	# now so the panel sits in the middle of the real window (found in the step-41 playtest).
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status.text = ""
	if player:
		player.ui_open = true
	get_tree().paused = true
	(buttons["resume"] as Button).grab_focus()  # keyboard/gamepad navigation
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	if settings_ui and settings_ui.visible:
		settings_ui.close()
	if player:
		player.ui_open = false
	if is_inside_tree():
		get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func press(id: String) -> void:
	match id:
		"resume":
			close()
		"settings":
			if settings_ui:
				settings_ui.open()
		"save":
			save_requested.emit()
			status.text = "Saved."
		"main_menu":
			save_requested.emit()
			var tree := get_tree()
			close()
			GameFlow.to_menu(tree)
		"quit":
			save_requested.emit()
			get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"menu"):
		return
	if visible:
		if settings_ui and settings_ui.visible:
			settings_ui.close()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif player == null or not player.ui_open:
		open()
		get_viewport().set_input_as_handled()
