extends TestCase
## Step 12 done check (port of the archived test_gnawer.cpp, old step 23): Gnawer AI.
##  - resources/enemies/gnawer.tres = data/enemies/gnawer.toml (ai table too); RusherDef
##    defaults are Magewar's enemy_base exports; bad ai tables rejected (C++ messages);
##  - next_state is the C++ table; Enemy.create gives a Gnawer for the rusher;
##  - from 7 m on open floor: Idle -> Detect at tick 1 (8 m detect range), Detect -> Chase
##    at 6 m (walking 3 m/s), Chase -> Attack at 1 m (sprinting 5.5 m/s); it stops at
##    0.9 m, bites at once and every 48 ticks (0.8 s), 3 Earth each; backs off -> chases
##    again; 12 m away -> Attack -> Chase -> Idle; beyond 8 m or behind a wall: idle;
##  - provoked behind a wall, it runs around it on the baked navmesh to the player;
##  - it falls onto the floor and climbs a 0.2 m step;
##  - a 10 hit doesn't knock it back, a real 15 Fire bolt does: 30 ticks, 2.5 m along
##    the bolt; a bite on an invulnerable target is dodged but spends the cooldown;
##  - dead, it stops thinking; in the Midden it bites a standing player >= 2 times in
##    3 s and never shoves him.
## World setups bake a LevelNavigation and await physics frames until the map syncs; the
## Gnawer (auto_tick off) is then ticked by hand at 1/60 s.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LEVEL_SCENE := "res://scenes/levels/midden.tscn"
const GNAWER_TOML := "res://data/enemies/gnawer.toml"
const E := ElementTable.Element
const S := Gnawer.State


## A target that is not a Player (dodge tests).
class Dummy:
	extends Node3D
	var inv := false

	func invulnerable() -> bool:
		return inv

	func eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.5, 0.0)


## A test world at `at`: Boxes (a 40 x 40 floor, top at y 0, + `boxes` [center, half])
## and a LevelNavigation baked from them, awaited until the navigation map has it.
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
	w.add_child(nav)  # bakes in _ready
	for i in 120:
		if nav.map_ready():
			break
		await runner_tree.physics_frame
	check(nav.map_ready(), "navmesh synced to the map")
	return w


func _box(parent: Node3D, center: Vector3, half: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.position = center
	parent.add_child(b)
	return b


func _gnawer(w: Node3D, feet: Vector3, yaw_deg := 0.0) -> Gnawer:
	var d := EnemyTable.load_default().find("gnawer")
	var g := Enemy.create(d, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), feet)) as Gnawer
	check(g != null, "the gnawer type spawns as a Gnawer")
	g.auto_tick = false
	w.add_child(g)
	return g


func _player(w: Node3D, feet: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position + feet, 0.0)
	return p


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _names(g: Gnawer) -> String:
	var out: PackedStringArray = []
	for t in g.transitions:
		out.append("%s->%s@%d(%.2f)" % [Gnawer.state_name(t.from), Gnawer.state_name(t.to), t.tick, t.distance])
	return ", ".join(out)


func test_tres_matches_toml_and_rusher_def() -> void:
	var r := EnemyTable.from_toml_files([GNAWER_TOML])
	check(not r.has("error"), "gnawer.toml loads (%s)" % r.get("error", ""))
	if r.has("error"):
		return
	var want := (r["table"] as EnemyTable).find("gnawer")
	var got := EnemyTable.load_default().find("gnawer")
	check(got != null and EnemyTable.DEFAULT_PATHS.has("res://resources/enemies/gnawer.tres"), "gnawer.tres is shipped")
	if got == null:
		return
	check(
		(
			got.display_name == want.display_name
			and got.affinity == want.affinity
			and got.max_health == want.max_health
			and got.size.is_equal_approx(want.size)
			and got.color.is_equal_approx(want.color)
			and got.weak_point_offset.is_equal_approx(want.weak_point_offset)
			and got.weak_point_size.is_equal_approx(want.weak_point_size)
		),
		"gnawer.tres body = gnawer.toml"
	)
	check(got.ai == want.ai, "ai tables equal: %s vs %s" % [got.ai, want.ai])
	var rd := got.rusher()
	check(rd != null, "rusher def parses")
	if rd == null:
		return
	check(
		(
			rd.detect_range == 8.0
			and rd.aggro_range == 6.0
			and rd.walk_speed == 3.0
			and rd.sprint_speed == 5.5
			and rd.attack_range == 1.0
			and rd.attack_damage == 3.0
			and rd.attack_cooldown == 0.8
		),
		"Mutant Rat numbers"
	)
	check(
		(
			rd.knockback_strength == 10.0
			and rd.knockback_time == 0.5
			and rd.knockback_threshold == 10.0
			and rd.turn_rate_deg == 540.0
		),
		"enemy_base knockback, 540 deg/s turn (default)"
	)
	var dflt: RusherDef = RusherDef.parse({"kind": "rusher"}, Vector3(0.5, 0.5, 0.5))["def"]
	check(
		(
			dflt.detect_range == 15.0
			and dflt.aggro_range == 10.0
			and dflt.walk_speed == 2.0
			and dflt.sprint_speed == 4.0
			and dflt.attack_damage == 5.0
			and dflt.attack_cooldown == 1.5
		),
		"defaults = Magewar enemy_base exports"
	)


func test_bad_ai_rejected() -> void:
	var ok := '[[enemy]]\nid = "g"\nname = "G"\naffinity = "earth"\nmax_health = 30\nsize = [0.5, 0.45, 0.8]\ncolor = [0.5, 0.5, 0.5]\n'
	var good := EnemyTable.from_toml(LevelToml.parse(ok + 'ai = { kind = "rusher" }\n'))
	check(not good.has("error"), "minimal rusher loads (%s)" % good.get("error", ""))
	var cases := {
		'ai = { kind = "flier" }': "unknown ai kind",
		'ai = { kind = "tank", attack_cooldown = 1.0, attack_windup = 1.0 }': "attack_windup must be shorter",
		"ai = { detect_range = 8.0 }": "missing key 'kind'",
		'ai = { kind = "rusher", detect_range = 5.0, aggro_range = 6.0 }': "aggro_range must not exceed detect_range",
		'ai = { kind = "rusher", attack_cooldown = -1.0 }': "attack_cooldown",
		'ai = { kind = "rusher", sight = 3.0 }': "unknown key 'sight'",
		'ai = { kind = "rusher", attack_range = 0.5 }': "attack_range must exceed",
		"ai = 5": "ai must be a table",
	}
	for k in cases:
		var r := EnemyTable.from_toml(LevelToml.parse(ok + k + "\n"))
		check(
			r.has("error") and String(r.get("error", "")).contains(cases[k]),
			"%s -> %s (got %s)" % [k, cases[k], r.get("error", "loaded")]
		)


func test_next_state_table() -> void:
	var r := EnemyTable.load_default().find("gnawer").rusher()
	var s := Gnawer.Senses.new()
	s.target_valid = true
	s.line_of_sight = true
	s.distance = 7.0
	check(Gnawer.next_state(S.IDLE, r, s) == S.DETECT, "7 m in sight: detect")
	s.line_of_sight = false
	check(Gnawer.next_state(S.IDLE, r, s) == S.IDLE, "no sight: idle")
	s.provoked = true
	check(
		Gnawer.next_state(S.IDLE, r, s) == S.CHASE and Gnawer.next_state(S.DETECT, r, s) == S.CHASE, "provoked: chase"
	)
	s.provoked = false
	s.line_of_sight = true
	s.distance = 8.01
	check(Gnawer.next_state(S.IDLE, r, s) == S.IDLE and Gnawer.next_state(S.DETECT, r, s) == S.IDLE, "beyond 8 m: idle")
	check(Gnawer.next_state(S.CHASE, r, s) == S.IDLE, "chase gives up beyond 8 m")
	s.hunting = true
	check(Gnawer.next_state(S.CHASE, r, s) == S.CHASE, "unless hunting")
	s.hunting = false
	s.distance = 6.0
	check(
		Gnawer.next_state(S.DETECT, r, s) == S.CHASE and Gnawer.next_state(S.IDLE, r, s) == S.DETECT,
		"6 m: chase (one step a tick)"
	)
	s.line_of_sight = false
	check(
		Gnawer.next_state(S.CHASE, r, s) == S.CHASE and Gnawer.next_state(S.DETECT, r, s) == S.IDLE,
		"chase needs no sight, detect does"
	)
	s.distance = 1.0
	check(Gnawer.next_state(S.CHASE, r, s) == S.ATTACK, "1 m: attack")
	s.distance = 1.3
	check(Gnawer.next_state(S.ATTACK, r, s) == S.ATTACK, "attack slack 0.3")
	s.distance = 1.31
	check(Gnawer.next_state(S.ATTACK, r, s) == S.CHASE, "past the slack: chase")
	s.knockback_left = 0.1
	check(
		Gnawer.next_state(S.ATTACK, r, s) == S.KNOCKBACK and Gnawer.next_state(S.IDLE, r, s) == S.KNOCKBACK,
		"knockback overrides"
	)
	s.knockback_left = 0.0
	check(Gnawer.next_state(S.KNOCKBACK, r, s) == S.CHASE, "after knockback: chase")
	s.distance = 0.9
	check(Gnawer.next_state(S.KNOCKBACK, r, s) == S.ATTACK, "after knockback, close: attack")
	s.target_valid = false
	check(Gnawer.next_state(S.ATTACK, r, s) == S.IDLE, "no target: idle")
	s.dead = true
	check(
		Gnawer.next_state(S.CHASE, r, s) == S.DEAD and Gnawer.next_state(S.DEAD, r, Gnawer.Senses.new()) == S.DEAD,
		"dead is terminal"
	)


## Done check: transitions at 8 / 6 / 1 m, bites 48 ticks apart, re-chase, give up.
func test_detect_chase_attack_from_7m() -> void:
	var w := await _world(Vector3(-2400, 0, 2400))
	var g := _gnawer(w, Vector3(0, 0, 0))
	var p := _player(w, Vector3(0, 0, -7))
	g.target = p
	check(g.collision_mask == 1 | 4 and g.collision_layer == 4, "layer enemy, mask world + enemy (never the player)")
	var min_dist := 100.0
	var bite_ticks: Array[int] = []
	g.attacked.connect(func(_g: Gnawer, b: Gnawer.Bite) -> void: bite_ticks.append(b.tick))
	for i in 200:
		g.tick(DT)
		min_dist = minf(min_dist, _flat_dist(g.global_position, p.global_position))
	var t := g.transitions
	print("    transitions: ", _names(g), "; bites at ", bite_ticks, "; travelled %.3f" % g.travelled)
	check(t.size() == 3, "three transitions (%s)" % _names(g))
	if t.size() < 3:
		w.free()
		return
	check(
		t[0].from == S.IDLE and t[0].to == S.DETECT and t[0].tick == 1 and is_equal_approx(t[0].distance, 7.0),
		"idle -> detect at tick 1, 7 m (in the 8 m range)"
	)
	check(
		(
			t[1].from == S.DETECT
			and t[1].to == S.CHASE
			and t[1].distance <= 6.0
			and t[1].distance > 5.9
			and absi(t[1].tick - 21) <= 1
		),
		"detect -> chase at 6 m, ~tick 21 (walk 3 m/s)"
	)
	check(
		t[2].from == S.CHASE and t[2].to == S.ATTACK and t[2].distance <= 1.0 and absi(t[2].tick - t[1].tick - 56) <= 2,
		"chase -> attack at 1 m, ~56 ticks later (sprint 5.5 m/s)"
	)
	check_near(g.distance, 0.9, 0.02, "stops at 90 % of the bite range")
	check(min_dist >= 0.7, "never into the player (min %.3f)" % min_dist)
	check_near(g.travelled, 6.1, 0.05, "travelled")
	check(bite_ticks.size() >= 3 and bite_ticks[0] == t[2].tick, "first bite on entering attack")
	for i in range(1, bite_ticks.size()):
		check(bite_ticks[i] - bite_ticks[i - 1] == 48, "bites 48 ticks (0.8 s) apart: %s" % [bite_ticks])
	check(
		(
			g.attacks.size() > 0
			and g.attacks[0].damage == 3.0
			and g.attacks[0].element == E.EARTH
			and not g.attacks[0].dodged
		),
		"3 Earth per bite"
	)
	var face := Player.forward_for(g.rotation.y)
	check(face.dot((p.global_position - g.global_position).normalized()) > 0.99, "faces the player (yaw 0 = -Z)")
	# The player backs off 0.6 m: chase, then attack again.
	var n := g.transitions.size()
	p.global_position += Vector3(0, 0, -0.6)
	for i in 60:
		g.tick(DT)
	var again := g.transitions.slice(n)
	check(
		again.size() == 2 and again[0].to == S.CHASE and again[1].to == S.ATTACK,
		"backs off 0.6 m: chase, attack (%s)" % _names(g)
	)
	# 12 m away: attack -> chase -> idle (beyond detect, not hunting).
	n = g.transitions.size()
	p.global_position = g.global_position + Vector3(0, 0, -12)
	for i in 3:
		g.tick(DT)
	var gone := g.transitions.slice(n)
	check(
		gone.size() == 2 and gone[0].to == S.CHASE and gone[1].to == S.IDLE and g.state == S.IDLE,
		"12 m: attack -> chase -> idle (%s)" % _names(g)
	)
	w.free()


func test_idle_beyond_8m_and_behind_a_wall() -> void:
	var w := await _world(Vector3(-2400, 0, 2500), [[Vector3(0, 1.5, -3), Vector3(2, 1.5, 0.2)]])
	var far := _gnawer(w, Vector3(6, 0, 0))
	var _p := _player(w, Vector3(6, 0, -8.2))
	var hidden := _gnawer(w, Vector3(0, 0, 0))
	hidden.target = _p
	far.target = _p
	_p.global_position = w.global_position + Vector3(6, 0, -8.2)
	for i in 120:
		far.tick(DT)
	check(far.state == S.IDLE and far.transitions.is_empty() and far.travelled == 0.0, "8.2 m away: stays idle")
	_p.global_position = w.global_position + Vector3(0, 0, -5)  # behind the 3 m wall
	for i in 120:
		hidden.tick(DT)
	check(
		hidden.state == S.IDLE and hidden.transitions.is_empty(),
		"5 m away behind a 3 m wall: stays idle (%s)" % _names(hidden)
	)
	_p.global_position = w.global_position + Vector3(6, 0, -7.9)
	far.tick(DT)
	check(far.state == S.DETECT, "7.9 m in sight: detect")
	w.free()


## Done check: provoked behind a wall, it paths around it on the navmesh.
func test_chases_around_a_wall() -> void:
	var wall_c := Vector3(0, 1.0, -3)
	var wall_h := Vector3(2, 1.0, 0.2)
	var w := await _world(Vector3(-2400, 0, 2600), [[wall_c, wall_h]])
	var g := _gnawer(w, Vector3(0, 0, 0))
	var p := _player(w, Vector3(0, 0, -6))
	g.target = p
	g.provoked = true  # as if hit (C++ test: provoked)
	g.hunt_left = Gnawer.HUNT_TIME
	var max_x := 0.0
	var inside := false
	var reached := -1
	for i in 360:
		g.tick(DT)
		var lp := g.global_position - w.global_position
		max_x = maxf(max_x, absf(lp.x))
		if absf(lp.x - wall_c.x) < wall_h.x and absf(lp.z - wall_c.z) < wall_h.z:
			inside = true
		if g.state == S.ATTACK and reached < 0:
			reached = i + 1
	print(
		(
			"    around the wall: reached attack at tick %d, |x| max %.2f, %d nav ticks, %s"
			% [reached, max_x, g.nav_ticks, _names(g)]
		)
	)
	check(
		reached > 0 and g.distance <= 1.0,
		"reaches the player behind the wall (attack at tick %d, %.2f m)" % [reached, g.distance]
	)
	check(max_x > wall_h.x, "went around the wall's end (|x| max %.2f)" % max_x)
	check(not inside, "never through the wall")
	check(g.nav_ticks > 0, "steered by the navmesh path")
	check(g.bites >= 1, "and bites")
	w.free()


func test_falls_and_climbs_a_step() -> void:
	var w := await _world(Vector3(-2400, 0, 2700), [[Vector3(0, 0.1, -5), Vector3(3, 0.1, 2)]])
	var g := _gnawer(w, Vector3(0, 1.0, 2))
	var t := Dummy.new()
	t.position = Vector3(0, 0.2, -5.5)
	w.add_child(t)
	for i in 60:
		g.tick(DT)
	check_near(g.global_position.y - w.global_position.y, 0.0, 0.02, "fell onto the floor")
	check(g.state == S.IDLE, "no target: idle")
	g.target = t
	for i in 240:
		g.tick(DT)
	print(
		(
			"    step: feet y %.3f, %d step(s), %.2f m, %s"
			% [g.global_position.y - w.global_position.y, g.steps_climbed, g.distance, _names(g)]
		)
	)
	check_near(g.global_position.y - w.global_position.y, 0.2, 0.03, "climbed onto the 0.2 m step")
	check(g.distance <= 1.0 and g.state == S.ATTACK, "reached its target up there")
	w.free()


func test_knockback() -> void:
	var w := await _world(Vector3(-2400, 0, 2800))
	var g := _gnawer(w, Vector3(0, 0, 0))
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	g.tick(DT)  # settled
	var start := g.global_position
	# 10 Arcane (neutral on Earth) = 10: not over the threshold.
	var hits := _shoot(w, bolts, Vector3(-3, 0.15, 0), Vector3(1, 0, 0), E.ARCANE, 10.0)
	check(
		hits.size() == 1 and hits[0].collider == g and is_equal_approx(hits[0].result.amount, 10.0),
		"a 10 hit (%s)" % [hits.map(func(h: SpellBolts.Hit) -> float: return h.result.amount if h.result else -1.0)]
	)
	g.tick(DT)
	check(g.knockbacks == 0 and g.state != S.KNOCKBACK and g.flash > 0.0, "10 damage: no knockback (flash still runs)")
	check(g.state == S.IDLE, "no target: provoked but idle")
	await runner_tree.physics_frame  # Jolt sees its settled pose
	# A real Apprentice-Fire-Staff-sized bolt: Fire 10 x 1.5 on Earth = 15.
	hits = _shoot(w, bolts, Vector3(-3, 0.15, 0), Vector3(1, 0, 0), E.FIRE, 10.0)
	check(
		hits.size() == 1 and hits[0].collider == g and is_equal_approx(hits[0].result.amount, 15.0),
		"the Fire bolt does 15"
	)
	check(g.knockbacks == 1 and is_equal_approx(g.knockback_left, 0.5), "15 > 10: knocked back for 0.5 s")
	start = g.global_position
	var kb_ticks := 0
	for i in 45:
		g.tick(DT)
		if g.state == S.KNOCKBACK:
			kb_ticks += 1
	var moved := g.global_position - start
	print("    knockback: %d ticks, moved %s" % [kb_ticks, moved])
	check(kb_ticks == 30, "30 knockback ticks (%d)" % kb_ticks)
	check_near(moved.x, 2.5, 0.02, "pushed 2.5 m along the bolt")
	check(absf(moved.z) < 0.01, "straight along it")
	check(g.state == S.IDLE, "then idle (no target)")
	# Step 53: the Fire bolt also burns (MagicEffects), so the burn so far comes off too.
	check(g.burn_damage > 0.0 and is_equal_approx(g.health, 30.0 - 10.0 - 15.0 - g.burn_damage), "health 5 less burn")
	w.free()


func _shoot(
	w: Node3D, bolts: SpellBolts, origin: Vector3, dir: Vector3, element: E, damage: float
) -> Array[SpellBolts.Hit]:
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


func test_dodged_bite_spends_the_cooldown() -> void:
	var w := await _world(Vector3(-2400, 0, 2900))
	var g := _gnawer(w, Vector3(0, 0, 0))
	var t := Dummy.new()
	t.inv = true
	t.position = Vector3(0, 0, -0.95)
	w.add_child(t)
	g.target = t
	for i in 3:
		g.tick(DT)
	check(
		g.state == S.ATTACK and g.transitions.size() == 3 and g.transitions[2].tick == 3,
		"attack on tick 3 from 0.95 m (%s)" % _names(g)
	)
	check(
		g.dodged == 1 and g.bites == 0 and g.attacks.size() == 1 and g.attacks[0].dodged,
		"the bite is dodged (i-frames)"
	)
	t.inv = false
	var at := -1
	for i in 60:
		g.tick(DT)
		if g.bites == 1 and at < 0:
			at = g.ticks
	check(at == 3 + 48, "next bite 48 ticks later (tick %d)" % at)
	w.free()


func test_dead_stops_thinking() -> void:
	var w := await _world(Vector3(-2400, 0, 3000))
	var g := _gnawer(w, Vector3(0, 0, 0))
	var p := _player(w, Vector3(0, 0, -3))
	g.target = p
	for i in 10:
		g.tick(DT)
	check(g.state == S.CHASE, "chasing")
	g.apply_damage(100.0, E.FIRE)
	g.tick(DT)
	check(g.state == S.DEAD and g.transitions[-1].to == S.DEAD, "dead")
	var at := g.global_position
	var n := g.ticks
	for i in 30:
		g.tick(DT)
	check(g.ticks == n and g.global_position == at and g.bites == 0, "stops thinking and moving")
	w.free()


func test_midden_gnawer_bites_without_shoving() -> void:
	var w := Node3D.new()
	w.position = Vector3(-2400, 0, 3200)
	runner_tree.root.add_child(w)
	var level: Node3D = (load(LEVEL_SCENE) as PackedScene).instantiate()
	w.add_child(level)
	var nav := level.get_node("Navigation") as LevelNavigation
	check(
		nav != null and nav.bakes == 1 and nav.navigation_mesh.get_polygon_count() > 0,
		"the Midden bakes its navmesh at load"
	)
	for i in 120:
		if nav.map_ready():
			break
		await runner_tree.physics_frame
	check(nav.map_ready(), "Midden navmesh synced")
	var enemies := Node3D.new()
	w.add_child(enemies)
	var got := Enemy.spawn_at_markers(level, enemies, EnemyTable.load_default())
	var g: Gnawer = null
	for e in got:
		if e is Gnawer and not e is Heap:  # (step 13: the Heap is a Gnawer subclass)
			g = e
	check(g != null, "the Midden's gnawer_3 marker spawns a Gnawer")
	if g == null:
		w.free()
		return
	g.auto_tick = false
	# The player stands 4 m in front of it (its yaw -135: facing +X +Z).
	var p := _player(w, g.global_position - w.global_position + Vector3(2.8, 0, 2.8))
	g.target = p
	var still := PlayerInput.hold([])
	for i in 10:
		p.tick(still, DT)
	var feet := p.global_position
	for i in 180:
		g.tick(DT)
		p.tick(still, DT)
	print("    midden: %d bite(s), player moved %.4f m, %s" % [g.bites, _flat_dist(p.global_position, feet), _names(g)])
	check(g.bites >= 2, "bites the standing player >= 2 times in 3 s (%d)" % g.bites)
	check(_flat_dist(p.global_position, feet) < 0.01, "never shoves him")
	w.free()
