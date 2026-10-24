extends TestCase
## Step 5 done check (port of the archived test_dash.cpp, old step 16): the dash.
##  - 2 charges, a 3rd dash is refused, a charge is back exactly 1.5 s (90 ticks) after the
##    first was spent and the 2nd 1.5 s later (180); bonus charge hook;
##  - a dash covers 6.000 m +-0.05 in 9 ticks (0.15 s at 60 Hz), along the view with no
##    move key or along the move keys, and ends into rest / straight back to walking;
##  - a wall stops it (no tunnelling at 40 m/s), one air dash per jump (back on landing),
##    25 Breath per dash, refused when short or exhausted (nothing spent), the 1 s regen
##    delay restarting, a dash ending a slide (crouch kept while Crouch is held, no new
##    slide), 0.1 s i-frames (6 ticks at 60 Hz, 15 at 144 Hz).

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const NORTH := Vector3(0, 0, -1)


func _world() -> Node3D:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	return w


func _box(parent: Node, center: Vector3, half: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.position = center
	parent.add_child(b)


func _flat() -> Node3D:
	var w := _world()
	_box(w, Vector3(0, -0.5, 0), Vector3(40, 0.5, 40))
	return w


func _player(parent: Node) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	parent.add_child(p)
	p.spawn(Vector3.ZERO, 0.0)
	return p


func _run(p: Player, n: int, held: Array = [], pressed: Array = []) -> void:
	for i in n:
		p.tick(PlayerInput.hold(held, pressed), DT)


# --- Dash on its own ----------------------------------------------------------------


func test_charges_and_recharge_90_180() -> void:
	var d := Dash.new()
	var b := Breath.new()
	check(d.charges == 2 and d.max_charges() == 2 and not d.active(), "2 charges")
	check(d.try_start(NORTH, true, b), "1st dash")
	check(not d.try_start(NORTH, true, b), "refused while dashing")
	var ticks := 0
	var dash_ticks := 0
	var covered := 0.0
	while d.active():
		covered += d.advance(DT)
		dash_ticks += 1
		ticks += 1
	check(dash_ticks == 9 and absf(covered - 9.0) < 1e-4, "0.15 s = 9 ticks (%d, %f)" % [dash_ticks, covered])
	check(d.charges == 1 and d.try_start(NORTH, true, b), "2nd dash")
	while d.active():
		d.advance(DT)
		ticks += 1
	check(d.charges == 0 and not d.try_start(NORTH, true, b), "3rd refused: no charge")
	check_near(b.value, 50.0, 1e-6, "2 x 25 Breath, the refused one cost nothing")
	var first := -1
	var second := -1
	while second < 0 and ticks < 1000:
		d.advance(DT)
		ticks += 1
		if first < 0 and d.charges == 1:
			first = ticks
		if d.charges == 2:
			second = ticks
	print(
		"    dash charges: 2 used (dash = %d ticks), back after %d and %d ticks (90/180)" % [dash_ticks, first, second]
	)
	check(first == 90 and second == 180, "recharge 1.5 s each from the first dash (%d/%d)" % [first, second])
	check(d.recharge_progress() == 0.0, "full: no recharge running")
	d.set_bonus_charges(1)  # PLAN §30.8 Sandals: a 3rd charge
	check(d.max_charges() == 3 and d.charges == 2, "bonus charge slot")
	for i in 90:
		d.advance(DT)
	check(d.charges == 3, "bonus charge recharges")
	d.set_bonus_charges(0)
	check(d.charges == 2, "bonus removed")


func test_air_dash_unit_and_refusals() -> void:
	var d := Dash.new()
	var b := Breath.new()
	check(d.try_start(Vector3.RIGHT, false, b), "one in the air")
	while d.active():
		d.advance(DT)
	check(d.charges == 1 and not d.air_dash_available(), "air dash used")
	check(
		not d.try_start(Vector3.RIGHT, false, b) and d.charges == 1 and b.value == 75.0, "2nd air dash refused, no cost"
	)
	d.land()
	check(d.try_start(Vector3.RIGHT, false, b), "back after landing")
	var z := Dash.new()
	check(
		not z.try_start(Vector3.ZERO, true, b) and not z.try_start(Vector3.UP, true, b) and z.dashes == 0,
		"zero / vertical direction refused"
	)
	var g := Dash.new()
	check(g.try_start(NORTH, true, Breath.new()) and g.air_dash_available(), "a ground dash keeps the air dash")
	# Breath: 24 left -> refused; back at >= 25 -> dash and the 1 s delay restarts.
	var s := Dash.new()
	var sb := Breath.new()
	check(sb.spend(76.0), "24 left")
	check(
		not s.try_start(NORTH, true, sb) and s.charges == 2 and s.dashes == 0 and sb.value == 24.0,
		"short Breath: refused, nothing spent"
	)
	for i in 63:
		sb.tick(false, DT)
	check(sb.value >= 25.0 and s.try_start(NORTH, true, sb), "dash once 25 is back")
	check(sb.seconds_since_use == 0.0, "spend restarted the regen delay")


func test_iframes_60_and_144_hz() -> void:
	for hz in [60, 144]:
		var d := Dash.new()
		var dt := 1.0 / float(hz)
		check(d.try_start(NORTH, true, Breath.new()) and d.invulnerable(), "invulnerable from the start")
		var n := 0
		for i in 100:
			d.advance(dt)
			if d.invulnerable():
				n += 1
		print("    i-frames @%d Hz: %d tick(s)" % [hz, n])
		check(n == (6 if hz == 60 else 15), "every tick starting within 0.1 s @%d Hz (%d)" % [hz, n])
		var t := Dash.new()
		var cov := 0.0
		t.try_start(NORTH, true, Breath.new())
		while t.active():
			cov += t.advance(dt) * dt
		check_near(cov * t.speed(), 6.0, 1e-6, "6 m @%d Hz" % hz)


func test_from_tuning() -> void:
	var d := Dash.from_tuning(load("res://resources/player/player_tuning.tres"))
	check(
		(
			d.distance == 6.0
			and d.duration == 0.15
			and d.base_charges == 2
			and d.charges == 2
			and d.breath_cost == 25.0
			and d.invulnerability == 0.1
			and d.recharge_seconds == 1.5
			and d.air_dashes == 1
			and is_equal_approx(d.speed(), 40.0)
		),
		"PLAN §30.8 numbers"
	)


# --- Player ---------------------------------------------------------------------------


func test_dash_6_m_in_9_ticks() -> void:
	var w := _flat()
	var p := _player(w)
	_run(p, 30)
	var s := p.feet()
	_run(p, 1, [], [&"dash"])  # no move key: along the view (north, -Z)
	var ticks := 1
	check(p.dashing() and p.breath.value == 75.0, "dashing, Breath 75")
	while p.dashing() and ticks < 100:
		_run(p, 1)
		ticks += 1
	var d := p.feet() - s
	print("    dash: %.4f m north in %d ticks (6.000 in 9), sideways %.4f, dy %.4f" % [-d.z, ticks, d.x, d.y])
	check_near(-d.z, 6.0, 0.05, "6 m")
	check(ticks == 9, "9 ticks (%d)" % ticks)
	check(absf(d.x) < 1e-3 and absf(d.y) < 1e-2 and p.on_ground(), "straight, on the floor")
	_run(p, 5)
	check(p.horizontal_speed() < 0.5, "ends into rest, no 40 m/s carry-over (%.3f)" % p.horizontal_speed())
	# With a move key: along the move direction (right = +X at yaw 0), even when walking.
	var q := _player(w)
	q.spawn(Vector3(-10, 0, 10), 0.0)
	_run(q, 30, [&"right"])
	var a := q.feet()
	_run(q, 1, [&"right"], [&"dash"])
	_run(q, 8, [&"right"])
	var e := q.feet() - a
	print("    dash while walking right: %.4f m east in 9 ticks, dz %.4f" % [e.x, e.z])
	check_near(e.x, 6.0, 0.05, "6 m east")
	check(absf(e.z) < 1e-3 and not q.dashing(), "straight, done")
	_run(q, 1, [&"right"])
	check_near(q.horizontal_speed(), 4.0, 0.1, "straight back to walking")
	w.free()


func test_wall_stops_dash() -> void:
	var w := _flat()
	_box(w, Vector3(0, 1.5, -3.5), Vector3(10, 1.5, 0.5))  # south face at z -3, 3 m tall
	var p := _player(w)
	_run(p, 30)
	_run(p, 1, [], [&"dash"])
	_run(p, 20)
	var e := p.feet()
	print("    dash into a wall at z -3: stopped at z %.3f (radius 0.3), y %.3f" % [e.z, e.y])
	check(e.z > -3.0 and e.z < -2.6, "against the face, not through it (z %.3f)" % e.z)
	check(absf(e.x) < 1e-3 and absf(e.y) < 0.03, "no sideways / climb")
	w.free()


func test_air_dash_once_per_jump() -> void:
	var w := _flat()
	var p := _player(w)
	_run(p, 30)
	_run(p, 1, [], [&"jump"])
	_run(p, 10)
	check(not p.on_ground(), "airborne")
	_run(p, 1, [], [&"dash"])
	check(p.dash.dashes == 1, "air dash")
	_run(p, 9)
	check(not p.on_ground() and not p.dashing(), "still in the air, dash over")
	_run(p, 1, [], [&"dash"])
	var refused := p.dash.dashes == 1 and p.dash.charges == 1 and absf(p.breath.value - 75.0) < 0.5
	print("    air dash: %d dash(es), 2nd refused %s, Breath %.2f" % [p.dash.dashes, refused, p.breath.value])
	check(refused, "2nd air dash in the same jump refused, no cost")
	for i in 120:
		if p.on_ground():
			break
		_run(p, 1)
	check(p.on_ground(), "landed")
	_run(p, 1)
	_run(p, 1, [], [&"jump"])
	_run(p, 5)
	_run(p, 1, [], [&"dash"])
	check(p.dash.dashes == 2, "the next jump has its air dash again")
	w.free()


func test_breath_refusal_and_exhausted() -> void:
	var w := _flat()
	var p := _player(w)
	_run(p, 30)
	check(p.breath.spend(80.0), "20 left")
	var a := p.feet()
	_run(p, 1, [], [&"dash"])
	_run(p, 9)
	check(p.dash.dashes == 0 and p.dash.charges == 2 and (p.feet() - a).length() < 1e-3, "refused at 20, didn't move")
	var q := _player(w)
	q.spawn(Vector3(0, 0, 30), 0.0)  # sprint north ~35 m on the 80 m floor
	_run(q, 30)
	var n := 0
	while not q.breath.exhausted and n < 400:
		_run(q, 1, [&"forward", &"sprint"])
		n += 1
	check(q.breath.exhausted, "sprinted dry")
	_run(q, 1, [&"forward"], [&"dash"])
	check(q.dash.dashes == 0, "exhausted: refused")
	_run(q, 120)  # 1 s delay + 1 s regen -> 30
	var before := q.breath.value
	_run(q, 1, [], [&"dash"])
	print("    dash Breath: refused at 20 and exhausted, then %.2f -> %.2f" % [before, q.breath.value])
	check(q.dash.dashes == 1 and absf(q.breath.value - (before - 25.0)) < 1e-3, "costs 25")
	check(not q.breath.regenerating(), "the 1 s delay restarted")
	w.free()


func test_dash_ends_slide() -> void:
	var w := _flat()
	var p := _player(w)
	p.spawn(Vector3(0, 0, 30), 0.0)
	_run(p, 30)
	var held := [&"forward", &"sprint", &"crouch"]
	_run(p, 60, [&"forward", &"sprint"])
	_run(p, 11, held)
	check(p.sliding(), "sliding")
	var a := p.feet()
	_run(p, 1, held, [&"dash"])
	check(not p.sliding() and p.slide_left == 0.0 and p.dashing(), "the dash ends the slide")
	check(p.crouched, "Crouch held on the ground keeps the crouch")
	_run(p, 8, held)
	var moved := a.z - p.feet().z
	_run(p, 60, held)
	print(
		(
			"    dash out of a slide: %.3f m in 9 ticks, then %s at %.3f m/s, %d slide(s)"
			% [moved, "crouched" if p.crouched else "standing", p.horizontal_speed(), p.slides]
		)
	)
	check_near(moved, 6.0, 0.3, "dash distance out of a slide (blend with crouch-walk)")
	check(p.crouched and not p.sliding() and p.slides == 1, "no new slide from the dash")
	check_near(p.horizontal_speed(), 3.0, 0.05, "crouch speed afterwards")
	w.free()
