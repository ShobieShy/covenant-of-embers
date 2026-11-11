extends TestCase
## 0.8.3 #24: each fighting enemy has at least two named patterns, strafes inside
## its pocket, and can wind up a second strike. Boss phase thresholds stay put.

const DT := 1.0 / 60.0
class Dummy:
	extends Node3D
	func eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.5, 0.0)


func _flat(at: Vector3) -> Node3D:
	var w := Node3D.new()
	w.position = at
	runner_tree.root.add_child(w)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(40, 0.2, 40)
	cs.shape = s
	b.add_child(cs)
	b.position = Vector3(0, -0.1, 0)
	w.add_child(b)
	await runner_tree.physics_frame
	await runner_tree.physics_frame
	return w


func _spawn(w: Node3D, id: String, at: Vector3) -> Gnawer:
	var e := Enemy.create(EnemyTable.load_default().find(id), Transform3D(Basis.IDENTITY, at)) as Gnawer
	e.auto_tick = false
	w.add_child(e)
	return e


func test_every_fighter_has_two_patterns() -> void:
	var table := EnemyTable.load_default()
	var n := 0
	for d in table.defs:
		if d.ai.is_empty():
			check(CombatStyle.for_id(d.id) == null, "dummy %s has no style" % d.id)
			continue
		var s := CombatStyle.for_id(d.id)
		check(s != null and s.patterns.size() >= 2, "%s has two patterns (%s)" % [d.id, s.patterns if s else "missing"])
		n += 1
	check(n >= 16, "covered the fighting roster (%d)" % n)
	var maw := CombatStyle.for_id("blightmaw_matriarch")
	check(maw.special == "feint" and maw.patterns.has("spore") and maw.patterns.has("husk"), "matriarch keeps her phase attacks")
	check(is_equal_approx(Blightmaw.PHASE_2_AT, 0.66) and is_equal_approx(Blightmaw.PHASE_3_AT, 0.33), "matriarch phases")
	check(is_equal_approx(Forgemaw.PHASE_2_AT, 0.66) and is_equal_approx(Forgemaw.PHASE_3_AT, 0.33), "forgemaw phases")
	check(is_equal_approx(Filth.PHASE_2_AT, 0.66) and is_equal_approx(Filth.PHASE_3_AT, 0.33), "filth phases")
	var delta := CombatStyle.clamp_pocket(Vector3(0, 0, 5), Vector3(0, 0, -1), 0.9, 1.0, 0.7)
	check_near(delta.z, 0.08, 0.02, "a 5 m retreat is shaved to the pocket")


func test_gnawer_strafes_lunges_and_poses() -> void:
	var w := await _flat(Vector3(12000, 0, 0))
	var g := _spawn(w, "gnawer", Vector3.ZERO)
	var t := Dummy.new()
	t.position = Vector3(0, 0, -30)
	w.add_child(t)
	for i in 5:
		g.tick(DT)
	check(g.pose == "idle", "no target in range yet is idle (%s)" % g.pose)
	g.target = t
	t.position = Vector3(0, 0, -4)
	var saw_chase := false
	for i in 40:
		g.tick(DT)
		saw_chase = saw_chase or g.pose == "chase"
	check(saw_chase and (g.state == Gnawer.State.CHASE or g.state == Gnawer.State.ATTACK), "closes with a chase pose")
	t.position = g.position + Vector3(0, 0, -0.9)
	g.style.arm_s = 100.0
	var x0 := g.global_position.x
	for i in 50:
		g.tick(DT)
	check(absf(g.global_position.x - x0) > 0.25, "strafes in the pocket (dx %.2f)" % absf(g.global_position.x - x0))
	check(g.distance <= g.rusher.attack_range + 0.05, "strafe stays in bite range (%.2f)" % g.distance)
	g.style.arm_s = 0.0
	g.style.windup = 0.2
	g.engaged = 10.0
	g.attack_timer = 1.0
	g.pattern_cd = 0.0
	var saw_windup := false
	var saw_attack := false
	var saw_recover := false
	for i in 40:
		g.tick(DT)
		saw_windup = saw_windup or g.pose == "windup"
		saw_attack = saw_attack or g.pose == "attack"
		saw_recover = saw_recover or g.pose == "recover"
		if g.specials > 0 and g.pose == "recover":
			break
	check(g.specials >= 1 and saw_windup and saw_attack and saw_recover, "lunge winds up, hits, recovers (poses windup %s attack %s recover %s)" % [saw_windup, saw_attack, saw_recover])
	check(is_equal_approx(g.attacks[-1].damage, 3.0 * g.style.damage_mul), "lunge hits harder (%.2f)" % g.attacks[-1].damage)
	var before := g.global_position
	var hit := SpellBolts.Hit.new()
	hit.direction = Vector3(0, 0, 1)
	hit.element = ElementTable.Element.ARCANE
	hit.result = Damage.Result.new()
	hit.result.amount = 4.0
	g.take_hit(hit)
	check(g.dodge_left > 0.0 and g.knockbacks == 0, "a light hit sidesteps")
	for i in 8:
		g.tick(DT)
	check(g.pose == "hurt" or g.flinches > 0, "the hit reads as hurt")
	check(Gnawer._flat(g.global_position - before).length() > 0.05, "the dodge moves it")
	g.apply_damage(1000.0, ElementTable.Element.FIRE)
	g.tick(DT)
	check(g.pose == "death" and g.state == Gnawer.State.DEAD, "death pose")
	w.free()


func test_heap_cleave_does_not_replace_the_slam() -> void:
	var w := await _flat(Vector3(12100, 0, 0))
	var h := _spawn(w, "heap", Vector3.ZERO) as Heap
	var t := Dummy.new()
	t.position = Vector3(0, 0, -1.5)
	w.add_child(t)
	h.target = t
	h.style.arm_s = 100.0
	for i in 80:
		h.tick(DT)
		if h.landed > 0:
			break
	check(h.landed == 1 and h.specials == 0 and is_equal_approx(h.attacks[0].damage, 8.0), "first strike is still the slam")
	h.style.arm_s = 0.0
	h.engaged = 20.0
	h.attack_timer = 1.5
	h.pattern_cd = 0.0
	for i in 50:
		h.tick(DT)
		if h.specials > 0:
			break
	check(h.specials == 1 and is_equal_approx(h.attacks[-1].damage, 8.0 * h.style.damage_mul), "cleave is the second strike")
	check(h.slams == 1, "the cleave did not start another slam")
	w.free()


func test_scorchling_fans_once_the_fight_has_lasted() -> void:
	var w := await _flat(Vector3(12200, 0, 0))
	var e := _spawn(w, "scorchling", Vector3.ZERO) as Scorchling
	var t := Dummy.new()
	t.position = Vector3(0, 0, -5)
	w.add_child(t)
	e.target = t
	e.style.arm_s = 0.0
	e.engaged = 10.0
	for i in 20:
		e.tick(DT)
		if e.specials > 0:
			break
	check(e.specials >= 1 and e.shots >= 2, "the fan is a second ember (%d shots, %d fans)" % [e.shots, e.specials])
	w.free()
