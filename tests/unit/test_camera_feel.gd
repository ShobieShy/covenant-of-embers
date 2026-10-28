extends TestCase
## Step 5 done check (port of the archived test_camera_feel.cpp, old step 16): camera feel.
##  - head bob (Cogito wiggle): only while bobbing; walk y within +-0.015 / x +-0.03, sprint
##    bobs harder; centred sway; eases back to exactly 0; bob_scale 0 = off;
##  - landing dip: 0 below 2 m/s, 0.12 x (s - 2) / 6 up to 0.12 m at 8 m/s (capped above),
##    deepest at ~0.1 s, gone by ~0.3 s;
##  - reduced motion: offset exactly 0 for the same inputs, and snaps to 0 mid-bob;
##  - step smoothing (Cogito step_height_camera_lerp 2.5): add_step keeps the camera, then
##    it eases back at 2.5/s;
##  - in the Player: walking bobs the Head off the plain eye, a jump landing (~4.6 m/s)
##    dips it, reduced motion keeps it on the eye; a climbed 0.35 m step lifts the camera
##    smoothly (no 0.35 m jump in one tick); stepping back down 0.35 m doesn't jump either.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _bob_range(f: CameraFeel, gait: CameraFeel.Gait, ticks: int) -> Dictionary:
	var r := {"max_y": 0.0, "min_y": 0.0, "max_x": 0.0, "min_x": 0.0}
	for i in ticks:
		f.tick(true, gait, false, 0.0, DT)
		if i < 60:
			continue  # past the ease-in
		var o := f.offset()
		r.max_y = maxf(r.max_y, o.y)
		r.min_y = minf(r.min_y, o.y)
		r.max_x = maxf(r.max_x, o.x)
		r.min_x = minf(r.min_x, o.x)
	return r


func test_head_bob_amplitudes() -> void:
	var w := _bob_range(CameraFeel.new(), CameraFeel.Gait.WALK, 300)
	var s := _bob_range(CameraFeel.new(), CameraFeel.Gait.SPRINT, 300)
	var c := _bob_range(CameraFeel.new(), CameraFeel.Gait.CROUCH, 300)
	print(
		(
			"    bob walk: y %.4f..%.4f x %.4f..%.4f | sprint y %.4f..%.4f x %.4f | crouch y %.4f x %.4f"
			% [w.min_y, w.max_y, w.min_x, w.max_x, s.min_y, s.max_y, s.max_x, c.max_y, c.max_x]
		)
	)
	# Target amplitude y = I/2 (0.015 walk, 0.025 sprint, 0.04 crouch), x = I; easing trims it.
	check(w.max_y > 0.005 and w.max_y <= 0.015 and w.min_y < -0.005 and w.min_y >= -0.015, "walk y")
	check(w.max_x > 0.01 and w.max_x <= 0.03, "walk x")
	check(s.max_y > w.max_y and s.max_x > w.max_x and s.max_y <= 0.025 and s.max_x <= 0.05, "sprint bobs harder")
	check(c.max_y <= 0.04 and c.max_x <= 0.08 and c.max_x > w.max_x, "crouch within 0.08")
	check(w.min_x < -0.01 and absf(w.min_x + w.max_x) < 0.01, "centred sway (Cogito's +0.5 bias dropped)")
	var f := CameraFeel.new()
	_bob_range(f, CameraFeel.Gait.WALK, 100)
	for i in 120:
		f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check(f.offset() == Vector2.ZERO, "eases back to exactly 0")
	var off := CameraFeel.new()
	off.set_bob_scale(0.0)
	var o := _bob_range(off, CameraFeel.Gait.CROUCH, 120)
	check(o.max_x == 0.0 and o.max_y == 0.0, "bob_scale 0 = off")


func test_landing_dip() -> void:
	var soft := CameraFeel.new()
	soft.tick(false, CameraFeel.Gait.WALK, true, 1.9, DT)
	check(soft.dip == 0.0 and soft.landings == 0, "no dip below 2 m/s")
	for speed in [5.0, 8.0, 12.0]:
		var f := CameraFeel.new()
		f.tick(false, CameraFeel.Gait.WALK, true, speed, DT)
		var deepest := 0.0
		var deepest_tick := 0
		var end_tick := -1
		for i in range(1, 40):
			if f.dip < deepest:
				deepest = f.dip
				deepest_tick = i
			if end_tick < 0 and i > 1 and f.dip == 0.0:
				end_tick = i
			f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
		var expect := 0.12 * minf(1.0, (speed - 2.0) / 6.0)
		print(
			(
				"    landing dip at %.1f m/s: %.4f m (%.4f) at tick %d, back by tick %d"
				% [speed, deepest, -expect, deepest_tick, end_tick]
			)
		)
		check_near(-deepest, expect, 0.002, "dip depth at %.1f m/s" % speed)
		check(-deepest <= 0.12 + 1e-9, "max 0.12 m")
		check(deepest_tick >= 5 and deepest_tick <= 7, "deepest ~0.1 s (%d)" % deepest_tick)
		check(end_tick >= 17 and end_tick <= 19, "back by ~0.3 s (%d)" % end_tick)


func test_reduced_motion_zero() -> void:
	var f := CameraFeel.new()
	f.set_reduced_motion(true)
	var nonzero := 0
	for i in 200:
		f.tick(true, CameraFeel.Gait.SPRINT, i == 100, 8.0, DT)
		if f.offset() != Vector2.ZERO:
			nonzero += 1
	check(nonzero == 0, "reduced motion: offset exactly 0 (%d nonzero ticks)" % nonzero)
	var g := CameraFeel.new()
	for i in 30:
		g.tick(true, CameraFeel.Gait.SPRINT, false, 0.0, DT)
	check(g.offset() != Vector2.ZERO, "bobbing")
	g.set_reduced_motion(true)
	check(g.offset() == Vector2.ZERO, "turning it on snaps to 0")


func test_step_smoothing_unit() -> void:
	var f := CameraFeel.from_tuning(load("res://resources/player/player_tuning.tres"))
	check(f.step_lerp == 2.5 and f.max_dip == 0.12 and f.walk_rate == 12.0, "tuning numbers")
	f.add_step(0.35)
	f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check_near(f.step, -0.35 * (1.0 - 2.5 / 60.0), 1e-9, "camera stays, first ease in the same tick")
	for i in 59:
		f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check_near(f.step, -0.35 * pow(1.0 - 2.5 / 60.0, 60), 1e-9, "eases at 2.5/s")
	for i in 240:
		f.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check(f.step == 0.0, "back to exactly 0")
	var r := CameraFeel.new()
	r.set_reduced_motion(true)
	r.add_step(0.3)
	r.tick(false, CameraFeel.Gait.WALK, false, 0.0, DT)
	check(r.offset().y < -0.25, "step smoothing stays on under reduced motion")


# --- Player ---------------------------------------------------------------------------


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


func _player(parent: Node, feet: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	parent.add_child(p)
	p.spawn(feet, 0.0)
	return p


func _controller(reduced: bool) -> Dictionary:
	var w := _world()
	_box(w, Vector3(0, -0.5, 0), Vector3(40, 0.5, 40))
	var p := _player(w, Vector3.ZERO)
	p.set_reduced_motion(reduced)
	var seen := {"max_offset": 0.0, "min_dip": 0.0, "landing": 0.0, "head_eye": 0.0}
	var ticks := [[30, [], []], [120, [&"forward"], []], [60, [], []], [1, [], [&"jump"]], [120, [], []]]
	var phase := 0
	for t in ticks:
		for i in t[0]:
			p.tick(PlayerInput.hold(t[1], t[2]), DT)
			var d := p.camera_position() - p.eye_position()
			seen.max_offset = maxf(seen.max_offset, d.length())
			seen.head_eye = maxf(
				seen.head_eye, (d - Vector3(0, p.camera_offset().y, 0) - p.basis.x * p.camera_offset().x).length()
			)
			if phase == 4:
				seen.min_dip = minf(seen.min_dip, d.y)
		phase += 1
	seen.landing = p.last_landing_speed
	check(p.landings >= 1, "landed")
	w.free()
	return seen


func test_player_bob_and_dip_reduced_motion() -> void:
	var on := _controller(false)
	var off := _controller(true)
	print(
		(
			"    player: max camera offset %.4f m, landing at %.2f m/s dips %.4f m | reduced motion %.4f / %.4f"
			% [on.max_offset, on.landing, on.min_dip, off.max_offset, off.min_dip]
		)
	)
	check(on.max_offset > 0.01, "walking bobs the camera")
	check(on.head_eye < 1e-5 and off.head_eye < 1e-5, "Head = eye + offset (x along the view's right)")
	check(on.landing > 4.0 and on.landing < 5.2, "4.5 m/s jump lands at ~4.6 (%.3f)" % on.landing)
	check_near(-on.min_dip, 0.12 * (on.landing - 2.0) / 6.0, 0.005, "landing dip")
	check(off.max_offset == 0.0 and off.min_dip == 0.0, "reduced motion: camera exactly on the eye")


func test_player_step_up_and_down_smoothed() -> void:
	var w := _world()
	_box(w, Vector3(0, -0.5, 0), Vector3(20, 0.5, 20))
	_box(w, Vector3(0, 0.175, -4.0), Vector3(3, 0.175, 1.5))  # 0.35 m step, front face z -2.5
	var p := _player(w, Vector3.ZERO)
	p.set_reduced_motion(true)  # isolate the step offset
	for i in 30:
		p.tick(PlayerInput.hold(), DT)
	var last_cam := p.camera_position().y
	var max_jump := 0.0
	var climbed_tick := -1
	var lowest_at_climb := 0.0
	for i in 60:
		p.tick(PlayerInput.hold([&"forward"]), DT)
		var cy := p.camera_position().y
		max_jump = maxf(max_jump, absf(cy - last_cam))
		last_cam = cy
		if climbed_tick < 0 and p.steps_climbed > 0:
			climbed_tick = i
			lowest_at_climb = p.camera_offset().y
	var up_jump := max_jump
	print(
		(
			"    step up 0.35: climbed at tick %d (rise %.3f), camera offset %.3f, max camera move %.4f m/tick"
			% [climbed_tick, p.last_step_rise, lowest_at_climb, up_jump]
		)
	)
	check(climbed_tick >= 0 and p.feet().y > 0.34, "climbed")
	check(lowest_at_climb < -0.3, "camera held below after the lift")
	check(up_jump < 0.05, "no 0.35 m camera jump in one tick (%.4f)" % up_jump)
	# Keep walking off the far edge (z -5.5) back down 0.35 m: the capsule rolls off and
	# falls, so the camera never jumps either.
	max_jump = 0.0
	for i in 90:
		p.tick(PlayerInput.hold([&"forward"]), DT)
		var cy2 := p.camera_position().y
		max_jump = maxf(max_jump, absf(cy2 - last_cam))
		last_cam = cy2
	print("    step down 0.35: feet y %.3f z %.2f, max camera move %.4f m/tick" % [p.feet().y, p.feet().z, max_jump])
	check(p.feet().y < 0.01 and p.feet().z < -6.0 and p.on_ground(), "back on the floor")
	check(max_jump < 0.05, "no camera jump stepping down (%.4f)" % max_jump)
	w.free()


## 0.3.1 P5 (M5): the dash FOV kick eases back; none under reduced motion.
func test_dash_fov_kick() -> void:
	var f := CameraFeel.new()
	f.add_fov_kick()
	check_near(f.fov_kick, CameraFeel.DASH_FOV_KICK, 1e-6, "kick on")
	for i in 30:
		f.tick(false, CameraFeel.Gait.WALK, false, 0.0, 1.0 / 60.0)
	check_near(f.fov_kick, 0.0, 1e-6, "eased back in FOV_KICK_SECONDS")
	f.set_reduced_motion(true)
	f.add_fov_kick()
	check_near(f.fov_kick, 0.0, 1e-6, "no kick under reduced motion")


## 0.3.1 P5 (L5): dead, the eye sinks DEATH_DROP; alive again it rises in RISE_SECONDS.
func test_death_fall_and_rise() -> void:
	var f := CameraFeel.new()
	for i in 90:
		f.tick_death(true, 1.0 / 60.0)
	check_near(f.death(), 1.0, 1e-6, "fully fallen")
	check_near(f.offset().y, -CameraFeel.DEATH_DROP, 1e-6, "eye dropped")
	for i in 12:
		f.tick_death(false, 1.0 / 60.0)
	check(f.death() > 0.0 and f.death() < 1.0, "rising")
	for i in 20:
		f.tick_death(false, 1.0 / 60.0)
	check_near(f.offset().y, 0.0, 1e-6, "back at the eye")
	f.set_reduced_motion(true)
	f.tick_death(true, 1.0)
	check_near(f.offset().y, 0.0, 1e-6, "no fall under reduced motion")
	check(f.death() > 0.0, "desaturate still runs")
