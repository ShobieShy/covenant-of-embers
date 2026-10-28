class_name SkillsUi
extends CanvasLayer
## Skill tree screen (BUILD_PLAN step 72; K): one column per branch, a button per skill
## ("Name r/max", disabled with the reason as tooltip when it can't take a rank), free
## points, and Respec (only when `can_respec` says so: the Old Oak, step 71).
## Opening sets player.ui_open like the inventory.
## Step 149 (docs/ELEMENT_TREES_PLAN.md §4.8): a tab strip (Core + the 7 element trees, LB/RB on a
## pad); an element tab is a 5x4 grid (tiers 0-4) plus its capstone. The owned element capstone
## gets a gold frame + crown (and a crown on its tab); every other element capstone is greyed with
## a padlock (and a padlock on its tab) and a tooltip naming the owned one. Taking a capstone asks
## first (confirm dialog; A takes, B cancels).

const ACTION := &"skills"

var player: Player
var can_respec := Callable()  ## () -> bool; main.gd binds Main.can_respec
var root: PanelContainer
var columns: HBoxContainer
var points_label: Label
var respec_button: Button
var buttons := {}  ## skill id -> Button
var tabs: HBoxContainer
var tab_buttons := {}  ## "core" / element id -> Button
var pages := {}  ## "core" / element id -> Control
var current := "core"
var el_buttons := {}  ## "el/sid" -> Button
var locks := {}  ## "el/sid" -> Padlock (capstones only)
var crowns := {}  ## "el/sid" -> Crown (capstones only)
var card_line: Label
var confirm: PanelContainer
var confirm_label: Label
var confirm_take: Button
var pending := ""  ## "el/sid" awaiting the confirm dialog


## Small padlock drawn over a locked capstone (and on its tab).
class Padlock:
	extends Control

	func _init(sz := 18.0) -> void:
		custom_minimum_size = Vector2(sz, sz)
		size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		draw_arc(Vector2(w * 0.5, w * 0.45), w * 0.25, PI, TAU, 12, Color(0.85, 0.85, 0.85), 2.0)
		draw_rect(Rect2(w * 0.15, w * 0.45, w * 0.7, w * 0.5), Color(0.8, 0.8, 0.8))
		draw_circle(Vector2(w * 0.5, w * 0.68), w * 0.07, Color(0.2, 0.2, 0.2))


## Crown pip on the owned capstone (and its tab).
class Crown:
	extends Control

	func _init(sz := 18.0) -> void:
		custom_minimum_size = Vector2(sz, sz)
		size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var pts := PackedVector2Array(
			[
				Vector2(0.1, 0.85) * w,
				Vector2(0.1, 0.3) * w,
				Vector2(0.3, 0.55) * w,
				Vector2(0.5, 0.15) * w,
				Vector2(0.7, 0.55) * w,
				Vector2(0.9, 0.3) * w,
				Vector2(0.9, 0.85) * w,
			]
		)
		draw_colored_polygon(pts, Color(1.0, 0.8, 0.2))


func _init() -> void:
	layer = 3
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(1040, 600)
	root.position = Vector2(-520, -300)
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
	tabs = HBoxContainer.new()
	v.add_child(tabs)
	columns = HBoxContainer.new()
	v.add_child(columns)
	pages["core"] = columns
	card_line = Label.new()
	card_line.modulate = Color(0.85, 0.8, 0.65)
	v.add_child(card_line)
	confirm = PanelContainer.new()
	confirm.visible = false
	confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	confirm.custom_minimum_size = Vector2(460, 120)
	confirm.position = Vector2(-230, -60)
	add_child(confirm)
	var cv := VBoxContainer.new()
	confirm.add_child(cv)
	confirm_label = Label.new()
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	cv.add_child(confirm_label)
	var cb := HBoxContainer.new()
	cv.add_child(cb)
	confirm_take = Button.new()
	confirm_take.text = "Take"
	confirm_take.pressed.connect(func(): confirm_pending(true))
	cb.add_child(confirm_take)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): confirm_pending(false))
	cb.add_child(cancel)


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
	_build_tabs()
	p.skills.changed.connect(refresh)
	p.progression.leveled_up.connect(func(_l): refresh())
	refresh()


func _build_tabs() -> void:
	for c in tabs.get_children():
		c.queue_free()
	for k in pages.keys():
		if k != "core":
			(pages[k] as Control).queue_free()
			pages.erase(k)
	tab_buttons.clear()
	el_buttons.clear()
	locks.clear()
	crowns.clear()
	var et := ElementTable.load_default()
	_add_tab(
		"core", player.skills.tree.name if player.skills.tree.name != "" else "Core", Color.WHITE
	)
	for el in ElementTable.IDS:
		var t := SkillTree.element_tree(el)
		if t == null:
			continue
		var col := et.color(ElementTable.parse(el)) if et != null else Color.WHITE
		_add_tab(el, t.name, col)
		pages[el] = _build_element_page(el, t, col)
		columns.get_parent().add_child(pages[el])
		columns.get_parent().move_child(pages[el], columns.get_index() + 1)
	show_tab("core")


func _add_tab(key: String, label: String, col: Color) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.add_theme_color_override("font_color", col)
	b.pressed.connect(func(): show_tab(key))
	tabs.add_child(b)
	tab_buttons[key] = b
	if key != "core":
		var lock := Padlock.new(14)
		lock.position = Vector2(2, 2)
		lock.name = "TabLock"
		b.add_child(lock)
		var crown := Crown.new(14)
		crown.position = Vector2(2, 2)
		crown.name = "TabCrown"
		b.add_child(crown)


func _build_element_page(el: String, t: SkillTree, col: Color) -> Control:
	var page := VBoxContainer.new()
	page.visible = false
	var grid := GridContainer.new()
	grid.columns = 4
	page.add_child(grid)
	var caps: Array = []
	for s in t.skills.values():
		if bool(s.get("capstone", false)):
			caps.append(s)
			continue
		grid.add_child(_el_button(el, s, col, Vector2(250, 40)))
	for s in caps:
		var b := _el_button(el, s, col, Vector2(1012, 48))
		page.add_child(b)
		var lock := Padlock.new(26)
		lock.position = Vector2(8, 11)
		b.add_child(lock)
		locks["%s/%s" % [el, s["id"]]] = lock
		var crown := Crown.new(22)
		crown.position = Vector2(10, 13)
		b.add_child(crown)
		crowns["%s/%s" % [el, s["id"]]] = crown
	return page


func _el_button(el: String, s: Dictionary, col: Color, sz: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = sz
	b.add_theme_color_override("font_color", col.lightened(0.3))
	var sid := String(s["id"])
	b.pressed.connect(func(): take_element(el, sid))
	b.focus_entered.connect(func(): _card(el, sid))
	b.mouse_entered.connect(func(): _card(el, sid))
	el_buttons["%s/%s" % [el, sid]] = b
	return b


func show_tab(key: String) -> void:
	if not pages.has(key):
		return
	current = key
	for k in pages:
		(pages[k] as Control).visible = k == key
	for k in tab_buttons:
		(tab_buttons[k] as Button).button_pressed = k == key
	refresh()
	if visible:
		Gamepad.focus_first(pages[key])


func cycle_tab(dir: int) -> void:
	var keys := tab_buttons.keys()
	if keys.is_empty():
		return
	show_tab(keys[posmod(keys.find(current) + dir, keys.size())])


## Bottom card line: the hovered/focused element skill's name, rank and effect.
func _card(el: String, sid: String) -> void:
	var t := SkillTree.element_tree(el)
	if t == null or player == null:
		return
	var s := t.skill(sid)
	card_line.text = (
		"%s  %d/%d  —  %s" % [s["name"], player.skills.el_rank(el, sid), s["max_rank"], s["desc"]]
	)


## Takes a rank of element skill `sid`; a capstone first opens the confirm dialog (returns false
## until confirm_pending(true)).
func take_element(el: String, sid: String) -> bool:
	if player == null:
		return false
	var t := SkillTree.element_tree(el)
	if t != null and bool(t.skill(sid).get("capstone", false)) and pending.is_empty():
		if not player.skills.el_why_not(el, sid, player.progression.level).is_empty():
			return false
		pending = "%s/%s" % [el, sid]
		confirm_label.text = (
			"Taking %s locks the other %d element capstones until you respec. Continue?"
			% [t.skill(sid)["name"], ElementTable.IDS.size() - 1]
		)
		confirm.visible = true
		confirm_take.grab_focus.call_deferred()
		return false
	var ok := player.spend_element_skill(el, sid)
	refresh()
	return ok


func confirm_pending(yes: bool) -> bool:
	var key := pending
	confirm.visible = false
	if key.is_empty():
		return false
	var parts := key.split("/")
	var ok := false
	if yes:
		ok = player.spend_element_skill(parts[0], parts[1])
	pending = ""
	refresh()
	if is_instance_valid(el_buttons.get(key)) and visible:
		(el_buttons[key] as Button).grab_focus.call_deferred()
	return ok


## Tooltip text for a capstone locked by exclusivity.
func locked_text(own: String) -> String:
	var t := SkillTree.element_tree(own)
	var cap := ""
	for s in t.skills.values():
		if bool(s.get("capstone", false)) and player.skills.el_rank(own, s["id"]) > 0:
			cap = s["name"]
	var et := ElementTable.load_default()
	var en := et.display_name(ElementTable.parse(own)) if et != null else own
	return (
		"Locked – you hold %s (%s). Only one element capstone per character. Respec at the Old Oak to choose again."
		% [cap, en]
	)


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
	respec_button.disabled = (
		not (can_respec.is_valid() and bool(can_respec.call())) or player.inventory.gold < price
	)
	for sid in buttons:
		var s := player.skills.tree.skill(sid)
		var b: Button = buttons[sid]
		var why := player.skills.why_not(sid, lv)
		b.text = (
			"%s%s  %d/%d"
			% ["* " if s["capstone"] else "", s["name"], player.skills.rank(sid), s["max_rank"]]
		)
		b.tooltip_text = String(s["desc"]) + ("" if why.is_empty() else "\n(" + why + ")")
		b.disabled = not why.is_empty()
	_refresh_elements(lv)


func _refresh_elements(lv: int) -> void:
	var own := player.skills.capstone_owner()
	for key in el_buttons:
		var parts: PackedStringArray = key.split("/")
		var el := parts[0]
		var sid := parts[1]
		var t := SkillTree.element_tree(el)
		var s := t.skill(sid)
		var b: Button = el_buttons[key]
		var r := player.skills.el_rank(el, sid)
		var why := player.skills.el_why_not(el, sid, lv)
		var locked := why == Skills.CAPSTONE_LOCKED
		var owned := bool(s["capstone"]) and r > 0
		b.text = "%s%s  %d/%d" % ["      " if s["capstone"] else "", s["name"], r, s["max_rank"]]
		b.disabled = not why.is_empty()
		b.modulate = Color(0.6, 0.6, 0.6, 0.4) if locked else Color.WHITE
		b.tooltip_text = String(s["desc"])
		if locked:
			b.tooltip_text = locked_text(own)
		elif not why.is_empty() and why != "max rank":
			b.tooltip_text += "\n(" + why + ")"
		if owned:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.2, 0.16, 0.05)
			sb.set_border_width_all(3)
			sb.border_color = Color(1.0, 0.8, 0.2)
			for st in ["normal", "disabled", "hover", "focus"]:
				b.add_theme_stylebox_override(st, sb)
		if locks.has(key):
			(locks[key] as Control).visible = locked
			(crowns[key] as Control).visible = owned
	for k in tab_buttons:
		if k == "core":
			continue
		var tb: Button = tab_buttons[k]
		tb.get_node("TabLock").visible = not own.is_empty() and own != k
		tb.get_node("TabCrown").visible = own == k
		tb.text = (
			"%s%s (%d)"
			% [
				"    " if not own.is_empty() else "",
				SkillTree.element_tree(k).name,
				player.skills.el_spent(k)
			]
		)


func is_open() -> bool:
	return visible


func open() -> void:
	UiAnim.open(self)  # 0.3.1 P1
	if player:
		player.ui_open = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	Gamepad.focus_first(pages.get(current, self))


func close() -> void:
	UiAnim.close(self)  # 0.3.1 P1
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
	if visible and confirm.visible:
		if (
			event.is_action_pressed(&"ui_cancel")
			or (
				event is InputEventJoypadButton
				and event.pressed
				and event.button_index == JOY_BUTTON_B
			)
		):
			confirm_pending(false)
			get_viewport().set_input_as_handled()
		return
	if visible and event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			cycle_tab(-1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
