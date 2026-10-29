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
var party: Label
var _leave_armed := false
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
	for id in ["resume", "skills", "settings", "save", "main_menu", "quit"]:
		var b := Button.new()
		b.text = id.capitalize()
		b.pressed.connect(press.bind(id))
		v.add_child(b)
		buttons[id] = b
	party = Label.new()
	party.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	party.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(party)
	var leave := Button.new()
	leave.text = "Leave co-op"
	leave.pressed.connect(press.bind("leave"))
	v.add_child(leave)
	buttons["leave"] = leave
	status = Label.new()
	v.add_child(status)


func bind(p: Player, s: SettingsUi) -> void:
	player = p
	settings_ui = s


func open() -> void:
	if Cinematic.playing:  # step 110: Esc held during a cinematic skips it instead
		return
	# Anchors set in _init (before entering the tree) resolve against a zero rect; re-apply
	# now so the panel sits in the middle of the real window (found in the step-41 playtest).
	# Before UiAnim.open, which reads the resting position (QA round 9).
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiAnim.open(self)  # 0.3.1 P1
	status.text = ""
	_leave_armed = false
	if party:
		var n := 1
		if Coop.session and is_instance_valid(Coop.session):
			n = Coop.session.roster.size()
		party.text = CoopFlow.party_line(n)
	if buttons.has("leave"):
		(buttons["leave"] as Button).visible = Coop.active()
		(buttons["leave"] as Button).text = "Leave co-op"
	if player:
		player.ui_open = true
	get_tree().paused = true
	(buttons["skills"] as Button).text = skills_label(
		player.skills.available(player.progression.level) if player else 0
	)
	(buttons["resume"] as Button).grab_focus()  # keyboard/gamepad navigation
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if settings_ui and settings_ui.visible:
		settings_ui.close()
	# QA round 10: unpause once the fade is done, not at its start (the game ran 8 frames
	# under a still-visible menu).
	UiAnim.close(self, _closed)  # 0.3.1 P1


func _closed() -> void:
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
		"leave":
			if not Coop.active():
				return
			if not _leave_armed:
				_leave_armed = true
				status.text = "Leave the session? Press again to confirm."
				return
			var tree := get_tree()
			close()
			Coop.end("left")
			GameFlow.to_menu(tree)
		"skills":  # 0.3.1 P4 (M4): opens the K panel once the menu is gone
			var sk := get_tree().root.find_child("SkillsUi", true, false)
			if settings_ui and settings_ui.visible:
				settings_ui.close()
			UiAnim.close(
				self,
				func() -> void:
					_closed()
					if sk and sk.has_method(&"open"):
						sk.call(&"open")
			)
		"settings":
			if settings_ui:
				settings_ui.open()
		"save":
			if IntroDirector.refuse(self, "save"):  # step 112 (quit / travel still save)
				status.text = IntroDirector.lock_text("save")
				return
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
	if UiAnim.is_shown(self):
		if settings_ui and settings_ui.visible:
			settings_ui.close()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif player == null or not player.ui_open:
		open()
		get_viewport().set_input_as_handled()


## M4: the Skills entry, with the unspent point count as a badge. QA r12: a plain space
## before the ◆ (a fallback-font glyph) was eaten at the run break ("Skills◆ 15"); a
## no-break space keeps the gap: "Skills ◆ 15".
static func skills_label(points: int) -> String:
	return "Skills\u00a0◆ %d" % points if points > 0 else "Skills"
