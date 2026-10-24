class_name MainMenu
extends Control
## Main menu (step 39): New Run (the Midden), Continue (the saved level + state; greyed
## without a save), Settings, Quit. User args (after `--`):
##  --start      begin a new run at once (scripted launches, CI smoke);
##  --continue   continue the save at once (falls back to a new run without one);
##  --seconds N  quit after N s if still on the menu (never hangs a headless run).

var buttons := {}
var version_label: Label
var slot_buttons: Array[Button] = []
## Step 49: New Run over an existing save asks first.
var confirm: ConfirmationDialog
var settings_ui: SettingsUi
var coop_menu: CoopMenu  ## step 88
var _seconds := -1.0
var _elapsed := 0.0
var archetype_pick: OptionButton  ## step 73
var name_edit: LineEdit
var color_pick: ColorPickerButton


## "v0.1.0" from application/config/version (step 84; also stamped into the Windows exe).
static func version_string() -> String:
	return "v" + String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.05, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(320, 0)
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	var title := Label.new()
	title.text = "Covenant of Embers"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	v.add_child(title)
	version_label = Label.new()  # step 84
	version_label.text = version_string()
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.modulate = Color(1, 1, 1, 0.6)
	v.add_child(version_label)
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(slots)
	for n in range(1, SaveGame.SLOTS + 1):
		var sb := Button.new()
		sb.toggle_mode = true
		sb.custom_minimum_size = Vector2(96, 32)
		sb.pressed.connect(select_slot.bind(n))
		slots.add_child(sb)
		slot_buttons.append(sb)
	_build_identity(v)  # step 73
	for id in ["new_run", "continue", "coop", "settings", "quit"]:
		var b := Button.new()
		b.text = "Co-op" if id == "coop" else id.capitalize()
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(press.bind(id))
		v.add_child(b)
		buttons[id] = b
	for f in UserDir.migrate_legacy():  # step 83
		print("[menu] migrated %s from the old user dir" % f)
	UiDriver.attach(get_tree())  # step 41: --ui-test <dir>
	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "This slot already has a save. Start a new run and overwrite it?"
	confirm.ok_button_text = "Overwrite"
	confirm.confirmed.connect(_start_new)
	add_child(confirm)
	select_slot(GameFlow.slot)
	settings_ui = SettingsUi.new()
	add_child(settings_ui)
	settings_ui.setup(Settings.load_from())
	coop_menu = CoopMenu.new()
	coop_menu.visible = false
	add_child(coop_menu)
	var coop_opts := Coop.parse_args(OS.get_cmdline_user_args())
	if coop_opts["mode"] != "":  # step 88: --host / --join
		coop_menu.auto.call_deferred(coop_opts)
	var launch_lobby := LobbyBackend.launch_lobby(OS.get_cmdline_args())  # step 89: Steam join-on-launch
	if launch_lobby != 0:
		coop_menu.join_lobby_id.call_deferred(launch_lobby)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(buttons["new_run"] as Button).grab_focus.call_deferred()
	var args := Array(OS.get_cmdline_user_args())
	var i := args.find("--seconds")
	if i >= 0 and i + 1 < args.size():
		_seconds = float(args[i + 1])
	if args.has("--autoplay"):  # step 40: the bot never touches the real save
		GameFlow.save_path = "user://playtest_save.json"
		PlaytestBot.reset_run()
		var cargs := Coop.parse_args(OS.get_cmdline_user_args())
		if cargs["mode"] != "" and not PlaytestBot.coop_started:  # step 93: bots start fresh
			PlaytestBot.coop_started = true
			for f in [GameFlow.save_path, CharacterSave.path_for(String(cargs["name"]))]:
				if FileAccess.file_exists(f):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if not args.has("--start"):
			args.append("--start")
	Screenshots.attach(self, "menu")
	print("[menu] main menu, save %s" % ("found" if GameFlow.has_save() else "none"))
	if Coop.parse_args(OS.get_cmdline_user_args())["mode"] != "":
		pass
	elif args.has("--continue"):
		press.call_deferred("continue")
	elif args.has("--start"):  # scripted: no overwrite prompt
		_start_new.call_deferred()


func press(id: String) -> void:
	match id:
		"new_run":
			if GameFlow.has_save():
				confirm.popup_centered()
			else:
				_start_new()
		"continue":
			if not GameFlow.continue_run(get_tree()):
				GameFlow.new_run(get_tree())
		"coop":
			coop_menu.show()
		"settings":
			settings_ui.open()
		"quit":
			get_tree().quit(0)


func _start_new() -> void:
	GameFlow.new_identity = identity()
	GameFlow.new_run(get_tree())


## Step 73: archetype picker + name + colour for a new run.
func _build_identity(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	archetype_pick = OptionButton.new()
	for id in Archetype.IDS:
		archetype_pick.add_item("%s (%s)" % [Archetype.label(id), Archetype.blurb(id)])
	archetype_pick.item_selected.connect(_on_archetype)
	row.add_child(archetype_pick)
	color_pick = ColorPickerButton.new()
	color_pick.custom_minimum_size = Vector2(40, 0)
	color_pick.edit_alpha = false
	color_pick.color = Archetype.default_color(Archetype.DEFAULT)
	row.add_child(color_pick)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Character name"
	name_edit.max_length = Archetype.NAME_MAX
	name_edit.text = "Ember"
	v.add_child(name_edit)


func _on_archetype(i: int) -> void:
	color_pick.color = Archetype.default_color(Archetype.IDS[i])


func identity() -> Dictionary:
	if archetype_pick == null:
		return {}
	return {
		"archetype": Archetype.IDS[maxi(0, archetype_pick.selected)],
		"name": name_edit.text,
		"color": color_pick.color,
	}


func select_slot(n: int) -> void:
	GameFlow.select_slot(n)
	for i in slot_buttons.size():
		var b := slot_buttons[i]
		b.button_pressed = i + 1 == GameFlow.slot
		b.text = "Slot %d%s" % [i + 1, "" if GameFlow.slot_has_save(i + 1) else " (empty)"]
	(buttons["continue"] as Button).disabled = not GameFlow.has_save()


func _process(delta: float) -> void:
	_elapsed += delta
	if _seconds > 0.0 and _elapsed >= _seconds:
		print("[menu] quit after %.2f s on the menu" % _elapsed)
		get_tree().quit(0)
