extends TestCase
## Step 52 done check (Q2/Q3: Magewar Dark): a Dark hit that leaves a non-boss enemy at
## <= 25% health has a 40% chance to corrupt it into an ally for 30 s; the ally hunts and
## bites other enemies, bosses are immune, and the husk crumbles when it runs out.

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


func test_threshold_and_roll() -> void:
	var w := _world(1)
	var e := _enemy(w, "gnawer", Vector3.ZERO)
	MagicEffects.dark_roll = func() -> float: return 0.1
	e.health = e.max_health() * 0.5
	check(not MagicEffects.dark(_dark(e)), "above 25%: no")
	e.health = e.max_health() * 0.25
	MagicEffects.dark_roll = func() -> float: return 0.45
	check(not MagicEffects.dark(_dark(e)), "roll 0.45 misses the 40%")
	MagicEffects.dark_roll = func() -> float: return 0.39
	check(MagicEffects.dark(_dark(e)) and e.is_ally(), "roll 0.39 corrupts")
	check(is_equal_approx(e.corrupted_left, 30.0), "for 30 s")
	MagicEffects.on_hit(_dark(e))
	check(e.corruptions == 1, "already an ally: not again")
	MagicEffects.dark_roll = Callable()
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
