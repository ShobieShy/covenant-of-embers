extends TestCase
## Step 24 done check: inventory capacity; equip/unequip from the backpack updates stats.
##  - 30 slots, add/remove, no duplicates, only backpack item types, dust counter;
##  - equip_from_inventory: gear -> Equipment (bonuses applied, replaced piece back in the
##    backpack), staff/wand -> Loadout slot (replacing the one in hand starts a draw);
##  - unequip to the backpack restores the stats; refused (with a hint) when full;
##  - R (use_potion) drinks the quick-slot potion.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const S := EquipmentItem.Slot

func _player() -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 200, 900), 0.0)
	return p

func test_capacity_and_types() -> void:
	var inv := Inventory.new()
	check(inv.capacity == 30 and inv.free_slots() == 30, "30 slots")
	var part := WieldablePart.new()
	check(inv.add(part) and not inv.add(part), "no duplicates")
	check(not inv.add(null) and not inv.add(ConsumableItem.new()), "only backpack types")
	for i in 29:
		check(inv.add(EquipmentItem.new()), "fill %d" % i)
	check(inv.is_full() and not inv.add(WieldablePart.new()), "full at 30")
	check(inv.remove(part) and inv.free_slots() == 1, "remove frees a slot")
	inv.add_dust(12)
	check(inv.spend_dust(5) and not inv.spend_dust(8) and inv.dust == 7, "dust")

func test_equip_unequip_updates_stats() -> void:
	var p := _player()
	var base_mana := p.mana.max_value()
	var base_speed := p.speed_multiplier
	var robes := EquipmentItem.load_item("basic_robes")
	var shoes := EquipmentItem.load_item("traveler_shoes")
	p.inventory.add(robes)
	p.inventory.add(shoes)
	check(p.equip_from_inventory(robes) and p.equip_from_inventory(shoes), "equip gear")
	check(p.inventory.size() == 0, "moved out of the backpack")
	check_near(p.mana.max_value(), base_mana + robes.mana_bonus + shoes.mana_bonus, 1e-4, "mana bonus")
	check_near(p.speed_multiplier, base_speed * shoes.speed_modifier, 1e-4, "shoes speed")
	# Replacing a worn piece sends the old one back.
	var shoes2 := shoes.duplicate() as EquipmentItem
	shoes2.speed_modifier = 1.3
	p.inventory.add(shoes2)
	check(p.equip_from_inventory(shoes2) and p.inventory.has(shoes) and not p.inventory.has(shoes2), "swap back")
	check_near(p.speed_multiplier, base_speed * 1.3, 1e-4, "new shoes speed")
	check(p.unequip_item_to_inventory(S.SHOES) and p.unequip_item_to_inventory(S.CLOTHES), "unequip")
	check_near(p.mana.max_value(), base_mana, 1e-4, "mana back")
	check_near(p.speed_multiplier, base_speed, 1e-4, "speed back")
	check(not p.equip_from_inventory(WieldablePart.new()), "parts can't be equipped")
	p.queue_free()

func test_wieldables_and_draw() -> void:
	var p := _player()
	var staff := WieldableInstance.load_base("novice_arcane_wand")
	var wind := WieldableInstance.load_base("swift_wind_wand")
	p.inventory.add(staff)
	p.inventory.add(wind)
	check(p.equip_from_inventory(staff), "equip wand")
	check(p.caster.wieldable == staff and not p.loadout.swapping(), "empty hands: drawn at once")
	check(p.equip_from_inventory(wind), "replace the wand in hand")
	check(p.caster.wieldable == wind and p.loadout.swapping(), "replacing in hand starts a draw")
	check(p.inventory.has(staff) and not p.inventory.has(wind), "old wand back in the pack")
	check(p.unequip_wieldable_to_inventory(Loadout.Slot.WAND) and p.caster.wieldable == null, "unequip wand")
	# Full backpack refuses unequip.
	p.equip_from_inventory(staff)
	while not p.inventory.is_full():
		p.inventory.add(WieldablePart.new())
	check(not p.unequip_wieldable_to_inventory(Loadout.Slot.WAND) and p.caster.wieldable == staff, "full: refused")
	check(p.last_hint == PickupCollector.HINT_FULL, "full hint")
	p.queue_free()

func test_use_potion_key() -> void:
	var p := _player()
	check(InputMap.has_action(&"use_potion"), "use_potion action bound")
	p.equipment.add_potions(ConsumableItem.load_item("mana_potion"), 2)
	p.mana.value = 10.0
	p.tick(PlayerInput.hold([&"use_potion"], [&"use_potion"]), DT)
	check(p.equipment.potion_count == 1 and p.mana.value > 10.0, "R drinks a potion")
	p.queue_free()
