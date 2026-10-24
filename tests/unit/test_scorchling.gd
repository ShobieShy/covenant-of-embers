extends TestCase
## Step 54 done check: the Ember Scorchling (ai kind "ranged").
##  - scorchling.tres = scorchling.toml (Fire, 40 HP, range 7, ranged def parses);
##  - it closes from 9 m to about its range and stops (keeps range, never melee);
##  - its embers fly to the target and land as 4.5 Fire bites; dodged in i-frames;
##  - inside min_range (3 m) it backs off; under 30 % health it flees past detect range.

const DT := 1.0 / 60.0
const TOML := "res://data/enemies/scorchling.toml"


class Dummy:
	extends Node3D
	var inv := false
	var hits := 0.0

	func invulnerable() -> bool:
		return inv

	func eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.5, 0.0)

	func on_attack(_g: Gnawer, b: Gnawer.Bite) -> void:
		if not b.dodged:
			hits += b.damage


func _world(at: Vector3) -> Node3D:
	var w := Node3D.new()
	w.position = at
	runner_tree.root.add_child(w)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(80, 0.2, 80)
	cs.shape = s
	b.add_child(cs)
	b.position = Vector3(0, -0.1, 0)
	w.add_child(b)
	return w


func _setup(at: Vector3, gap: float) -> Array:
	var w := _world(at)
	var t := Dummy.new()
	w.add_child(t)
	var d := EnemyTable.load_default().find("scorchling")
	var e := Enemy.create(d, Transform3D(Basis.IDENTITY, Vector3(0, 0, -gap))) as Scorchling
	e.auto_tick = false
	w.add_child(e)
	e.target = t
	e.attacked.connect(t.on_attack)
	await runner_tree.physics_frame
	await runner_tree.physics_frame
	return [w, t, e]


func _run(e: Scorchling, n: int) -> void:
	for i in n:
		e.tick(DT)
		await runner_tree.physics_frame


func test_tres_matches_toml() -> void:
	var r := EnemyTable.from_toml_files([TOML])
	check(not r.has("error"), "scorchling.toml loads (%s)" % r.get("error", ""))
	if r.has("error"):
		return
	var want := (r["table"] as EnemyTable).find("scorchling")
	var got := EnemyTable.load_default().find("scorchling")
	check(got != null and got.ai == want.ai and got.max_health == want.max_health, "tres = toml")
	check(got.affinity == ElementTable.Element.FIRE and got.rusher().kind == "ranged", "Fire, ranged")


func test_keeps_range_and_shoots() -> void:
	var s: Array = await _setup(Vector3(9000, 0, 0), 8.5)
	var t: Dummy = s[1]
	var e: Scorchling = s[2]
	await _run(e, 240)
	var d := Gnawer._flat(e.global_position - t.global_position).length()
	check(d > 4.0 and d < 7.5, "keeps range (%.2f m)" % d)
	check(
		e.shots >= 2 and t.hits >= 4.5 and is_equal_approx(fmod(t.hits, 4.5), 0.0),
		"embers hit (%d shots, %.1f)" % [e.shots, t.hits]
	)
	t.inv = true
	var before := t.hits
	await _run(e, 120)
	check(t.hits == before and e.dodged > 0, "embers dodged in i-frames")
	(s[0] as Node).free()


func test_backs_off_and_flees() -> void:
	var s: Array = await _setup(Vector3(9100, 0, 0), 1.6)
	var t: Dummy = s[1]
	var e: Scorchling = s[2]
	await _run(e, 60)
	var d := Gnawer._flat(e.global_position - t.global_position).length()
	check(d > 2.0, "backs off from close range (%.2f m)" % d)
	e.health = e.def.max_health * 0.2
	await _run(e, 180)
	d = Gnawer._flat(e.global_position - t.global_position).length()
	check(e.flee_ticks > 0 and d >= 8.5, "flees under 30 %% (%.2f m)" % d)
	var shots := e.shots
	await _run(e, 60)
	check(e.shots == shots or d >= 9.0, "no shots while fleeing")
	(s[0] as Node).free()
