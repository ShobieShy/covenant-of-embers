extends TestCase
## Step 55 done check: the Mire Ooze (ai kind "splitter").
##  - ooze.tres = ooze.toml (Water, 60 HP, splitter);
##  - death splits it into 2 halves (30 HP, gen 1) that do not split again;
##  - a Fire hit leaving it under half health splits it at once;
##  - its puddle slows a target inside it (Player.apply_slow -> slower walk) and expires.

const TOML := "res://data/enemies/ooze.toml"


class Slowable:
	extends Node3D
	var factor := 1.0

	func apply_slow(f: float, _t: float) -> void:
		factor = f

	func eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.5, 0.0)


func _world(at: Vector3) -> Node3D:
	var w := Node3D.new()
	w.position = at
	runner_tree.root.add_child(w)
	return w


func _oozes(w: Node) -> Array:
	var out := []
	for c in w.get_children():
		if c is Ooze and not (c as Ooze).dead:
			out.append(c)
	return out


func _spawn(w: Node3D) -> Ooze:
	var d := EnemyTable.load_default().find("ooze")
	var o := Enemy.create(d, Transform3D.IDENTITY) as Ooze
	o.auto_tick = false
	w.add_child(o)
	return o


func test_tres_matches_toml() -> void:
	var r := EnemyTable.from_toml_files([TOML])
	check(not r.has("error"), "ooze.toml loads (%s)" % r.get("error", ""))
	if r.has("error"):
		return
	var want := (r["table"] as EnemyTable).find("ooze")
	var got := EnemyTable.load_default().find("ooze")
	check(got != null and got.ai == want.ai and got.max_health == want.max_health, "tres = toml")
	check(got.affinity == ElementTable.Element.WATER and got.rusher().kind == "splitter", "Water, splitter")


func test_split_on_death() -> void:
	var w := _world(Vector3(9500, 0, 0))
	var o := _spawn(w)
	o.apply_damage(1000.0, ElementTable.Element.WATER)
	await runner_tree.physics_frame
	var live := _oozes(w)
	check(live.size() == 2, "2 halves (%d)" % live.size())
	var ok := true
	for h: Ooze in live:
		ok = ok and h.generation == 1 and is_equal_approx(h.max_health(), 30.0)
	check(ok, "halves: gen 1, 30 HP")
	if live.size() == 2:
		(live[0] as Ooze).apply_damage(1000.0, ElementTable.Element.WATER)
		await runner_tree.physics_frame
		check(_oozes(w).size() == 1, "a half does not split again")
	w.queue_free()


func test_fire_splits_early() -> void:
	var w := _world(Vector3(9600, 0, 0))
	var o := _spawn(w)
	o.apply_damage(35.0, ElementTable.Element.FIRE)
	var h := SpellBolts.Hit.new()
	h.element = ElementTable.Element.FIRE
	o._on_damaged(o, h)
	await runner_tree.physics_frame
	await runner_tree.physics_frame
	check(o.dead and _oozes(w).size() == 2, "Fire under half health splits it (%d)" % _oozes(w).size())
	w.queue_free()


func test_puddle_slows() -> void:
	var w := _world(Vector3(9700, 0, 0))
	var t := Slowable.new()
	w.add_child(t)
	var p := Ooze.Puddle.new()
	p.auto_tick = false
	p.target = t
	w.add_child(p)
	p.tick(0.1)
	check(is_equal_approx(t.factor, Ooze.PUDDLE_SLOW) and p.slowed_ticks == 1, "inside: slowed")
	t.factor = 1.0
	t.position = Vector3(3, 0, 0)
	p.tick(0.1)
	check(t.factor == 1.0, "outside: not slowed")
	p.tick(Ooze.PUDDLE_TIME)
	check(p.is_queued_for_deletion(), "puddle expires")
	var pl := Player.new()
	pl.apply_slow(0.6, 0.5)
	check(is_equal_approx(pl.current_slow(), 0.6), "player slow applies")
	pl.slow_left = 0.0
	check(pl.current_slow() == 1.0, "and wears off")
	pl.free()
	w.queue_free()
