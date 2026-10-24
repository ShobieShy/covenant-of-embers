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
