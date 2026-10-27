extends TestCase
## Steps 56-57 done check: The Filth (three-phase Landfill boss) and Joe's Trash.
##  - the_filth.tres = data/enemies/the_filth.toml; ai kind "filth" spawns a Filth (a boss);
##  - phases at 66 % / 33 % (phase_changed 2 then 3, once each); phase 2 regenerates after
##    REGEN_DELAY with no hits, never above the phase-2 ceiling; phase 3 exposes the core;
##  - balance (Q8): each phase is 20-35 s of the starter staff at a realistic hit rate;
##  - acid blobs land as attacks; death drops Joe's Trash, which a player collects
##    (quest_items + EventBus.quest_item_collected).

const TOML := "res://data/enemies/the_filth.toml"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const E := ElementTable.Element
const STAFF_BOLT := 15.0  ## Apprentice Fire Staff bolt (heap.toml: 150 HP = ten bolts)
const REAL_BOLTS_PER_S := 0.75  ## a realistic hit rate while dodging slams and blobs


func _world(z: float) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(0, 700, z)
	runner_tree.root.add_child(w)
	return w


func _spawn(w: Node3D) -> Filth:
	var e := Enemy.create(EnemyTable.load_default().find("the_filth"), Transform3D.IDENTITY)
	e.auto_tick = false
	w.add_child(e)
	return e as Filth


func test_tres_matches_toml() -> void:
	var r := EnemyTable.from_toml_files([TOML])
	check(not r.has("error"), "toml loads (%s)" % r.get("error", ""))
	if r.has("error"):
		return
	var want := (r["table"] as EnemyTable).find("the_filth")
	var got := EnemyTable.load_default().find("the_filth")
	check(got != null, "shipped")
	if got == null:
		return
	for k in [
		"display_name",
		"affinity",
		"max_health",
		"level",
		"xp_reward",
		"size",
		"color",
		"weak_point_offset",
		"weak_point_size",
		"ai"
	]:
		check(
			got.get(k) == want.get(k) if k == "ai" else str(got.get(k)) == str(want.get(k)),
			"%s: %s vs %s" % [k, got.get(k), want.get(k)]
		)


func test_phases_and_balance() -> void:
	var w := _world(3000)
	var f := _spawn(w)
	check(f != null and f.is_boss(), "filth kind spawns a Filth boss")
	if f == null:
		w.free()
		return
	var per_phase := f.max_health() / 3.0
	var secs := per_phase / (STAFF_BOLT * REAL_BOLTS_PER_S)
	check(secs >= 20.0 and secs <= 35.0, "a phase is 20-35 s of the starter staff (%.1f s)" % secs)
	var seen: Array = []
	f.phase_changed.connect(func(_x, p): seen.append(p))
	f.apply_damage(f.max_health() * 0.30, E.FIRE)
	check(f.phase == 1, "phase 1 at 70 %")
	f.apply_damage(f.max_health() * 0.05, E.FIRE)
	check(f.phase == 2 and seen == [2], "phase 2 below 66 %% (%s)" % [seen])
	var before := f.health
	for i in 60:  # 1 s: no regen yet
		f.think(1.0 / 60.0)
	check(is_equal_approx(f.health, before), "no regen right after a hit")
	for i in 600:
		f.think(1.0 / 60.0)
	check(
		f.health > before and f.health <= f.max_health() * Filth.PHASE_2_AT + 0.01,
		"phase 2 regenerates up to its ceiling (%.1f)" % f.health
	)
	check(f.phase == 2, "regen never returns it to phase 1")
	var size0 := (f.head_shape.shape as BoxShape3D).size
	f.apply_damage(f.health - f.max_health() * 0.30, E.FIRE)
	check(f.phase == 3 and seen == [2, 3] and f.core_exposed(), "phase 3 below 33 %% (%s)" % [seen])
	check((f.head_shape.shape as BoxShape3D).size.x > size0.x, "core exposed: bigger weak point")
	var h3 := f.health
	for i in 600:
		f.think(1.0 / 60.0)
	check(f.health <= h3, "no regen in phase 3")
	f.reset()
	check(f.phase == 1 and is_equal_approx(f.health, f.max_health()), "reset -> phase 1, full")
	w.free()


func test_trash_drop_and_collect() -> void:
	var w := _world(3300)
	var f := _spawn(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	w.add_child(p)
	p.global_position = f.global_position + Vector3(8, 0, 0)
	var got: Array = []
	var cb := func(_pl, id): got.append(id)
	GameEvents.bus().quest_item_collected.connect(cb)
	f.apply_damage(5000.0, E.FIRE)
	check(f.dead and f.trash != null, "death drops Joe's Trash")
	await runner_tree.process_frame
	var t := f.trash
	check(t.is_inside_tree() and t.item_id == "joes_discards", "on the ground, quest id")
	t.auto_tick = false
	t.tick()
	check(got.is_empty(), "not collected from 8 m")
	p.global_position = t.global_position + Vector3(0.5, 0, 0)
	t.tick()
	check(got == ["joes_discards"] and p.quest_items.has("joes_discards"), "collected (%s)" % [got])
	GameEvents.bus().quest_item_collected.disconnect(cb)
	w.free()


func test_blob_lands() -> void:
	var w := _world(3600)
	var f := _spawn(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	w.add_child(p)
	p.global_position = f.global_position + Vector3(0, 0, -6)
	f.target = p
	f.fire_blob()
	check(f.blobs.size() == 1 and is_equal_approx(f.blob_timer, f.blob_cooldown()), "blob out")
	for i in 120:
		f._tick_blobs(1.0 / 60.0)
	check(f.blobs_landed == 1 and f.blobs.is_empty(), "blob lands (%d)" % f.blobs_landed)
	w.free()


func test_checkpoint() -> void:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.spawn_feet = Vector3(0, 0, 12)
	check(
		not Filth.checkpoint(p, "flank", Vector3(1, 0, 1)) and p.spawn_feet == Vector3(0, 0, 12),
		"other waves: no checkpoint"
	)
	check(
		(
			Filth.checkpoint(p, "the_filth", Vector3(5, 0, -1.5))
			and p.spawn_feet == Vector3(5, 0, -1.5)
		),
		"boss wave: respawn at the boss door"
	)
	p.free()


## Arena lock: The Filth's wave raises a ring of walls around the trigger; other waves don't;
## the walls block a ray out of the arena and drop when the waves are done.
func test_arena_walls() -> void:
	var w := _world(2400)
	var sp := EnemySpawner.new()
	sp.process_mode = Node.PROCESS_MODE_DISABLED
	w.add_child(sp)
	sp.trigger_center = w.global_position
	sp.trigger_radius = 8.0
	var lock := ArenaLock.attach(sp, Filth.WAVE_ID)
	lock.process_mode = Node.PROCESS_MODE_ALWAYS  # the bare spawner is disabled; its walls must not be
	sp.wave_started.emit(0, "midden_trash")
	check(not lock.raised(), "other waves: no walls")
	sp.wave_started.emit(1, Filth.WAVE_ID)
	check(
		lock.get_child_count() == ArenaLock.SEGMENTS, "boss wave: %d walls" % lock.get_child_count()
	)
	await runner_tree.physics_frame
	await runner_tree.physics_frame
	var c := w.global_position + Vector3(0, 1, 0)
	var q := PhysicsRayQueryParameters3D.create(c, c + Vector3(20, 0, 0), 1)
	var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
	check(
		not hit.is_empty() and absf((hit["position"] - c).length() - 9.5) < 0.6,
		"a ray out hits the wall (%s)" % [hit.get("position")]
	)
	sp.waves_completed.emit()
	check(not lock.raised(), "walls drop when the waves are done")
	sp.wave_started.emit(1, Filth.WAVE_ID)  # again, now with a boss that spawns after the walls
	check(lock.raised(), "walls up again")
	var boss := Enemy.create(EnemyTable.load_default().find("the_filth"), Transform3D.IDENTITY)
	boss.auto_tick = false
	sp.add_child(boss)
	boss.died.emit(boss, ElementTable.Element.FIRE)
	await runner_tree.process_frame
	check(not lock.raised(), "walls drop when the Filth dies, even with wave enemies left")
	w.free()
