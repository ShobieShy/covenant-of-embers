extends TestCase
## A conversation freezes the player who is talking. Their partner is not frozen.
## Advance and choices still run. Closing, or destroying the box, gives control back.


func _box(who: Player) -> Array:
	var r := DialogueRunner.new()
	var ui := DialogueUI.new()
	runner_tree.root.add_child(ui)
	ui.bind(r, who)
	return [r, ui]


func test_locks_only_the_talking_player() -> void:
	var talker := Player.new()
	var partner := Player.new()
	var box: Array = _box(talker)
	var r: DialogueRunner = box[0]
	var ui: DialogueUI = box[1]
	r.start("Bob")
	check(talker.dialogue_lock and talker.input_blocked(), "the talker is frozen")
	check(not partner.dialogue_lock and not partner.input_blocked(), "the partner is not")
	check(Interaction.prompt(talker) == "", "no interact prompt while talking")
	var echo := EchoMenu.new()
	echo.player = talker
	runner_tree.root.add_child(echo)
	echo.open("map")
	check(not echo.is_open() and not runner_tree.paused, "the Echo menu stays shut")
	var inv := InventoryUi.new()
	inv.player = talker
	runner_tree.root.add_child(inv)
	inv.open()
	check(not inv.is_open(), "the backpack stays shut")
	check(ui.press_interact() and r.active, "Interact still advances the line")
	var guard := 0
	while r.active and not r.awaiting_choice() and guard < 20:
		ui.press_interact()
		guard += 1
	check(r.awaiting_choice() and ui.button_texts().size() == 2, "choices still appear")
	check(r.choose(1), "a choice still selects")
	while r.active and guard < 40:
		if r.awaiting_choice():
			r.choose(0)
		else:
			r.advance()
		guard += 1
	check(not r.active and not talker.dialogue_lock and not talker.ui_open, "closing gives control back")
	talker.ui_open = true
	r.start("Bored Guard")
	check(talker.dialogue_lock and talker.ui_open, "a menu that was already open stays noted")
	ui.free()
	check(not talker.dialogue_lock and talker.ui_open, "destroying the box unlocks, and restores the menu")
	partner.free()
	talker.free()
	echo.free()
	inv.free()
