extends TestCase
## t61u: a distinct icon per item type; t60u: in-game screens get the pixel theme and 4 px slots.


func _all_types() -> Array:
	var items: Array = []
	items.append(WieldableInstance.load_base("apprentice_fire_staff"))
	for t in WieldablePart.PartType.values():
		items.append(WieldablePart.make(t))
	for s in EquipmentItem.Slot.values():
		var e := EquipmentItem.new()
		e.slot = s
		items.append(e)
	items.append(ElementGem.make(ElementTable.Element.FIRE))
	for c in ConsumableItem.list_ids():
		items.append(ConsumableItem.load_item(c))
	return items


func test_every_type_has_a_loadable_icon() -> void:
	for it in _all_types():
		check(ItemIcons.for_item(it) != null, "icon for %s (%s)" % [it, ItemIcons.path_for(it)])
	check(ItemIcons.for_item(null) == null, "no icon for an empty slot")


func test_types_are_distinct() -> void:
	var seen := {}
	for it in _all_types():
		if it is ConsumableItem or it is WieldableInstance:
			continue  # potions share by attribute; one staff base
		var p := ItemIcons.path_for(it)
		check(not seen.has(p), "%s reuses %s" % [it, p])
		seen[p] = true
	var staff := ItemIcons.path_for(WieldableInstance.load_base("apprentice_fire_staff"))
	var wand := ItemIcons.path_for(WieldableInstance.load_base("swift_wind_wand"))
	check(staff != wand and not seen.has(staff) and not seen.has(wand), "staff and wand icons differ")


func test_in_game_ui_inherits_pixel_theme() -> void:
	UiTheme.apply(runner_tree.root)
	var ui := InventoryUi.new()
	runner_tree.root.add_child(ui)
	var slot: Button = ui.slot_buttons[0]
	var sb := slot.get_theme_stylebox(&"normal") as StyleBoxTexture
	check(sb != null, "slot stylebox is the pixel texture, not the default flat box")
	check(sb.texture_margin_left == UiTheme.SLOT_MARGIN, "4 px slot 9-slice margin")
	check(ui.root.get_theme_stylebox(&"panel") is StyleBoxTexture, "panel is themed under a CanvasLayer")
	ui.queue_free()
