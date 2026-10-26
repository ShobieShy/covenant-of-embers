extends TestCase
## Step 31 done check: assembling through the station screen produces the item.


func _setup() -> Array:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 300, 1800), 0.0)
	var st := AssemblyStation.new()
	runner_tree.root.add_child(st)
	st.global_position = Vector3(1, 300, 1800)
	var ui := StationUi.new()
	runner_tree.root.add_child(ui)
	ui.bind(p)
	return [p, st, ui]


func _part(id: String) -> WieldablePart:
	return WieldablePart.load_part(id).duplicate()


func test_assemble_via_ui() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: StationUi = s[2]
	Interaction.face(p, s[1])
	check(ui.nearest_station() == s[1], "station in reach")
	p.loadout.unequip(0)  # empty hands: this test drives the base by hand
	p.loadout.unequip(1)
	ui.open(s[1])
	check(p.ui_open and ui.visible, "open freezes the player")
	var base := WieldableInstance.load_base("apprentice_fire_staff")
	var parts := [_part("basic_fire_head"), _part("basic_exterior"), _part("basic_interior"), _part("basic_handle")]
	p.inventory.add(base)
	for part in parts:
		p.inventory.add(part)
	ui.pick(base)
	check(ui.base == base, "base slot")
	ui.pick(parts[0])
	check(ui.preview_text().is_empty(), "no preview while incomplete")
	check(" ".join(ui.errors()).contains("Exterior"), "error lists missing: %s" % ui.error_label.text)
	for i in range(1, 4):
		ui.pick(parts[i])
	check(ui.errors().is_empty(), "valid: %s" % ui.error_label.text)
	check(
		ui.preview_text().begins_with("[") and ui.preview_text().contains("Damage:"), "preview: %s" % ui.preview_text()
	)
	var w := ui.assemble()
	check(w != null and w.assembled and p.inventory.has(w), "assembled into the pack")
	check(p.inventory.size() == 1, "parts + base consumed")
	ui.pick(w)
	check(ui.disassemble_selected() and p.inventory.size() == 5, "disassemble returns 4 parts + base")
	ui.close()
	check(not p.ui_open, "close unfreezes")
	p.queue_free()
	s[1].queue_free()
	ui.queue_free()


func test_wand_disables_interior_and_charm() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: StationUi = s[2]
	ui.open(s[1])
	var wand := WieldableInstance.load_base("novice_arcane_wand")
	p.inventory.add(wand)
	ui.pick(wand)
	check(
		(
			ui.slot_buttons[WieldablePart.PartType.INTERIOR].disabled
			and ui.slot_buttons[WieldablePart.PartType.CHARM].disabled
		),
		"wand slots"
	)
	check(not ui.slot_buttons[WieldablePart.PartType.HANDLE].disabled, "wand handle optional")
	var interior := _part("basic_interior")
	p.inventory.add(interior)
	ui.pick(interior)
	check(not ui.parts.has(WieldablePart.PartType.INTERIOR), "interior refused for a wand")
	ui.close()
	p.queue_free()
	s[1].queue_free()
	ui.queue_free()


## Step 45: the station preview lists socketed gems.
func test_preview_lists_gems() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: StationUi = s[2]
	ui.open(s[1])
	var head := _part("basic_fire_head")
	head.gems = [ElementGem.make(ElementTable.Element.WATER)] as Array[ElementGem]
	ui.set_base(WieldableInstance.load_base("apprentice_fire_staff"))
	var parts := [head, _part("basic_exterior"), _part("basic_interior"), _part("basic_handle")]
	for part in parts:
		ui.set_part(part.part_type, part)
	var t := ui.preview_text()
	check(t.contains("Gems: ") and t.contains("Water"), "gem line: %s" % t)
	check(t.contains("+1 damage"), "gem damage shown")
	ui.close()
	p.queue_free()
	s[1].queue_free()
	ui.queue_free()


## t60u: opening the station puts the staff in hand in as the base; closing returns it
## (or what it was built into) to the hand. Never lost, never duplicated.
func test_held_staff_auto_loads_and_returns() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: StationUi = s[2]
	p.loadout.unequip(1)
	var held := WieldableInstance.load_base("apprentice_fire_staff")
	p.equip(held)
	check(p.loadout.wieldable() == held, "holding a bare staff")
	ui.open(s[1])
	check(ui.base == held and p.inventory.has(held) and p.loadout.wieldable(0) == null, "held staff is the base")
	ui.close()
	check(p.loadout.wieldable(0) == held and not p.inventory.has(held), "cancel: back in hand, not duplicated")
	var parts := [_part("basic_fire_head"), _part("basic_exterior"), _part("basic_interior"), _part("basic_handle")]
	for part in parts:
		p.inventory.add(part)
	ui.open(s[1])
	for part in parts:
		ui.pick(part)
	var w := ui.assemble()
	check(w != null and w.assembled, "built from the auto-loaded base: %s" % ui.status.text)
	ui.close()
	check(p.loadout.wieldable(0) == w and p.inventory.size() == 0, "the new staff is in hand, nothing left over")
	ui.open(s[1])
	check(ui.selected == w and p.inventory.has(w), "assembled staff loaded for Disassemble")
	check(
		ui.disassemble_selected() and ui.base != null and ui.chosen_parts().size() == 4, "disassemble refills the slots"
	)
	ui.close()
	check(p.loadout.wieldable(0) == ui.base or p.loadout.wieldable(0) != null, "bare base back in hand")
	check(p.inventory.size() == 4, "4 parts in the pack, base in hand: %d" % p.inventory.size())
	p.queue_free()
	s[1].queue_free()
	ui.queue_free()


func test_full_backpack_keeps_staff_in_hand() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: StationUi = s[2]
	var held := WieldableInstance.load_base("apprentice_fire_staff")
	p.equip(held)
	p.loadout.active = 0
	while not p.inventory.is_full():
		p.inventory.add(_part("basic_handle"))
	ui.open(s[1])
	check(
		p.loadout.wieldable(0) == held and ui.base == null and ui.status.text.contains("full"),
		"full pack: stays in hand"
	)
	ui.close()
	check(p.loadout.wieldable(0) == held, "still in hand")
	p.queue_free()
	s[1].queue_free()
	ui.queue_free()
