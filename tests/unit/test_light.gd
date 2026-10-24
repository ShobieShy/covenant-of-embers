extends TestCase
## Steps 50/51 done check (Q2/Q3: Magewar Light): a Light hit heals its caster for
## max(8, 35% of the damage) and calls one 30 s Light summon per caster that smites enemies.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const E := ElementTable.Element


func _world(k: int) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(-7000 - 300 * k, 0, 7000)
	runner_tree.root.add_child(w)
	return w


func _player(w: Node3D) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	return p


func _enemy(w: Node3D, at: Vector3) -> Enemy:
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"), Transform3D(Basis(), at))
	w.add_child(e)
	if e is Gnawer:
		(e as Gnawer).auto_tick = false
	return e


func _hit(p: Player, e: Enemy, el: E, amount: float) -> SpellBolts.Hit:
	var h := SpellBolts.Hit.new()
	h.collider = e
	h.source = p
	h.element = el
	h.result = Damage.Result.new()
	h.result.amount = amount
	h.point = e.global_position
	return h


func test_heal_amounts() -> void:
	check(MagicEffects.light_heal_amount(5.0) == 8.0, "minimum 8")
	check(is_equal_approx(MagicEffects.light_heal_amount(100.0), 35.0), "35%")


func test_light_heals_and_summons_once() -> void:
	var w := _world(1)
	var p := _player(w)
	var e := _enemy(w, Vector3(0, 0, -3))
	p.health.value = 20.0
	var healed := [0.0]
	var on_heal := func(_pl: Player, a: float) -> void: healed[0] += a
	GameEvents.bus().player_healed.connect(on_heal)
	MagicEffects.on_hit(_hit(p, e, E.ARCANE, 40.0))
	check(p.health.value == 20.0, "Arcane doesn't heal")
	MagicEffects.on_hit(_hit(p, e, E.LIGHT, 40.0))
	check(is_equal_approx(p.health.value, 34.0), "healed 14: %f" % p.health.value)
	check(is_equal_approx(healed[0], 14.0), "heal event")
	var s := LightSummon.of(p)
	check(s != null, "summon called")
	MagicEffects.on_hit(_hit(p, e, E.LIGHT, 40.0))
	var count := runner_tree.get_nodes_in_group(LightSummon.GROUP).filter(
		func(n: Node) -> bool: return (n as LightSummon).owner_player == p
	)
	check(count.size() == 1, "one summon per caster")
	p.health.value = p.health.max_value() - 1.0
	MagicEffects.on_hit(_hit(p, e, E.LIGHT, 40.0))
	check(p.health.value == p.health.max_value(), "heal clamps at max")
	GameEvents.bus().player_healed.disconnect(on_heal)
	w.queue_free()


func test_summon_smites_then_expires() -> void:
	var w := _world(2)
	var p := _player(w)
	var e := _enemy(w, Vector3(0, 0, -4))
	var s := MagicEffects.summon_light(p)
	check(s != null, "made")
	s.auto_tick = false
	var hp := e.health
	s.tick(DT)
	check(s.smites == 1 and e.health < hp, "smote the gnawer: %f -> %f" % [hp, e.health])
	var far := _enemy(w, Vector3(0, 0, -40))
	var far_hp := far.health
	for i in int(LightSummon.LIFETIME / DT) + 2:
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			break
		s.tick(DT)
	check(far.health == far_hp, "out of range untouched")
	check(not is_instance_valid(s) or s.is_queued_for_deletion(), "gone after 30 s")
	await runner_tree.process_frame
	check(LightSummon.of(p) == null, "no live summon")
	check(MagicEffects.summon_light(p) != null, "can summon again")
	w.queue_free()
