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
	p.queue_free()
	ui.queue_free()


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
	p.queue_free()
	ui.queue_free()


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
	check(
		copy != null and copy.display_name == h.display_name and is_equal_approx(copy.health_bonus, h.health_bonus),
		"same item"
	)
	check(not ui.import_code("garbage!!") and ui.status.text.begins_with("Bad Ember Mark"), "bad code refused")
	p.queue_free()
	ui.queue_free()


## Step 45: cards list gems (element colour) and consecrations with a delta line.
func test_card_gems_and_consecration() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	var head := WieldablePart.load_part("basic_fire_head").duplicate() as WieldablePart
	head.gems = [ElementGem.make(ElementTable.Element.DARK)] as Array[ElementGem]
	var t := ui.card_text(head)
	var dark := ElementTable.load_default().color(ElementTable.Element.DARK).to_html(false)
	check(t.contains("Gems: [color=#%s]Dark" % dark), "gem in element colour: %s" % t)
	var a := _hat("rare", 3)
	a.consecration = "reaping"
	t = ui.card_text(a)
	check(t.contains("Consecrated: Reaping") and t.contains("Kills restore 10 mana"), "consecration line: %s" % t)
	p.equip_item(a)
	var b := _hat("rare", 4)
	b.consecration = "kindling"
	check(ui.card_text(b).contains("(replaces Reaping)"), "replaces delta")
	var c := _hat("rare", 5)
	check(ui.card_text(c).contains("(loses Reaping)"), "loses delta")
	check(not ui.card_text(_hat("rare", 6)).contains("Gems:"), "no gem line without gems")
	p.queue_free()
	ui.queue_free()


## t60u: every worn slot can be unequipped, the staff and wand included.
func test_unequip_everything() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	p.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	p.equip(WieldableInstance.load_base("swift_wind_wand"))
	p.equip_item(_hat("basic", 3))
	var worn: Array = []
	for i in 2 + EquipmentItem.SLOT_COUNT:
		if ui._worn(i):
			worn.append(ui._worn(i))
	check(worn.size() >= 3, "staff, wand and a hat worn")
	var before := p.inventory.size()
	for it in worn:
		ui.select(it)
		check(ui.unequip_selected(), "unequipped %s" % InventoryUi.name_of(it))
		check(p.inventory.has(it), "in the backpack")
	check(p.loadout.wieldable(0) == null and p.loadout.wieldable(1) == null, "hands empty")
	check(p.inventory.size() == before + worn.size(), "nothing lost or duplicated")
	ui.select(worn[0])
	check(not ui.unequip_selected(), "a backpack item can't be unequipped")
	check(ui.equip_selected() and p.loadout.wieldable(0) == worn[0], "re-equip works")
	p.queue_free()
	ui.queue_free()
