extends TestCase
## Phase V step 147: marks (Soaked, Hex) and conditional bonuses (vs_status_pct, mark_pct,
## vs_mark_status_pct for Tremor/Conductive).

const E := ElementTable.Element


func _world(k: int) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(-9000, 0, -9000 - 300 * k)
	runner_tree.root.add_child(w)
	return w


func _enemy(w: Node3D) -> Enemy:
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"), Transform3D())
	w.add_child(e)
	if e is Gnawer:
		(e as Gnawer).auto_tick = false
	e.set_physics_process(false)
	return e


func _hit(e: Enemy, el: E, dmg: float, md: Dictionary) -> SpellBolts.Hit:
	var h := SpellBolts.Hit.new()
	h.collider = e
	h.element = el
	h.damage = dmg
	h.spawn = SpellBolts.Spawn.new()
	h.spawn.mods = md
	h.result = Damage.Result.new()
	h.result.amount = dmg
	return h


func test_marks_applied() -> void:
	var w := _world(11)
	var e := _enemy(w)
	MagicEffects.on_hit(_hit(e, E.WATER, 10.0, {"mark_seconds": 4.0}))
	check_near(e.soaked_left, 4.0, 1e-6, "soaked 4 s")
	check_near(e.hex_left, 0.0, 1e-6, "no hex from water")
	var f := _enemy(w)
	MagicEffects.on_hit(_hit(f, E.DARK, 10.0, {"mark_seconds": 5.0}))
	check_near(f.hex_left, 5.0, 1e-6, "hex 5 s")
	f.tick(1.0)
	check(f.hex_left <= 4.0 + 1e-6, "hex decays")
	f.clear_statuses()
	check_near(f.hex_left, 0.0, 1e-6, "cleared")
	var g := _enemy(w)
	MagicEffects.on_hit(_hit(g, E.FIRE, 10.0, {}))
	check_near(g.hex_left + g.soaked_left, 0.0, 1e-6, "no mods, no mark")


func test_conditionals() -> void:
	var w := _world(12)
	var e := _enemy(w)
	var md := {"vs_status_pct": 10.0, "mark_pct": 20.0}
	check_near(MagicEffects.conditional_mult(md, E.FIRE, e), 1.0, 1e-6, "clean target")
	e.burn_left = 2.0
	check_near(MagicEffects.conditional_mult(md, E.FIRE, e), 1.1, 1e-6, "burning +10%")
	check_near(MagicEffects.conditional_mult(md, E.WATER, e), 1.0, 1e-6, "water needs slow")
	e.hex_left = 2.0
	check_near(MagicEffects.conditional_mult(md, E.FIRE, e), 1.1 * 1.2, 1e-6, "hexed +20%")
	var h := _hit(e, E.FIRE, 10.0, md)
	MagicEffects.apply_skill_hit(h, false, e)
	check_near(h.result.amount, 13.2, 1e-4, "hit amount")


func test_tremor_soaked() -> void:
	var w := _world(13)
	var e := _enemy(w)
	e.soaked_left = 3.0
	MagicEffects.on_hit(_hit(e, E.EARTH, 10.0, {"vs_mark_status_pct": 100.0}))
	var f := _enemy(w)
	MagicEffects.on_hit(_hit(f, E.EARTH, 10.0, {"vs_mark_status_pct": 100.0}))
	check(e.stagger_left > f.stagger_left * 1.9, "soaked stagger doubled")
