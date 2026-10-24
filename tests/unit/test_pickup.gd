extends TestCase
## Step 23 done check: walk-over collects, Interact picks the item.
##  - mana orbs / Arcane Dust / potions auto-collect when the player walks over them; a
##    mana orb waits while mana is full; potions that don't fit stay on the ground;
##  - Interact (F) puts the looked-at item pickup in the backpack, nothing outside the
##    look cone / reach; a full backpack refuses with a hint and the pickup stays;
##  - compare card rows carry deltas against the equipped item in the same slot.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _flat() -> Node3D:
	var w := Node3D.new()
	w.position = Vector3.ZERO  # pickups use global == local
	w.name = "PickupWorld"
	runner_tree.root.add_child(w)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(100, 1, 100)
	cs.shape = s
	b.add_child(cs)
	b.position = Vector3(0, -0.5, 0)
	w.add_child(b)
	return w


func _player(w: Node3D) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	return p


func _part_drop() -> LootDrop:
	var d := LootDrop.new()
	d.kind = LootDrop.Kind.PART
	var part := WieldablePart.new()
	part.id = "test_head"
	part.display_name = "Test Head"
	part.rarity = "rare"
	part.damage_bonus = 3.0
	d.item = part
	d.rarity_id = "rare"
	return d


func test_walk_over_collects() -> void:
	var w := _flat()
	var p := _player(w)
	p.tick(PlayerInput.hold([]), DT)
	var ahead := p.forward_for(0.0)
	var base := p.global_position
	p.mana.value = 40.0
	var orb := LootPickup.create_mana(25, base + ahead * 2.0)
	var dust := LootPickup.create_dust(7, base + ahead * 2.5)
	var mp := ConsumableItem.load_item("mana_potion")
	var pot := LootPickup.create_potion(mp, 7, base + ahead * 3.0)  # stack_size 5: 2 stay
	var far := LootPickup.create_dust(3, base + ahead * 20.0)
	for n in [orb, dust, pot, far]:
		w.add_child(n)
	check(not is_instance_valid(orb) or orb.is_inside_tree(), "orb placed")
	for i in 90:  # walk forward ~3.5 m
		p.tick(PlayerInput.hold([&"forward"]), DT)
		await runner_tree.physics_frame
	check(not is_instance_valid(orb) or not orb.is_inside_tree(), "orb collected")
	check(
		p.mana.value >= 65.0 - 1e-3 and p.mana.value <= 72.0, "orb restored 25 mana (+1.5 s regen): %.1f" % p.mana.value
	)
	check(p.inventory.dust == 7, "dust 7, got %d" % p.inventory.dust)
	check(p.equipment.potion_count == 5, "potion slot filled to 5, got %d" % p.equipment.potion_count)
	check(is_instance_valid(pot) and pot.is_inside_tree() and pot.amount == 2, "2 potions stay on the ground")
	check(is_instance_valid(far) and far.is_inside_tree(), "far dust not collected")
	check(p.pickups.auto_collected >= 3, "3 auto collects")
	# Mana orb waits while mana is full.
	p.mana.refill()
	var orb2 := LootPickup.create_mana(10, p.global_position)
	w.add_child(orb2)
	p.tick(PlayerInput.hold([]), DT)
	check(is_instance_valid(orb2) and orb2.is_inside_tree(), "orb waits at full mana")
	p.mana.value = p.mana.max_value() - 20.0
	p.tick(PlayerInput.hold([]), DT)
	check(not is_instance_valid(orb2) or not orb2.is_inside_tree(), "orb taken once mana is down")
	w.queue_free()


func test_interact_picks_item() -> void:
	var w := _flat()
	var p := _player(w)
	p.tick(PlayerInput.hold([]), DT)
	var eye := p.eye_position()
	var dir := p.look_direction().normalized()
	var d := _part_drop()
	var target := LootPickup.create(d, eye + dir * 2.0 - Vector3(0, LootPickup.GEM_SIZE * 0.5, 0))
	var side := LootPickup.create(_part_drop(), eye + p.right_for(0.0) * 2.0)  # 90° off
	var far := LootPickup.create(_part_drop(), eye + dir * 6.0)
	for n in [target, side, far]:
		w.add_child(n)
	# Walking does not pick items up.
	p.tick(PlayerInput.hold([]), DT)
	check(p.inventory.size() == 0, "no auto pickup of items")
	check(p.pickups.focused == target, "looking at the target")
	p.tick(PlayerInput.hold([&"interact"], [&"interact"]), DT)
	check(p.inventory.size() == 1 and p.inventory.has(d.item), "Interact picked the item")
	check(not target.is_inside_tree(), "target pickup removed")
	check(side.is_inside_tree() and far.is_inside_tree(), "others stay")
	p.tick(PlayerInput.hold([&"interact"], [&"interact"]), DT)
	check(p.inventory.size() == 1, "nothing in the cone/reach: no pickup")
	# Full backpack refuses with a hint.
	while not p.inventory.is_full():
		var filler := WieldablePart.new()
		p.inventory.add(filler)
	var d2 := _part_drop()
	var t2 := LootPickup.create(d2, eye + dir * 1.5 - Vector3(0, LootPickup.GEM_SIZE * 0.5, 0))
	w.add_child(t2)
	p.tick(PlayerInput.hold([&"interact"], [&"interact"]), DT)
	check(t2.is_inside_tree() and not p.inventory.has(d2.item), "full backpack refuses")
	check(p.last_hint == PickupCollector.HINT_FULL, "hint: " + p.last_hint)
	check(p.inventory.size() == Inventory.CAPACITY, "30 slots")
	w.queue_free()


func test_compare_card_deltas() -> void:
	var w := _flat()
	var p := _player(w)
	var cur := EquipmentItem.load_item("traveler_shoes")
	p.equip_item(cur)
	var better := cur.duplicate() as EquipmentItem
	better.display_name = "Better Shoes"
	better.speed_modifier = cur.speed_modifier + 0.1
	better.mana_bonus = cur.mana_bonus - 5.0
	var c := CompareCard.for_item(better, p)
	check(c.compared_to == cur.display_name, "compared to the worn shoes")
	var sr := c.row("speed_modifier")
	check(sr["compared"] and sr["better"], "speed up = better")
	check_near(sr["delta"], 0.1, 1e-5, "speed delta")
	var mr := c.row("mana_bonus")
	check(not mr["better"] and mr["delta"] < 0.0, "mana down = worse")
	check(c.color == RarityTable.load_default().color(better.rarity), "rarity colour")
	var part_card := CompareCard.for_item(_part_drop().item, p)
	check(
		part_card.kind == "part" and part_card.rarity_id == "rare" and not part_card.row("damage_bonus")["compared"],
		"part card"
	)
	var wand := WieldableInstance.load_base("swift_wind_wand")
	p.equip(WieldableInstance.load_base("novice_arcane_wand"))
	var sc := CompareCard.for_item(wand, p)
	check(sc.kind == "wand" and sc.row("damage")["compared"], "wand card compares with the worn wand")
	w.queue_free()
