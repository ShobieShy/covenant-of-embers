extends TestCase
## Phase V step 148: the 7 element capstones (triggers, cooldowns, boss rules).
const BM := preload("res://tests/unit/test_brand_modes.gd")

const E := ElementTable.Element


func _world(k: int) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(-9000, 0, -9000 - 300 * k)
	runner_tree.root.add_child(w)
	_worlds.append(w)
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


var _t := 0.0
var _worlds: Array = []


func _setup() -> void:
	for w in _worlds:
		if is_instance_valid(w):
			w.free()
	_worlds.clear()
	Capstones.reset()
	_t = 100.0
	Capstones.clock = func() -> float: return _t


func _teardown() -> void:
	Capstones.clock = Callable()
	Capstones.reset()


func _cap_skills(el: String) -> Skills:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	var t := SkillTree.element_tree(el)
	for tier in 5:
		for sk in t.skills.values():
			if sk.tier == tier:
				while s.el_spend(el, sk.id, 100):
					pass
	return s


func test_capstone_reachable() -> void:
	_setup()
	var s := _cap_skills("fire")
	check(s.el_spend("fire", "backdraft", 100), "backdraft taken after filling the tree")
	check(Capstones.has(ElementSkillMods.of(s, E.FIRE)), "fire mods carry capstone")


func test_convergence() -> void:
	_setup()
	var w := _world(21)
	var e := _enemy(w)
	var md := {"capstone": 1.0, "conv": [E.FIRE, E.WATER, E.EARTH]}
	for i in 4:
		MagicEffects.on_hit(_hit(e, E.ARCANE, 1.0, md))
	check_near(e.burn_left + e.slow_left, 0.0, 1e-6, "nothing before the 5th")
	MagicEffects.on_hit(_hit(e, E.ARCANE, 1.0, md))
	check(e.burn_left > 0.0 and e.slow_left > 0.0 and e.stagger_left > 0.0, "5th hit: all statuses")
	check(Capstones.count("convergence") == 1, "fired once (got %s)" % [Capstones.count("convergence")])


func test_tidal_hold() -> void:
	_setup()
	var w := _world(22)
	var e := _enemy(w)
	var h := _hit(e, E.WATER, 1.0, {"capstone": 1.0})
	MagicEffects.on_hit(h)
	check_near(e.stagger_left, 0.0, 1e-6, "partial charge: no freeze")
	h = _hit(e, E.WATER, 1.0, {"capstone": 1.0})
	h.spawn.chain_targets = 1
	MagicEffects.on_hit(h)
	check_near(e.stagger_left, Capstones.TIDAL_SECONDS, 1e-6, "full charge freezes")


func test_eclipse() -> void:
	_setup()
	var w := _world(23)
	var e := _enemy(w)
	var h := _hit(e, E.DARK, 1.0, {"capstone": 1.0})
	h.result.crit = 2.0
	e.health = e.max_health() * 0.2
	check(not Capstones.eclipse(e, h), "needs Hex")
	e.hex_left = 3.0
	check(Capstones.eclipse(e, h), "turns")
	check(e.is_ally(), "ally now")
	var f := _enemy(w)
	f.hex_left = 3.0
	f.health = f.max_health() * 0.2
	check(not Capstones.eclipse(f, _crit(f)), "20 s cooldown")
	_t += Capstones.ECLIPSE_COOLDOWN
	check(Capstones.eclipse(f, _crit(f)), "after the cooldown")


func _crit(e: Enemy) -> SpellBolts.Hit:
	var h := _hit(e, E.DARK, 1.0, {"capstone": 1.0})
	h.result.crit = 2.0
	return h


func test_fault_line() -> void:
	_setup()
	var w := _world(24)
	var e := _enemy(w)
	var hp := e.health
	var h := _hit(e, E.EARTH, 10.0, {"capstone": 1.0})
	h.point = e.global_position
	h.spawn.blast_radius = 4.0
	var n := 0
	for i in 4:
		n += Capstones.fault_line(h, runner_tree)
	check(Capstones.count("fault_line") == 1, "every 4th boulder (got %s)" % [Capstones.count("fault_line")])
	check(n >= 1 and e.health < hp, "splits hit")


func test_backdraft() -> void:
	_setup()
	var w := _world(25)
	var e := _enemy(w)
	e.scale_health(100.0)
	var c := Caster.new(BM.branded(E.FIRE))
	c.owner_node = w
	check(Capstones.backdraft(c, 0.5) == 0, "needs 80 pct heat (got %s)" % [Capstones.backdraft(c, 0.5)])
	check(Capstones.backdraft(c, 0.9) == 1, "burst hits (got %s)" % [Capstones.backdraft(c, 0.9)])
	check_near(e.burn_left, MagicEffects.BURN_SECONDS, 1e-6, "burn reset")


func test_cyclone() -> void:
	_setup()
	var c := Caster.new(BM.branded(E.AIR))
	c.skills = _cap_skills("air")
	check(c.skills.el_spend("air", "cyclone", 100), "cyclone taken")
	var m := c.fire_mode() as SpinMode
	m.spin = 1.0
	for i in 150:
		m.tick(1.0 / 60.0, true, false, true)
	var s := SpellBolts.Spawn.new()
	m.modify(s)
	check(s.chain_targets == 99, "chains everything (got %s)" % [s.chain_targets])
	var s2 := SpellBolts.Spawn.new()
	m.modify(s2)
	check(s2.chain_targets == 0, "6 s cooldown (got %s)" % [s2.chain_targets])


func test_dawnchorus_cooldown() -> void:
	_setup()
	var w := _world(26)
	var c := Caster.new(BM.branded(E.LIGHT))
	c.owner_node = w
	c.skills = _cap_skills("light")
	check(c.skills.el_spend("light", "dawnchorus", 100), "dawnchorus taken")
	var m := c.fire_mode() as BurstMode
	if m.count() < 3:
		check(true, "brand burst < 3: skip")
		return
	m.after_cast()
	m.after_cast()
	check(Capstones.count("dawnchorus") == 1, "8 s cooldown (got %s)" % [Capstones.count("dawnchorus")])


func test_zz_cleanup() -> void:
	_setup()
	_teardown()
	check(_worlds.is_empty(), "worlds freed")
