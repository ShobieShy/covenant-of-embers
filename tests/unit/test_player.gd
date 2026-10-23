extends TestCase
## Steps 3-4 done checks (port of the archived test_player.cpp, old steps 14-15), driving
## Player.tick() over deterministic simulated 60 Hz physics frames:
##  1 s of W from the Midden PlayerStart ~ 3.67 m; jump apex 1.07 / 0.48 m (stand / crouch);
##  crouch eye 0.6 m and no standing up under a 1 m slab; 0.35 m step climbed, 0.5 m
##  blocked; ramp_west -> scrap_ledge (y 1.5). Plus look, spawn eye, InputMap, tuning.
## Step 4: sprint 7 m/s drains Breath, runs dry at 300 ticks, resumes ~100 later; slide from
##  sprint 90 ticks ~ 7.5 m along the entry direction; no slide from walk / crouch-first /
##  standing / exhausted; slide jump 4.5 x 1.3 keeps its speed; speed multiplier.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const MIDDEN_SCENE := "res://scenes/levels/midden.tscn"

func _world() -> Node3D:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	return w

func _box(parent: Node, center: Vector3, half: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.position = center
	parent.add_child(b)
	return b

## Flat floor with its top at y 0 (40 x 40 m).
func _flat() -> Node3D:
	var w := _world()
	_box(w, Vector3(0, -0.5, 0), Vector3(20, 0.5, 20))
	return w

## A 400 x 400 m floor (top y 0): long sprints stay on it.
func _big_flat() -> Node3D:
	var w := _world()
	_box(w, Vector3(0, -0.5, 0), Vector3(200, 0.5, 200))
	return w

func _midden() -> Node3D:
	var w := _world()
	w.add_child((load(MIDDEN_SCENE) as PackedScene).instantiate())
	return w

func _player(parent: Node, feet: Vector3, yaw: float) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false   # driven by tick() only
	parent.add_child(p)
	p.spawn(feet, yaw)
	return p

func _run(p: Player, n: int, held: Array = [], pressed: Array = []) -> void:
	for i in n:
		p.tick(PlayerInput.hold(held, pressed), DT)

# --- done check ---------------------------------------------------------------------

func test_walk_one_second_from_player_start() -> void:
	var w := _midden()
	var start := w.get_child(0).get_node("PlayerStart") as Node3D
	var p := _player(w, start.global_position, 0.0)
	_run(p, 30)
	check(p.on_ground(), "on the Midden ground after settling")
	var s := p.feet()
	_run(p, 60, [&"forward"])
	var d := p.feet() - s
	var along := d.dot(Player.forward_for(p.yaw))
	print("    walk 1 s: %.3f m (3.67), sideways %.4f, dy %.4f, speed %.3f" % [along, absf(d.x), d.y, p.horizontal_speed()])
	check_near(along, 3.67, 0.5, "1 s W distance")
	check(absf(d.x) < 1e-3 and absf(d.y) < 1e-3, "straight north on the floor")
	check_near(p.horizontal_speed(), 4.0, 0.05, "walk speed reached")
	_run(p, 60)
	check(p.horizontal_speed() < 0.05, "eases to rest within 1 s")
	_run(p, 90, [&"forward", &"right"])
	check_near(p.horizontal_speed(), 4.0, 0.05, "diagonal not faster")
	w.free()

func _apex(crouch: bool) -> float:
	var w := _flat()
	var p := _player(w, Vector3.ZERO, 0.0)
	var stance: Array = [&"crouch"] if crouch else []
	_run(p, 30, stance)
	_run(p, 1, stance, [&"jump"])
	var apex := 0.0
	var stayed := true
	var landed := false
	for i in 120:
		p.tick(PlayerInput.hold(), DT)   # crouch released mid-air: a crouch-jump stays crouched
		apex = maxf(apex, p.feet().y)
		if not p.on_ground():
			stayed = stayed and p.crouched == crouch
		if p.on_ground() and p.feet().y < 0.01:
			landed = true
	check(stayed and landed and p.jumps == 1, "stance kept in the air, landed, one jump (crouch=%s)" % crouch)
	_run(p, 30, [&"jump"])   # held Jump, no new press edge
	check(p.jumps == 1 and p.feet().y < 0.01, "held Jump does not re-jump")
	w.free()
	return apex

func test_jump_apex_standing_and_crouched() -> void:
	var stand := _apex(false)
	var crouch := _apex(true)
	print("    jump apex: %.3f m standing (1.07), %.3f m crouched (0.48)" % [stand, crouch])
	check_near(stand, 1.07, 0.06, "standing apex")
	check_near(crouch, 0.48, 0.06, "crouched apex")
	var w := _flat()
	var p := _player(w, Vector3(0, 3, 0), 0.0)
	_run(p, 1, [], [&"jump"])
	check(p.jumps == 0 and not p.on_ground(), "no jump in the air")
	w.free()

func test_crouch_eye_and_low_ceiling() -> void:
	var w := _flat()
	_box(w, Vector3(0, 1.25, -6), Vector3(5, 0.25, 3))   # slab bottom at y 1.0, south face z -3
	var p := _player(w, Vector3.ZERO, 0.0)
	_run(p, 60, [&"crouch"])
	check(p.crouched, "crouched")
	check_near(p.eye_height, 0.6, 0.01, "crouch eye")
	check_near(p.capsule_height(), 0.7, 1e-6, "crouch capsule")
	check_near(p.head.position.y, 0.6, 0.01, "Head follows the eye")
	_run(p, 120, [&"crouch", &"forward"])
	print("    crouch: eye %.3f, speed %.3f, feet z %.2f" % [p.eye_height, p.horizontal_speed(), p.feet().z])
	check_near(p.horizontal_speed(), 3.0, 0.05, "crouch speed")
	check(p.feet().z < -4.0, "walked under the slab")
	_run(p, 30)
	check(p.crouched and p.capsule_height() < 1.0, "can't stand under the 1 m slab")
	_run(p, 120, [&"back"])
	_run(p, 60)
	check(not p.crouched and absf(p.eye_height - 1.5) < 0.01 and p.feet().z > -2.5, "stands up once clear")
	w.free()

func _walk_into_step(height: float) -> Vector3:
	var w := _flat()
	_box(w, Vector3(0, height * 0.5, -6), Vector3(5, height * 0.5, 3))   # south face at z -3
	var p := _player(w, Vector3.ZERO, 0.0)
	_run(p, 30)
	_run(p, 120, [&"forward"])
	var f := p.feet()
	print("    step %.2f m: feet (%.2f, %.3f, %.2f), steps climbed %d" % [height, f.x, f.y, f.z, p.steps_climbed])
	w.free()
	return f

func test_step_035_climbed_050_blocked() -> void:
	var up := _walk_into_step(0.35)
	check(absf(up.y - 0.35) < 0.03 and up.z < -4.0, "0.35 m step climbed and walking on (y %.3f z %.2f)" % [up.y, up.z])
	var blocked := _walk_into_step(0.5)
	check(absf(blocked.y) < 0.03 and blocked.z > -3.0 and blocked.z < -2.5, "0.5 m step blocks (y %.3f z %.2f)" % [blocked.y, blocked.z])

func test_ramp_west_onto_scrap_ledge() -> void:
	var w := _midden()
	var p := _player(w, Vector3(-4.5, 0.0, -2.0), 0.0)
	_run(p, 30)
	var mid_y := -1.0
	var grounded_on_slope := true
	for i in 150:
		p.tick(PlayerInput.hold([&"forward"]), DT)
		var f := p.feet()
		if f.z < -5.5 and f.z > -8.5:
			grounded_on_slope = grounded_on_slope and p.on_ground()
		if mid_y < 0.0 and f.z <= -7.0:
			mid_y = f.y
	var e := p.feet()
	print("    ramp_west: y %.3f at z -7 (0.75), end (%.2f, %.3f, %.2f)" % [mid_y, e.x, e.y, e.z])
	check_near(mid_y, 0.75, 0.1, "on the slope mid-way")
	check(grounded_on_slope, "grounded all the way up (no hops)")
	check(e.z < -9.5, "past the ramp top")
	check_near(e.y, 1.5, 0.03, "up on scrap_ledge")
	check(p.on_ground(), "on the ledge")
	w.free()

# --- step 4: sprint, Breath, slide -------------------------------------------------------

func test_sprint_drain_run_dry_resume() -> void:
	var w := _big_flat()
	var p := _player(w, Vector3(0, 0, 150), 0.0)
	_run(p, 30)
	_run(p, 30, [&"sprint"])   # Sprint without a move key: no sprint, no drain
	check(not p.sprinting and p.breath.value == 100.0, "standing Sprint doesn't drain")
	var s := p.feet()
	_run(p, 120, [&"forward", &"sprint"])
	print("    sprint 2 s: %.3f m/s (7.0), %.2f m, Breath %.2f (60)" % [p.horizontal_speed(), s.z - p.feet().z, p.breath.value])
	check(p.sprinting and absf(p.horizontal_speed() - 7.0) < 0.05, "sprint 7 m/s")
	check_near(p.breath.value, 60.0, 0.01, "Breath after 2 s")
	var dry := -1
	for i in 240:
		p.tick(PlayerInput.hold([&"forward", &"sprint"]), DT)
		if p.breath.empty():
			dry = 120 + i + 1
			break
	var resumed := -1
	for i in range(1, 201):
		p.tick(PlayerInput.hold([&"forward", &"sprint"]), DT)
		if i == 60:
			check(not p.sprinting and absf(p.horizontal_speed() - 4.0) < 0.05, "walks while exhausted (%.3f)" % p.horizontal_speed())
		if resumed < 0 and p.sprinting:
			resumed = i
	print("    sprint: ran dry after %d ticks (300), sprinting again %d ticks later (~100)" % [dry, resumed])
	check(absi(dry - 300) <= 1, "dry at 300")
	check(resumed >= 99 and resumed <= 102, "resumes ~100 ticks later")
	w.free()

func test_crouch_sprint_and_speed_multiplier() -> void:
	var w := _big_flat()
	var c := _player(w, Vector3(0, 0, 0), 0.0)
	_run(c, 30)
	_run(c, 120, [&"forward", &"sprint", &"crouch"])
	check(not c.sprinting and not c.sliding() and c.slides == 0 and c.crouched, "crouch + Sprint: no sprint/slide")
	check(absf(c.horizontal_speed() - 3.0) < 0.05 and c.breath.value == 100.0, "crouch speed, no drain")
	c.free()
	var m := _player(w, Vector3(5, 0, 0), 0.0)
	m.set_speed_multiplier(1.1)   # step 19 Shoes hook
	_run(m, 30)
	_run(m, 90, [&"forward"])
	var walk := m.horizontal_speed()
	_run(m, 90, [&"forward", &"sprint"])
	var sprint := m.horizontal_speed()
	_run(m, 90, [&"forward", &"crouch"])
	var crouch := m.horizontal_speed()
	print("    speed x1.1: walk %.3f (4.4), sprint %.3f (7.7), crouch %.3f (3.3)" % [walk, sprint, crouch])
	check_near(walk, 4.4, 0.05, "walk x1.1")
	check_near(sprint, 7.7, 0.05, "sprint x1.1")
	check_near(crouch, 3.3, 0.05, "crouch x1.1 (Magewar scales CROUCHING_SPEED too)")
	w.free()

func test_slide_from_sprint_90_ticks_7_5_m() -> void:
	var w := _big_flat()
	var p := _player(w, Vector3.ZERO, 0.0)
	_run(p, 30)
	_run(p, 60, [&"forward", &"sprint"])
	check(p.sprinting, "sprinting before the slide")
	var start := p.feet()
	var breath_start := p.breath.value
	var counting := true
	var slide_ticks := 0
	var entry := 0.0
	var dist := 0.0
	var side := 0.0
	var breath_end := 0.0
	for i in 180:
		if i == 30:
			p.set_look(deg_to_rad(90.0), 0.0)   # look west: the slide keeps going north
		p.tick(PlayerInput.hold([&"forward", &"sprint", &"crouch"]), DT)
		if i == 0:
			entry = p.horizontal_speed()
			check(p.sliding() and p.crouched, "sliding + crouched on the first tick")
		if counting and p.sliding():
			slide_ticks += 1
		if counting and not p.sliding():
			counting = false
			dist = start.z - p.feet().z
			side = absf(p.feet().x - start.x)
			breath_end = p.breath.value
	var after := p.horizontal_speed()
	print("    slide: %d ticks (90), %.3f m north (~7.5), sideways %.4f, entry %.3f m/s (7.5), then %.3f m/s, Breath %.2f -> %.2f"
		% [slide_ticks, dist, side, entry, after, breath_start, breath_end])
	check(p.slides == 1, "one slide, no re-trigger while held")
	check(absi(slide_ticks - 90) <= 1, "90 ticks")
	check_near(entry, 7.5, 0.05, "entry speed")
	check_near(dist, 7.5, 0.3, "slide distance")
	check(side < 0.02, "look doesn't steer the slide")
	check_near(after, 3.0, 0.05, "crouch speed once it ends")
	check(breath_end >= breath_start - 0.01, "sliding doesn't drain")
	check(p.crouched and not p.sprinting, "crouched afterwards")
	w.free()

func test_no_slide_from_walk_standing_or_exhausted() -> void:
	var w := _big_flat()
	var p := _player(w, Vector3(0, 0, 0), 0.0)
	_run(p, 30)
	_run(p, 60, [&"forward"])
	_run(p, 60, [&"forward", &"crouch"])
	check(p.slides == 0 and p.crouched and absf(p.horizontal_speed() - 3.0) < 0.05, "walk + Crouch just crouches")
	_run(p, 60, [&"forward", &"crouch", &"sprint"])
	check(p.slides == 0, "crouch first, then Sprint: no slide")
	p.free()
	var s := _player(w, Vector3(10, 0, 0), 0.0)
	_run(s, 30, [&"sprint"])
	_run(s, 30, [&"sprint", &"crouch"])
	check(s.slides == 0, "standing Sprint + Crouch: no slide")
	s.free()
	var e := _player(w, Vector3(20, 0, 150), 0.0)
	_run(e, 30)
	_run(e, 310, [&"forward", &"sprint"])
	check(not e.sprinting and e.breath.exhausted, "exhausted")
	_run(e, 1, [&"forward", &"sprint", &"crouch"])
	check(e.slides == 0 and not e.sliding(), "exhausted + Crouch: no slide")
	e.free()
	var r := _player(w, Vector3(30, 0, 0), 0.0)
	_run(r, 30)
	_run(r, 60, [&"forward", &"sprint"])
	_run(r, 20, [&"forward", &"sprint", &"crouch"])
	check(r.sliding(), "sliding")
	_run(r, 1, [&"forward", &"crouch"])
	check(not r.sliding() and r.crouched and r.slides == 1, "releasing Sprint ends the slide")
	w.free()

func test_slide_jump() -> void:
	var w := _big_flat()
	var p := _player(w, Vector3.ZERO, 0.0)
	_run(p, 30)
	_run(p, 60, [&"forward", &"sprint"])
	_run(p, 10, [&"forward", &"sprint", &"crouch"])
	check(p.sliding(), "sliding")
	var slide_speed := p.horizontal_speed()
	_run(p, 1, [&"forward", &"sprint", &"crouch"], [&"jump"])
	check(not p.sliding() and p.slide_jumps == 1 and p.jumps == 1, "slide jump")
	var apex := 0.0
	var lo := 1e9
	var hi := 0.0
	var stood := false
	for i in 120:
		p.tick(PlayerInput.hold([&"forward", &"sprint", &"crouch"]), DT)
		apex = maxf(apex, p.feet().y)
		if not p.on_ground():
			stood = stood or not p.crouched
			lo = minf(lo, p.horizontal_speed())
			hi = maxf(hi, p.horizontal_speed())
	var v := 4.5 * 1.3
	print("    slide jump: apex %.3f m (%.3f + discretisation), air speed %.3f..%.3f m/s (slide %.3f)" % [apex, v * v / 19.6, lo, hi, slide_speed])
	check_near(apex, v * v / 19.6, 0.08, "slide jump apex")
	check(stood, "stands up in the air")
	check(hi - lo < 0.05 and hi > 6.0, "slide speed kept in the air")
	check(p.on_ground() and p.slides == 1, "landing with Crouch held doesn't re-slide")
	w.free()

# --- beyond the done check --------------------------------------------------------------

func test_spawns_at_player_start_eye_in_main() -> void:
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(main)   # main.gd _ready spawns the player
	var eye := main.get_node("Level/PlayerStart/Eye") as Node3D
	var p := main.get_node("Player") as Player
	check(p.camera.global_position.distance_to(eye.global_position) < 1e-4,
		"camera at PlayerStart/Eye (%s vs %s)" % [p.camera.global_position, eye.global_position])
	check((-p.camera.global_basis.z).distance_to(-eye.global_basis.z) < 1e-4, "facing the Eye's forward (north)")
	check(main.get_node_or_null("Camera3D") == null, "placeholder camera removed")
	main.free()

func test_look_sensitivity_clamp_wrap() -> void:
	var w := _flat()
	var p := _player(w, Vector3.ZERO, 0.0)
	p.add_look(360.0, 0.0)   # 360 counts x 0.25 deg = 90 deg right
	check_near(p.yaw, deg_to_rad(-90.0), 1e-4, "yaw after 90 deg right")
	check(Player.forward_for(p.yaw).distance_to(Vector3(1, 0, 0)) < 1e-4, "facing east")
	check((-p.camera.global_basis.z).distance_to(Vector3(1, 0, 0)) < 1e-4, "camera faces east")
	p.add_look(0.0, -1000.0)
	check_near(p.pitch, deg_to_rad(89.0), 1e-6, "pitch clamp +89")
	p.add_look(0.0, 2000.0)
	check_near(p.pitch, deg_to_rad(-89.0), 1e-6, "pitch clamp -89")
	check_near(p.head.rotation.x, p.pitch, 1e-6, "Head pitch")
	p.add_look(-360.0 * 7, 0.0)   # 630 deg left -> 540 = 180
	check_near(absf(p.yaw), PI, 1e-3, "yaw wraps")
	p.set_look(deg_to_rad(-90.0), 0.0)
	_run(p, 30)
	_run(p, 60, [&"forward"])
	check(p.feet().x > 3.0 and absf(p.feet().z) < 1e-3, "walks where it looks (east)")
	w.free()

func test_ray_hits_player_on_character_layer() -> void:
	var w := _flat()
	var p := _player(w, Vector3.ZERO, 0.0)
	_run(p, 5)
	check(p.collision_layer == 2 and p.collision_mask == (1 | 4), "player on layer 'character', collides with world + enemy (step 11)")
	check(ProjectSettings.get_setting("layer_names/3d_physics/layer_2") == "character", "layer 2 named")
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 5), Vector3(0, 1, -5), 0xFFFFFFFF)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and hit["collider"] == p, "chest-height ray hits the player")
	if not hit.is_empty():
		check_near(hit["position"].z, 0.3, 0.02, "capsule radius 0.3")
	w.free()

func _has_key(action: StringName, physical: Key) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == physical:
			return true
	return false

func _has_button(action: StringName, b: MouseButton) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == b:
			return true
	return false

func test_input_map_actions() -> void:
	var keys := {&"forward": KEY_W, &"back": KEY_S, &"left": KEY_A, &"right": KEY_D, &"jump": KEY_SPACE,
		&"sprint": KEY_SHIFT, &"dash": KEY_Q, &"interact": KEY_F,
		&"slot_1": KEY_1, &"slot_2": KEY_2, &"slot_3": KEY_3, &"slot_4": KEY_4}
	for a in keys:
		check(InputMap.has_action(a) and _has_key(a, keys[a]), "action %s bound to %s" % [a, OS.get_keycode_string(keys[a])])
	check(_has_key(&"crouch", KEY_C) and _has_key(&"crouch", KEY_CTRL), "crouch = C + LCtrl")
	check(_has_button(&"action_primary", MOUSE_BUTTON_LEFT), "fire = LMB")
	check(_has_button(&"action_secondary", MOUSE_BUTTON_RIGHT), "focus = RMB")
	for a in PlayerInput.ACTIONS:
		check(InputMap.has_action(a), "PlayerInput action %s in the InputMap" % a)

func test_tuning_resource_defaults() -> void:
	var t: PlayerTuning = load("res://resources/player/player_tuning.tres")
	check(t != null, "player_tuning.tres loads")
	var expect := {"walk_speed": 4.0, "crouch_speed": 3.0, "lerp_speed": 10.0, "air_lerp_speed": 6.0,
		"jump_velocity": 4.5, "crouch_jump_velocity": 3.0, "gravity": 9.8, "radius": 0.3,
		"standing_height": 1.7, "crouching_height": 0.7, "standing_eye": 1.5, "crouching_eye": 0.6,
		"step_height": 0.35, "max_slope_deg": 45.0, "look_deg_per_count": 0.25, "max_pitch_deg": 89.0,
		"sprint_speed": 7.0, "slide_speed": 5.0, "slide_duration": 1.5, "slide_jump_mod": 1.3,
		"breath_max": 100.0, "breath_drain_per_sec": 20.0, "breath_regen_per_sec": 30.0,
		"breath_regen_delay": 1.0, "breath_resume_at": 20.0}
	for k in expect:
		check_near(float(t.get(k)), expect[k], 1e-6, k)
	var w := _flat()
	var p := _player(w, Vector3.ZERO, 0.0)
	check_near(p.floor_max_angle, deg_to_rad(45.0), 1e-6, "floor_max_angle")
	check_near(p.head.position.y, 1.5, 1e-6, "standing eye")
	w.free()
