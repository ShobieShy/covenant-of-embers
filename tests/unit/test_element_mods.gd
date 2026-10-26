extends TestCase
## Phase V step 145: ElementSkillMods; each element tree changes only its own element;
## Caster damage/cost/accuracy; MagicEffects status knobs.

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


func _skills(el: String, sid: String, n: int) -> Skills:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	for i in n:
		s.el_spend(el, sid, 100)
	return s


func test_only_own_element() -> void:
	var s := _skills("fire", "long_burn", 3)
	check_near(ElementSkillMods.value(ElementSkillMods.of(s, E.FIRE), "status_seconds"), 1.5, 1e-6, "fire +1.5 s")
	check(ElementSkillMods.of(s, E.WATER).is_empty(), "water untouched")
	check(ElementSkillMods.of(null, E.FIRE).is_empty(), "no skills")


func test_status_knobs() -> void:
	var w := _world(1)
	var e := _enemy(w)
	MagicEffects.on_hit(_hit(e, E.FIRE, 10.0, {"status_seconds": 1.5}))
	check_near(e.burn_left, 4.5, 1e-6, "burn 4.5 s")
	var f := _enemy(w)
	MagicEffects.on_hit(_hit(f, E.WATER, 10.0, {"status_pct": 30.0, "status_seconds": 1.0}))
	check_near(f.slow_factor, ElementSkillMods.SLOW_FLOOR, 1e-6, "slow floor")
	check_near(f.slow_left, 3.5, 1e-6, "slow 3.5 s")
	var g := _enemy(w)
	MagicEffects.on_hit(_hit(g, E.EARTH, 10.0, {"status_seconds": 0.2}))
	check_near(g.stagger_left, 0.6, 1e-6, "stagger 0.6")
	var k := _enemy(w)
	MagicEffects.on_hit(_hit(k, E.FIRE, 10.0, {}))
	check_near(k.burn_left, 3.0, 1e-6, "plain burn unchanged")
	w.queue_free()


func test_caster_mods() -> void:
	var c := Caster.new(WieldableInstance.load_base("apprentice_fire_staff"))
	var base_acc := c.accuracy_bonus()
	c.skills = _skills("fire", "hot_coals", 5)
	check_near(ElementSkillMods.value(c.mods(), "damage_pct"), 15.0, 1e-6, "15% fire")
	var s := SpellBolts.Spawn.new()
	s.damage = 10.0
	c._apply_mods(s)
	check_near(s.damage, 11.5, 1e-6, "damage x1.15")
	c.skills = _skills("water", "cold_current", 5)
	check(c.mods().is_empty(), "water skills don't touch a fire staff")
	check_near(c.accuracy_bonus(), base_acc, 1e-6, "accuracy unchanged")
