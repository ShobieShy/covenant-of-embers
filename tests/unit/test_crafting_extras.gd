extends TestCase
## Step 26 done check: dust amounts, tier cap (Unique is never reached by upgrading).
##  - salvage gives SALVAGE_DUST[tier] and returns socketed gems;
##  - upgrade costs UPGRADE_COST[tier], keeps seed/element/relative roll, raises stats and
##    gem slots; stops at Primordial; hand-made parts refuse; not enough dust refuses;
##  - gems: socket into free Head slots (wand cap 1), first gem sets the element, +1 dmg each;
##    templates are never mutated.

const P := WieldablePart.PartType
const E := ElementTable.Element


func test_salvage_dust() -> void:
	var inv := Inventory.new()
	var expect := 0
	for t in Rarity.COUNT:
		var part := PartRoller.from_seed(100 + t, P.HANDLE, Rarity.IDS[t], E.FIRE)
		inv.add(part)
		check(CraftingExtras.salvage(inv, part) == "", "salvage tier %d" % t)
		expect += CraftingExtras.SALVAGE_DUST[t]
	check(inv.dust == expect and expect == 97, "dust %d" % inv.dust)
	check(inv.size() == 0, "parts gone")
	check(CraftingExtras.salvage(inv, WieldablePart.new()) != "", "not in pack")


func test_upgrade_chain_and_cap() -> void:
	var inv := Inventory.new()
	var part := PartRoller.from_seed(4242, P.HEAD, "basic", E.WATER)
	inv.add(part)
	inv.add_dust(1000)
	var spent := 0
	var last_dmg := part.damage_bonus
	var lo := PartRoller.stat_range(P.HEAD, "basic", "damage_bonus")
	var rel := (part.damage_bonus - lo.x) / (lo.y - lo.x)
	for t in range(0, 4):
		var cost := CraftingExtras.upgrade_cost(part)
		check(cost == CraftingExtras.UPGRADE_COST[t], "cost tier %d" % t)
		check(CraftingExtras.upgrade(inv, part) == "", "upgrade from tier %d" % t)
		spent += cost
		check(
			part.rarity == Rarity.IDS[t + 1] and part.roll_seed == 4242 and part.element == E.WATER, "same seed/element"
		)
		check(part.damage_bonus > last_dmg, "damage grows")
		last_dmg = part.damage_bonus
		var r := PartRoller.stat_range(P.HEAD, part.rarity, "damage_bonus")
		check_near((part.damage_bonus - r.x) / (r.y - r.x), rel, 1e-4, "relative roll kept")
		check(inv.has(part), "same object in the pack")
	check(part.rarity == "primordial" and part.gem_slots == 3, "Primordial, 3 slots")
	check(CraftingExtras.upgrade_cost(part) == -1 and CraftingExtras.upgrade(inv, part) != "", "never to Unique")
	check(inv.dust == 1000 - spent and spent == 122, "dust spent %d" % spent)
	var poor := Inventory.new()
	var p2 := PartRoller.from_seed(7, P.EXTERIOR, "basic", E.FIRE)
	check(CraftingExtras.upgrade(poor, p2) != "" and p2.rarity == "basic", "not enough dust")
	var tmpl := WieldablePart.load_part("basic_handle")
	check(CraftingExtras.upgrade(inv, tmpl.duplicate()) != "", "hand-made refuses")


func test_gems() -> void:
	var inv := Inventory.new()
	var head := PartRoller.from_seed(99, P.HEAD, "rare", E.WATER)  # 2 slots
	var g1 := ElementGem.make(E.FIRE)
	var g2 := ElementGem.make(E.EARTH)
	var g3 := ElementGem.make(E.AIR)
	for g in [g1, g2, g3]:
		inv.add(g)
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	var w := Assembly.assemble(
		staff.def,
		[
			head,
			PartRoller.from_seed(1, P.EXTERIOR, "rare", E.FIRE),
			PartRoller.from_seed(2, P.INTERIOR, "rare", E.FIRE),
			PartRoller.from_seed(3, P.HANDLE, "rare", E.FIRE)
		]
	)
	check(w != null, "built")
	var dmg0 := w.damage()
	check(w.element() == E.WATER, "Head element before gems")
	check(CraftingExtras.socket(inv, head, g1, w) == "" and CraftingExtras.socket(inv, head, g2, w) == "", "2 gems")
	check(CraftingExtras.socket(inv, head, g3, w) != "", "no 3rd slot on a Rare head")
	check(w.element() == E.FIRE, "first gem sets the element")
	check_near(w.damage(), dmg0 + 2.0 * ElementGem.GEM_DAMAGE, 1e-4, "+1 dmg per gem")
	check(WieldablePart.load_part(PartRoller.TEMPLATE_IDS[P.HEAD]).gems.is_empty(), "template untouched")
	check(CraftingExtras.unsocket(inv, head, 0) == "" and inv.has(g1) and w.element() == E.EARTH, "unsocket")
	# Wand Heads use 1 slot.
	var wand := Assembly.assemble(
		WieldableInstance.load_base("swift_wind_wand").def,
		[PartRoller.from_seed(5, P.HEAD, "primordial", E.AIR), PartRoller.from_seed(6, P.EXTERIOR, "basic", E.AIR)]
	)
	var wh := wand.part(P.HEAD)
	check(
		CraftingExtras.socket(inv, wh, g1, wand) == "" and CraftingExtras.socket(inv, wh, g3, wand) != "",
		"wand: 1 slot"
	)
	# Salvage returns gems.
	inv.add(head)
	check(CraftingExtras.salvage(inv, head) == "" and inv.has(g2), "salvage returns the gem")
