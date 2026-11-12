class_name EchoMenu
extends CanvasLayer
## 0.9.1: one pause menu. Map, Missions, Inventory, Skills, Character, Challenges,
## Social, Settings. Esc opens and closes it and pauses. Q and E move tabs while it
## is open. LB / RB move tabs until the skill tree has focus, then the tree keeps them.
## Motion is a sliding underline and a fading page. Reduced motion and headless skip it.

signal save_requested

const TABS: PackedStringArray = [
	"map",
	"missions",
	"inventory",
	"skills",
	"character",
	"challenges",
	"social",
	"settings",
]
const LABELS: PackedStringArray = [
	"Map",
	"Missions",
	"Inventory",
	"Skills",
	"Character",
	"Challenges",
	"Social",
	"Settings",
]

var player: Player
var settings_ui: SettingsUi
var inventory: InventoryUi
var skills: SkillsUi
var level_map: WorldMapScreen
var world_map: WorldMap
var quests: QuestLog
var bounties := Bounties.new()
var current := 0
var last_tab := 0
var underline: ColorRect
var mission_detail: Label
var character_label: Label
var map_corner: Label
var status: Label
var party: Label
var tab_buttons: Array[Button] = []
var content: Control
var slide: Control
var pages: Array[Control] = []
var _leave_armed := false
var _mission_id := ""
var _mission_filter := "main"
var _homes := {}
var _page_tween: Tween
var _line_tween: Tween


func _init() -> void:
	layer = 6
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 28)
	margin.add_theme_constant_override(&"margin_right", 28)
	margin.add_theme_constant_override(&"margin_top", 24)
	margin.add_theme_constant_override(&"margin_bottom", 24)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var title := Label.new()
	title.text = "ECHO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var strip := Control.new()
	strip.custom_minimum_size = Vector2(0, 40)
	v.add_child(strip)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.add_child(row)
	for i in TABS.size():
		var b := Button.new()
		b.text = LABELS[i]
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(show_tab.bind(i))
		b.mouse_entered.connect(_hover.bind(b, true))
		b.mouse_exited.connect(_hover.bind(b, false))
		row.add_child(b)
		tab_buttons.append(b)
	underline = ColorRect.new()
	underline.color = Color(1.0, 0.62, 0.28)
	underline.position = Vector2(0, 34)
	underline.size = Vector2(48, 2)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(underline)
	content = Control.new()
	content.custom_minimum_size = Vector2(0, 420)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	v.add_child(content)
	slide = Control.new()
	slide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(slide)
	for _i in TABS.size():
		var page := Control.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		slide.add_child(page)
		pages.append(page)
	_build_missions(pages[1])
	_build_character(pages[4])
	_build_challenges(pages[5])
	_build_social(pages[6])
	_build_map(pages[0])
	var foot := HBoxContainer.new()
	v.add_child(foot)
	for id in ["resume", "save", "main_menu", "quit"]:
		var b := Button.new()
		b.text = id.capitalize().replace("_", " ")
		b.pressed.connect(press.bind(id))
		foot.add_child(b)
	status = Label.new()
	v.add_child(status)


func _ready() -> void:
	var bus := GameEvents.bus()
	if not bus.enemy_killed.is_connected(_on_kill):
		bus.enemy_killed.connect(_on_kill)


func _exit_tree() -> void:
	var bus := GameEvents.bus()
	if bus.enemy_killed.is_connected(_on_kill):
		bus.enemy_killed.disconnect(_on_kill)


func bind(p: Player, settings: SettingsUi, inv: InventoryUi, sk: SkillsUi) -> void:
	player = p
	settings_ui = settings
	inventory = inv
	skills = sk
	if settings_ui:
		settings_ui.echo = self
	if inventory:
		inventory.echo = self
	if skills:
		skills.echo = self


func is_open() -> bool:
	return UiAnim.is_shown(self)


func tab_id() -> String:
	return TABS[current]


## Open on a tab. Does not toggle. Esc and the footer use this.
func open(tab := "") -> void:
	if Cinematic.playing:
		return
	var id := tab if tab != "" else TABS[last_tab]
	if _locked(id):
		return
	var idx := maxi(0, TABS.find(id))
	if not is_open():
		_open_shell()
	show_tab(idx)


## Key that already means this tab: open it, switch to it, or close if it is showing.
func open_on(tab: String) -> void:
	if Cinematic.playing:
		return
	if is_open() and tab_id() == tab:
		close()
		return
	open(tab)


func close() -> void:
	if settings_ui and settings_ui.listening != &"":
		settings_ui.listening = &""
	_leave_armed = false
	UiAnim.close(self, _closed)


func press(id: String) -> void:
	match id:
		"resume":
			close()
		"leave":
			_leave()
		"save":
			_save()
		"main_menu":
			save_requested.emit()
			var tree := get_tree()
			close()
			GameFlow.to_menu(tree)
		"quit":
			save_requested.emit()
			get_tree().quit(0)
		_:
			if TABS.has(id):
				open(id)


func show_tab(i: int) -> void:
	var prev := current
	current = posmod(i, TABS.size())
	last_tab = current
	_release_hosted()
	for p in pages:
		p.visible = false
	pages[current].visible = true
	_style_tabs()
	_place_underline()
	_animate_page(1 if current >= prev else -1)
	_present()
	if tab_id() not in ["inventory", "skills", "settings"] and tab_buttons.size() > current:
		tab_buttons[current].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and _tab_key(event):
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"menu"):
		return
	if is_open():
		if tab_id() == "map" and level_map and level_map.card.visible:
			level_map.cancel()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif player == null or not player.ui_open:
		open()
		get_viewport().set_input_as_handled()


func _on_kill(enemy: Enemy, _element: ElementTable.Element) -> void:
	if enemy == null or enemy.def == null:
		return
	bounties.note(enemy.def.id)
	if is_open() and tab_id() == "challenges":
		_fill_challenges()


func _open_shell() -> void:
	UiAnim.open(self)
	status.text = ""
	_leave_armed = false
	if player:
		player.ui_open = true
	if is_inside_tree():
		get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _closed() -> void:
	_release_hosted()
	if player:
		player.ui_open = false
	if is_inside_tree():
		get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _locked(id: String) -> bool:
	if id in ["map", "inventory", "skills"] and IntroDirector.refuse(self, id):
		return true
	return false


func _tab_key(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit:
			return false
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_Q:
			show_tab(current - 1)
			return true
		if key == KEY_E:
			show_tab(current + 1)
			return true
	if event is InputEventJoypadButton and event.pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b != JOY_BUTTON_LEFT_SHOULDER and b != JOY_BUTTON_RIGHT_SHOULDER:
			return false
		if tab_id() == "skills" and _skill_focus():
			return false
		show_tab(current + (-1 if b == JOY_BUTTON_LEFT_SHOULDER else 1))
		return true
	return false


func _skill_focus() -> bool:
	if skills == null or skills.root == null:
		return false
	var f := get_viewport().gui_get_focus_owner()
	return f != null and (f == skills.root or skills.root.is_ancestor_of(f))


func _snap() -> bool:
	return UiAnim.reduced_motion or DisplayServer.get_name() == "headless"


func _style_tabs() -> void:
	for i in tab_buttons.size():
		var b := tab_buttons[i]
		if i == 3 and player:
			b.text = PauseMenu.skills_label(player.skills.available(player.progression.level))
		elif i == 3:
			b.text = LABELS[i]
		b.modulate = Color(1, 0.92, 0.75) if i == current else Color.WHITE


func _hover(b: Button, on: bool) -> void:
	var i := tab_buttons.find(b)
	if i == current:
		b.modulate = Color(1, 0.92, 0.75)
	elif on:
		b.modulate = Color(1.12, 1.06, 0.96)
	else:
		b.modulate = Color.WHITE


func _place_underline() -> void:
	if underline == null or tab_buttons.is_empty():
		return
	var b := tab_buttons[current]
	var thick := 4.0 if Accessibility.high_contrast else 2.0
	underline.color = Color.WHITE if Accessibility.high_contrast else Color(1.0, 0.62, 0.28)
	underline.size.y = thick
	if _line_tween and _line_tween.is_valid():
		_line_tween.kill()
	if _snap() or b.size.x <= 1.0:
		underline.position = Vector2(b.position.x, 36.0 - thick)
		underline.size.x = maxf(b.size.x, 24.0)
		return
	_line_tween = create_tween()
	_line_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_line_tween.set_ignore_time_scale(true)
	_line_tween.set_parallel(true)
	_line_tween.tween_property(underline, "position:x", b.position.x, 0.16)
	_line_tween.tween_property(underline, "size:x", b.size.x, 0.16)


func _animate_page(dir: int) -> void:
	if _page_tween and _page_tween.is_valid():
		_page_tween.kill()
	if _snap():
		slide.modulate.a = 1.0
		slide.position = Vector2.ZERO
		_page_tween = null
		return
	slide.modulate.a = 0.0
	slide.position = Vector2(24.0 * dir, 0)
	_page_tween = create_tween()
	_page_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_page_tween.set_ignore_time_scale(true)
	_page_tween.set_parallel(true)
	_page_tween.tween_property(slide, "modulate:a", 1.0, 0.16)
	_page_tween.tween_property(slide, "position", Vector2.ZERO, 0.16)


func _present() -> void:
	match tab_id():
		"map":
			_present_map()
		"missions":
			_fill_missions()
		"inventory":
			_host(inventory.root if inventory else null, pages[2], true)
			if inventory:
				inventory.refresh()
				Gamepad.focus_first(inventory.root)
		"skills":
			_host(skills.root if skills else null, pages[3], true)
			_host(skills.confirm if skills else null, pages[3], false)
			if skills:
				skills.refresh()
				Gamepad.focus_first(skills.pages.get(skills.current, skills.root))
		"character":
			_fill_character()
		"challenges":
			_fill_challenges()
		"social":
			_fill_social()
		"settings":
			_present_settings()


func _present_map() -> void:
	if world_map:
		var here := level_map.linear_level if level_map else ""
		map_corner.text = "\n".join(world_map.level_lines(here, []) if here != "" else world_map.lines())
	if level_map:
		level_map.hosted = true
		_host(level_map, pages[0].find_child("MapSlot", true, false), true)
		level_map.open()


func _present_settings() -> void:
	if settings_ui == null:
		return
	settings_ui.visible = true
	_host(settings_ui.root, pages[7], true)
	settings_ui.refresh()
	Gamepad.focus_first(settings_ui.root)


func _host(node: Control, slot: Control, fill: bool) -> void:
	if node == null or slot == null:
		return
	if not _homes.has(node):
		_homes[node] = {
			"parent": node.get_parent(),
			"min": node.custom_minimum_size,
			"pos": node.position,
			"center": is_equal_approx(node.anchor_left, node.anchor_right),
		}
	if node.get_parent() != slot:
		node.reparent(slot)
	if fill:
		node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if fill:
		node.visible = true


func _release_hosted() -> void:
	for node in _homes.keys():
		_unhost(node as Control)
	if level_map:
		level_map.hosted = false
	if settings_ui:
		settings_ui.visible = false


func _unhost(node: Control) -> void:
	if node == null or not _homes.has(node):
		return
	var home: Dictionary = _homes[node]
	var parent := home["parent"] as Node
	if parent and is_instance_valid(parent) and node.get_parent() != parent:
		node.reparent(parent)
	if home.get("center", false):
		node.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	else:
		node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.custom_minimum_size = home["min"]
	node.position = home["pos"]
	node.visible = false


func _build_map(page: Control) -> void:
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(box)
	map_corner = Label.new()
	map_corner.custom_minimum_size = Vector2(260, 0)
	map_corner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(map_corner)
	var slot := Control.new()
	slot.name = "MapSlot"
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(slot)


func _build_missions(page: Control) -> void:
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(box)
	var left := VBoxContainer.new()
	box.add_child(left)
	var filters := HBoxContainer.new()
	left.add_child(filters)
	for id in ["main", "side", "done"]:
		var b := Button.new()
		b.text = "Completed" if id == "done" else id.capitalize()
		b.pressed.connect(_set_mission_filter.bind(id))
		filters.add_child(b)
	var list := VBoxContainer.new()
	list.name = "MissionList"
	list.custom_minimum_size = Vector2(280, 0)
	left.add_child(list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(right)
	mission_detail = Label.new()
	mission_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(mission_detail)
	var track := Button.new()
	track.text = "Track"
	track.pressed.connect(_track_selected)
	right.add_child(track)


func _build_character(page: Control) -> void:
	character_label = Label.new()
	character_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(character_label)


func _build_challenges(page: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "ChallengeList"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(box)


func _build_social(page: Control) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(box)
	party = Label.new()
	party.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(party)
	var leave := Button.new()
	leave.text = "Leave co-op"
	leave.pressed.connect(press.bind("leave"))
	box.add_child(leave)


func _set_mission_filter(id: String) -> void:
	_mission_filter = id
	_fill_missions()


func _track_selected() -> void:
	if quests and _mission_id != "":
		quests.track(_mission_id)
		status.text = "Tracking."


func _fill_missions() -> void:
	var list := pages[1].find_child("MissionList", true, false) as VBoxContainer
	for c in list.get_children():
		c.free()
	if quests == null:
		mission_detail.text = "No missions."
		return
	var ids: PackedStringArray = []
	for id in quests.order:
		var show := false
		if _mission_filter == "done":
			show = quests.done.has(id)
		elif _mission_filter == "side":
			show = quests.kind_of(id) == "side" and quests.active.has(id)
		else:
			show = quests.kind_of(id) == "main" and quests.active.has(id)
		if show:
			ids.append(id)
	if _mission_id == "" or not ids.has(_mission_id):
		_mission_id = ids[0] if not ids.is_empty() else ""
	for id in ids:
		var b := Button.new()
		var title := String(quests.quests[id]["title"])
		b.text = title if not quests.done.has(id) else title + "  (done)"
		b.modulate = (
			Color(0.7, 0.7, 0.7)
			if quests.done.has(id)
			else (Color(0.55, 0.75, 1.0) if quests.kind_of(id) == "side" else Color(1.0, 0.85, 0.45))
		)
		b.pressed.connect(_select_mission.bind(id))
		list.add_child(b)
	_select_mission(_mission_id)


func _select_mission(id: String) -> void:
	_mission_id = id
	if id == "" or quests == null or not quests.quests.has(id):
		mission_detail.text = "No missions yet."
		return
	var q: Dictionary = quests.quests[id]
	var lines: PackedStringArray = [
		String(q["title"]), quests.kind_of(id).capitalize(), "Level %d" % quests.recommended(id)
	]
	var step := int(quests.active[id]["step"]) if quests.active.has(id) else -1
	var i := 0
	for o in q["objectives"]:
		var mark := ">" if i == step else ("+" if quests.done.has(id) or step > i else "-")
		var count := ""
		if i == step and int(o["count"]) > 1:
			count = " (%d/%d)" % [int(quests.active[id]["have"]), int(o["count"])]
		lines.append("%s %s%s" % [mark, o["text"], count])
		i += 1
	lines.append("Reward: %s" % quests.reward_line(id))
	if String(q["clue"]) != "" and quests.clue_defs.has(q["clue"]):
		var got := quests.clues.has(String(q["clue"]))
		var clue: Dictionary = quests.clue_defs[q["clue"]]
		lines.append("Clue: %s" % (String(clue["title"]) if got else "not yet"))
		if got:
			lines.append(String(clue["text"]))
	mission_detail.text = "\n".join(lines)


func _fill_character() -> void:
	if player == null:
		character_label.text = "No character."
		return
	var arch := Archetype.label(player.archetype)
	var shield := player.gear.shield.display_name if player.gear.shield else "standard"
	var relic := player.gear.relic.display_name if player.gear.relic else "-"
	var mantle := "worn" if player.get_node_or_null("Mantle") else "none"
	character_label.text = (
		"\n"
		. join(
			[
				"%s  —  %s" % [player.character_name, arch],
				(
					"Level %d    XP %d / %d"
					% [player.progression.level, player.progression.xp, player.progression.xp_to_next]
				),
				"Health %.0f / %.0f" % [player.health.value, player.health.max_value()],
				"Shield %.0f / %.0f  (%s)" % [player.health.shield, player.health.shield_max, shield],
				"Mana %.0f / %.0f" % [player.mana.value, player.mana.max_value()],
				"Breath %.0f / %.0f" % [player.breath.value, player.breath.max_value()],
				"Gold %d    Dust %d" % [player.inventory.gold, player.inventory.dust],
				"Skill points %d" % player.skills.available(player.progression.level),
				"Relic %s    Flask %d    Mantle %s" % [relic, player.gear.flask, mantle],
			]
		)
	)


func _fill_challenges() -> void:
	var box := pages[5].get_node("ChallengeList") as VBoxContainer
	for c in box.get_children():
		c.free()
	var head := Label.new()
	head.text = "Bounties. Repeatable. Gold is paid when you claim. Counts are saved."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	for row in Bounties.ROWS:
		var id := String(row["id"])
		var have := int(bounties.counts.get(id, 0))
		var line := Label.new()
		line.text = ("%s  %d / %d    %d gold" % [id.capitalize(), have, int(row["need"]), int(row["gold"])])
		box.add_child(line)
		var b := Button.new()
		b.text = "Claim"
		b.pressed.connect(_claim.bind(id))
		box.add_child(b)


func _claim(id: String) -> void:
	if player and bounties.claim(player, id):
		status.text = "Claimed."
	else:
		status.text = "Not enough yet."
	_fill_challenges()


func _fill_social() -> void:
	var n := 1
	if Coop.session and is_instance_valid(Coop.session):
		n = Coop.session.roster.size()
	party.text = CoopFlow.party_line(n)
	var leave := party.get_parent().get_child(1) as Button
	leave.visible = Coop.active()
	leave.text = "Leave co-op"


func _save() -> void:
	if IntroDirector.refuse(self, "save"):
		status.text = IntroDirector.lock_text("save")
		return
	save_requested.emit()
	status.text = "Saved."


func _leave() -> void:
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
