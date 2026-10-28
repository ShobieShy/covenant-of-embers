extends TestCase
## 0.3.1 P5: enemy flinch / crit root (M1), per-element cast sounds and the muzzle flare (M5).

const E := ElementTable.Element
const DT := 1.0 / 60.0


func _hit(e: Enemy, dmg: float, crit := 1.0) -> SpellBolts.Hit:
	var h := SpellBolts.Hit.new()
	h.collider = e
	h.element = E.ARCANE
	h.damage = dmg
	h.direction = Vector3(1, 0, 0)
	h.result = Damage.Result.new()
	h.result.amount = dmg
	h.result.crit = crit
	return h


func _enemy(w: Node3D, id: String) -> Enemy:
	var e := Enemy.create(
		EnemyTable.load_default().find(id), Transform3D(Basis.IDENTITY, Vector3.ZERO)
	)
	e.auto_tick = false
	w.add_child(e)
	e.set_physics_process(false)
	return e


func test_flinch_and_crit_root() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 700, 4200)
	runner_tree.root.add_child(w)
	var e := _enemy(w, "heap")
	var vis: Node3D = e.model if e.model else e._body_mesh
	var rest := vis.transform
	e.health = 1000.0
	e.take_hit(_hit(e, 1.0))
	check(e.flinches == 1 and e.crit_stun_left == 0.0, "a plain hit flinches, no root")
	e.tick(DT)
	check(not vis.transform.is_equal_approx(rest), "the body punches/leans")
	check(vis.transform.basis.y.x > 0.0, "leans along the hit (+x)")
	for i in 20:
		e.tick(DT)
	check(vis.transform.is_equal_approx(rest), "back at rest after FLINCH_S")
	e.take_hit(_hit(e, 1.0, 2.0))
	check_near(e.crit_stun_left, Enemy.CRIT_STUN_S, 1e-6, "a crit roots")
	check_near(e.move_scale(), 0.0, 1e-6, "rooted: no walk")
	check(not e.has_status_of(E.EARTH), "the root is not Earth's stagger")
	check(
		Enemy.flinch_pose(Enemy.FLINCH_S, true).y > Enemy.flinch_pose(Enemy.FLINCH_S, false).y,
		"a crit leans harder"
	)
	for i in 15:
		e.tick(DT)
	check_near(e.move_scale(), 1.0, 1e-6, "root over")
	e.reset()
	check(vis.transform.is_equal_approx(rest), "reset restores the pose")
	w.free()


func test_cast_keys() -> void:
	for i in ElementTable.IDS.size():
		var k := GameAudio.cast_key_for(i)
		check(k == "cast_" + ElementTable.IDS[i], "element %d -> %s" % [i, k])
		check(GameAudio.load_stream(k) != null, "%s loads" % k)
	check(GameAudio.cast_key_for(-1) == "cast", "no element -> cast")


func test_muzzle_flare() -> void:
	var v := Viewmodel.new()
	v.flash_muzzle()
	check(v.flare.visible and v.flares == 1, "flare on")
	for i in 6:
		v.tick_flare(DT)
	check(not v.flare.visible, "flare gone after FLARE_SECONDS")
	v.free()
