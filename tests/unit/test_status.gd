extends TestCase
## Step 53 done check (Q5): Fire burns, Water slows, Earth staggers, Air chains; durations
## shrink with the (60%-capped) resist.

const DT := 1.0 / 60.0
const E := ElementTable.Element


func _world(k: int) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(-7000, 0, -7000 - 300 * k)
	runner_tree.root.add_child(w)
	return w


func _enemy(w: Node3D, at: Vector3) -> Enemy:
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"), Transform3D(Basis(), at))
	w.add_child(e)
	if e is Gnawer:
		(e as Gnawer).auto_tick = false
	e.set_physics_process(false)
	return e


func _hit(e: Enemy, el: E, dmg: float, resist := 0.0) -> SpellBolts.Hit:
	var h := SpellBolts.Hit.new()
	h.collider = e
	h.element = el
	h.damage = dmg
	h.result = Damage.Result.new()
	h.result.amount = dmg
	h.result.resist = resist
	return h


func test_burn_deals_30_percent_over_3s() -> void:
	var w := _world(1)
	var e := _enemy(w, Vector3.ZERO)
	e.health = 100.0
	MagicEffects.on_hit(_hit(e, E.FIRE, 10.0))
	check(is_equal_approx(e.burn_left, 3.0), "3 s burn")
	for i in 240:
		e.tick(DT)
	check(is_equal_approx(e.health, 97.0), "burned 3: %f" % e.health)
	check(e.burn_left == 0.0, "burn over")
	w.queue_free()


func test_slow_stagger_and_resist_cap() -> void:
	var w := _world(2)
	var e := _enemy(w, Vector3.ZERO)
	MagicEffects.on_hit(_hit(e, E.WATER, 5.0))
	check(is_equal_approx(e.move_scale(), 0.6), "slowed to 60%")
	MagicEffects.on_hit(_hit(e, E.EARTH, 5.0))
	check(e.staggered() and e.move_scale() == 0.0, "staggered")
	for i in 30:
		e.tick(DT)
	check(not e.staggered() and is_equal_approx(e.move_scale(), 0.6), "stagger 0.4 s, slow lasts")
	var f := _enemy(w, Vector3(10, 0, 0))
	MagicEffects.on_hit(_hit(f, E.WATER, 5.0, 0.9))
	check(is_equal_approx(f.slow_left, 2.5 * 0.4), "resist capped at 60%%: %f" % f.slow_left)
	w.queue_free()


func test_staggered_gnawer_neither_walks_nor_bites() -> void:
	var w := _world(3)
	var g := _enemy(w, Vector3.ZERO) as Gnawer
	var decoy := Node3D.new()
	w.add_child(decoy)
	decoy.position = Vector3(0, 0, -0.9)
	g.target = decoy
	g.stagger_left = 10.0
	var at := g.global_position
	for i in 60:
		g.tick(DT)
	check(g.bites == 0, "no bite while staggered")
	var moved := Vector2(g.global_position.x - at.x, g.global_position.z - at.z).length()
	check(moved < 0.01, "didn't walk: %f" % moved)
	w.queue_free()


func test_air_chains_once() -> void:
	var w := _world(4)
	var a := _enemy(w, Vector3.ZERO)
	var b := _enemy(w, Vector3(3, 0, 0))
	var c := _enemy(w, Vector3(30, 0, 0))
	var hb := b.health
	var hc := c.health
	var to := MagicEffects.chain(_hit(a, E.AIR, 10.0))
	check(to == b, "jumped to the near one")
	check(b.health < hb and c.health == hc, "only one jump")
	w.queue_free()
