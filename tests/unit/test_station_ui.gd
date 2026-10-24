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
	check(ui.nearest_station() == s[1], "station in reach")
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
	check(ui.preview_text().begins_with("[") and ui.preview_text().contains("Damage:"), "preview: %s" % ui.preview_text())
	var w := ui.assemble()
	check(w != null and w.assembled and p.inventory.has(w), "assembled into the pack")
	check(p.inventory.size() == 1, "parts + base consumed")
	ui.pick(w)
	check(ui.disassemble_selected() and p.inventory.size() == 5, "disassemble returns 4 parts + base")
	ui.close()
	check(not p.ui_open, "close unfreezes")
	p.queue_free(); s[1].queue_free(); ui.queue_free()

func test_wand_disables_interior_and_charm() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: StationUi = s[2]
	ui.open(s[1])
	var wand := WieldableInstance.load_base("novice_arcane_wand")
	p.inventory.add(wand)
	ui.pick(wand)
	check(ui.slot_buttons[WieldablePart.PartType.INTERIOR].disabled and ui.slot_buttons[WieldablePart.PartType.CHARM].disabled, "wand slots")
	check(not ui.slot_buttons[WieldablePart.PartType.HANDLE].disabled, "wand handle optional")
	var interior := _part("basic_interior")
	p.inventory.add(interior)
	ui.pick(interior)
	check(not ui.parts.has(WieldablePart.PartType.INTERIOR), "interior refused for a wand")
	ui.close()
	p.queue_free(); s[1].queue_free(); ui.queue_free()
