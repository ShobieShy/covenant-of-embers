class_name Vendor
extends RefCounted
## Shops (BUILD_PLAN steps 60-61; PLAN §11 roles with Magewar gold). Three Eldoria vendors:
##  - SUPPLIES (the Potion Merchant): potions + Basic/Uncommon parts;
##  - GEAR (the Tailor): equipment, Basic..Rare;
##  - REROLL (the Runesmith): re-rolls a rolled part's bonuses for gold + Arcane Dust, keeping
##    its type, rarity, element and gems (a new roll seed, so Ember Mark codes stay valid).
## Stock is seeded by (vendor id, day) and restocks when the day changes. Buy price =
## BASE x rarity step; sell = a quarter of that.

enum Role { SUPPLIES, GEAR, REROLL }

const BASE := 20  ## gold for a Basic part / item
const TIER_MULT: Array[int] = [1, 2, 5, 12, 30, 60]  ## basic..unique
const SELL_DIV := 4
const POTION_PRICE := 15
const STOCK_SIZE := 6
const REROLL_GOLD := 30  ## x tier step
const REROLL_DUST := 5  ## x (tier + 1)
const SPEAKERS := {"Potion Merchant": Role.SUPPLIES, "Tailor": Role.GEAR, "Runesmith": Role.REROLL}

var role: Role
var id := ""
var day := -1
var stock: Array = []  ## [{item: Resource, price: int, count: int}]


static func for_speaker(speaker: String) -> Vendor:
	if not SPEAKERS.has(speaker):
		return null
	var v := Vendor.new()
	v.role = SPEAKERS[speaker]
	v.id = speaker.to_snake_case()
	return v


static func tier_of(item: Resource) -> int:
	var r := ""
	if item is WieldablePart or item is EquipmentItem:
		r = String(item.get("rarity"))
	elif item is WieldableInstance:
		r = (item as WieldableInstance).rarity_id()
	return clampi(Rarity.parse(r), 0, Rarity.COUNT - 1)


static func price_of(item: Resource) -> int:
	if item is ConsumableItem:
		return POTION_PRICE
	return BASE * TIER_MULT[tier_of(item)]


static func sell_price(item: Resource) -> int:
	return maxi(1, price_of(item) / SELL_DIV)


static func reroll_cost(part: WieldablePart) -> Dictionary:
	var t := tier_of(part)
	return {"gold": REROLL_GOLD * TIER_MULT[t], "dust": REROLL_DUST * (t + 1)}


## Rebuilds the stock for `d` (same id + day = same stock); no-op when it's already that day.
func restock(d: int) -> void:
	if d == day:
		return
	day = d
	stock.clear()
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s:%d" % [id, d])
	match role:
		Role.SUPPLIES:
			for pid in ["health_potion", "mana_potion"]:
				var c := ConsumableItem.load_item(pid)
				if c:
					stock.append({"item": c, "price": POTION_PRICE, "count": -1})
			for i in STOCK_SIZE - stock.size():
				var t := (r.randi() % 5) as WieldablePart.PartType
				var p := PartRoller.roll(r, t, "basic" if r.randf() < 0.7 else "uncommon")
				if p:
					stock.append({"item": p, "price": price_of(p), "count": 1})
		Role.GEAR:
			for i in STOCK_SIZE:
				var rar: String = ["basic", "uncommon", "rare"][mini(2, int(r.randf() * r.randf() * 3.5))]
				var it := EquipmentRoller.roll(r, r.randi() % EquipmentItem.SLOT_COUNT, rar)
				if it:
					stock.append({"item": it, "price": price_of(it), "count": 1})


## "" on success, else why not. Potions go to the quick slot, the rest to the backpack.
func buy(p: Player, i: int) -> String:
	if i < 0 or i >= stock.size():
		return "Nothing there."
	var s: Dictionary = stock[i]
	var price := Archetype.discounted(int(s["price"]), p.archetype)  # step 73: the Gal's discount
	if p.inventory.gold < price:
		return "Not enough gold."
	var item: Resource = s["item"]
	if item is ConsumableItem:
		if p.equipment.add_potions(item, 1) <= 0:
			return "Your potion slot is full."
	elif p.inventory.is_full():
		return PickupCollector.HINT_FULL
	else:
		p.inventory.add(item)
	p.inventory.spend_gold(price)
	if int(s["count"]) > 0:
		stock.remove_at(i)
	return ""


## Sells a backpack item for sell_price(); "" on success.
func sell(inv: Inventory, item: Resource) -> String:
	if item == null or not inv.has(item):
		return "Choose something in your backpack."
	inv.remove(item)
	inv.add_gold(sell_price(item))
	return ""


## Runesmith: new roll for a rolled loose part; "" on success. `seed_rng` draws the new seed.
func reroll(inv: Inventory, part: WieldablePart, seed_rng: RandomNumberGenerator) -> String:
	if role != Role.REROLL:
		return "Only the Runesmith re-rolls parts."
	if part == null or not inv.has(part):
		return "Choose a loose part in your backpack."
	if part.roll_seed < 0:
		return "Hand-made parts can't be re-rolled."
	var c := reroll_cost(part)
	if inv.gold < c["gold"] or inv.dust < c["dust"]:
		return "Needs %d gold and %d Arcane Dust." % [c["gold"], c["dust"]]
	var n := PartRoller.from_seed(seed_rng.randi(), part.part_type, part.rarity, part.element)
	if n == null:
		return "That part can't be re-rolled."
	inv.spend_gold(c["gold"])
	inv.spend_dust(c["dust"])
	for prop in ["damage_bonus", "fire_rate_modifier", "accuracy_bonus", "handling_bonus", "roll_seed", "id"]:
		part.set(prop, n.get(prop))
	part.description = part.full_description()
	inv.changed.emit()
	return ""
