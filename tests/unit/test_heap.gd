extends TestCase
## Step 13 done check (Heap half): the tank.
##  - resources/enemies/heap.tres = data/enemies/heap.toml; the golem's numbers (Earth,
##    slam 8 per 2 s, detect 10 / aggro 7, walk 1.2 / sprint 2.5); 150 HP; ai kind "tank"
##    spawns a Heap (a Gnawer subclass: same states and tick); the seam weak point glows
##    on its back;
##  - slow: it closes at <= 2.5 m/s;
##  - the slam: in reach it plants and winds up 0.6 s (36 ticks, no move), lands, and
##    winds up again 2 s (120 ticks) after the first started;
##  - a slam on a player takes 8 Earth off the shield; during i-frames it is dodged; out
##    of reach it whiffs;
##  - a 15 front hit doesn't stagger it; a 30 Fire seam crit (x2 from behind) knocks it
##    back 1.5 m and cancels the wind-up;
##  - enough slams kill the player; it then loses him.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const HEAP_TOML := "res://data/enemies/heap.toml"
const E := ElementTable.Element
const S := Gnawer.State

class Dummy:
	extends Node3D
	var inv := false
	func invulnerable() -> bool:
		return inv
	func eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.5, 0.0)

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

func _heap(w: Node3D, feet: Vector3) -> Heap:
	var d := EnemyTable.load_default().find("heap")
	var h := Enemy.create(d, Transform3D(Basis.IDENTITY, feet)) as Heap
	check(h != null, "the heap type spawns as a Heap")
	h.auto_tick = false
	w.add_child(h)
	return h

func _dummy(w: Node3D, feet: Vector3) -> Dummy:
	var t := Dummy.new()
	t.position = feet
	w.add_child(t)
	return t

func _player(w: Node3D, feet: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	p.position = feet   # local, placed before add_child (Jolt sees it at once)
	w.add_child(p)
	p.spawn(w.global_position + feet, 0.0)
	return p

func test_tres_matches_toml() -> void:
	var r := EnemyTable.from_toml_files([HEAP_TOML])
	check(not r.has("error"), "heap.toml loads (%s)" % r.get("error", ""))
	if r.has("error"):
		return
	var want := (r["table"] as EnemyTable).find("heap")
	var got := EnemyTable.load_default().find("heap")
	check(got != null and EnemyTable.DEFAULT_PATHS.has("res://resources/enemies/heap.tres"), "heap.tres is shipped")
	if got == null:
		return
	check(got.display_name == want.display_name and got.affinity == want.affinity and got.max_health == want.max_health
		and got.size.is_equal_approx(want.size) and got.color.is_equal_approx(want.color) and got.has_weak_point
		and got.weak_point_offset.is_equal_approx(want.weak_point_offset)
		and got.weak_point_size.is_equal_approx(want.weak_point_size), "heap.tres body = heap.toml")
	check(got.ai == want.ai, "ai tables equal: %s vs %s" % [got.ai, want.ai])
	var rd := got.rusher()
	check(rd != null and rd.kind == "tank", "tank def parses")
	if rd == null:
		return
	check(got.affinity == E.EARTH and got.max_health == 150.0 and got.size.is_equal_approx(Vector3(1.5, 2.4, 1.5)), "Earth, 150 HP, the golem's 1.5 x 2.4 x 1.5")
	check(rd.detect_range == 10.0 and rd.aggro_range == 7.0 and rd.walk_speed == 1.2 and rd.sprint_speed == 2.5
		and rd.attack_damage == 8.0 and rd.attack_cooldown == 2.0 and rd.knockback_strength == 15.0, "garbage golem numbers")
	check(rd.attack_windup == 0.6 and rd.knockback_threshold == 25.0 and rd.knockback_time == 0.2 and rd.turn_rate_deg == 120.0, "tank design: 0.6 s wind-up, hard to shove, slow turn")
	check(got.weak_point_offset.z > got.size.z * 0.5 and got.weak_point_size.x > got.weak_point_size.y * 3.0, "a wide flat seam on its back (+Z)")
	var dflt: RusherDef = RusherDef.parse({"kind": "rusher"}, Vector3(0.5, 0.5, 0.5))["def"]
	check(dflt.attack_windup == 0.0, "rushers bite at once (windup 0)")
	var h := Enemy.create(got) as Heap
	check(h is Gnawer and h.rusher.kind == "tank" and h.health == 150.0, "a Heap is a Gnawer with the tank def")
	var mat := (h.get_node("HeadMesh") as MeshInstance3D).material_override as StandardMaterial3D
	if mat == null:
		mat = (h.get_node("HeadMesh") as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
	check(mat != null and mat.emission_enabled, "the seam glows")
	h.free()

func test_slow_chase() -> void:
	var w := await _world(Vector3(3400, 0, -2400))
	var h := _heap(w, Vector3(0, 0, 0))
	h.target = _dummy(w, Vector3(0, 0, -6.5))
	var max_step := 0.0
	for i in 90:
		var at := h.global_position
		h.tick(DT)
		max_step = maxf(max_step, Gnawer._flat(h.global_position - at).length())
	print("    heap chase: %s, travelled %.3f, max step %.4f" % [h.transitions.map(func(t: Gnawer.Transition) -> String: return Gnawer.state_name(t.to)), h.travelled, max_step])
	check(h.state == S.CHASE, "6.5 m (< aggro 7): chasing")
	check(max_step <= 2.5 / 60.0 + 1e-4, "never faster than 2.5 m/s (%.4f m/tick)" % max_step)
	check_near(h.travelled, 1.2 / 60.0 + 89.0 * 2.5 / 60.0, 0.01, "detect tick at 1.2 m/s, then 89 ticks at 2.5 m/s")
	w.free()

func test_slam_windup_and_cooldown() -> void:
	var w := await _world(Vector3(3400, 0, -2200))
	var h := _heap(w, Vector3(0, 0, 0))
	h.target = _dummy(w, Vector3(0, 0, -1.5))
	var slam_ticks: Array[int] = []
	h.attacked.connect(func(_g: Gnawer, b: Gnawer.Bite) -> void: slam_ticks.append(b.tick))
	var start := -1
	var moved_in_windup := 0.0
	for i in 170:
		var at := h.global_position
		h.tick(DT)
		if h.winding_up():
			if start < 0:
				start = h.windup_started_tick
			moved_in_windup = maxf(moved_in_windup, Gnawer._flat(h.global_position - at).length())
	print("    slams at %s, wind-ups %d from tick %d" % [slam_ticks, h.slams, start])
	check(start == 3 and h.state == S.ATTACK, "1.5 m: attack + wind-up on tick 3 (%d)" % start)
	check(slam_ticks.size() == 2 and slam_ticks[0] == start + 36, "lands 36 ticks (0.6 s) later (%s)" % [slam_ticks])
	check(slam_ticks.size() == 2 and slam_ticks[1] == slam_ticks[0] + 120, "the next 2 s later (%s)" % [slam_ticks])
	check(moved_in_windup < 1e-4, "planted while winding up")
	check(h.attacks.size() == 2 and h.attacks[0].damage == 8.0 and h.attacks[0].element == E.EARTH and h.landed == 2 and h.whiffs == 0, "8 Earth slams")
	w.free()

func test_slam_hits_player_shield_dodge_and_whiff() -> void:
	var w := await _world(Vector3(3400, 0, -2000))
	var h := _heap(w, Vector3(0, 0, 0))
	var p := _player(w, Vector3(0, 0, -1.5))
	h.target = p
	h.attacked.connect(p.on_enemy_attack)
	var still := PlayerInput.hold([])
	for i in 3 + 36:
		h.tick(DT)
		p.tick(still, DT)
	check(h.landed == 1 and p.hits_taken == 1, "the slam lands on the player")
	check(p.health.shield == 42.0 and p.health.value == 100.0, "8 Earth off the shield (%.1f)" % p.health.shield)
	# A dodge: i-frames at the moment it lands.
	var t := _dummy(w, Vector3(1.5, 0, 0))
	h.target = t
	for i in 200:
		h.tick(DT)
		t.inv = h.winding_up() and h.windup_left <= DT * 1.5
	check(h.dodged >= 1 and h.attacks[-1].dodged, "a slam into i-frames is dodged (%d)" % h.dodged)
	# A whiff: the target steps out of reach during the wind-up.
	var whiffs := h.whiffs
	var n := h.attacks.size()
	for i in 200:
		if h.winding_up():
			t.position = Vector3(4.0, 0, 0)
			h.tick(DT)
			break
		h.tick(DT)
	for i in 40:
		h.tick(DT)
	check(h.whiffs == whiffs + 1 and h.attacks.size() == n, "out of reach when it lands: a whiff, no attack")
	w.free()

func test_seam_crit_staggers_and_cancels() -> void:
	var w := await _world(Vector3(3400, 0, -1800))
	var h := _heap(w, Vector3(0, 0, 0))
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	h.target = _dummy(w, Vector3(0, 0, -1.5))
	for i in 3:
		h.tick(DT)
	check(h.winding_up(), "winding up")
	await runner_tree.physics_frame
	# From the front (-Z): the body, Fire 10 x 1.5 = 15 <= 25: no stagger.
	var hits := _shoot(w, bolts, Vector3(0.3, 1.0, -0.9), Vector3(0, 0, 1), E.FIRE, 10.0)
	check(hits.size() == 1 and hits[0].collider == h and is_equal_approx(hits[0].result.amount, 15.0) and not hits[0].result.crit > 1.0, "front: 15")
	h.tick(DT)
	check(h.knockbacks == 0 and h.winding_up(), "15: no knockback, still winding up")
	await runner_tree.physics_frame
	# From behind (+Z) into the seam: x2 = 30 > 25.
	hits = _shoot(w, bolts, Vector3(0, 1.4, 4), Vector3(0, 0, -1), E.FIRE, 10.0)
	check(hits.size() == 1 and hits[0].collider == h and is_equal_approx(hits[0].result.amount, 30.0), "the seam crit does 30 (%s)" % [hits.map(func(x: SpellBolts.Hit) -> float: return x.result.amount if x.result else -1.0)])
	var at := h.global_position
	var kb := 0
	for i in 20:
		h.tick(DT)
		if h.state == S.KNOCKBACK:
			kb += 1
	var moved := h.global_position - at
	print("    seam crit: %d knockback ticks, moved %s, interrupted %d" % [kb, moved, h.interrupted])
	check(h.knockbacks == 1 and kb == 12, "knocked back 0.2 s = 12 ticks (%d)" % kb)
	check_near(moved.z, -1.5, 0.03, "pushed 1.5 m along the bolt")
	check(h.interrupted == 1 and h.landed == 0 and h.attacks.is_empty(), "the wind-up is cancelled")
	check(h.health == 150.0 - 15.0 - 30.0, "105 HP left")
	w.free()

func _shoot(w: Node3D, bolts: SpellBolts, origin: Vector3, dir: Vector3, element: E, damage: float) -> Array[SpellBolts.Hit]:
	var s := SpellBolts.Spawn.new()
	s.origin = w.global_position + origin
	s.direction = dir
	s.speed = 60.0
	s.range_m = 20.0
	s.element = element
	s.damage = damage
	bolts.spawn(s)
	var out: Array[SpellBolts.Hit] = []
	for i in 30:
		out.append_array(bolts.tick(DT))
	return out

func test_slams_kill_the_player_then_it_loses_him() -> void:
	var w := await _world(Vector3(3400, 0, -1600))
	var h := _heap(w, Vector3(0, 0, 0))
	var p := _player(w, Vector3(0, 0, -1.5))
	h.target = p
	h.attacked.connect(p.on_enemy_attack)
	p.health.take(140.0)   # shield 0, 10 health; the regen delay restarts
	var still := PlayerInput.hold([])
	var died_at := -1
	for i in 200:
		h.tick(DT)
		p.tick(still, DT)
		if not p.alive() and died_at < 0:
			died_at = h.ticks
	check(p.deaths == 1 and died_at == 3 + 36 + 120, "two slams (8 + 8 > 10) kill him (tick %d)" % died_at)
	check(p.health.value == 0.0, "at 0")
	check(h.state == S.IDLE and h.landed == 2, "then it loses him: idle (%s)" % Gnawer.state_name(h.state))
	w.free()
