extends TestCase
## Step 14 done check: enemy spawner + kill events (BUILD_PLAN step 14).
##  - the EventBus autoload is GameEvents.bus(); enemy_killed fires once per death (a
##    hit on the dead, or killing it again before a reset, doesn't re-fire), with the
##    killing element; player_damaged fires for every hit the player takes;
##  - the Midden's [waves] / [[wave]] / [[spawn_point]] TOML = the generated Waves /
##    WaveSpawns nodes (via LevelToml); the dummies carry respawn_s = 3;
##  - EnemySpawner in the Midden: 4 marker enemies, Gnawers hunt the player and their
##    bites hurt him; a dead dummy is back at full health at its marker after exactly
##    180 ticks (3 s) and can die (and be announced) again; a dead Gnawer is freed 2
##    ticks after its death;
##  - the waves: nothing until the player stands at the mound; then gnawer_pack (3) 1 s
##    later on the north_ledge ring, flank (2 + 2) 3 s after it is cleared, heap_push
##    (Heap + 2 Gnawers) 3 s after that, then waves_completed once; every wave enemy's
##    death is one enemy_killed and it is freed;
##  - spawn protection: 1 s (60 ticks) of ignored hits after a respawn;
##  - separation: 3 Gnawers lined up behind each other all reach and bite the player
##    (with separation off the back ones queue out of reach), one tick per physics frame;
##    none climbs onto another's back (a step 12 bug: they used to ride each other).

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LEVEL_SCENE := "res://scenes/levels/midden.tscn"
const LEVEL_TOML := "res://data/levels/midden_greybox.toml"
const E := ElementTable.Element


func _plain_world(at: Vector3, with_nav := true) -> Node3D:
	var w := Node3D.new()
	w.position = at
	runner_tree.root.add_child(w)
	var b := Node3D.new()
	b.name = "Boxes"
	w.add_child(b)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(40, 0.2, 40)
	cs.shape = s
	body.add_child(cs)
	body.position = Vector3(0, -0.1, 0)
	b.add_child(body)
	if with_nav:
		var nav := LevelNavigation.new()
		nav.name = "Navigation"
		w.add_child(nav)
		for i in 120:
			if nav.map_ready():
				break
			await runner_tree.physics_frame
		check(nav.map_ready(), "navmesh synced to the map")
	return w


## The Midden at `at`, its navmesh synced, a player at `feet` (level space) and a manual
## EnemySpawner set up on it.
func _midden(at: Vector3, feet: Vector3) -> Dictionary:
	var w := Node3D.new()
	w.position = at
	runner_tree.root.add_child(w)
	var level: Node3D = (load(LEVEL_SCENE) as PackedScene).instantiate()
	w.add_child(level)
	var nav := level.get_node("Navigation") as LevelNavigation
	for i in 120:
		if nav.map_ready():
			break
		await runner_tree.physics_frame
	check(nav.map_ready(), "Midden navmesh synced")
	var p := _player(w, feet)
	var sp := EnemySpawner.new()
	sp.auto_tick = false
	sp.vigil_tier = -1  # step 95: no random elites (a Splitting one made this flaky)
	sp.name = "Enemies"
	w.add_child(sp)
	var got := sp.setup(level, p)
	return {"w": w, "level": level, "player": p, "spawner": sp, "got": got}


func _player(w: Node3D, feet: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position + feet, 0.0)
	return p


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_event_bus_autoload() -> void:
	check(
		ProjectSettings.get_setting("autoload/EventBus", "") == "*res://scripts/core/event_bus.gd",
		"EventBus is a project autoload"
	)
	var n := runner_tree.root.get_node_or_null("EventBus")
	check(n is GameEvents and GameEvents.bus() == n, "GameEvents.bus() is the autoload node")


func test_kill_events_fire_once_per_death() -> void:
	var w := await _plain_world(Vector3(4000, 0, -4000), false)
	var d := EnemyTable.load_default().find("earth_training_dummy")
	var e := Enemy.create(d, Transform3D(Basis.IDENTITY, Vector3(0, 0, -3)))
	w.add_child(e)
	var bus := GameEvents.bus()
	var seen: Array = []
	var died := [0]
	var on_kill := func(en: Enemy, el: ElementTable.Element) -> void: seen.append([en, el])
	bus.enemy_killed.connect(on_kill)
	e.died.connect(func(_en: Enemy, _el: ElementTable.Element) -> void: died[0] += 1)
	var k0 := bus.kills
	check(not e.apply_damage(20.0, E.FIRE) and seen.is_empty(), "a hit that doesn't kill: no event")
	check(e.apply_damage(1000.0, E.WATER), "the lethal hit kills")
	check(
		seen.size() == 1 and seen[0][0] == e and seen[0][1] == E.WATER and died[0] == 1 and bus.kills == k0 + 1,
		"one enemy_killed (this enemy, the killing Water) and one died (%d, %d)" % [seen.size(), died[0]]
	)
	check(
		not e.apply_damage(50.0, E.FIRE) and seen.size() == 1 and died[0] == 1 and e.deaths == 1,
		"hits on the dead: no second event"
	)
	e.reset()
	check(
		(
			not e.dead
			and e.health == e.max_health()
			and e.is_in_group(Enemy.GROUP)
			and e.visible
			and e.collision_layer == 1 << (Enemy.ENEMY_LAYER - 1)
			and not e.body_shape.disabled
		),
		"reset: alive, full health, colliding, in the group"
	)
	e.apply_damage(1000.0, E.EARTH)
	check(seen.size() == 2 and seen[1][1] == E.EARTH and e.deaths == 2, "after a reset its next death fires again")
	bus.enemy_killed.disconnect(on_kill)
	await runner_tree.process_frame  # the deferred collision calls of both deaths + the reset ran
	check(e.collision_layer == 0 and e.body_shape.disabled, "dead again: no collision after the deferred calls")
	e.reset()
	await runner_tree.process_frame
	check(
		e.collision_layer == 1 << (Enemy.ENEMY_LAYER - 1) and not e.body_shape.disabled,
		"a reset survives the frame flush"
	)
	# A death and a reset in the same frame: the reset wins after the flush.
	e.apply_damage(1000.0, E.FIRE)
	e.reset()
	await runner_tree.process_frame
	check(
		e.collision_layer == 1 << (Enemy.ENEMY_LAYER - 1) and not e.body_shape.disabled and not e.head_shape.disabled,
		"death + reset in one frame: colliding after the flush"
	)
	w.free()


func test_player_damaged_and_spawn_protection() -> void:
	var w := await _plain_world(Vector3(4000, 0, -3800), false)
	var p := _player(w, Vector3(0, 0, 0))
	var bus := GameEvents.bus()
	var got: Array = []
	var on_hit := func(pl: Player, r: Damage.Result) -> void: got.append([pl, r])
	bus.player_damaged.connect(on_hit)
	var still := PlayerInput.hold([])
	p.tick(still, DT)
	var r := p.take_enemy_hit(3.0, E.EARTH)
	check(
		got.size() == 1 and got[0][0] == p and got[0][1] == r and is_equal_approx(r.amount, 3.0),
		"player_damaged with the hit's result"
	)
	p.take_enemy_hit(1000.0, E.EARTH)
	check(not p.alive() and got.size() == 2, "the lethal hit is announced too")
	check(p.take_enemy_hit(5.0, E.EARTH) == null and got.size() == 2, "hits on the dead: none")
	for i in 180:
		p.tick(still, DT)
	check(p.alive() and p.respawns == 1, "respawned after 3 s")
	check(p.invulnerable() and is_equal_approx(p.protection_left, 1.0), "1 s spawn protection")
	var ignored := p.hits_ignored
	check(
		p.take_enemy_hit(5.0, E.EARTH) == null and p.hits_ignored == ignored + 1 and got.size() == 2,
		"a hit during spawn protection is ignored"
	)
	for i in 59:
		p.tick(still, DT)
	check(p.invulnerable(), "still protected after 59 ticks")
	p.tick(still, DT)
	check(not p.invulnerable() and p.protection_left == 0.0, "protection over after exactly 60 ticks")
	check(p.take_enemy_hit(5.0, E.EARTH) != null and got.size() == 3, "hit again (announced)")
	bus.player_damaged.disconnect(on_hit)
	w.free()


func test_midden_waves_match_toml() -> void:
	var d := LevelToml.load_file(LEVEL_TOML)
	var level: Node3D = (load(LEVEL_SCENE) as PackedScene).instantiate()
	var waves := level.get_node("Waves")
	var tw: Array = d.get("wave", [])
	check(tw.size() == 3 and waves.get_child_count() == 3, "3 waves (%d / %d)" % [tw.size(), waves.get_child_count()])
	var counts: Array = []
	for i in mini(tw.size(), waves.get_child_count()):
		var n := waves.get_child(i)
		var t: Dictionary = tw[i]
		check(
			(
				String(n.name) == t["id"]
				and int(n.get_meta("index")) == i
				and is_equal_approx(float(n.get_meta("delay_s")), float(t["delay_s"]))
			),
			"wave %d id/index/delay" % i
		)
		var groups: Array = n.get_meta("enemies")
		var tg: Array = t["enemies"]
		check(groups.size() == tg.size(), "wave %d groups" % i)
		var c := 0
		for j in mini(groups.size(), tg.size()):
			check(
				(
					groups[j]["enemy"] == tg[j]["enemy"]
					and int(groups[j]["count"]) == int(tg[j]["count"])
					and groups[j]["at"] == tg[j]["at"]
				),
				"wave %d group %d" % [i, j]
			)
			c += int(groups[j]["count"])
		counts.append(c)
	check(counts == [3, 4, 3], "wave sizes 3 / 4 / 3 (%s)" % [counts])
	var wt: Dictionary = d["waves"]
	check(
		(
			(waves.get_meta("trigger_center") as Vector3).is_equal_approx(LevelToml.vec3(wt["trigger_center"]))
			and is_equal_approx(float(waves.get_meta("trigger_radius")), float(wt["trigger_radius"]))
		),
		"trigger centre / radius"
	)
	var pts: Array = d.get("spawn_point", [])
	var ws := level.get_node("WaveSpawns")
	check(pts.size() == 3 and ws.get_child_count() == 3, "3 wave spawn points")
	for sp in pts:
		var m := ws.get_node_or_null(NodePath(String(sp["name"]))) as Marker3D
		check(m != null and m.position.is_equal_approx(LevelToml.vec3(sp["position"])), "spawn point %s" % sp["name"])
	var marks := level.get_node("EnemySpawns").get_children()
	var resp := marks.map(func(m: Node) -> float: return float(m.get_meta("respawn_s", 0.0)))
	check(
		resp == [3.0, 3.0, 0.0, 0.0], "the two dummies respawn after 3 s, the Gnawer and the Heap don't (%s)" % [resp]
	)
	level.free()


func test_spawner_markers_respawn_and_free() -> void:
	var m := await _midden(Vector3(4000, 0, -3000), Vector3(0, 0, 12.5))
	var sp := m["spawner"] as EnemySpawner
	var p := m["player"] as Player
	var level := m["level"] as Node3D
	var got: Array = m["got"]
	check(got.size() == 4 and sp.spawned == 4 and sp.alive_count() == 4 and sp.skipped.is_empty(), "4 marker enemies")
	var g: Gnawer
	var dummy: Enemy
	for e in got:
		if e is Gnawer:
			check(
				(e as Gnawer).target == p and (e as Gnawer).attacked.is_connected(p.on_enemy_attack),
				"%s hunts the player, its attacks hurt him" % e.name
			)
			if not e is Heap:
				g = e
		elif dummy == null:
			dummy = e
	var bus := GameEvents.bus()
	var k0 := bus.kills
	var spawned_events := [0]
	var on_spawn := func(_e: Enemy) -> void: spawned_events[0] += 1
	bus.enemy_spawned.connect(on_spawn)
	# The dummy: back after 3 s.
	var home := (level.get_node("EnemySpawns").get_node(NodePath(String(dummy.name))) as Node3D).global_transform
	dummy.apply_damage(1000.0, E.FIRE)
	check(dummy.dead and bus.kills == k0 + 1 and sp.kills == 1, "dummy killed: one event")
	for i in 179:
		sp.tick(DT)
	check(
		dummy.dead and is_instance_valid(dummy) and not dummy.is_queued_for_deletion(),
		"still dead after 179 ticks, not freed"
	)
	sp.tick(DT)
	check(
		(
			not dummy.dead
			and dummy.health == dummy.max_health()
			and dummy.is_in_group(Enemy.GROUP)
			and dummy.visible
			and sp.respawns == 1
			and spawned_events[0] == 1
		),
		"respawned on tick 180 at full health (%.0f)" % dummy.health
	)
	check(dummy.global_transform.is_equal_approx(home), "back at its marker")
	dummy.apply_damage(1000.0, E.FIRE)
	check(bus.kills == k0 + 2, "it dies again: a second event")
	# The Gnawer: freed after 2 ticks.
	g.apply_damage(1000.0, E.FIRE)
	check(bus.kills == k0 + 3, "Gnawer killed: one event")
	sp.tick(DT)
	check(not g.is_queued_for_deletion() and sp.freed == 0, "not freed on the next tick")
	sp.tick(DT)
	check(g.is_queued_for_deletion() and sp.freed == 1, "freed 2 ticks after its death")
	for i in 5:
		sp.tick(DT)
	check(sp.freed == 1 and bus.kills == k0 + 3, "freed once, no more events")
	check(sp.wave_state == EnemySpawner.WaveState.WAITING, "no waves while the player stays at the start")
	bus.enemy_spawned.disconnect(on_spawn)
	(m["w"] as Node).free()


func test_waves_in_the_midden() -> void:
	# The player stands 3.5 m south of the mound centre: inside the 4 m trigger.
	var m := await _midden(Vector3(4000, 0, -2000), Vector3(0, 0, 2.0))
	var sp := m["spawner"] as EnemySpawner
	var level := m["level"] as Node3D
	var bus := GameEvents.bus()
	var k0 := bus.kills
	var started: Array = []
	var cleared: Array = []
	var completed := [0]
	sp.wave_started.connect(func(i: int, id: String) -> void: started.append([i, id, sp.ticks]))
	sp.wave_cleared.connect(func(i: int, id: String) -> void: cleared.append([i, id, sp.ticks]))
	sp.waves_completed.connect(func() -> void: completed[0] += 1)
	var bus_started := [0]
	var on_bus_start := func(_i: int, _id: String) -> void: bus_started[0] += 1
	bus.wave_started.connect(on_bus_start)
	check(sp.waves.size() == 3 and sp.trigger_radius == 4.0, "3 waves read from the level")
	sp.tick(DT)
	check(sp.wave_state == EnemySpawner.WaveState.DELAY and sp.wave_index == 0, "triggered on the first tick")
	for i in 59:
		sp.tick(DT)
	check(started.is_empty(), "nothing during the 1 s delay")
	sp.tick(DT)
	check(
		started.size() == 1 and started[0][0] == 0 and started[0][1] == "gnawer_pack" and started[0][2] == 61,
		"gnawer_pack after 60 ticks (%s)" % [started]
	)
	var sizes: Array = []
	var ledge := (level.get_node("WaveSpawns/north_ledge") as Node3D).global_position
	sizes.append(sp.wave_alive.size())
	for e in sp.wave_alive:
		check(
			e is Gnawer and not e is Heap and (e as Gnawer).target == sp.player,
			"%s: a Gnawer hunting the player" % e.name
		)
		check(
			absf(_flat(e.global_position, ledge) - EnemySpawner.WAVE_RING) < 0.05, "%s on the 1.5 m ledge ring" % e.name
		)
	_kill_wave(sp)
	sp.tick(DT)
	check(cleared.size() == 1 and cleared[0][1] == "gnawer_pack", "gnawer_pack cleared")
	for i in 179:
		sp.tick(DT)
	check(started.size() == 1, "nothing during the 3 s delay")
	sp.tick(DT)
	check(
		started.size() == 2 and started[1][1] == "flank" and started[1][2] - cleared[0][2] == 180,
		"flank 3 s after the clear (%s)" % [started]
	)
	sizes.append(sp.wave_alive.size())
	var west := (level.get_node("WaveSpawns/west_flank") as Node3D).global_position
	var east := (level.get_node("WaveSpawns/east_flank") as Node3D).global_position
	var near := [0, 0]
	for e in sp.wave_alive:
		if _flat(e.global_position, west) < 1.6:
			near[0] += 1
		elif _flat(e.global_position, east) < 1.6:
			near[1] += 1
	check(near == [2, 2], "2 at the west flank, 2 at the east (%s)" % [near])
	# Half the wave dead: not cleared.
	sp.wave_alive[0].apply_damage(1000.0, E.FIRE)
	sp.wave_alive[0].apply_damage(1000.0, E.FIRE)
	sp.tick(DT)
	check(cleared.size() == 1 and sp.wave_alive.size() == 2, "2 of 4 dead: the wave goes on")
	_kill_wave(sp)
	sp.tick(DT)
	for i in 180:
		sp.tick(DT)
	check(started.size() == 3 and started[2][1] == "heap_push", "heap_push next")
	sizes.append(sp.wave_alive.size())
	var heaps := sp.wave_alive.filter(func(e: Enemy) -> bool: return e is Heap).size()
	check(heaps == 1, "heap_push brings one Heap (%d)" % heaps)
	check(completed[0] == 0, "not completed while the last wave lives")
	_kill_wave(sp)
	for i in 5:
		sp.tick(DT)
	check(
		completed[0] == 1 and sp.wave_state == EnemySpawner.WaveState.DONE and cleared.size() == 3,
		"waves_completed once after the third clear"
	)
	check(
		sizes == [3, 4, 3] and sp.spawned == 14,
		"wave counts 3 / 4 / 3, 14 enemies in all (%s, %d)" % [sizes, sp.spawned]
	)
	check(bus.kills == k0 + 10 and sp.kills == 10, "10 kills, one event each (%d)" % (bus.kills - k0))
	check(
		sp.freed == 10 and sp.alive_count() == 4,
		"every wave enemy freed; the 4 marker enemies remain (%d freed, %d alive)" % [sp.freed, sp.alive_count()]
	)
	check(bus_started[0] == 3, "the bus saw 3 wave starts")
	bus.wave_started.disconnect(on_bus_start)
	(m["w"] as Node).free()


func _kill_wave(sp: EnemySpawner) -> void:
	for e in sp.wave_alive.duplicate():
		e.apply_damage(1000.0, E.FIRE)


## 3 Gnawers lined up behind each other at 5 / 6.2 / 7.4 m: with separation all three get
## around each other and bite within 4 s; without it the back two queue out of reach.
func _pack(at: Vector3, separate: bool) -> Array:
	var w := await _plain_world(at)
	var p := _player(w, Vector3.ZERO)
	var d := EnemyTable.load_default().find("gnawer")
	var gs: Array[Gnawer] = []
	for z in [5.0, 6.2, 7.4]:
		var g := Enemy.create(d, Transform3D(Basis.IDENTITY, Vector3(0, 0, z))) as Gnawer
		g.auto_tick = false
		g.target = p
		g.separation = separate
		g.provoked = true
		w.add_child(g)
		gs.append(g)
	await runner_tree.physics_frame
	var min_gap := 99.0
	var all_at := -1
	var max_y := -99.0
	for t in 240:
		# One tick per physics frame, as in the game: Jolt sees the others' new poses only
		# after a physics step (hand-ticking 240 times in one frame they pass through).
		await runner_tree.physics_frame
		for g in gs:
			g.tick(DT)
		if all_at < 0 and gs.all(func(g: Gnawer) -> bool: return g.bites + g.dodged > 0):
			all_at = t + 1
		for i in gs.size():
			for j in range(i + 1, gs.size()):
				min_gap = minf(min_gap, _flat(gs[i].global_position, gs[j].global_position))
		for g in gs:
			max_y = maxf(max_y, g.position.y)
	var biters := gs.filter(func(g: Gnawer) -> bool: return g.bites + g.dodged > 0).size()
	var seps := 0
	for g in gs:
		seps += g.separations
	var out := [biters, min_gap, seps, p.hits_taken, all_at, max_y]
	print(
		(
			"    pack (separation %s): %d biting, all by tick %d, closest %.2f m, highest feet %.3f m, %d steer ticks, bites %s, ends %s"
			% [
				separate,
				biters,
				all_at,
				min_gap,
				max_y,
				seps,
				gs.map(func(g: Gnawer) -> int: return g.bites),
				gs.map(func(g: Gnawer) -> String: return "(%.2f, %.2f)" % [g.position.x, g.position.z])
			]
		)
	)
	w.free()
	return out


func test_three_gnawers_separate_and_all_bite() -> void:
	var on: Array = await _pack(Vector3(4000, 0, -1000), true)
	check(on[0] == 3, "separation on: all 3 Gnawers bite within 4 s (%d)" % on[0])
	check(on[2] > 0, "the steer did bend paths (%d ticks)" % on[2])
	check(on[1] > 0.8, "they keep apart: closest %.2f m (> 0.8)" % on[1])
	check(on[4] > 0 and on[4] <= 120, "all 3 bit by tick %d (<= 2 s)" % on[4])
	check(on[5] < 0.05, "none climbs onto another (highest feet %.3f m)" % on[5])
	var off: Array = await _pack(Vector3(4000, 0, 0), false)
	check(off[0] < 3, "control, separation off: the back ones queue out of reach (%d biting)" % off[0])
	check(off[5] < 0.05, "and still none rides another's back (step 12 bug fixed: highest feet %.3f m)" % off[5])
