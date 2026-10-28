extends TestCase
## Step 149: element tabs, locked-capstone look and the take-confirm dialog.

const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _player() -> Array:
	var w := Node3D.new()
	w.position = Vector3(0, 800, 4100)
	runner_tree.root.add_child(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	while p.progression.level < 40:
		p.add_xp(p.progression.xp_to_next)
	return [w, p]


func _cap(el: String) -> String:
	for s in SkillTree.element_tree(el).skills.values():
		if bool(s.get("capstone", false)):
			return s["id"]
	return ""


## Fills tree `el` to the capstone requirement without taking it.
func _fill(p: Player, el: String) -> void:
	var d := {}
	var n := 0
	for s in SkillTree.element_tree(el).skills.values():
		if bool(s.get("capstone", false)) or n >= Skills.CAPSTONE_POINTS:
			continue
		d[s["id"]] = int(s["max_rank"])
		n += int(s["max_rank"])
	for s in SkillTree.element_tree(el).skills.values():
		if int(s["tier"]) == 4 and not bool(s.get("capstone", false)):
			d[s["id"]] = 1
	p.skills.el_ranks[el] = d


func test_tabs_and_layout() -> void:
	var s := _player()
	var p: Player = s[1]
	var ui := SkillsUi.new()
	s[0].add_child(ui)
	ui.bind(p)
	check(ui.tab_buttons.size() == 8, "core + 7 element tabs")
	check(ui.el_buttons.size() == 7 * 21, "21 nodes per element tree")
	ui.show_tab("fire")
	check(ui.pages["fire"].visible and not ui.columns.visible, "fire tab shown")
	ui.cycle_tab(1)
	check(ui.current == "water", "RB cycles to the next tab")
	ui.cycle_tab(-2)
	check(ui.current == "arcane", "LB cycles back")
	s[0].free()


func test_capstone_confirm_and_lock() -> void:
	var s := _player()
	var p: Player = s[1]
	var ui := SkillsUi.new()
	s[0].add_child(ui)
	ui.bind(p)
	_fill(p, "fire")
	ui.refresh()
	var cap := _cap("fire")
	check(not ui.take_element("fire", cap) and ui.confirm.visible, "capstone asks first")
	check(ui.confirm_label.text.contains("locks the other 6"), "dialog text")
	check(not ui.confirm_pending(false) and p.skills.el_rank("fire", cap) == 0, "cancel takes nothing")
	ui.take_element("fire", cap)
	check(ui.confirm_pending(true) and p.skills.el_rank("fire", cap) == 1, "take confirms")
	check(ui.crowns["fire/" + cap].visible, "crown on the owned capstone")
	var wk := "water/" + _cap("water")
	check(ui.locks[wk].visible and ui.el_buttons[wk].disabled, "other capstone padlocked")
	check(ui.el_buttons[wk].tooltip_text.begins_with("Locked – you hold"), "locked tooltip names the owner")
	check(ui.tab_buttons["water"].get_node("TabLock").visible, "tab padlock")
	check(ui.tab_buttons["fire"].get_node("TabCrown").visible, "tab crown")
	s[0].free()


## 0.3.1 P6 (M8): hover pop, purchase pulse along the owned path, respec confirm, counter.
func test_polish_pulse_respec_counter() -> void:
	var s := _player()
	var p: Player = s[1]
	var ui := SkillsUi.new()
	s[0].add_child(ui)
	ui.bind(p)
	ui.refresh()
	var before := p.skills.available(p.progression.level)
	check(ui.points_label.text.begins_with("Skill points: %d " % before), "counter shows points")
	var t := SkillTree.element_tree("fire")
	var t0 := ""
	var t1 := ""
	for sk in t.skills.values():
		if int(sk["tier"]) == 0 and t0.is_empty():
			t0 = sk["id"]
	check(ui.take_element("fire", t0), "tier-0 bought")
	check(ui.path_pulses == 1, "pulse on the bought node")
	check(ui.points_label.text.begins_with("Skill points: %d " % (before - 1)), "counter lands")
	for sk in t.skills.values():
		if int(sk["tier"]) == 1 and t1.is_empty() and p.skills.el_why_not("fire", sk["id"], 40).is_empty():
			t1 = sk["id"]
	if not t1.is_empty():
		ui.path_pulses = 0
		check(ui.take_element("fire", t1) and ui.path_pulses >= 2, "pulse runs down the path")
	(ui.el_buttons["fire/" + t0] as Button).mouse_entered.emit()
	check(ui.hovers >= 1, "hover pops")
	ui.can_respec = func() -> bool: return true
	p.inventory.gold = 100000
	var spent := p.skills.el_spent("fire")
	check(ui.request_respec() and ui.confirm.visible, "respec asks first")
	check(ui.confirm_label.text.contains("refunds"), "refund text")
	check(not ui.confirm_pending(false) and p.skills.el_spent("fire") == spent, "cancel keeps")
	check(ui.confirm_take.text == "Take", "button text reset")
	ui.request_respec()
	check(ui.confirm_pending(true) and p.skills.el_spent("fire") == 0, "confirm refunds")
	s[0].free()
