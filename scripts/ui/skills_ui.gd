class_name SkillsUi
extends CanvasLayer
## Skill tree screen (BUILD_PLAN step 72; K): one column per branch, a button per skill
## ("Name r/max", disabled with the reason as tooltip when it can't take a rank), free
## points, and Respec (only when `can_respec` says so: the Old Oak, step 71).
## Opening sets player.ui_open like the inventory.

const ACTION := &"skills"

var player: Player
var can_respec := Callable()  ## () -> bool; main.gd binds Main.can_respec
var root: PanelContainer
var columns: HBoxContainer
var points_label: Label
var respec_button: Button
var buttons := {}  ## skill id -> Button


func _init() -> void:
	layer = 3
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(900, 520)
	root.position = Vector2(-450, -260)
	add_child(root)
	var v := VBoxContainer.new()
	root.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	points_label = Label.new()
	points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(points_label)
	respec_button = Button.new()
	respec_button.text = "Respec (Old Oak)"
	respec_button.pressed.connect(respec)
	top.add_child(respec_button)
	columns = HBoxContainer.new()
	v.add_child(columns)


func bind(p: Player) -> void:
	player = p
	for c in columns.get_children():
		c.queue_free()
	buttons.clear()
	var t := p.skills.tree
	if t == null:
		return
	for b in t.branches:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(290, 0)
		columns.add_child(col)
		var l := Label.new()
		l.text = String(b["name"])
		col.add_child(l)
		for sid in t.in_branch(b["id"]):
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(280, 36)
			btn.pressed.connect(func(): take(sid))
			col.add_child(btn)
			buttons[sid] = btn
	p.skills.changed.connect(refresh)
	p.progression.leveled_up.connect(func(_l): refresh())
	refresh()


func take(sid: String) -> bool:
	var ok := player != null and player.spend_skill(sid)
	refresh()
	return ok


func respec() -> int:
	if player == null or not (can_respec.is_valid() and bool(can_respec.call())):
		return -1
	var n := player.respec_skills()
	refresh()
	return n


func refresh() -> void:
	if player == null or player.skills.tree == null:
		return
	var lv := player.progression.level
	points_label.text = "Skill points: %d   (level %d)" % [player.skills.available(lv), lv]
	var price := player.respec_price()
	respec_button.text = "Respec (Old Oak, %d Gold)" % price if price > 0 else "Respec (Old Oak)"
	respec_button.disabled = not (can_respec.is_valid() and bool(can_respec.call())) or player.inventory.gold < price
	for sid in buttons:
		var s := player.skills.tree.skill(sid)
		var b: Button = buttons[sid]
		var why := player.skills.why_not(sid, lv)
		b.text = "%s%s  %d/%d" % ["* " if s["capstone"] else "", s["name"], player.skills.rank(sid), s["max_rank"]]
		b.tooltip_text = String(s["desc"]) + ("" if why.is_empty() else "\n(" + why + ")")
		b.disabled = not why.is_empty()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	if player:
		player.ui_open = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	Gamepad.focus_first(self)


func close() -> void:
	visible = false
	if player:
		player.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if visible:
		close()
	elif not IntroDirector.refuse(self, "skills"):  # step 112: locked early in the intro
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
