extends TestCase
## Steps 137-139 (Brands B3-B5): the brand fire modes on a Caster at 60 Hz.

const DT := 1.0 / 60.0
const P := WieldablePart.PartType
const E := ElementTable.Element


static func branded(e: E, wand := false, rarity := "basic") -> WieldableInstance:
	var base := "swift_wind_wand" if wand else "apprentice_fire_staff"
	var parts: Array[WieldablePart] = [PartRoller.from_seed(99, P.HEAD, rarity, e)]
	for id in ["basic_exterior"] if wand else ["basic_exterior", "basic_interior", "basic_handle"]:
		parts.append(WieldablePart.load_part(id))
	return Assembly.assemble(WieldableInstance.load_base(base).def, parts)


class Pool:
	extends RefCounted
	var mana := 1000.0
	var spent := 0.0

	func spend(c: float) -> bool:
		if mana + 1e-9 < c:
			return false
		mana -= c
		spent += c
		return true


func _caster(w: WieldableInstance) -> Array:
	var c := Caster.new(w)
	var pool := Pool.new()
	c.mana_spender = pool.spend
	return [c, pool]


## Holds the trigger for `ticks`; returns casts made.
func _hold(c: Caster, ticks: int, bolts: SpellBolts = null, aim: Caster.Aim = null) -> int:
	var n := 0
	for t in ticks:
		if c.tick(t == 0, true, DT, aim, bolts):
			n += 1
	return n


func _idle(c: Caster, ticks: int) -> void:
	for t in ticks:
		c.tick(false, false, DT, null, null)


# --- B3 -------------------------------------------------------------------------------


func test_heat_mode() -> void:
	var w := branded(E.FIRE)
	var cp := _caster(w)
	var c: Caster = cp[0]
	var pool: Pool = cp[1]
	var m := c.fire_mode() as HeatMode
	check(m != null and m.id() == &"heat", "Fire Head -> HeatMode")
	var events := []
	c.brand_event.connect(func(k, _v): events.append(k))
	var n := _hold(c, 600)
	var per := m.param("heat_per_cast", 0.0)
	check(is_equal_approx(pool.spent, 0.0), "no mana per cast")
	check(events.has(&"overheated"), "overheats under sustained fire")
	var expect_to_lock := ceili(1.0 / per - 1e-6)
	check(n >= expect_to_lock and n < 60, "casts %d (lock after %d)" % [n, expect_to_lock])
	check(m.cooldown_mult() < 1.0, "faster than base (%.2f)" % m.cooldown_mult())
	# Lockout: a fresh mode overheats, then cannot cast for overheat_seconds.
	var c2: Caster = _caster(branded(E.FIRE))[0]
	var m2 := c2.fire_mode() as HeatMode
	var t := 0
	while not m2.overheated and t < 600:
		c2.tick(false, true, DT, null, null)
		t += 1
	check(m2.overheated and m2.is_locked(), "locked at 100 %")
	var locked_ticks := 0
	while m2.overheated and locked_ticks < 600:
		if c2.tick(true, true, DT, null, null) and m2.overheated:
			fail("cast while overheated")
		locked_ticks += 1
	check(absf(locked_ticks * DT - m2.raw("overheat_seconds", 2.0)) < 0.05, "lock %.2f s" % (locked_ticks * DT))
	check(not m2.is_locked() and m2.heat <= m2.param("heat_per_cast", 0.0) + 1e-6, "cooled after the lock")


func test_heat_decay_and_vent() -> void:
	var c: Caster = _caster(branded(E.FIRE))[0]
	var m := c.fire_mode() as HeatMode
	c.tick(true, true, DT, null, null)
	var h := m.heat
	_idle(c, int(m.raw("vent_delay", 0.4) / DT) - 2)
	check(is_equal_approx(m.heat, h), "no decay inside vent_delay")
	_idle(c, 30)
	check(m.heat < h, "decays after the delay")
	for i in 20:
		c.tick(true, true, DT, null, null)
		_idle(c, 2)
	check(m.heat > 0.0 and c.reload(null, null) and m.venting, "R vents")
	check(not c.tick(true, true, DT, null, null), "no cast while venting")
	_idle(c, int(m.raw("vent_seconds", 1.0) / DT) + 2)
	check(m.heat == 0.0 and not m.venting, "vented to 0")
	check(not c.reload(null, null), "R at 0 heat does nothing")
	# Holstered: heat keeps cooling through Caster.cool().
	c.tick(true, true, DT, null, null)
	var h2 := m.heat
	for i in 60:
		c.cool(DT)
	check(m.heat < h2, "cools while holstered")


func test_heat_wand_lighter() -> void:
	var staff := _caster(branded(E.FIRE))[0].fire_mode() as HeatMode
	var wand := _caster(branded(E.FIRE, true))[0].fire_mode() as HeatMode
	check(wand.is_wand and wand.param("heat_per_cast", 0.0) < staff.param("heat_per_cast", 0.0), "wand heat lighter")
	check(wand.cooldown_mult() > staff.cooldown_mult() and wand.cooldown_mult() < 1.0, "wand cooldown cut scaled")


func test_spin_mode() -> void:
	var w := branded(E.AIR)
	var c: Caster = _caster(w)[0]
	var m := c.fire_mode() as SpinMode
	check(m != null, "Air Head -> SpinMode")
	check(c.wants_aim(false, true), "full auto: holding wants casts")
	var first := _hold(c, 30)
	var later := _hold(c, 30)
	_hold(c, 40)
	check(m.spin >= 1.0 - 1e-6, "spun up after spin_seconds held (spin %.2f)" % m.spin)
	var full := _hold(c, 30)
	check(full > first, "spins up: %d -> %d -> %d casts/0.5 s" % [first, later, full])
	check(c.bloom_mult() < 1.0, "less bloom")
	_idle(c, 30)
	check(m.spin < 1.0 and m.spin > 0.0, "spins down when released")
	_idle(c, 120)
	check(m.spin == 0.0, "stopped")
	# Q45: never below the 0.1 s floor, even on a fast wand at full spin.
	var fast := branded(E.AIR, true)
	fast.parts[1].fire_rate_modifier = 0.3
	var cf: Caster = _caster(fast)[0]
	_hold(cf, 120)
	var mins := 99.0
	var last := -1
	for t in 240:
		if cf.tick(false, true, DT, null, null):
			if last >= 0:
				mins = minf(mins, (t - last) * DT)
			last = t
	check(mins >= WieldableDef.MIN_COOLDOWN - 1e-6, "clamped at 0.1 s (%.3f)" % mins)


func test_events_and_fx_bits() -> void:
	var c: Caster = _caster(branded(E.FIRE))[0]
	var m := c.fire_mode()
	var t := 0
	while not (m as HeatMode).overheated and t < 600:
		c.tick(false, true, DT, null, null)
		t += 1
	check(m.fx_bits() & 2 != 0 or m.fx_bits() & 1 != 0, "heat bits while hot")
	check(m.meter_kind() == &"heat" and m.meter() >= 0.0, "heat meter")
	var u: Caster = _caster(WieldableInstance.load_base("apprentice_fire_staff"))[0]
	check(u.fire_mode().meter() < 0.0 and u.fire_mode().fx_bits() == 0, "unbranded: no meter")


# --- B4 -------------------------------------------------------------------------------


func _aim() -> Caster.Aim:
	return Caster.Aim.make(Vector3.ZERO, Vector3.FORWARD)


## Holds for `ticks` then releases; returns the last spawned bolt (or null).
func _charge_shot(c: Caster, ticks: int, bolts: SpellBolts) -> SpellBolts.Spawn:
	var n := bolts.live.size()
	for t in ticks:
		c.tick(t == 0, true, DT, _aim(), bolts)
	c.tick(false, false, DT, _aim(), bolts)
	return bolts.live[-1].spawn if bolts.live.size() > n else null


func test_charge_mode() -> void:
	var w := branded(E.WATER)
	var cp := _caster(w)
	var c: Caster = cp[0]
	var pool: Pool = cp[1]
	var bolts := SpellBolts.new()
	var m := c.fire_mode() as ChargeMode
	check(m != null and m.id() == &"charge", "Water Head -> ChargeMode")
	check(_hold(c, 30) == 0, "no cast while holding")
	check(absf(m.charge - 0.5) < 0.02, "half charged after 0.5 s (%.2f)" % m.charge)
	c.tick(false, false, DT, _aim(), bolts)
	check(bolts.live.size() == 1, "release casts")
	var half := bolts.live[0].spawn
	var base := w.damage()
	check(absf(half.damage - base * lerpf(0.6, 1.8, 0.5)) < base * 0.03, "half charge damage curve")
	check(half.chain_targets == 0, "half charge does not chain")
	check(absf(pool.spent - w.mana_cost()) < w.mana_cost() * 0.05, "half charge = ~1x mana")
	_idle(c, 60)
	var full := _charge_shot(c, 70, bolts)
	check(full != null and absf(full.damage - base * 1.8) < 1e-3, "full charge = max_mult")
	check(full.chain_targets == 2 and full.chain_range == 6.0, "full charge chains 2")
	_idle(c, 60)
	var tap := _charge_shot(c, 1, bolts)
	check(tap != null and tap.damage < base * 0.65, "tap = weak quick shot")
	var wm := (Caster.new(branded(E.WATER, true))).fire_mode()
	wm.shot = 1.0
	check(wm.damage_mult() < 1.8 and wm.damage_mult() > 1.0, "wand charge lighter")
	bolts.free()


func test_charge_lost_when_holstered() -> void:
	var c: Caster = _caster(branded(E.WATER))[0]
	_hold(c, 30)
	c.cool(DT)
	check((c.fire_mode() as ChargeMode).charge == 0.0, "holstering drops the charge")
	check(not c.tick(false, false, DT, null, null), "no cast after holstering")


func test_explosive_mode() -> void:
	var w := branded(E.EARTH)
	var cp := _caster(w)
	var c: Caster = cp[0]
	var pool: Pool = cp[1]
	var bolts := SpellBolts.new()
	check(c.fire_mode() is ExplosiveMode, "Earth Head -> ExplosiveMode")
	check(c.tick(true, true, DT, _aim(), bolts), "press casts")
	var s := bolts.live[0].spawn
	check(absf(s.damage - w.damage() * 2.0) < 1e-3, "boulder damage x2")
	check(absf(s.speed - w.projectile_speed() * 0.6) < 1e-3, "slow boulder")
	check(s.blast_radius == 3.0 and s.blast_fraction == 0.6, "blast fields")
	check(absf(pool.spent - w.mana_cost() * 1.6) < 1e-3, "x1.6 mana")
	check(absf(c.cooldown_left - w.cooldown() * 1.8) < 1e-6, "x1.8 cooldown")
	var ws := Caster.new(branded(E.EARTH, true)).fire_mode() as ExplosiveMode
	var sp := SpellBolts.Spawn.new()
	ws.modify(sp)
	check(sp.blast_radius < 3.0 and sp.blast_radius > 0.0, "wand blast smaller")
	bolts.free()


func _world(k: int) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(-9000, 0, -9000 - 300 * k)
	runner_tree.root.add_child(w)
	return w


func _enemy(w: Node3D, at: Vector3) -> Enemy:
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"), Transform3D(Basis(), at))
	w.add_child(e)
	if e is Gnawer:
		(e as Gnawer).auto_tick = false
	e.set_physics_process(false)
	return e


func _brand_hit(e: Enemy, el: E, dmg: float, s: SpellBolts.Spawn) -> SpellBolts.Hit:
	var h := SpellBolts.Hit.new()
	h.collider = e
	h.element = el
	h.damage = dmg
	h.point = e.global_position
	h.spawn = s
	h.result = Damage.Result.new()
	h.result.amount = dmg
	return h


func test_blast_hits_nearby_enemies() -> void:
	var w := _world(1)
	var a := _enemy(w, Vector3.ZERO)
	var near := _enemy(w, Vector3(1, 0, 0))
	var edge := _enemy(w, Vector3(2.9, 0, 0))
	var far := _enemy(w, Vector3(10, 0, 0))
	var hn := near.health
	var he := edge.health
	var hf := far.health
	var ha := a.health
	var s := SpellBolts.Spawn.new()
	s.blast_radius = 3.0
	s.blast_falloff = 0.5
	s.blast_fraction = 0.6
	var n := MagicEffects.blast(_brand_hit(a, E.EARTH, 10.0, s), runner_tree)
	check(n == 2, "two enemies in the blast (%d)" % n)
	check(a.health == ha, "the direct target is not blasted again")
	check(far.health == hf, "far enemy untouched")
	check(hn - near.health > he - edge.health and he > edge.health, "falloff toward the edge")
	check(near.stagger_left > 0.0, "earth blast staggers")
	w.queue_free()


func test_water_full_charge_chains_two() -> void:
	var w := _world(2)
	var a := _enemy(w, Vector3.ZERO)
	var b := _enemy(w, Vector3(3, 0, 0))
	var c := _enemy(w, Vector3(6, 0, 0))
	var d := _enemy(w, Vector3(9, 0, 0))
	var hb := b.health
	var hc := c.health
	var hd := d.health
	var s := SpellBolts.Spawn.new()
	s.chain_targets = 2
	s.chain_range = 6.0
	s.chain_fraction = 0.5
	var h := _brand_hit(a, E.WATER, 10.0, s)
	MagicEffects.on_hit(h)
	check(b.health < hb and c.health < hc, "jumped twice, onward from the last")
	check(d.health == hd, "only two jumps")
	var b2 := b.health
	MagicEffects.on_hit(_brand_hit(a, E.WATER, 10.0, null))
	check(b.health == b2, "a plain Water hit never chains")
	w.queue_free()
