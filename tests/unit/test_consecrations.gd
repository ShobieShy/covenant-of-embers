extends TestCase
## Step 36 done check: Consecrations trigger as specified and follow the worn set.
##  - fleetfoot: +1 dash charge while worn, gone (charges clamped) when removed;
##  - kindling: a dash arms +10 on the next cast only;
##  - bulwark: +5 per cast while the shield is full, 0 once it is hit;
##  - reaping: a kill restores 10 mana;
##  - vault equipment: Rare+ pieces are sometimes Consecrated with a known id.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const S := EquipmentItem.Slot
const E := ElementTable.Element


func _setup() -> Array:
	var w := Node3D.new()
	w.position = Vector3(0, 800, 3300)
	runner_tree.root.add_child(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	return [w, p]


func _piece(slot: S, id: String) -> EquipmentItem:
	var i := EquipmentRoller.from_seed(11 + slot, slot, "rare", E.FIRE)
	i.consecration = id
	return i


func _tick(p: Player, n := 1) -> void:
	for i in n:
		p.tick(PlayerInput.new(), 1.0 / 60.0)


func test_fleetfoot() -> void:
	var s := _setup()
	var p: Player = s[1]
	var base := p.dash.max_charges()
	p.equip_item(_piece(S.SHOES, "fleetfoot"))
	check(p.dash.max_charges() == base + 1, "+1 dash charge (%d)" % p.dash.max_charges())
	p.unequip_item(S.SHOES)
	check(p.dash.max_charges() == base and p.dash.charges <= base, "removed with the piece")
	s[0].free()


func test_kindling_and_bulwark() -> void:
	var s := _setup()
	var p: Player = s[1]
	p.equip_item(_piece(S.HAT, "kindling"))
	p.equip_item(_piece(S.BELT, "bulwark"))
	var c: Caster = p.loadout.casters[0]
	p.health.shield = p.health.shield_max
	_tick(p)
	check(c.next_cast_bonus == 0.0, "no kindling before a dash")
	check(c.conditional_bonus == Consecrations.BULWARK_BONUS, "bulwark at full shield")
	p.dash.dashes += 1
	_tick(p)
	check(
		c.next_cast_bonus == Consecrations.KINDLING_BONUS and p.consecrations.kindling_procs == 1,
		"a dash arms kindling"
	)
	p.health.shield = p.health.shield_max * 0.5
	_tick(p)
	check(c.conditional_bonus == 0.0, "no bulwark below full shield")
	check(c.next_cast_bonus == Consecrations.KINDLING_BONUS, "kindling waits for a cast")
	p.unequip_item(S.HAT)
	check(not p.consecrations.has("kindling"), "unequip drops it")
	s[0].free()


func test_reaping() -> void:
	var s := _setup()
	var p: Player = s[1]
	p.equip_item(_piece(S.CLOTHES, "reaping"))
	p.mana.value = 0.0
	var e := Enemy.create(EnemyTable.load_default().find("heap"), Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	e.auto_tick = false
	s[0].add_child(e)
	e.apply_damage(1000.0, E.FIRE)
	check(is_equal_approx(p.mana.value, Consecrations.REAPING_MANA), "kill -> +10 mana (%s)" % p.mana.value)
	s[0].free()


func test_vault_rolls_consecrations() -> void:
	var r := RandomNumberGenerator.new()
	var n := 0
	for sd in 200:
		r.seed = sd
		var q: EquipmentItem = VaultChest.roll_contents(r)[2].item
		if q.consecration != "":
			check(Consecrations.DEFS.has(q.consecration), "known id")
			n += 1
	check(n > 40 and n < 160, "about half consecrated (%d/200)" % n)


func test_pool_and_world_drops() -> void:
	check(Consecrations.IDS.size() == 7 and Consecrations.IDS.size() <= 7, "3-bit item codes hold 7 ids")
	for id in ["steady", "keen", "siphon"]:
		check(Consecrations.DEFS.has(id), id)
	var rare_hits := 0
	var siphon := 0
	for seed in 400:
		var it := EquipmentRoller.from_seed(seed + 1, S.HAT, "rare", E.FIRE)
		Consecrations.roll_onto(it, "rare", PackedStringArray(["siphon"]))
		if it.consecration != "":
			check(Consecrations.DEFS.has(it.consecration), "known id %s" % it.consecration)
			rare_hits += 1
			if it.consecration == "siphon":
				siphon += 1
	check(rare_hits > 40 and rare_hits < 140, "about 20 pct of Rare+ (%d/400)" % rare_hits)
	check(siphon > rare_hits / 3, "branch bias shows up (%d/%d siphon)" % [siphon, rare_hits])
	for seed in 40:
		var low := EquipmentRoller.from_seed(seed + 1, S.BELT, "uncommon", E.EARTH)
		Consecrations.roll_onto(low, "uncommon")
		check(low.consecration == "", "uncommon stays plain")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var drops := DropRoller.roll_procedural(rng, 5, E.FIRE, 4.0)
	for d in drops:
		if d.kind != LootDrop.Kind.EQUIPMENT:
			continue
		var eq := d.item as EquipmentItem
		if Rarity.parse(d.rarity_id) < Rarity.Tier.RARE:
			check(eq.consecration == "", "below Rare on a kill drop")
		elif eq.consecration != "":
			check(Consecrations.DEFS.has(eq.consecration), "kill drop id")


func test_steady_keen_siphon() -> void:
	var s := _setup()
	var p: Player = s[1]
	p.equip_item(_piece(S.HAT, "steady"))
	p.equip_item(_piece(S.BELT, "keen"))
	p.focus.focused = true
	_tick(p)
	check(p.loadout.casters[0].conditional_bonus == Consecrations.STEADY_BONUS, "steady while focused")
	check_near(p.loadout.casters[0].crit_chance_bonus, Consecrations.KEEN_CRIT, 1e-6, "keen crit")
	p.focus.focused = false
	_tick(p)
	check(p.loadout.casters[0].conditional_bonus == 0.0, "steady drops when you stop focusing")
	p.equip_item(_piece(S.CLOTHES, "siphon"))
	p.health.value = 40.0
	var e := Enemy.create(EnemyTable.load_default().find("heap"), Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	e.auto_tick = false
	s[0].add_child(e)
	e.apply_damage(1000.0, E.FIRE)
	check_near(p.health.value, 48.0, 0.05, "siphon +8 health")
	var marked := EquipmentRoller.from_seed(9, S.SHOES, "mythic", E.WATER)
	marked.consecration = "siphon"
	var back := ItemCodes.decode(ItemCodes.encode(marked))
	check(back.ok() and (back.item as EquipmentItem).consecration == "siphon", "siphon survives an Ember Mark")
	s[0].free()
