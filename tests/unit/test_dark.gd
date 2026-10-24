extends TestCase
## Step 52 done check (Q2/Q3: Magewar Dark), reworked in step 108: every Dark hit on a
## non-boss brute has 1% + the Dark-part bonus (capped at 15%) to corrupt it into an ally for
## 30 s; the ally hunts and bites other enemies, bosses are immune, and the husk crumbles.

const DT := 1.0 / 60.0
const E := ElementTable.Element


func _world(k: int) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(7000, 0, -7000 - 300 * k)
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


func _enemy(w: Node3D, id: String, at: Vector3) -> Enemy:
	var e := Enemy.create(EnemyTable.load_default().find(id), Transform3D(Basis(), at))
	w.add_child(e)
	if e is Gnawer:
		(e as Gnawer).auto_tick = false
	return e


func _dark(e: Enemy) -> SpellBolts.Hit:
	var h := SpellBolts.Hit.new()
	h.collider = e
	h.element = E.DARK
	h.result = Damage.Result.new()
	h.result.amount = 1.0
	return h


func test_base_chance_and_roll() -> void:
	var w := _world(1)
	var e := _enemy(w, "gnawer", Vector3.ZERO)
	check(is_equal_approx(MagicEffects.dark_chance(0.0), 0.01), "1% base")
	check(is_equal_approx(MagicEffects.dark_chance(1.0), MagicEffects.DARK_MAX_CHANCE), "capped at 15%")
	MagicEffects.dark_roll = func() -> float: return 0.011
	check(not MagicEffects.dark(_dark(e)), "roll 0.011 misses the 1%")
	var h := _dark(e)
	h.dark_bonus = 0.005
	check(MagicEffects.dark(h) and e.is_ally(), "+0.5% bonus: 0.011 < 1.5% corrupts (at full health)")
	check(is_equal_approx(e.corrupted_left, 30.0), "for 30 s")
	MagicEffects.dark_roll = func() -> float: return 0.0
	MagicEffects.on_hit(_dark(e))
	check(e.corruptions == 1, "already an ally: not again")
	var pup := _enemy(w, "gnawer", Vector3(0, 0, 5))
	pup.hold_death = true
	check(not MagicEffects.dark(_dark(pup)), "a co-op puppet never converts locally (the host rolls)")
	MagicEffects.dark_roll = Callable()
	w.queue_free()


func test_part_bonuses() -> void:
	var b := WieldablePart.DARK_BONUS
	check(b["basic"] == 0.0025 and b["rare"] == 0.01 and b["unique"] == 0.03, "per-rarity table")
	check_near(WieldablePart.load_part("uncommon_dark_handle").dark_chance_bonus(), 0.005, 1e-6, "uncommon +0.5%")
	check(WieldablePart.load_part("rare_light_charm").dark_chance_bonus() == 0.0, "non-Dark part: none")
	check(
		WieldablePart.load_part("uncommon_dark_handle").full_description().ends_with("Dark Conversion: +0.5%"),
		"tooltip line"
	)
	var wand := WieldableInstance.load_base("novice_arcane_wand")
	wand.parts.append(WieldablePart.load_part("uncommon_dark_handle"))
	wand.parts.append(WieldablePart.load_part("unique_void_charm"))
	check_near(wand.dark_chance_bonus(), 0.035, 1e-6, "parts add up")
	var card := CompareCard.for_item(WieldablePart.load_part("unique_void_charm"))
	check_near(float(card.row("dark_bonus").get("value", 0.0)), 3.0, 1e-6, "compare card row")
	# The caster carries it on the bolt.
	var w := _world(4)
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	var c := Caster.new(wand)
	check(c.tick(true, true, DT, Caster.Aim.make(w.global_position + Vector3(0, 50, 0), Vector3.UP), bolts), "cast")
	check_near(bolts.live[0].spawn.dark_bonus, 0.035, 1e-6, "Spawn.dark_bonus")
	w.queue_free()


func test_boss_immune() -> void:
	var w := _world(2)
	var f := _enemy(w, "the_filth", Vector3.ZERO)
	MagicEffects.dark_roll = func() -> float: return 0.0
	f.health = 1.0
	check(f.is_boss() and not MagicEffects.dark(_dark(f)) and not f.is_ally(), "The Filth is immune")
	MagicEffects.dark_roll = Callable()
	w.queue_free()


func test_ally_bites_enemies_then_crumbles() -> void:
	var w := _world(3)
	var ally := _enemy(w, "gnawer", Vector3.ZERO) as Gnawer
	var foe := _enemy(w, "gnawer", Vector3(0, 0, -3))
	var decoy := Node3D.new()
	w.add_child(decoy)
	ally.target = decoy
	foe.target = decoy
	await runner_tree.physics_frame
	check(ally.corrupt(MagicEffects.DARK_SECONDS), "corrupted")
	var hp := foe.health
	for i in 600:
		ally.tick(DT)
		await runner_tree.physics_frame
		if foe.dead:
			break
	check(ally.target == foe or foe.dead, "hunts the foe")
	check(ally.ally_bites > 0 and foe.health < hp, "bit it: %d bites, %f -> %f" % [ally.ally_bites, hp, foe.health])
	check(ally.bites == 0 and ally.attacks.is_empty(), "no attacks at players")
	var t := 0.0
	while t < MagicEffects.DARK_SECONDS + 1.0 and not ally.dead:
		ally.tick(DT)
		t += DT
	check(ally.dead and not ally.is_ally(), "crumbled after 30 s")
	w.queue_free()
