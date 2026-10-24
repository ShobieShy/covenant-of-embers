extends TestCase
## Step 30 done check: equip from the backpack, compare deltas, Ember Mark copy -> import.

const DT := 1.0 / 60.0

func _setup() -> Array:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 200, 1500), 0.0)
	var ui := InventoryUi.new()
	runner_tree.root.add_child(ui)
	ui.bind(p)
	return [p, ui]

func _hat(rarity: String, seed_: int) -> EquipmentItem:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	return EquipmentRoller.roll(rng, EquipmentItem.Slot.HAT, rarity)

func test_open_close_freezes_player() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	check(ui.layer > 2 and not ui.visible, "starts hidden above the HUD")
	var ev := InputEventAction.new()
	ev.action = InventoryUi.ACTION
	ev.pressed = true
	ui._unhandled_input(ev)
	check(ui.is_open() and p.ui_open, "Tab opens and freezes the player")
	ui.toggle()
	check(not ui.is_open() and not p.ui_open, "toggle closes")
	p.queue_free(); ui.queue_free()

func test_equip_and_compare() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	var a := _hat("basic", 1)
	var b := _hat("mythic", 2)
	p.inventory.add(a)
	p.inventory.add(b)
	ui.open()
	check(ui.slot_buttons[0].text == a.display_name, "grid shows items")
	check(ui.slot_buttons[1].modulate.is_equal_approx(b.rarity_color()), "rarity tint")
	ui.select(a)
	check(ui.equip_selected(), "equip")
	check(p.equipment.item(EquipmentItem.Slot.HAT) == a and not p.inventory.has(a), "worn, out of pack")
	check(ui.worn_buttons[2].text.contains(a.display_name), "worn panel")
	ui.select(b)
	var t := ui.card_text(b)
	check(t.contains("vs %s" % a.display_name), "compare against worn: %s" % t)
	check(t.contains("(+") or t.contains("(-"), "has deltas")
	check(ui.equip_selected() and p.inventory.has(a), "swap puts old back in the pack")
	p.queue_free(); ui.queue_free()

func test_ember_mark_round_trip() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	var h := _hat("rare", 7)
	p.inventory.add(h)
	ui.select(h)
	var code := ui.copy_selected()
	check(not code.is_empty() and ui.code_field.text == code, "copied '%s'" % code)
	check(ui.import_code(code), "import: %s" % ui.status.text)
	check(p.inventory.size() == 2, "pack has the copy")
	var copy := p.inventory.at(1) as EquipmentItem
	check(copy != null and copy.display_name == h.display_name and is_equal_approx(copy.health_bonus, h.health_bonus), "same item")
	check(not ui.import_code("garbage!!") and ui.status.text.begins_with("Bad Ember Mark"), "bad code refused")
	p.queue_free(); ui.queue_free()
