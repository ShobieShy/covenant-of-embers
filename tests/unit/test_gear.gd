extends TestCase
## 0.8.7: shield replaces the Health numbers, the flask is not the potion, the relic
## clears when removed, new codes round-trip, and a golden EM1 string is untouched.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DT := 1.0 / 60.0


func test_shield_on_and_off() -> void:
	var p := _player()
	var base_cap := p.health.shield_max
	var base_delay := p.health.shield_regen_delay
	p.gear.equip_shield(ShieldDrop.make(80.0, 1.0, "ward"))
	p.apply_bonuses()
	check(is_equal_approx(p.health.shield_max, 80.0), "capacity replaced")
	check(is_equal_approx(p.health.shield_regen_per_sec, p.tuning.shield_regen_per_sec * 1.5), "ward effect")
	check(is_equal_approx(p.health.shield_regen_delay, 1.0), "delay replaced")
	p.gear.clear_shield()
	p.apply_bonuses()
	check(is_equal_approx(p.health.shield_max, base_cap), "capacity restored")
	check(is_equal_approx(p.health.shield_regen_delay, base_delay), "delay restored")
	p.free()


func test_flask_does_not_drink_a_potion() -> void:
	var p := _player()
	p.health.value = 40.0
	p.equipment.add_potions(ConsumableItem.load_item("health_potion"), 2)
	var before := p.equipment.potion_count
	p.tick(PlayerInput.hold([], ["use_flask"]), DT)
	check(p.gear.flask == 0 and p.gear.flasks_used == 1, "flask spent")
	check(p.health.value > 40.0, "flask heals")
	check(p.equipment.potion_count == before and p.potions_used == 0, "potion slot untouched")
	p.tick(PlayerInput.hold([], ["use_flask"]), DT)
	check(p.gear.flasks_used == 1, "empty flask does nothing")
	p.gear.refill()
	check(p.gear.flask == 1, "rest refills the flask")
	p.free()


func test_relic_clears_when_removed() -> void:
	var p := _player()
	p.gear.equip_relic(RelicDrop.make("ember_chip"))
	p.apply_bonuses()
	check(is_equal_approx(p.caster.damage_bonus, GearKit.EMBER_DAMAGE), "ember chip adds damage")
	p.gear.clear_relic()
	p.apply_bonuses()
	check(is_equal_approx(p.caster.damage_bonus, 0.0), "removing the relic clears it")
	p.free()


func test_new_codes_and_side_stream() -> void:
	var staff := WieldableInstance.load_base("cinder_staff")
	var code := ItemCodes.encode(staff)
	var back := ItemCodes.decode(code)
	check(back.ok() and (back.item as WieldableInstance).def.id == "cinder_staff", "new base round-trips")
	check(code.begins_with("EM1-"), "bare base stays an EM1 code")
	var grip := WieldablePart.load_part("slag_grip")
	var pc := ItemCodes.encode(grip)
	var pg := ItemCodes.decode(pc)
	check(pg.ok() and (pg.item as WieldablePart).id == "slag_grip", "new part round-trips (%s)" % pg.error)
	var golden := "EM1-0M09G-00002-03THG"
	check(ItemCodes.decode(golden).ok(), "golden EM1 still decodes")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var before := rng.state
	GearDrops.chance = 0.0
	DropRoller.roll_kill(rng, "gnawer", 3, 0)
	var quiet := rng.state
	rng.seed = 42
	rng.state = before
	GearDrops.chance = 1.0
	var loud := DropRoller.roll_kill(rng, "gnawer", 3, 0)
	check(rng.state == quiet, "the side stream does not draw on the kill rng")
	var found := false
	for d in loud:
		if _is_gear(d):
			found = true
	check(found, "a forced chance adds gear")
	GearDrops.chance = 0.0


func _is_gear(d: LootDrop) -> bool:
	if d.item is ShieldDrop or d.item is RelicDrop:
		return true
	if d.item is WieldableInstance:
		return EquipmentRoller.extra_bases().has((d.item as WieldableInstance).def.id)
	if d.item is WieldablePart:
		return PartRoller.extra_ids().has((d.item as WieldablePart).id)
	return false


func _player() -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(9000, 0, 9000), 0.0)
	return p
