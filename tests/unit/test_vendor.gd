extends TestCase
## Steps 60-61 done check: buy/sell math, no overspending, daily restock, the three vendors'
## stock, and the Runesmith re-roll keeps type/rarity/element and stays code-valid.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _w: Node3D


func _player() -> Player:
	_w = Node3D.new()
	_w.position = Vector3(-7000, 0, 7000)
	runner_tree.root.add_child(_w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	_w.add_child(p)
	p.spawn(_w.global_position, 0.0)
	return p


func test_three_vendors_and_stock() -> void:
	check(Vendor.for_speaker("Bored Guard") == null, "not a vendor")
	var sup := Vendor.for_speaker("Potion Merchant")
	var gear := Vendor.for_speaker("Tailor")
	var rr := Vendor.for_speaker("Runesmith")
	sup.restock(100)
	gear.restock(100)
	rr.restock(100)
	check(sup.stock.size() == Vendor.STOCK_SIZE, "supplies stock %d" % sup.stock.size())
	check(sup.stock[0]["item"] is ConsumableItem and sup.stock[1]["item"] is ConsumableItem, "potions first")
	for s in sup.stock.slice(2):
		check(s["item"] is WieldablePart and Vendor.tier_of(s["item"]) <= 1, "basic/uncommon parts")
	check(gear.stock.size() == Vendor.STOCK_SIZE, "gear stock")
	for s in gear.stock:
		check(s["item"] is EquipmentItem and Vendor.tier_of(s["item"]) <= 2, "gear up to Rare")
	check(rr.stock.is_empty(), "the Runesmith sells nothing")
	var names := []
	for s in gear.stock:
		names.append(s["item"].display_name)
	var again := Vendor.for_speaker("Tailor")
	again.restock(100)
	var names2 := []
	for s in again.stock:
		names2.append(s["item"].display_name)
	check(names == names2, "same day, same stock")
	gear.stock.clear()
	gear.restock(100)
	check(gear.stock.is_empty(), "no restock within the day")
	gear.restock(101)
	check(gear.stock.size() == Vendor.STOCK_SIZE, "restocked the next day")


func test_prices() -> void:
	var a := PartRoller.from_seed(1, WieldablePart.PartType.HEAD, "basic")
	var b := PartRoller.from_seed(1, WieldablePart.PartType.HEAD, "rare")
	check(Vendor.price_of(a) == 20 and Vendor.sell_price(a) == 5, "basic 20 / sells 5")
	check(Vendor.price_of(b) == 100 and Vendor.sell_price(b) == 25, "rare 100 / sells 25")


func test_buy_sell() -> void:
	var p := _player()
	var v := Vendor.for_speaker("Potion Merchant")
	v.restock(7)
	var n := v.stock.size()
	var part_i := 2
	var part: Resource = v.stock[part_i]["item"]
	var price: int = v.stock[part_i]["price"]
	p.inventory.gold = price - 1
	check(v.buy(p, part_i) == "Not enough gold." and p.inventory.gold == price - 1, "can't overspend")
	p.inventory.gold = price + 15
	check(v.buy(p, part_i) == "" and p.inventory.has(part), "bought")
	check(p.inventory.gold == 15 and v.stock.size() == n - 1, "paid, one-off item gone")
	check(v.buy(p, 0) == "" and p.inventory.gold == 0 and v.stock.size() == n - 1, "potions never run out")
	check(p.equipment.potion_count == 1, "potion in the quick slot")
	check(v.sell(p.inventory, part) == "" and p.inventory.gold == Vendor.sell_price(part), "sold")
	check(v.sell(p.inventory, part) != "", "can't sell twice")
	_w.queue_free()


func test_reroll_keeps_rarity() -> void:
	var inv := Inventory.new()
	var rr := Vendor.for_speaker("Runesmith")
	var part := PartRoller.from_seed(42, WieldablePart.PartType.HEAD, "rare", ElementTable.Element.FIRE)
	inv.add(part)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var c := Vendor.reroll_cost(part)
	check(rr.reroll(inv, part, r) != "", "needs dust")
	inv.gold = c["gold"]
	inv.dust = c["dust"]
	var old_dmg := part.damage_bonus
	check(rr.reroll(inv, part, r) == "", "re-rolled")
	check(inv.gold == 0 and inv.dust == 0, "paid gold + dust")
	check(part.rarity == "rare" and part.element == ElementTable.Element.FIRE, "rarity/element kept")
	check(part.part_type == WieldablePart.PartType.HEAD and part.roll_seed != 42, "new seed")
	check(not is_equal_approx(part.damage_bonus, old_dmg), "stats changed")
	var regen := PartRoller.regenerate(part)
	check(is_equal_approx(regen.damage_bonus, part.damage_bonus), "still matches its seed")
	check(ItemCodes.encode(part) != "", "still code-valid: " + ItemCodes.encode_error(part))
	check(Vendor.for_speaker("Tailor").reroll(inv, part, r) != "", "only the Runesmith")
	var hand := WieldablePart.new()
	inv.add(hand)
	inv.gold = 999
	inv.dust = 999
	check(rr.reroll(inv, hand, r) != "", "hand-made refused")


func test_shop_screen() -> void:
	var p := _player()
	var ui := VendorUi.new()
	_w.add_child(ui)
	ui.bind(p)
	ui.open(Vendor.for_speaker("Tailor"))
	check(ui.visible and p.ui_open, "open")
	check(ui.stock_list.item_count == Vendor.STOCK_SIZE, "stock listed")
	check(not ui.reroll_button.visible, "no re-roll at the Tailor")
	p.inventory.gold = 100000
	ui.stock_list.select(0)
	check(ui.buy_selected() and p.inventory.size() == 1, "bought from the screen")
	ui.pack_list.select(0)
	check(ui.sell_selected() and p.inventory.size() == 0, "sold from the screen")
	ui.close()
	check(not p.ui_open, "closed")
	_w.queue_free()


func _hat(seed_: int, rarity: String) -> EquipmentItem:
	return EquipmentRoller.from_seed(seed_, EquipmentItem.Slot.HAT, rarity, ElementTable.Element.FIRE)


func test_bulk_sale_confirms_and_skips_favorites() -> void:
	var p := _player()
	var ui := VendorUi.new()
	_w.add_child(ui)
	ui.bind(p)
	var vendor := Vendor.for_speaker("Tailor")
	ui.open(vendor)
	var a := _hat(11, "basic")
	var b := _hat(12, "basic")
	var c := _hat(13, "rare")
	var plain := _hat(14, "basic")
	for it in [a, b, c, plain]:
		p.inventory.add(it)
	p.inventory.set_junk(a, true)
	p.inventory.set_junk(b, true)
	p.inventory.set_favorite(c, true)
	var g0 := p.inventory.gold
	var price := Vendor.sell_price(a) + Vendor.sell_price(b)
	check(not ui.sell_junk() and ui.confirm_row.visible and ui.keep_button.has_focus(), "junk asks, Keep focused")
	check(ui.confirm_label.text == "Sell 2 items for %d gold." % price, "count and gold: %s" % ui.confirm_label.text)
	ui.cancel_sale(true)
	check(not ui.confirm_row.visible and p.inventory.gold == g0 and p.inventory.size() == 4, "Keep changes nothing")
	check(ui.sell_junk_button.has_focus(), "focus returns to Sell all junk")
	ui.sell_junk()
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	ui._unhandled_input(cancel)
	check(ui.visible and p.ui_open and not ui.confirm_row.visible and p.inventory.gold == g0, "Esc leaves the shop")
	ui.sell_junk()
	check(ui.confirm_sale() and p.inventory.gold == g0 + price, "paid once")
	check(p.inventory.has(c) and p.inventory.has(plain) and not p.inventory.has(a), "only junk left the pack")
	var other := Inventory.new()
	other.gold = 3
	other.add(_hat(15, "basic"))
	p.inventory.set_favorite(plain, true)
	var locked_gold := p.inventory.gold
	check(not ui.sell_all() and ui.status.text == "Everything left is locked.", "all favorite")
	check(p.inventory.gold == locked_gold and other.gold == 3 and other.size() == 1, "no pay, other pack untouched")
	p.inventory.remove(plain)
	p.inventory.remove(c)
	check(not ui.sell_all() and ui.status.text == "Nothing to sell.", "empty pack")
	check(not ui.sell_junk() and ui.status.text == "Nothing marked as junk.", "no junk")
	var fav := _hat(16, "basic")
	p.inventory.add(fav)
	p.inventory.set_favorite(fav, true)
	ui.refresh()
	ui.pack_list.select(0)
	check(
		ui.sell_selected() and not ui.confirm_row.visible and not p.inventory.has(fav), "single Sell skips the confirm"
	)
	var gem := ElementGem.make(ElementTable.Element.FIRE)
	var rare := _hat(17, "rare")
	p.inventory.add(gem)
	p.inventory.add(rare)
	var worn := _hat(18, "basic")
	p.inventory.add(worn)
	check(p.equip_from_inventory(worn), "worn")
	p.quest_items.append("breach_key")
	var both := _hat(19, "basic")
	p.inventory.add(both)
	p.inventory.junk.append(both)
	p.inventory.favorite.append(both)
	check(vendor.sell_junk(p.inventory) == 0 and p.inventory.has(both), "a favorite stuck in junk is not sold")
	ui.sell_all()
	var expect := Vendor.sell_price(gem) + Vendor.sell_price(rare)
	check(
		ui.confirm_label.text.contains("Sell 2 items for %d gold." % expect), "gem and rare: %s" % ui.confirm_label.text
	)
	check(ui.confirm_label.text.contains("1 Rare or better") and ui.confirm_label.text.contains("1 gems"), "tally")
	check(Vendor.sell_price(gem) == 5, "gem sells at 5")
	vendor.sell_all(p.inventory)
	var gold_once := p.inventory.gold
	check(not ui.confirm_sale() and p.inventory.gold == gold_once, "accept after the rows are gone pays nothing")
	check(p.equipment.item(EquipmentItem.Slot.HAT) == worn, "worn hat stayed")
	check(p.quest_items.has("breach_key"), "quest id stayed")
	check(p.inventory.has(both), "favorite stayed")
	_w.queue_free()
