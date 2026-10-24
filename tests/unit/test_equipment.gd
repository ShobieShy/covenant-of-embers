extends TestCase
## Step 19 done check: equipment items (EquipmentItem / EquipmentRoller / Equipment /
## ConsumableItem, Player.apply_bonuses):
##  - the 5 Magewar templates + 2 potions import with Magewar's numbers;
##  - bonuses applied and removed exactly (totals recomputed, Health/Mana raise adds the
##    difference, removal clamps); resist cap: two 0.4 Fire pieces -> 0.8 stored, 0.6
##    applied by Damage.resolve_hit;
##  - Leather Belt -> Breath max 115 without refill; Traveler's Shoes -> walk 4.6 m/s;
##  - Novice Grimoire (+5 / +0.5) on 80/100 -> 85/105 and 3.5/s; removed -> 85/100, 3/s;
##    its +3 spell damage reaches every caster;
##  - Mana Potion 30 -> 55 (refused when full), Health Potion +30, stacks of 5;
##  - EquipmentRoller = Magewar generate_equipment_with_rng: ranges × rarity, Clothes resist
##    only when elemental, template stats kept, names, one rng draw, regenerate();
##  - DropRoller's equipment drops carry the rolled item.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const S := EquipmentItem.Slot
const E := ElementTable.Element

func _flat() -> Node3D:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(400, 1, 400)
	cs.shape = s
	b.add_child(cs)
	b.position = Vector3(0, -0.5, 0)
	w.add_child(b)
	return w

func _player(w: Node3D, feet := Vector3.ZERO) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(feet, 0.0)
	return p

func _item(slot: S, element: E, resist: float) -> EquipmentItem:
	var i := EquipmentItem.new()
	i.id = "test_%d" % slot
	i.display_name = "Test"
	i.slot = slot
	i.element_affinity = element
	i.elemental_resistance = resist
	return i

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func test_templates_and_potions_import_magewar_numbers() -> void:
	var ids := EquipmentItem.list_ids()
	check(ids == PackedStringArray(["apprentice_hat", "basic_robes", "leather_belt", "novice_grimoire", "traveler_shoes"]), "5 templates: %s" % [ids])
	# [id, slot, name, health, mana, stamina, speed, spell, resist, regen] (Magewar .tres)
	for row in [["apprentice_hat", S.HAT, "Apprentice's Pointed Hat", 0, 10, 0, 1.0, 1, 0.0, 0.5],
			["basic_robes", S.CLOTHES, "Tattered Mage Robes", 5, 5, 0, 1.0, 0, 0.05, 0.0],
			["leather_belt", S.BELT, "Leather Belt", 0, 0, 15, 1.0, 0, 0.0, 0.0],
			["traveler_shoes", S.SHOES, "Traveler's Shoes", 5, 0, 5, 1.15, 0, 0.0, 0.0],
			["novice_grimoire", S.GRIMOIRE, "Novice Grimoire", 0, 5, 0, 1.0, 3, 0.0, 0.5]]:
		var i := EquipmentItem.load_item(row[0])
		check(i != null and i.validate().is_empty(), "%s loads and validates" % row[0])
		if i == null:
			continue
		var got := [i.id, i.slot, i.display_name, i.health_bonus, i.mana_bonus, i.stamina_bonus,
			i.speed_modifier, i.spell_damage_bonus, i.elemental_resistance, i.mana_regen_bonus]
		var same: bool = got.size() == row.size()
		for k in row.size():
			same = same and (got[k] == row[k] if k < 3 else is_equal_approx(float(got[k]), float(row[k])))
		check(same, "%s = Magewar %s (got %s)" % [row[0], row, got])
		check(i.rarity == "basic" and i.element_affinity == E.ARCANE and i.roll_seed == -1 and not i.description.is_empty(), "%s basic Arcane template" % row[0])
	var shoes := EquipmentItem.load_item("traveler_shoes")
	check(shoes.full_description() == "[Basic] Shoes\nHealth: +5\nStamina: +5\nSpeed: x1.15", "Magewar description layout: %s" % shoes.full_description().c_escape())
	var robes := EquipmentItem.load_item("basic_robes")
	check(robes.full_description().ends_with("Resistance: 5%"), "resistance shown in %")
	var hp := ConsumableItem.load_item("health_potion")
	var mp := ConsumableItem.load_item("mana_potion")
	check(hp != null and hp.validate().is_empty() and hp.attribute == "health" and hp.amount == 30.0 and hp.stack_size == 5 and hp.hint == "Health restored!", "Health Potion +30, stack 5")
	check(mp != null and mp.validate().is_empty() and mp.attribute == "mana" and mp.amount == 25.0 and mp.stack_size == 5 and mp.hint == "Mana restored!", "Mana Potion +25, stack 5")
	var bad := _item(S.HAT, E.FIRE, 0.2)
	bad.rarity = "legendary"
	bad.speed_modifier = 0.0
	check(bad.validate().size() == 2, "unknown rarity + speed 0 rejected: %s" % [bad.validate()])

func test_bonuses_applied_and_removed_exactly() -> void:
	var w := _flat()
	var p := _player(w)
	var h0 := p.health.max_value()
	var m0 := p.mana.max_value()
	var b0 := p.breath.max_value()
	var r0 := p.mana.regen_rate()
	check(h0 == 100.0 and m0 == 100.0 and b0 == 100.0 and r0 == 3.0, "base 100/100/100, 3/s")
	for id in EquipmentItem.list_ids():
		check(p.equip_item(EquipmentItem.load_item(id)) == null, "%s into an empty slot" % id)
	# Hat 10 + Robes 5 + Grimoire 5 mana; Robes 5 + Shoes 5 health; Belt 15 + Shoes 5 stamina.
	check(p.health.max_value() == 110.0 and p.health.value == 110.0, "health 110 (+10 added): %f/%f" % [p.health.value, p.health.max_value()])
	check(p.mana.max_value() == 120.0 and p.mana.value == 120.0, "mana 120 (+20 added)")
	check(p.breath.max_value() == 120.0 and p.breath.value == 100.0, "Breath max 120, not refilled")
	check(is_equal_approx(p.mana.regen_rate(), 4.0), "regen 3 + 0.5 + 0.5 = 4 (%f)" % p.mana.regen_rate())
	check(is_equal_approx(p.speed_multiplier, 1.15), "speed x1.15")
	check(is_equal_approx(p.damage_target.resist[E.ARCANE], 0.05), "Arcane robes 5 %% vs Arcane (Magewar affinity rule)")
	for c in p.loadout.casters:
		check(c.damage_bonus == 4.0, "spell damage Hat 1 + Grimoire 3 on every caster")
	# Swapping a slot returns the old piece and recomputes.
	var old := p.equip_item(EquipmentRoller.from_seed(7, S.HAT, "rare", E.FIRE))
	check(old != null and old.id == "apprentice_hat", "swap returns the replaced Hat")
	for s in [S.HAT, S.CLOTHES, S.BELT, S.SHOES, S.GRIMOIRE]:
		check(p.unequip_item(s) != null, "unequip %d" % s)
	check(p.unequip_item(S.HAT) == null, "empty slot: nothing")
	check(p.health.max_value() == h0 and p.mana.max_value() == m0 and p.breath.max_value() == b0, "maxes back exactly")
	check(p.health.value == 100.0 and p.mana.value == 100.0 and p.breath.value == 100.0, "values clamped to the base")
	check(p.mana.regen_rate() == r0 and p.speed_multiplier == 1.0, "regen 3, speed x1 exactly")
	var zero := true
	for e in ElementTable.COUNT:
		zero = zero and p.damage_target.resist[e] == 0.0
	check(zero and p.loadout.casters[0].damage_bonus == 0.0, "resists and spell damage back to 0")
	# Many random pieces on and off: always exact.
	var rng := _rng(19)
	for n in 50:
		p.equip_item(EquipmentRoller.roll(rng, rng.randi_range(0, 4), Rarity.IDS[rng.randi_range(0, 5)]))
	for s in EquipmentItem.SLOT_COUNT:
		p.unequip_item(s)
	check(p.health.max_value() == h0 and p.mana.max_value() == m0 and p.breath.max_value() == b0 and p.mana.regen_rate() == r0 and p.speed_multiplier == 1.0, "50 random equips, all removed: exact")
	w.free()

func test_resist_cap_two_fire_pieces() -> void:
	var w := _flat()
	var p := _player(w)
	p.equip_item(_item(S.CLOTHES, E.FIRE, 0.4))
	p.equip_item(_item(S.GRIMOIRE, E.FIRE, 0.4))
	p.equip_item(_item(S.HAT, E.WATER, 0.3))
	check(is_equal_approx(p.damage_target.resist[E.FIRE], 0.8), "0.8 stored uncapped (%f)" % p.damage_target.resist[E.FIRE])
	check(is_equal_approx(p.damage_target.resist[E.WATER], 0.3) and p.damage_target.resist[E.EARTH] == 0.0, "per affinity")
	var hit := Damage.resolve_hit(100.0, E.FIRE, p.damage_target)
	var ref := Damage.resolve_hit(100.0, E.FIRE, Damage.Target.new(p.damage_target.affinity).set_resist(E.FIRE, 0.6))
	check(is_equal_approx(hit.resist, 0.6) and is_equal_approx(hit.amount, ref.amount), "0.6 applied: %f (cap %f)" % [hit.amount, ref.amount])
	var before := p.health.value + p.health.shield
	p.take_enemy_hit(10.0, E.FIRE)
	var lost := before - (p.health.value + p.health.shield)
	print("    resist: Fire 0.8 stored -> %.2f applied, 100 Fire bolt -> %.1f, 10 melee -> %.2f lost" % [hit.resist, hit.amount, lost])
	check_near(lost, 10.0 * ref.effectiveness * 0.4, 1e-6, "melee through the cap too")
	w.free()

func test_belt_breath_115_without_refill() -> void:
	var w := _flat()
	var p := _player(w)
	p.breath.value = 50.0
	p.equip_item(EquipmentItem.load_item("leather_belt"))
	check(p.breath.max_value() == 115.0 and p.breath.value == 50.0, "Belt: 50/115 (%f/%f)" % [p.breath.value, p.breath.max_value()])
	p.breath.refill()
	check(p.breath.value == 115.0, "refills to 115")
	p.unequip_item(S.BELT)
	check(p.breath.max_value() == 100.0 and p.breath.value == 100.0, "removed: clamped 100/100")
	w.free()

func test_shoes_walk_4_6() -> void:
	var w := _flat()
	var p := _player(w)
	p.equip_item(EquipmentItem.load_item("traveler_shoes"))
	for i in 30:
		p.tick(PlayerInput.hold([]), DT)
	for i in 90:
		p.tick(PlayerInput.hold([&"forward"]), DT)
	var walk := p.horizontal_speed()
	print("    shoes: walk %.3f m/s (4.6)" % walk)
	check_near(walk, 4.6, 0.05, "Traveler's Shoes walk")
	p.unequip_item(S.SHOES)
	for i in 90:
		p.tick(PlayerInput.hold([&"forward"]), DT)
	check_near(p.horizontal_speed(), 4.0, 0.05, "removed: walk 4")
	w.free()

func test_grimoire_mana_and_spell_damage() -> void:
	var w := _flat()
	var p := _player(w)
	p.mana.value = 80.0
	p.equip_item(EquipmentItem.load_item("novice_grimoire"))
	check(p.mana.value == 85.0 and p.mana.max_value() == 105.0, "85/105 (%f/%f)" % [p.mana.value, p.mana.max_value()])
	check(is_equal_approx(p.mana.regen_rate(), 3.5), "3.5/s")
	check(p.caster.damage_bonus == 3.0, "spell damage +3 on the caster")
	# The flat bonus reaches the bolt: Caster spawn damage = wieldable damage + 3.
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	p.equip(staff)
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	var aim := Caster.Aim.make(Vector3(0, 1.5, 0), Vector3.FORWARD)
	check(p.caster.tick(true, true, DT, aim, bolts) and bolts.live.size() == 1, "cast")
	if bolts.live.size() == 1:
		check_near(bolts.live[0].spawn.damage, staff.damage() + 3.0, 1e-6, "bolt damage = staff + 3")
	p.mana.value = 85.0
	p.unequip_item(S.GRIMOIRE)
	check(p.mana.value == 85.0 and p.mana.max_value() == 100.0, "removed: 85/100")
	check(is_equal_approx(p.mana.regen_rate(), 3.0) and p.caster.damage_bonus == 0.0, "3/s, no spell bonus")
	w.free()

func test_potions() -> void:
	var w := _flat()
	var p := _player(w)
	var mp := ConsumableItem.load_item("mana_potion")
	var hp := ConsumableItem.load_item("health_potion")
	check(not p.use_potion(), "empty quick-slot")
	check(p.equipment.add_potions(mp, 7) == 5 and p.equipment.potion_count == 5, "stack of 5")
	check(p.equipment.add_potions(hp, 1) == 0, "one kind at a time")
	check(not p.use_potion() and p.equipment.potion_count == 5 and p.last_hint == "mana is already maxed.", "full mana: refused, kept")
	p.mana.value = 30.0
	check(p.use_potion() and p.mana.value == 55.0 and p.equipment.potion_count == 4, "Mana Potion 30 -> 55 (%f)" % p.mana.value)
	check(p.last_hint == "Mana restored!", "hint")
	p.mana.value = 90.0
	check(p.use_potion() and p.mana.value == 100.0, "capped at max")
	while p.equipment.potion_count > 0:
		p.mana.value = 0.0
		p.use_potion()
	check(p.equipment.potion == null and p.equipment.add_potions(hp, 2) == 2, "empty slot takes Health Potions")
	p.health.value = 50.0
	check(p.use_potion() and p.health.value == 80.0, "Health Potion 50 -> 80 (%f)" % p.health.value)
	p.health.value = 0.0
	p.health.dead = true
	check(not p.use_potion() and p.equipment.potion_count == 1, "nothing while dead")
	w.free()

func test_roller_follows_magewar() -> void:
	var rt := RarityTable.load_default()
	var tpl := {}
	for s in EquipmentRoller.TEMPLATE_IDS:
		tpl[s] = EquipmentItem.load_item(EquipmentRoller.TEMPLATE_IDS[s])
	var ok := true
	var names_ok := true
	var seen_arcane_robes := false
	for rid in Rarity.IDS:
		for s in EquipmentItem.SLOT_COUNT:
			for n in 40:
				var seed := n * 7919 + s * 31
				var el := n % ElementTable.COUNT
				var i := EquipmentRoller.from_seed(seed, s, rid, el)
				if i == null or not i.validate().is_empty():
					ok = false
					continue
				for stat in EquipmentItem.STATS:
					var v: float = i.get(stat)
					var rolled := EquipmentRoller.rolled_stats(s).has(stat)
					if stat == "elemental_resistance" and el == E.ARCANE:
						rolled = false
					if rolled:
						var r := EquipmentRoller.stat_range(s, rid, stat)
						ok = ok and v >= r.x - 1e-9 and v <= r.y + 1e-9
					else:
						ok = ok and v == float(tpl[s].get(stat))
				if s == S.CLOTHES and el == E.ARCANE:
					seen_arcane_robes = true
					ok = ok and i.elemental_resistance == 0.05   # template's, unscaled (Magewar)
				ok = ok and i.slot == s and i.rarity == rid and i.element_affinity == el and i.roll_seed == seed
				var want := "%s %s%s" % [EquipmentRoller.PREFIXES[Rarity.parse(rid)],
					"" if el == E.ARCANE else ElementTable.load_default().display_name(el as E) + " ", EquipmentRoller.BASE_NAMES[s]]
				names_ok = names_ok and i.display_name == want and i.description == i.full_description()
				var again := EquipmentRoller.regenerate(i)
				ok = ok and again.id == i.id and again.mana_bonus == i.mana_bonus and again.speed_modifier == i.speed_modifier \
					and again.elemental_resistance == i.elemental_resistance and again.health_bonus == i.health_bonus
	check(ok and seen_arcane_robes, "every roll in range × rarity, template stats kept, regenerate() exact")
	check(names_ok, "Magewar names + descriptions")
	check(EquipmentRoller.stat_range(S.SHOES, "basic", "speed_modifier").is_equal_approx(Vector2(1.02, 1.10)), "Basic Shoes x1.02-1.10")
	var m := rt.multiplier("unique")
	check(EquipmentRoller.stat_range(S.SHOES, "unique", "speed_modifier").is_equal_approx(Vector2(1 + 0.02 * m, 1 + 0.1 * m)), "Unique Shoes speed range × %.1f" % m)
	check(EquipmentRoller.stat_range(S.CLOTHES, "rare", "elemental_resistance").is_equal_approx(Vector2(0.05, 0.15) * rt.multiplier("rare")), "Clothes resist 5-15 % × rarity")
	check(EquipmentRoller.from_seed(1, S.HAT, "nope") == null and EquipmentRoller.from_seed(1, 9, "basic") == null, "unknown rarity/slot")
	check(EquipmentRoller.regenerate(EquipmentItem.load_item("leather_belt")) == null, "templates don't regenerate")
	# One draw from the caller's rng; element rolled when not given.
	var a := _rng(5)
	var b := _rng(5)
	var i := EquipmentRoller.roll(a, S.GRIMOIRE, "mythic")
	b.randi()
	check(a.state == b.state and i.roll_seed == _rng(5).randi(), "exactly one randi()")
	var j := EquipmentRoller.from_seed(i.roll_seed, S.GRIMOIRE, "mythic")
	check(j.id == i.id and j.element_affinity == i.element_affinity, "rolled element is part of the seed")
	print("    roller: %s (%s): %s" % [i.display_name, i.id, i.description.replace("\n", " | ")])

func test_drops_carry_the_item() -> void:
	var rng := _rng(4242)
	var found := 0
	var ok := true
	for k in 400:
		for d in DropRoller.roll_procedural(rng, 1, E.FIRE, 0.0):
			if d.kind != LootDrop.Kind.EQUIPMENT:
				continue
			found += 1
			var it := d.item as EquipmentItem
			ok = ok and it != null and it.slot == d.equip_slot and it.slot < LootDrop.DROP_EQUIP_SLOTS \
				and it.rarity == d.rarity_id and it.element_affinity == d.element and it.roll_seed == d.roll_seed \
				and d.describe() == "%s %s" % [RarityTable.load_default().display_name(d.rarity_id), it.display_name]
	check(found > 50 and ok, "%d equipment drops, each with its rolled item" % found)
