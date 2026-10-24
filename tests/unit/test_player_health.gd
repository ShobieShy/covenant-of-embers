extends TestCase
## Step 13 done check (player half): health + shield, enemy hits, i-frames, death, respawn.
##  - the pool: 100 health (Magewar's value_max; full, not Magewar's 80 start) behind a
##    50 shield; damage takes the shield first, the rest comes off health;
##  - the shield regenerates 25/s once 3 s (180 ticks) have passed since the last damage
##    (sub-tick exact; a hit restarts the delay); health never regenerates;
##  - enemy hits resolve through Damage (Arcane target, no crit): a 3 Earth bite with 0.3
##    Earth resist takes 2.1; resist caps at 60 %; a Fire bolt resolves on damage_target;
##  - a Gnawer bite during the dash's i-frames is dodged and nothing is taken; the next
##    bite, 48 ticks later, lands (3 off the shield);
##  - health 0 = dead once (no more hits, no input, Gnawers lose him), respawn after 3 s
##    at the spawn point with health, shield, mana and Breath full (bonuses kept).

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const E := ElementTable.Element

func _world(at: Vector3, boxes: Array = []) -> Node3D:
	var w := Node3D.new()
	w.position = at
	runner_tree.root.add_child(w)
	var b := Node3D.new()
	b.name = "Boxes"
	w.add_child(b)
	_box(b, Vector3(0, -0.1, 0), Vector3(20, 0.1, 20))
	for spec in boxes:
		_box(b, spec[0], spec[1])
	var nav := LevelNavigation.new()
	nav.name = "Navigation"
	w.add_child(nav)
	for i in 120:
		if nav.map_ready():
			break
		await runner_tree.physics_frame
	check(nav.map_ready(), "navmesh synced to the map")
	return w

func _box(parent: Node3D, center: Vector3, half: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.position = center
	parent.add_child(b)

func _player(w: Node3D, feet: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	p.position = feet   # local, placed before add_child (Jolt sees it at once)
	w.add_child(p)
	p.spawn(w.global_position + feet, 0.0)
	return p

func _gnawer(w: Node3D, feet: Vector3, p: Player) -> Gnawer:
	var d := EnemyTable.load_default().find("gnawer")
	var g := Enemy.create(d, Transform3D(Basis.IDENTITY, feet)) as Gnawer
	g.auto_tick = false
	w.add_child(g)
	g.target = p
	g.attacked.connect(p.on_enemy_attack)
	return g

func test_tuning_and_full_start() -> void:
	var t := PlayerTuning.new()
	check(t.health_max == 100.0 and t.shield_max == 50.0 and t.shield_regen_per_sec == 25.0
		and t.shield_regen_delay == 3.0 and t.respawn_delay == 3.0, "health tuning 100 / 50 shield, 25/s after 3 s, respawn 3 s")
	var h := Health.from_tuning(t)
	check(h.value == 100.0 and h.shield == 50.0 and not h.dead and not h.regenerating(), "starts full (Magewar starts at 80)")
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	check(p.health != null and p.health.value == 100.0 and p.damage_target.affinity == E.ARCANE and p.alive(), "the player has health and an Arcane damage target")
	p.free()

## Done check: shield first, then health.
func test_damage_order_shield_then_health() -> void:
	var h := Health.from_tuning(PlayerTuning.new())
	var seen: Array = []
	h.damaged.connect(func(s: float, hp: float) -> void: seen.append([s, hp]))
	h.take(30.0)
	check(h.shield == 20.0 and h.value == 100.0, "30: the shield takes it all (%.1f / %.1f)" % [h.shield, h.value])
	h.take(30.0)
	check(h.shield == 0.0 and h.value == 90.0, "30 more: 20 off the shield, 10 off health (%.1f / %.1f)" % [h.shield, h.value])
	h.take(5.0)
	check(h.value == 85.0 and h.shield == 0.0, "no shield: health")
	check(seen == [[30.0, 0.0], [20.0, 10.0], [0.0, 5.0]], "damaged(shield, health) per hit: %s" % [seen])
	check(h.shield_absorbed == 50.0 and h.health_lost == 15.0 and h.hits == 3, "totals")
	h.take(0.0)
	h.take(-4.0)
	check(h.hits == 3 and h.value == 85.0, "0 / negative do nothing")

## Done check: regen timing.
func test_shield_regen_timing() -> void:
	var h := Health.from_tuning(PlayerTuning.new())
	h.take(60.0)   # shield 0, health 90
	for i in 179:
		h.tick(DT)
	check(h.shield == 0.0, "nothing for 179 ticks (%.6f)" % h.shield)
	h.tick(DT)
	check(h.shield < 1e-3, "tick 180 = exactly 3 s: still ~0 (%.6f)" % h.shield)
	h.tick(DT)
	check_near(h.shield, 25.0 / 60.0, 1e-4, "tick 181: one tick of 25/s")
	for i in 59:
		h.tick(DT)
	check_near(h.shield, 25.0, 1e-4, "1 s of regen: 25")
	h.take(10.0)
	check_near(h.shield, 15.0, 1e-4, "a hit mid-regen")
	for i in 179:
		h.tick(DT)
	check_near(h.shield, 15.0, 1e-4, "and the delay restarts")
	for i in 200:
		h.tick(DT)
	check(h.shield == 50.0, "regens to exactly 50 (%.9f)" % h.shield)
	check(h.value == 90.0, "health never regenerates")
	# Sub-tick exact at other rates: 3 s delay + 2 s full regen = 5 s at 144 Hz too.
	var g := Health.from_tuning(PlayerTuning.new())
	g.take(50.0)
	var t := 0
	while g.shield < 50.0 and t < 2000:
		g.tick(1.0 / 144.0)
		t += 1
	check(t == 720, "0 -> 50 in 720 ticks at 144 Hz (%d)" % t)

## Done check: 0.3 Earth resist turns a 3 bite into 2.1.
func test_enemy_hit_resolves_with_resist() -> void:
	var w := await _world(Vector3(3200, 0, -2400))
	var p := _player(w, Vector3(0, 0, 0))
	check(ElementTable.load_default().effectiveness(E.EARTH, E.ARCANE) == 1.0, "Earth on Arcane is neutral")
	var r := p.take_enemy_hit(3.0, E.EARTH)
	check(r != null and r.amount == 3.0 and p.health.shield == 47.0, "a 3 Earth bite takes 3 off the shield")
	p.damage_target.set_resist(E.EARTH, 0.3)
	r = p.take_enemy_hit(3.0, E.EARTH)
	check(r != null and absf(r.amount - 2.1) < 1e-9 and r.resist == 0.3, "0.3 Earth resist: 3 -> 2.1 (%f)" % (r.amount if r else -1.0))
	check_near(p.health.shield, 44.9, 1e-9, "shield 44.9")
	p.damage_target.set_resist(E.EARTH, 0.9)
	r = p.take_enemy_hit(10.0, E.EARTH)
	check(r != null and absf(r.amount - 4.0) < 1e-9, "0.9 resist caps at 60 %: 10 -> 4")
	r = p.take_enemy_hit(10.0, E.FIRE)
	check(r != null and r.amount == 10.0 * ElementTable.load_default().effectiveness(E.FIRE, E.ARCANE) and r.crit == 1.0, "other elements unresisted, melee never crits")
	p.damage_target.weak_point = true
	r = p.take_enemy_hit(5.0, E.WATER)
	check(r != null and r.crit == 1.0 and p.damage_target.weak_point, "even with weak_point set: no crit (flag left as it was)")
	p.damage_target.weak_point = false
	check(p.hits_taken == 5, "5 hits taken")
	# A bolt resolves on damage_target the same way (SpellBolts -> take_hit).
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	await runner_tree.physics_frame
	var before := p.health.shield + p.health.value
	var s := SpellBolts.Spawn.new()
	s.origin = w.global_position + Vector3(0, 1.0, -3)
	s.direction = Vector3(0, 0, 1)
	s.speed = 60.0
	s.range_m = 10.0
	s.element = E.FIRE
	s.damage = 10.0
	bolts.spawn(s)
	var hits: Array[SpellBolts.Hit] = []
	for i in 20:
		hits.append_array(bolts.tick(DT))
	var want := Damage.resolve_hit(10.0, E.FIRE, Damage.Target.new(E.ARCANE)).amount
	check(hits.size() == 1 and hits[0].collider == p and hits[0].result != null and is_equal_approx(hits[0].result.amount, want), "a Fire bolt hits the player and resolves on his Arcane target")
	check_near(before - (p.health.shield + p.health.value), want, 1e-6, "and he takes it")
	w.free()

## Done check: dash i-frames ignore a bite.
func test_dash_iframes_ignore_a_bite() -> void:
	# The player faces -Z with a wall right in front (the dash goes nowhere); the Gnawer
	# is 0.9 m behind him: it attacks on its 3rd tick.
	var w := await _world(Vector3(3200, 0, -2200), [[Vector3(0, 1.0, -0.45), Vector3(2, 1.0, 0.1)]])
	var p := _player(w, Vector3(0, 0, 0))
	var g := _gnawer(w, Vector3(0, 0, 0.9), p)
	var still := PlayerInput.hold([])
	for i in 5:
		p.tick(still, DT)   # settled on the floor
	await runner_tree.physics_frame
	g.tick(DT)
	g.tick(DT)
	check(g.state == Gnawer.State.CHASE, "chasing after 2 ticks (%s)" % Gnawer.state_name(g.state))
	p.tick(PlayerInput.hold([], [&"dash"]), DT)
	check(p.dash.dashes == 1 and p.invulnerable(), "dashing into the wall: i-frames on")
	g.tick(DT)
	check(g.attacks.size() == 1 and g.attacks[0].dodged and g.dodged == 1, "the bite during the i-frames is dodged")
	check(p.health.shield == 50.0 and p.health.value == 100.0 and p.hits_taken == 0 and p.hits_ignored == 1, "nothing taken")
	# Ignored even when called directly while invulnerable.
	check(p.take_enemy_hit(3.0, E.EARTH) == null and p.health.shield == 50.0 and p.hits_ignored == 2, "take_enemy_hit ignored in i-frames")
	var landed_at := -1
	for i in 60:
		p.tick(still, DT)
		g.tick(DT)
		if p.hits_taken == 1 and landed_at < 0:
			landed_at = g.ticks
	check(not p.invulnerable(), "i-frames over (0.1 s)")
	check(landed_at == 3 + 48, "the next bite lands 48 ticks later (tick %d)" % landed_at)
	check(p.health.shield == 47.0 and p.health.value == 100.0, "3 off the shield (%.1f / %.1f)" % [p.health.shield, p.health.value])
	w.free()

## Done check: death at 0; respawn.
func test_death_and_respawn() -> void:
	var w := await _world(Vector3(3200, 0, -2000))
	var p := _player(w, Vector3(0, 0, 5))
	var deaths := [0]
	var respawned := [0]
	p.died.connect(func(_p: Player) -> void: deaths[0] += 1)
	p.respawned.connect(func(_p: Player) -> void: respawned[0] += 1)
	var still := PlayerInput.hold([])
	for i in 5:
		p.tick(still, DT)
	# Wander off, spend mana and Breath, carry a mana bonus.
	p.mana.set_max_bonus(5.0)
	p.mana.spend(40.0)
	p.breath.spend(25.0)
	p.global_position = w.global_position + Vector3(3, 0, -2)
	p.take_enemy_hit(149.0, E.EARTH)
	check(p.alive() and p.health.value == 1.0 and p.health.shield == 0.0, "149: 1 health left")
	p.take_enemy_hit(1.0, E.EARTH)
	check(not p.alive() and p.health.value == 0.0 and p.health.dead and deaths[0] == 1 and p.deaths == 1, "1 more: dead at exactly 0, died once")
	check(p.take_enemy_hit(50.0, E.EARTH) == null and p.deaths == 1 and p.hits_ignored == 1, "hits on the dead are ignored")
	# A Gnawer loses a dead target.
	var g := _gnawer(w, Vector3(3, 0, -4), p)
	for i in 5:
		g.tick(DT)
	check(g.state == Gnawer.State.IDLE and g.bites == 0, "a Gnawer ignores the dead player (%s)" % Gnawer.state_name(g.state))
	var at := p.global_position
	for i in 179:
		p.tick(PlayerInput.hold([&"move_forward"], [&"jump"]), DT)
	check(not p.alive() and p.global_position == at and p.jumps == 0, "dead: no input, no movement for 179 ticks")
	p.tick(still, DT)
	check(p.alive() and respawned[0] == 1 and p.respawns == 1, "respawned on tick 180 (3 s)")
	check(p.global_position.is_equal_approx(w.global_position + Vector3(0, 0, 5)) and is_equal_approx(p.yaw, 0.0), "back at the spawn point")
	check(p.health.value == 100.0 and p.health.shield == 50.0, "full health and shield")
	check(p.mana.value == 105.0 and p.mana.max_bonus == 5.0, "mana refilled, bonus kept (%.1f)" % p.mana.value)
	check(p.breath.value == p.breath.max_value(), "Breath refilled")
	check(p.take_enemy_hit(3.0, E.EARTH) == null and p.health.shield == 50.0, "1 s spawn protection after the respawn (step 14)")
	for i in 60:
		p.tick(still, DT)
	p.take_enemy_hit(3.0, E.EARTH)
	check(p.health.shield == 47.0, "takes hits again after it")
	w.free()
