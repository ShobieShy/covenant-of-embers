extends TestCase
## Step 39 done check: scene flow headless. Menu -> new run (Midden); the gate travels to
## the Breach with an autosave; the game scene built for the Breach loads that state and
## gets the Breach logic; its gate leads back; the pause menu pauses / resumes / goes to
## the menu. GameFlow.dry_run records the scene changes instead of making them.

const FILE := "user://test_flow_save.json"


func _reset() -> void:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.last_request = ""


func _restore() -> void:
	GameFlow.dry_run = false
	GameFlow.save_path = SaveGame.PATH
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	runner_tree.paused = false
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


func _game(level: String, load_save: bool) -> Node:
	GameFlow.level_id = level
	GameFlow.load_save = load_save
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(5000, 0, 0) if level == "midden" else Vector3(-5000, 0, 0)
	runner_tree.root.add_child(g)
	return g


func test_menu_buttons() -> void:
	_reset()
	var m: MainMenu = (load(GameFlow.MENU) as PackedScene).instantiate()
	runner_tree.root.add_child(m)
	check((m.buttons["continue"] as Button).disabled, "continue greyed without a save")
	m.press("new_run")
	check(
		GameFlow.last_request == GameFlow.GAME and GameFlow.level_id == "midden" and not GameFlow.load_save,
		"new run -> Midden"
	)
	m.press("settings")
	check(m.settings_ui.visible, "settings opens")
	m.free()
	_restore()


func test_midden_to_breach_and_back() -> void:
	_reset()
	var g := _game("midden", false)
	check(GameFlow.id_of(g.get_node("Level")) == "midden" and g.breach == null, "Midden loaded, no Breach logic")
	var p := g.get_node("Player") as Player
	p.add_xp(300)
	var lvl := p.progression.level
	check(g.gate.target == "breach", "Midden gate leads to the Breach")
	g.gate.use()
	check(
		GameFlow.last_request == GameFlow.GAME and GameFlow.level_id == "breach" and GameFlow.load_save,
		"travel request"
	)
	check(GameFlow.has_save(), "autosaved on travel")
	g.free()
	var b := _game("breach", true)
	check(String(b.get_node("Level").get_meta("level_id", "")) == "breach_slice", "Breach level swapped in")
	check(b.breach != null and b.breach.chest != null, "Breach logic + vault chest")
	var bp := b.get_node("Player") as Player
	check(bp.progression.level == lvl and lvl > 1, "state carried over (level %d)" % bp.progression.level)
	check(b.load_warnings.is_empty(), "no load warnings")
	check(b.gate.target == "midden", "Breach gate leads back")
	b.gate.use()
	check(GameFlow.level_id == "midden", "back to the Midden")
	var r := SaveGame.read(FILE)
	check(r["data"]["progress"]["level_id"] == "midden", "save points at the Midden")
	b.free()
	m_continue()
	_restore()


func m_continue() -> void:
	check(
		GameFlow.continue_run(null) and GameFlow.level_id == "midden" and GameFlow.load_save, "continue uses the save"
	)


func test_pause_menu() -> void:
	_reset()
	var g := _game("midden", false)
	var pm: PauseMenu = g.pause_menu
	var p := g.get_node("Player") as Player
	var esc := InputEventAction.new()
	esc.action = &"menu"
	esc.pressed = true
	pm._unhandled_input(esc)
	check(pm.visible and runner_tree.paused and p.ui_open, "Esc pauses")
	pm.press("settings")
	check(pm.settings_ui.visible, "settings from pause")
	pm._unhandled_input(esc)
	check(not pm.settings_ui.visible and pm.visible, "Esc closes settings first")
	pm.press("resume")
	check(not pm.visible and not runner_tree.paused and not p.ui_open, "resume")
	p.ui_open = true  # e.g. the inventory is open: Esc is its, not the pause menu's
	pm._unhandled_input(esc)
	check(not pm.visible, "ignored while another screen is open")
	p.ui_open = false
	pm.open()
	pm.press("main_menu")
	check(GameFlow.last_request == GameFlow.MENU and not runner_tree.paused, "to the main menu, unpaused")
	check(GameFlow.has_save(), "saved on leaving")
	g.free()
	_restore()
