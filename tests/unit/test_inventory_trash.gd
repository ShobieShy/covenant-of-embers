extends TestCase
## t74u: trashing items from the inventory screen (removal, quest-item block, worn gear,
## Rare+ confirm, potion quantity, junk + sell all junk, no duplication).


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


func _codes(p: Player) -> Array:
	var out := []
	for it in p.inventory.items:
		out.append(ItemCodes.encode(it))
	return out


func test_trash_removes_once_without_duplication() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	var a := _hat("basic", 1)
	var b := _hat("basic", 2)
	p.inventory.add(a)
	p.inventory.add(b)
	var before := p.inventory.size()
	ui.select(a)
	check(ui.request_trash(a), "basic item trashed without a confirm")
	check(p.inventory.size() == before - 1 and not p.inventory.has(a), "removed from the backpack")
	check(p.inventory.has(b), "the other item stays")
	check(p.trash_item(a) != "", "trashing it again fails")
	check(p.inventory.size() == before - 1, "no second removal")
	check(not JSON.stringify(SaveGame.capture(p)).contains(ItemCodes.encode(a)), "not in the save")
	check(not _codes(p).has(ItemCodes.encode(a)), "no copy left in the backpack")
	p.queue_free()
	ui.queue_free()


func test_quest_items_and_worn_gear_blocked() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	p.quest_items.append("joes_trash")
	ui.select("joes_trash")
	check(not ui.request_trash("joes_trash"), "quest item refused")
	check(p.quest_items.has("joes_trash"), "quest item kept")
	check(ui.status.text.contains("Quest"), "says why: %s" % ui.status.text)
	var h := _hat("basic", 3)
	p.inventory.add(h)
	p.equip_from_inventory(h)
	check(p.trash_item(h) == "Unequip it first.", "worn gear refused")
	check(p.equipment.item(EquipmentItem.Slot.HAT) == h, "still worn")
	p.queue_free()
	ui.queue_free()


func test_rare_confirm_and_potion_quantity() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	var r := _hat("rare", 4)
	p.inventory.add(r)
	ui.select(r)
	check(not ui.request_trash(r) and ui.confirm_row.visible, "rare asks first")
	ui.cancel_trash()
	check(p.inventory.has(r), "Keep keeps it")
	ui.request_trash(r)
	check(ui.confirm_trash() and not p.inventory.has(r), "confirm trashes it")
	var pot := ConsumableItem.load_item("health_potion")
	check(pot != null, "a potion resource")
	if pot:
		p.equipment.potion = null
		p.equipment.potion_count = 0
		p.equipment.add_potions(pot, 3)
		var n0 := p.equipment.potion_count
		ui.select(pot)
		ui.qty.value = 2
		check(ui.request_trash(pot), "potions trashed")
		check(p.equipment.potion_count == n0 - 2, "only 2 of %d gone" % n0)
	p.queue_free()
	ui.queue_free()


func test_junk_sold_together_and_saved() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	var a := _hat("basic", 5)
	var b := _hat("basic", 6)
	var c := _hat("basic", 7)
	for it in [a, b, c]:
		p.inventory.add(it)
	ui.select(a)
	check(ui.toggle_junk(), "marked a")
	ui.select(c)
	ui.toggle_junk()
	var v := Vendor.new()
	var g0 := p.inventory.gold
	var earned := v.sell_junk(p.inventory)
	check(earned == Vendor.sell_price(a) + Vendor.sell_price(c), "paid for both junk items")
	check(p.inventory.gold == g0 + earned, "gold added once")
	check(p.inventory.has(b) and not p.inventory.has(a) and not p.inventory.has(c), "only junk sold")
	check(v.sell_junk(p.inventory) == 0, "nothing left to sell")
	ui.select(b)
	ui.toggle_junk()
	var data := SaveGame.capture(p)
	p.inventory.junk.clear()
	SaveGame.apply(p, data)
	check(p.inventory.junk_items().size() == 1, "junk mark survives save/load")
	var old := data.duplicate(true)
	check(old.has("items"), "save has an items block")
	if old.has("items"):
		old["items"].erase("junk")
		SaveGame.apply(p, old)
		check(p.inventory.junk_items().is_empty() and p.inventory.size() > 0, "old saves load without junk")
	p.queue_free()
	ui.queue_free()


func test_favorite_excludes_junk_and_clears_on_remove() -> void:
	var s := _setup()
	var p: Player = s[0]
	var a := _hat("basic", 11)
	var b := _hat("basic", 12)
	p.inventory.add(a)
	check(not p.inventory.set_favorite(_hat("basic", 99), true), "not in the backpack")
	check(p.inventory.set_favorite(a, true) and p.inventory.is_favorite(a), "favorite reads back")
	check(
		p.inventory.set_junk(a, true) and p.inventory.is_junk(a) and not p.inventory.is_favorite(a),
		"junk clears favorite"
	)
	check(
		p.inventory.set_favorite(a, true) and p.inventory.is_favorite(a) and not p.inventory.is_junk(a),
		"favorite clears junk"
	)
	p.inventory.add(b)
	p.inventory.set_junk(b, true)
	check(p.inventory.remove(a) and p.inventory.remove(b), "removed")
	check(p.inventory.junk.is_empty() and p.inventory.favorite.is_empty(), "remove drops both marks")
	p.inventory.add(a)
	p.inventory.add(b)
	check(not p.inventory.is_favorite(a) and not p.inventory.is_junk(b), "putting them back is unmarked")
	p.queue_free()
	s[1].queue_free()


func test_marks_round_trip_json_and_replace_stale() -> void:
	var s := _setup()
	var p: Player = s[0]
	var a := _hat("basic", 21)
	var b := _hat("basic", 22)
	var c := _hat("basic", 23)
	p.inventory.add(a)
	p.inventory.add(b)
	p.inventory.add(c)
	p.inventory.set_junk(a, true)
	p.inventory.set_favorite(c, true)
	var path := "user://test_marks.json"
	check(SaveGame.write(SaveGame.capture(p), path) == OK, "written")
	var read := SaveGame.read(path)
	check(not read.has("error"), "read (%s)" % read.get("error", ""))
	check(SaveGame.VERSION == 1, "save version stays 1")
	p.inventory.junk.clear()
	p.inventory.favorite.clear()
	p.inventory.set_junk(b, true)
	p.inventory.set_favorite(a, true)
	SaveGame.apply(p, read["data"])
	check(
		p.inventory.is_junk(p.inventory.items[0]) and not p.inventory.is_favorite(p.inventory.items[0]), "slot 0 junk"
	)
	check(
		not p.inventory.is_junk(p.inventory.items[1]) and not p.inventory.is_favorite(p.inventory.items[1]),
		"slot 1 plain"
	)
	check(
		p.inventory.is_favorite(p.inventory.items[2]) and not p.inventory.is_junk(p.inventory.items[2]),
		"slot 2 favorite"
	)
	check(p.inventory.junk.size() == p.inventory.junk_items().size(), "no stale junk refs")
	check(p.inventory.favorite.size() == p.inventory.favorite_items().size(), "no stale favorite refs")
	var both: Dictionary = (read["data"] as Dictionary).duplicate(true)
	both["items"]["junk"] = [0.0, 1.0]
	both["items"]["favorite"] = [1.0]
	SaveGame.apply(p, both)
	check(p.inventory.is_junk(p.inventory.items[0]), "float index 0 is junk")
	check(
		p.inventory.is_favorite(p.inventory.items[1]) and not p.inventory.is_junk(p.inventory.items[1]),
		"both lists: favorite wins"
	)
	var old: Dictionary = both.duplicate(true)
	old["items"].erase("junk")
	old["items"].erase("favorite")
	SaveGame.apply(p, old)
	check(
		p.inventory.junk.is_empty() and p.inventory.favorite.is_empty() and p.inventory.size() == 3,
		"missing keys load unmarked"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	p.queue_free()
	s[1].queue_free()


## 0.3.1 P6 (M6): Keep is the default focus, pad Y trashes on a hold, Undo puts it back.
func test_keep_focus_pad_hold_and_undo() -> void:
	var s := _setup()
	var p: Player = s[0]
	var ui: InventoryUi = s[1]
	ui.open()
	var r := _hat("rare", 7)
	p.inventory.add(r)
	ui.select(r)
	ui.request_trash(r)
	check(ui.keep_button.has_focus(), "the confirm focuses Keep")
	ui.cancel_trash()
	var b := _hat("basic", 8)
	p.inventory.add(b)
	ui.select(b)
	ui.pad_hold = 0.0
	ui.tick(0.2, true)
	check(p.inventory.has(b) and ui.pad_hold_progress() > 0.0, "a short hold does nothing yet")
	ui.tick(0.2, false)
	check(p.inventory.has(b) and ui.pad_hold < 0.0, "letting go cancels")
	ui.pad_hold = 0.0
	for i in 4:
		ui.tick(0.15, true)
	check(not p.inventory.has(b), "a full hold trashes")
	check(ui.undo_row.visible and ui.undo_left > 0.0, "Undo toast up")
	check(ui.undo_trash() and p.inventory.has(b), "Undo puts it back")
	check(not ui.undo_row.visible and not ui.undo_trash(), "one undo only")
	ui.select(b)
	ui.request_trash(b)
	ui.tick(InventoryUi.UNDO_S + 0.1, false)
	check(not ui.undo_row.visible and not ui.undo_trash(), "undo expires after UNDO_S")
	check(not p.inventory.has(b), "still gone")
	var pot := ConsumableItem.load_item("health_potion")
	if pot:
		p.equipment.potion = null
		p.equipment.potion_count = 0
		p.equipment.add_potions(pot, 3)
		ui.select(pot)
		ui.qty.value = 3
		ui.request_trash(pot)
		check(p.equipment.potion == null, "all potions gone")
		check(ui.undo_trash() and p.equipment.potion_count == 3, "potions come back (3)")
	ui.close()
	p.queue_free()
	ui.queue_free()
