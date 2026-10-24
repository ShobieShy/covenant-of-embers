extends TestCase
## Step 9 done check (port of the archived test_accuracy.cpp, old step 19): focus (ADS) FOV
## tween, Magewar accuracy, spread cone, stance multipliers and bloom.
##  - focus: 75 -> 55 deg exactly at tick 12 (0.2 s) for staff and wand, linear (65 at tick
##    6), back in 12, retarget mid-tween from the current FOV, 6/29 ticks at 30/144 Hz,
##    empty hands no focus, look scale tan(27.5)/tan(37.5) = 0.6784;
##  - accuracy = Magewar get_final_accuracy (50 + Head/Handle/Charm, Interior/Exterior
##    ignored, clamp 0..100);
##  - 100 % accuracy = zero spread (any stance, full bloom; bolts exactly along the aim);
##  - 50 % hip 2.0 deg / focused 0.7 deg (x0.35), crouch 0.8, moving 1.3, air 1.8, from the
##    real Player stance;
##  - bloom +1 deg/cast capped at 4 deg clears in 30 ticks (72 at 144 Hz, 15 at 30 Hz);
##  - a refused press (no mana, or cooldown) adds no bloom; focusing costs no mana;
##  - cone sampling uniform over the cap, seeded and reproducible.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const PT := WieldablePart.PartType


func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


func _player_world(at: Vector3) -> Array:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	w.global_position = at
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	floor.add_child(cs)
	floor.position = Vector3(0, -0.5, 0)
	w.add_child(floor)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	p.bolts = bolts
	return [w, p, bolts]


func _run(p: Player, input: PlayerInput, n: int) -> void:
	for i in n:
		p.tick(input, DT)


# --- Focus ------------------------------------------------------------------------------


func test_focus_tween_55_at_tick_12() -> void:
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	var wand := WieldableInstance.load_base("swift_wind_wand")
	var f := Focus.new()
	check(
		f.fov_for(WieldableDef.Type.STAFF) == 55.0 and f.fov_for(WieldableDef.Type.WAND) == 55.0,
		"staff and wand 55 (Magewar: same script)"
	)
	check(f.fov == 75.0 and not f.focused and f.amount() == 0.0, "starts at the hip 75")
	var reach := -1
	for i in range(1, 21):
		f.tick(true, staff, DT)
		if i == 6:
			check_near(f.fov, 65.0, 1e-6, "linear: 65 at tick 6")
			check_near(f.amount(), 0.5, 1e-6, "amount 0.5 half-way")
		if i == 11:
			check(f.fov > 55.0, "not yet at tick 11 (%f)" % f.fov)
		if reach < 0 and f.fov == 55.0:
			reach = i
	print(
		(
			"    focus: staff 75 -> 55 deg in %d ticks (%.4f s) at 60 Hz, look scale %.4f"
			% [reach, reach * DT, f.look_scale()]
		)
	)
	check(reach == 12, "55 deg exactly at tick 12 (got %d)" % reach)
	check(f.focused and f.amount() == 1.0, "fully focused")
	check_near(f.look_scale(), 0.6784, 1e-4, "look scale at 55")
	check_near(Focus.look_scale_for_fov(55.0), tan(deg_to_rad(27.5)) / tan(deg_to_rad(37.5)), 1e-9, "tan ratio")
	check(Focus.look_scale_for_fov(75.0) == 1.0, "hip look scale 1")
	# Render interpolation between the last two ticks.
	var g := Focus.new()
	g.tick(true, staff, DT)
	g.tick(true, staff, DT)
	check_near(g.fov_at(0.0), 75.0 - 20.0 / 12.0, 1e-6, "fov_at 0")
	check_near(g.fov_at(0.5), 75.0 - 30.0 / 12.0, 1e-6, "fov_at 0.5")
	check_near(g.fov_at(1.0), 75.0 - 40.0 / 12.0, 1e-6, "fov_at 1")
	# Release: back to 75 in 12 ticks.
	var back := -1
	for i in range(1, 21):
		f.tick(false, staff, DT)
		if back < 0 and f.fov == 75.0:
			back = i
	check(back == 12 and not f.focused and f.amount() == 0.0, "back to 75 in 12 ticks (%d)" % back)
	# Release mid-tween (at 65): a new 0.2 s tween from 65 (Godot tween_property).
	var h := Focus.new()
	for i in 6:
		h.tick(true, wand, DT)
	check_near(h.fov, 65.0, 1e-6, "wand 65 at tick 6")
	for i in 6:
		h.tick(false, wand, DT)
	check_near(h.fov, 70.0, 1e-6, "half-way back from 65")
	for i in 6:
		h.tick(false, wand, DT)
	check(h.fov == 75.0, "back at 75")
	# Other tick rates: 6 ticks at 30 Hz, 28.8 -> 29 at 144 Hz.
	for row in [[30, 6], [144, 29]]:
		var r := Focus.new()
		var n := 0
		while r.fov != 55.0 and n < 100:
			r.tick(true, wand, 1.0 / float(row[0]))
			n += 1
		check(n == row[1], "@%d Hz: %d ticks (got %d)" % [row[0], row[1], n])
	# Empty hands: no focus; unequipping while focused tweens back.
	var e := Focus.new()
	for i in 20:
		e.tick(true, null, DT)
	check(e.fov == 75.0 and not e.focused, "empty hands: no focus")
	for i in 12:
		e.tick(true, staff, DT)
	check(e.fov == 55.0, "focused with the staff")
	for i in 12:
		e.tick(true, null, DT)
	check(e.fov == 75.0 and not e.focused, "unequipped: back to 75")
	# A custom wand FOV is honoured per type; swapping while focused retargets.
	var w2 := Focus.new()
	w2.wand_fov = 65.0
	for i in 12:
		w2.tick(true, wand, DT)
	check(w2.fov == 65.0 and w2.amount() == 1.0, "wand at 65")
	for i in 12:
		w2.tick(true, staff, DT)
	check(w2.fov == 55.0, "swap to staff while focused: 55")


func test_player_focus_camera_look_scale_and_no_mana() -> void:
	var r := _player_world(Vector3(1300, 0, -1300))
	var w: Node3D = r[0]
	var p: Player = r[1]
	p.caster.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	_run(p, PlayerInput.hold(), 20)
	check(p.camera.fov == 75.0 and p.focus.fov == 75.0, "hip camera 75")
	var aimin := PlayerInput.hold(["action_secondary"])
	var reach := -1
	for i in range(1, 61):
		p.tick(aimin, DT)
		if reach < 0 and p.camera.fov == 55.0:
			reach = i
	print("    focus: player camera at 55 deg on tick %d, mana %.1f after 1 s of focus" % [reach, p.mana.value])
	check(reach == 12, "player camera 55 at tick 12 (%d)" % reach)
	check(
		p.mana.value == 100.0 and p.mana.spends == 0 and p.caster.casts == 0, "focusing costs no mana and casts nothing"
	)
	# Look scaled by 0.6784 while focused.
	p.set_look(0.0, 0.0)
	p.add_look(-100.0, 0.0)
	check_near(rad_to_deg(p.yaw), 25.0 * Focus.look_scale_for_fov(55.0), 1e-4, "100 counts = 16.96 deg focused")
	_run(p, PlayerInput.hold(), 12)
	p.set_look(0.0, 0.0)
	p.add_look(-100.0, 0.0)
	check_near(rad_to_deg(p.yaw), 25.0, 1e-4, "100 counts = 25 deg at the hip")
	# Empty hands: action_secondary does nothing.
	p.caster.equip(null)
	_run(p, aimin, 20)
	check(p.camera.fov == 75.0 and not p.focus.focused, "empty hands: no focus")
	w.free()


# --- Accuracy + cone --------------------------------------------------------------------


func test_accuracy_stat_magewar() -> void:
	var w := WieldableInstance.load_base("apprentice_fire_staff")
	check(w.accuracy() == 50.0, "Magewar base 50")
	# Magewar parts: basic_fire_head 5, basic_handle 10, unique_void_charm 12 count; the
	# interior's 2 and exterior's 6 don't (get_final_accuracy reads Head/Handle/Charm).
	w.parts = [
		WieldablePart.make(PT.HEAD, 0.0, 1.0, 5.0),
		WieldablePart.make(PT.HANDLE, 0.0, 1.0, 10.0),
		WieldablePart.make(PT.CHARM, 0.0, 1.0, 12.0),
		WieldablePart.make(PT.INTERIOR, 0.0, 1.0, 2.0),
		WieldablePart.make(PT.EXTERIOR, 0.0, 1.0, 6.0)
	]
	check(w.accuracy() == 77.0, "50 + 5 + 10 + 12 = 77 (%f)" % w.accuracy())
	w.parts.append(WieldablePart.make(PT.HANDLE, 0.0, 1.0, 22.0))
	w.parts.append(WieldablePart.make(PT.HEAD, 0.0, 1.0, 15.0))
	check(w.accuracy() == 100.0, "114 clamped to 100")
	w.parts = [WieldablePart.make(PT.CHARM, 0.0, 1.0, -80.0)]
	check(w.accuracy() == 0.0, "-30 clamped to 0")


func test_full_accuracy_zero_spread() -> void:
	var sp := Spread.new()
	var stances := [
		Spread.Stance.make(),
		Spread.Stance.make(0.0, false, true),
		Spread.Stance.make(0.0, false, false, true),
		Spread.Stance.make(1.0, true, true)
	]
	for s in stances:
		var m := sp.stance_multiplier(s)
		check(sp.cone_for(100.0, m, 0.0) == 0.0 and sp.cone_for(100.0, m, sp.bloom_max_deg) == 0.0, "100 %: 0 cone")
		check(sp.cone_for(130.0, m, 2.0) == 0.0, "over 100 clamps")
	for i in 8:
		sp.on_cast()
	check(sp.bloom == sp.bloom_max_deg, "full bloom")
	var dirs := [Vector3.FORWARD, Vector3(0.3, -0.4, -0.8).normalized(), Vector3.UP, Vector3.DOWN]
	var exact := true
	for i in 1000:
		var aim := Caster.Aim.make(Vector3.ZERO, dirs[i % 4])
		var out := sp.apply(aim, 100.0, stances[i % 4])
		exact = exact and out.direction == aim.direction and sp.last_cone_deg == 0.0
	check(exact, "1000 spread aims at 100 % are bit-exact")
	# Through the real Player: 10 Swift Wind casts at 100 %, airborne-free, fly along the aim.
	var r := _player_world(Vector3(1400, 0, -1400))
	var w: Node3D = r[0]
	var p: Player = r[1]
	var bolts: SpellBolts = r[2]
	var wand := WieldableInstance.load_base("swift_wind_wand")
	wand.parts = [WieldablePart.make(PT.HEAD, 0.0, 1.0, 30.0), WieldablePart.make(PT.HANDLE, 0.0, 1.0, 20.0)]
	check(wand.accuracy() == 100.0, "wand at 100 %")
	p.caster.equip(wand)
	p.set_look(0.3, -0.1)
	_run(p, PlayerInput.hold(), 20)
	var worst := 0.0
	var tick := 0
	while p.caster.casts < 10 and tick < 400:
		p.tick(PlayerInput.hold(["forward"] if tick % 2 == 0 else [], ["action_primary"]), DT)
		tick += 1
	for b in bolts.live:
		worst = maxf(worst, _angle_deg(b.spawn.direction, p.look_direction()))
	print(
		(
			"    spread: 100 %% accuracy -> cone 0, %d bolts within %.6f deg of the aim (bloom %.2f)"
			% [bolts.live.size(), worst, p.spread.bloom]
		)
	)
	check(
		p.caster.casts == 10 and bolts.live.size() == 10 and worst < 1e-3, "10 bolts exactly along the aim (%f)" % worst
	)
	w.free()


func test_hip_2_focused_0_7_and_stances() -> void:
	var sp := Spread.new()
	check(
		sp.focus_mul == 0.35 and sp.crouch_mul == 0.8 and sp.moving_mul == 1.3 and sp.airborne_mul == 1.8, "multipliers"
	)
	check_near(sp.cone_for(50.0, 1.0, 0.0), 2.0, 1e-9, "50 % hip still = 4 x 0.5")
	for acc in [0.0, 25.0, 50.0, 77.0, 99.0]:
		for body in [
			Spread.Stance.make(),
			Spread.Stance.make(0, true),
			Spread.Stance.make(0, false, true),
			Spread.Stance.make(0, true, true),
			Spread.Stance.make(0, false, false, true)
		]:
			var foc := Spread.Stance.make(1.0, body.crouched, body.moving, body.airborne)
			var hip := sp.cone_for(acc, sp.stance_multiplier(body), 1.5)
			var ads := sp.cone_for(acc, sp.stance_multiplier(foc), 1.5)
			check_near(ads, 0.35 * hip, 1e-9, "focused = 0.35 x hip @%.0f" % acc)
	check_near(sp.stance_multiplier(Spread.Stance.make(0, true)), 0.8, 1e-9, "crouch")
	check_near(sp.stance_multiplier(Spread.Stance.make(0, false, true)), 1.3, 1e-9, "moving")
	check_near(sp.stance_multiplier(Spread.Stance.make(0, true, true)), 1.04, 1e-9, "crouch-walk")
	check_near(sp.stance_multiplier(Spread.Stance.make(0, true, true, true)), 1.8, 1e-9, "airborne replaces the rest")
	check_near(sp.stance_multiplier(Spread.Stance.make(0.5)), 0.675, 1e-9, "half-way through the tween")
	# Through the real Player (Earthward, 50 %): stance from the body, cone used by a cast.
	var r := _player_world(Vector3(1500, 0, -1500))
	var w: Node3D = r[0]
	var p: Player = r[1]
	p.caster.equip(WieldableInstance.load_base("earthward_battlestaff"))
	check(p.accuracy() == 50.0, "Earthward 50 %")
	_run(p, PlayerInput.hold(), 30)
	var hip_cone := p.spread.cone_deg(p.accuracy(), p.spread_stance())
	p.tick(PlayerInput.hold([], ["action_primary"]), DT)
	check(p.caster.casts == 1, "hip cast")
	var hip_used := p.spread.last_cone_deg
	_run(p, PlayerInput.hold(), 60)  # cooldown + bloom gone
	_run(p, PlayerInput.hold(["action_secondary"]), 12)
	var ads_cone := p.spread.cone_deg(p.accuracy(), p.spread_stance())
	p.tick(PlayerInput.hold(["action_secondary"], ["action_primary"]), DT)
	var ads_used := p.spread.last_cone_deg
	print(
		(
			"    spread: 50 %% accuracy hip %.3f deg, focused %.3f deg (x%.3f), casts %d"
			% [hip_used, ads_used, ads_used / hip_used, p.caster.casts]
		)
	)
	check_near(hip_cone, 2.0, 1e-6, "player hip still 2.0")
	check_near(hip_used, 2.0, 1e-6, "hip cast used 2.0")
	check_near(ads_cone, 0.7, 1e-6, "player focused 0.7")
	check_near(ads_used, 0.7, 1e-6, "focused cast used 0.7")
	check(p.caster.casts == 2, "focused cast happened")
	_run(p, PlayerInput.hold(), 60)
	# Moving 1.3, crouched 0.8, airborne 1.8 from the body.
	_run(p, PlayerInput.hold(["forward"]), 30)
	var s := p.spread_stance()
	check(s.moving and not s.crouched and not s.airborne, "walking = moving")
	var walk_cone := p.spread.cone_deg(50.0, s)
	check_near(walk_cone, 2.6, 1e-6, "walking 2.6")
	_run(p, PlayerInput.hold(), 60)
	_run(p, PlayerInput.hold(["crouch"]), 30)
	s = p.spread_stance()
	check(s.crouched and not s.moving and not s.airborne, "crouched still")
	var crouch_cone := p.spread.cone_deg(50.0, s)
	check_near(crouch_cone, 1.6, 1e-6, "crouched 1.6")
	_run(p, PlayerInput.hold(), 30)
	p.tick(PlayerInput.hold([], ["jump"]), DT)
	_run(p, PlayerInput.hold(), 10)
	s = p.spread_stance()
	check(s.airborne, "airborne after a jump")
	check_near(p.spread.cone_deg(50.0, s), 3.6, 1e-6, "airborne 3.6")
	print(
		(
			"    spread: player walking %.2f, crouched %.2f, airborne %.2f deg"
			% [walk_cone, crouch_cone, p.spread.cone_deg(50.0, s)]
		)
	)
	w.free()


# --- Bloom ------------------------------------------------------------------------------


func test_bloom_clears_in_30_ticks() -> void:
	for row in [[60, 30], [144, 72], [30, 15]]:
		var sp := Spread.new()
		var hz: int = row[0]
		var dt := 1.0 / hz
		var base := sp.cone_deg(50.0, Spread.Stance.make())
		for i in 6:
			sp.on_cast()
		check(sp.bloom == sp.bloom_max_deg, "capped at 4")
		check_near(sp.cone_deg(50.0, Spread.Stance.make()), 2.0 * base, 1e-9, "full bloom doubles the cone")
		var n := 0
		while sp.bloom > 0.0 and n < 1000:
			sp.tick(dt)
			n += 1
		print("    bloom: full 4.0 deg -> 0 in %d ticks at %d Hz (%.4f s)" % [n, row[0], n * dt])
		check(n == row[1], "@%d Hz: %d ticks (got %d)" % [row[0], row[1], n])
		check(n * dt <= sp.bloom_recovery_seconds + 1e-9, "within 0.5 s")
		check(sp.cone_deg(50.0, Spread.Stance.make()) == base, "back to the base cone")
	# One cast: +1 deg (x0.5 at 50 %), gone in 0.125 s = 8 ticks.
	var one := Spread.new()
	one.on_cast()
	check_near(one.cone_deg(50.0, Spread.Stance.make()) - 2.0, 0.5, 1e-9, "+0.5 deg at 50 %")
	var k := 0
	while one.bloom > 0.0 and k < 100:
		one.tick(DT)
		k += 1
	check(k == 8, "one cast gone in 8 ticks (%d)" % k)
	# Hold-to-repeat at the 0.1 s floor through Caster: stacks to the cap, recovers <= 30.
	var fast := WieldableInstance.load_base("swift_wind_wand")
	fast.parts = [WieldablePart.make(WieldablePart.PartType.CHARM, 0.0, 0.1)]
	check(fast.cooldown() == 0.1, "0.1 s floor")
	var c := Caster.new(fast)
	c.hold_to_repeat = true
	var s3 := Spread.new()
	var peak := 0.0
	for t in 120:
		s3.tick(DT)
		if c.tick(t == 0, true, DT, s3.apply(Caster.Aim.new(), fast.accuracy(), Spread.Stance.make()), null):
			s3.on_cast()
		peak = maxf(peak, s3.bloom)
	var rec := 0
	while s3.bloom > 0.0 and rec < 1000:
		s3.tick(DT)
		rec += 1
	print("    bloom: rapid fire %d casts in 2 s peaked at %.1f deg, recovered in %d ticks" % [c.casts, peak, rec])
	check(c.casts >= 19 and peak == s3.bloom_max_deg and rec <= 30, "rapid fire hits the cap, clears in <= 30")


func test_refused_press_adds_no_bloom() -> void:
	var r := _player_world(Vector3(1600, 0, -1600))
	var w: Node3D = r[0]
	var p: Player = r[1]
	p.caster.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	_run(p, PlayerInput.hold(), 20)
	var fire := PlayerInput.hold([], ["action_primary"])
	# No mana: every press refused, bloom stays 0.
	p.mana.value = 0.0
	for i in 30:
		p.tick(fire, DT)
		check(p.spread.bloom == 0.0, "no bloom on a mana refusal (tick %d: %f)" % [i, p.spread.bloom])
	check(p.caster.casts == 0 and p.caster.mana_refused == 30 and p.not_enough_mana_cues == 30, "30 refused presses")
	# A real cast blooms by 1; a cooldown refusal the next tick doesn't add more.
	p.mana.refill()
	p.tick(fire, DT)
	check(p.caster.casts == 1 and p.spread.bloom == 1.0, "a real cast adds 1 deg (%f)" % p.spread.bloom)
	var before := p.caster.blocked
	p.tick(fire, DT)
	check(p.caster.blocked == before + 1 and p.caster.casts == 1, "cooldown refusal")
	check_near(p.spread.bloom, 1.0 - 8.0 * DT, 1e-9, "cooldown refusal: only decay")
	print(
		(
			"    bloom: %d no-mana presses -> bloom 0.00, a real cast -> 1.00, cooldown refusal -> %.3f"
			% [30, p.spread.bloom]
		)
	)
	w.free()


# --- Sampling ---------------------------------------------------------------------------


func test_cone_sampling_uniform_and_seeded() -> void:
	var sp := Spread.new(1234)
	var dir := Vector3(-0.5, 0.2, -1.0).normalized()
	var max_a := 0.0
	var sum := 0.0
	var mean := Vector3.ZERO
	var unit := true
	var n := 4000
	for i in n:
		var out := sp.apply(Caster.Aim.make(Vector3.ZERO, dir), 50.0, Spread.Stance.make())
		unit = unit and absf(out.direction.length() - 1.0) < 1e-5
		var a := _angle_deg(out.direction, dir)
		max_a = maxf(max_a, a)
		sum += a
		mean += out.direction
	var mean_a := sum / n
	print(
		(
			"    cone: %d samples at 2.000 deg: max %.3f, mean %.3f deg (uniform ~1.333), centroid off by %.4f deg"
			% [n, max_a, mean_a, _angle_deg(mean, dir)]
		)
	)
	check(unit, "unit directions")
	check(max_a <= 2.0 + 1e-3 and max_a > 1.95, "fills to the edge (%f)" % max_a)
	check(mean_a > 1.25 and mean_a < 1.42, "uniform over the cap (%f)" % mean_a)
	check(_angle_deg(mean, dir) < 0.1, "unbiased")
	var a1 := Spread.new(7)
	var b1 := Spread.new(7)
	var c1 := Spread.new(8)
	var same := true
	var differs := false
	for i in 50:
		var da := a1.apply(Caster.Aim.new(), 0.0, Spread.Stance.make()).direction
		var db := b1.apply(Caster.Aim.new(), 0.0, Spread.Stance.make()).direction
		var dc := c1.apply(Caster.Aim.new(), 0.0, Spread.Stance.make()).direction
		same = same and da == db
		differs = differs or da != dc
	check(same and differs, "same seed = same shots, other seed differs")
	for d in [Vector3.UP, Vector3.DOWN]:
		for i in 100:
			check(
				_angle_deg(Spread.cone_direction(d, deg_to_rad(3.0), i / 100.0, 0.37), d) <= 3.0 + 1e-3,
				"straight up/down inside"
			)
	# Two players with the same seed cast the same spread bolts.
	var dirs := []
	for k in 2:
		var r := _player_world(Vector3(1700 + 100 * k, 0, -1700))
		var p: Player = r[1]
		var bolts: SpellBolts = r[2]
		p.set_spread_seed(99)
		p.caster.equip(WieldableInstance.load_base("swift_wind_wand"))
		_run(p, PlayerInput.hold(), 10)
		for t in 60:
			p.tick(PlayerInput.hold([], ["action_primary"]) if t % 12 == 0 else PlayerInput.hold(), DT)
		var ds := []
		for b in bolts.live:
			ds.append(b.spawn.direction)
		dirs.append(ds)
		(r[0] as Node3D).free()
	check(dirs[0].size() == 5 and dirs[0] == dirs[1], "seeded player spread reproducible (%d bolts)" % dirs[0].size())
