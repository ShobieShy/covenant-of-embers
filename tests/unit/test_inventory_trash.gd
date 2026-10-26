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
	old["items"].erase("junk") if old.has("items") else null
	if old.has("items"):
		SaveGame.apply(p, old)
		check(p.inventory.junk_items().is_empty() and p.inventory.size() > 0, "old saves load without junk")
	p.queue_free()
	ui.queue_free()
