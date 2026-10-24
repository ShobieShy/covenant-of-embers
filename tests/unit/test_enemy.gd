extends TestCase
## Step 11 done check (port of the archived test_enemy.cpp + test_damage_numbers.cpp, old
## step 22): enemy entity, training dummies, damage numbers.
##  - LevelToml reads single-line inline tables (data/enemies/*.toml resist / weak_point);
##  - resources/enemies/training_dummies.tres = data/enemies/training_dummies.toml (read
##    with LevelToml + EnemyDef.from_toml), and so does gnawer.tres (step 12); bad defs
##    rejected with the C++ loader's errors;
##  - the Apprentice Fire Staff, cast by a Player, hits the Earth dummy for 15 per hit
##    (x1.5) and kills it at exactly 0 HP on the 4th hit (died once, no overkill counted);
##    the 5th bolt flies through to the wall behind;
##  - Fire 10 vs Water dummy = 5 (x0.5); Air 10 vs Water dummy (resist air 0.25) = 11.25;
##    the Swift Wind Wand (7.5) vs the Water dummy = 7.5 x 1.5 x 0.75 = 8.4375; a head hit
##    is x2 (Fire 10 on Earth = 30); 1000 Arcane = overkill to 0 (60 taken);
##  - bolts graze an enemy with the 0.1 m sphere (0.05 m beside: hit at its surface;
##    0.15 m beside or graze 0: miss), but never through a wall;
##  - damage numbers: format, element colour, crit/strong/weak scale, ease-out rise, fade,
##    lifetime, 64 cap, Magewar's "Super Effective!" / "Not Very Effective..." callouts,
##    one per resolved bolt hit;
##  - the Midden's EnemySpawns markers spawn the two dummies and (step 12) the Gnawer.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LEVEL_SCENE := "res://scenes/levels/midden.tscn"
const DUMMIES_TOML := "res://data/enemies/training_dummies.toml"
const GNAWER_TOML := "res://data/enemies/gnawer.toml"
const HEAP_TOML := "res://data/enemies/heap.toml"
const E := ElementTable.Element
const EPS := 1e-4

func _world(at: Vector3) -> Node3D:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	w.global_position = at
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

func _bolts(parent: Node3D) -> SpellBolts:
	var b := SpellBolts.new()
	b.auto_tick = false
	parent.add_child(b)
	return b

func _dummy(parent: Node3D, id: String, feet_local: Vector3) -> Enemy:
	var d := EnemyTable.load_default().find(id)
	check(d != null, "%s in the enemy table" % id)
	var e := Enemy.create(d, Transform3D(Basis.IDENTITY, feet_local))   # posed before add_child (Jolt)
	parent.add_child(e)
	return e

## One bolt from `origin` (world-local to w) along `dir`; returns the hits over 30 ticks.
func _shoot(w: Node3D, bolts: SpellBolts, origin: Vector3, dir: Vector3, element: E, damage: float, graze := SpellBolts.GRAZE_RADIUS) -> Array[SpellBolts.Hit]:
	var s := SpellBolts.Spawn.new()
	s.origin = w.global_position + origin
	s.direction = dir
	s.speed = 60.0
	s.range_m = 40.0
	s.element = element
	s.damage = damage
	s.graze_radius = graze
	bolts.spawn(s)
	var out: Array[SpellBolts.Hit] = []
	for i in 30:
		out.append_array(bolts.tick(DT))
	return out

func test_toml_inline_tables() -> void:
	var d := LevelToml.parse("[[enemy]]\nid = \"x\"\nresist = { air = 0.25, fire = 1 } # c\nwp = { offset = [0.0, 1.78, 0.0], size = [0.36, 0.36, 0.36], tag = \"a,b}\" }\nempty = {}\nnest = { a = { b = [1, [2, 3]] } }\n")
	check(not d.has("error"), "inline tables parse (%s)" % d.get("error", ""))
	if d.has("error"):
		return
	var row: Dictionary = d["enemy"][0]
	check(row["resist"] is Dictionary and is_equal_approx(float(row["resist"]["air"]), 0.25) and is_equal_approx(float(row["resist"]["fire"]), 1.0), "resist = { air = 0.25, fire = 1 }")
	check(LevelToml.vec3(row["wp"]["offset"]) == Vector3(0, 1.78, 0) and LevelToml.vec3(row["wp"]["size"]) == Vector3(0.36, 0.36, 0.36), "arrays inside an inline table")
	check(row["wp"]["tag"] == "a,b}", "commas/braces inside strings")
	check(row["empty"] is Dictionary and (row["empty"] as Dictionary).is_empty(), "empty inline table")
	check(float(row["nest"]["a"]["b"][1][1]) == 3.0, "nested tables and arrays")
	check(LevelToml.vec3(LevelToml.parse("v = [1, 2, 3,]")["v"]) == Vector3(1, 2, 3), "trailing comma in an array")
	for bad in ["t = { a = 1, a = 2 }", "t = { a = 1\nb = 2 }", "t = { a 1 }", "t = { a = [1, 2 }", "t = { = 1 }", "t = { a = lava }"]:
		check(LevelToml.parse(bad).has("error"), "rejected: %s" % bad.c_escape())
	# The old reader's behaviour is kept.
	check(LevelToml.parse("x = [1,\n2]").has("error"), "multi-line arrays still rejected")

func test_tres_matches_toml() -> void:
	var table := EnemyTable.load_default()
	check(table.validate().is_empty(), "shipped table valid: %s" % [table.validate()])
	var r := EnemyTable.from_toml_files([DUMMIES_TOML, GNAWER_TOML, HEAP_TOML, "res://data/enemies/breach_warden.toml"])
	check(not r.has("error"), "training_dummies.toml + gnawer.toml + heap.toml load (%s)" % r.get("error", ""))
	if r.has("error"):
		return
	var toml: EnemyTable = r["table"]
	check(toml.defs.size() == 5 and table.defs.size() == 5, "two dummies + Gnawer + Heap + Breach Warden (step 34) (%d toml, %d tres)" % [toml.defs.size(), table.defs.size()])
	for want in toml.defs:
		var got := table.find(want.id)
		check(got != null, "%s in the .tres" % want.id)
		if got == null:
			continue
		check(got.display_name == want.display_name, "%s name" % want.id)
		check(got.affinity == want.affinity, "%s affinity" % want.id)
		check(is_equal_approx(got.max_health, want.max_health), "%s max_health" % want.id)
		check(got.level == want.level, "%s level %d vs %d" % [want.id, got.level, want.level])
		check(got.size.is_equal_approx(want.size), "%s size" % want.id)
		check(got.color.is_equal_approx(want.color), "%s color" % want.id)
		check(got.resist == want.resist, "%s resist %s vs %s" % [want.id, got.resist, want.resist])
		check(got.has_weak_point == want.has_weak_point and got.weak_point_offset.is_equal_approx(want.weak_point_offset)
			and got.weak_point_size.is_equal_approx(want.weak_point_size), "%s weak point" % want.id)
		check(got.ai == want.ai, "%s ai %s vs %s" % [want.id, got.ai, want.ai])
	var water := table.find("water_training_dummy")
	check(water != null and water.affinity == E.WATER and is_equal_approx(water.resist_of(E.AIR), 0.25) and water.max_health == 60.0, "Tidal dummy: Water, 60 HP, resist air 0.25")
	var g := EnemyTable.from_toml_files([GNAWER_TOML])
	check(not g.has("error") and (g["table"] as EnemyTable).find("gnawer") != null, "gnawer.toml parses for step 12 (%s)" % g.get("error", ""))
	if not g.has("error"):
		var gn := (g["table"] as EnemyTable).find("gnawer")
		check(gn.affinity == E.EARTH and gn.max_health == 30.0 and not gn.ai.is_empty(), "Gnawer: Earth, 30 HP, ai table kept")

func test_bad_defs_rejected() -> void:
	var ok := "id = \"d\"\nname = \"D\"\naffinity = \"earth\"\nmax_health = 60\nsize = [0.7, 1.6, 0.7]\ncolor = [0.5, 0.5, 0.5]\n"
	check(not EnemyTable.from_toml(LevelToml.parse("[[enemy]]\n" + ok)).has("error"), "a minimal def loads")
	var cases := {
		"unknown affinity": "[[enemy]]\n" + ok.replace("\"earth\"", "\"lava\""),
		"duplicate id": "[[enemy]]\n" + ok + "[[enemy]]\n" + ok,
		"resist out of range": "[[enemy]]\n" + ok + "resist = { fire = 1.5 }\n",
		"unknown resist element": "[[enemy]]\n" + ok + "resist = { lava = 0.5 }\n",
		"weak point without size": "[[enemy]]\n" + ok + "weak_point = { offset = [0, 1, 0] }\n",
		"id not lower_snake_case": "[[enemy]]\n" + ok.replace("\"d\"", "\"Bad Id\""),
		"unknown key": "[[enemy]]\n" + ok + "hp = 5\n",
		"missing key": "[[enemy]]\n" + ok.replace("max_health = 60\n", ""),
		"health out of range": "[[enemy]]\n" + ok.replace("max_health = 60", "max_health = 0"),
		"empty file": "",
	}
	for k in cases:
		var r := EnemyTable.from_toml(LevelToml.parse(cases[k]))
		check(r.has("error"), "rejected: %s" % k)
		if r.has("error"):
			print("    %s -> %s" % [k, r["error"]])

func test_fire_staff_kills_earth_dummy() -> void:
	var w := _world(Vector3(-900, 0, 900))
	_box(w, Vector3(0, -0.5, 0), Vector3(30, 0.5, 30))
	_box(w, Vector3(0, 1.5, -10.5), Vector3(4, 1.5, 0.5))   # wall behind the dummy
	var dummy := _dummy(w, "earth_training_dummy", Vector3(0, 0, -5))
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	p.position = Vector3.ZERO
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	var bolts := _bolts(w)
	p.bolts = bolts
	p.caster.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	var numbers := DamageNumbers.new()
	numbers.auto_tick = false
	w.add_child(numbers)
	numbers.connect_bolts(bolts)
	var deaths: Array = []
	dummy.died.connect(func(e: Enemy, el: ElementTable.Element) -> void: deaths.append([e, el]))
	# Aim at the body's middle (0.8 m up, 4.65 m to its front face): clear of the head
	# whatever the hip spread does.
	p.set_look(0.0, -atan2(1.5 - 0.8, 4.65))
	var a := p.aim()
	check(a.direction.y < 0.0, "looking down at the body (%s)" % a.direction)
	var hs: Array[SpellBolts.Hit] = []
	for k in 5:
		p.tick(PlayerInput.hold(["action_primary"], ["action_primary"]), DT)
		hs.append_array(bolts.tick(DT))
		for i in 35:   # 0.6 s > the staff's 0.40 s cooldown
			p.tick(PlayerInput.hold([]), DT)
			hs.append_array(bolts.tick(DT))
	check(p.caster.casts == 5, "5 casts (%d)" % p.caster.casts)
	var on_dummy := hs.filter(func(h: SpellBolts.Hit) -> bool: return h.collider == dummy)
	print("    fire staff: %s; dummy %.2f/%.0f HP, %d hit(s), %.2f taken" % [
		hs.map(func(h: SpellBolts.Hit) -> String: return "%s %s" % [h.collider.name, DamageNumbers.format(h.result.amount) if h.result else "-"]),
		dummy.health, dummy.max_health(), dummy.hits, dummy.damage_taken])
	check(on_dummy.size() == 4, "4 bolts hit the dummy (%d)" % on_dummy.size())
	for h in on_dummy:
		check(h.result != null and is_equal_approx(h.result.amount, 15.0) and h.result.strong() and h.result.crit == 1.0,
			"Fire 10 vs Earth dummy = 15 per hit (%s)" % (h.result.amount if h.result else -1.0))
	check(dummy.health == 0.0 and dummy.dead and not dummy.alive(), "dies at exactly 0 HP (%.3f)" % dummy.health)
	check(is_equal_approx(dummy.damage_taken, 60.0) and dummy.hits == 4, "60 taken in 4 hits")
	check(deaths.size() == 1 and deaths[0][1] == E.FIRE, "died once, by Fire")
	check(hs.size() == 5 and not (hs[4].collider is Enemy) and absf(hs[4].distance - 10.0) < 0.2,
		"5th bolt flies through the dead dummy to the wall (%s)" % [hs.map(func(h: SpellBolts.Hit) -> String: return "%s %.2f" % [h.collider.name, h.distance])])
	check(not dummy.visible and not dummy.is_in_group(Enemy.GROUP), "dead dummy hidden, out of 'enemies'")
	check(numbers.spawned == 4 and numbers.numbers.all(func(n: DamageNumbers.Number) -> bool: return DamageNumbers.format(n.amount) == "15"),
		"one damage number \"15\" per hit (%d)" % numbers.spawned)
	w.free()

func test_effectiveness_resist_head_and_overkill() -> void:
	var w := _world(Vector3(-900, 0, -900))
	_box(w, Vector3(0, -0.5, 0), Vector3(30, 0.5, 30))
	var water := _dummy(w, "water_training_dummy", Vector3(0, 0, -5))
	var earth := _dummy(w, "earth_training_dummy", Vector3(4, 0, -5))
	var bolts := _bolts(w)
	var eye := Vector3(0, 1.0, 0)
	var hs := _shoot(w, bolts, eye, Vector3.FORWARD, E.FIRE, 10.0)
	check(hs.size() == 1 and hs[0].collider == water and hs[0].result != null, "Fire bolt hits the Water dummy")
	if hs.size() == 1 and hs[0].result:
		check(is_equal_approx(hs[0].result.amount, 5.0) and hs[0].result.weak(), "Fire 10 vs Water dummy = 5 (%f)" % hs[0].result.amount)
		check_near(hs[0].point.z - w.global_position.z, -5.0 + 0.35, 1e-3, "hit on the front face")
	hs = _shoot(w, bolts, eye, Vector3.FORWARD, E.AIR, 10.0)
	if check_one(hs, water, "Air bolt"):
		check_near(hs[0].result.amount, 11.25, EPS, "Air 10 vs Water dummy (x1.5, resist 0.25)")
		check(is_equal_approx(hs[0].result.resist, 0.25) and hs[0].result.strong(), "resist 0.25 applied, Super Effective")
	var swift := WieldableInstance.load_base("swift_wind_wand")
	check(swift.element() == E.AIR and is_equal_approx(swift.damage(), 7.5), "Swift Wind Wand: Air 7.5")
	hs = _shoot(w, bolts, eye, Vector3.FORWARD, swift.element(), swift.damage())
	if check_one(hs, water, "Swift Wind bolt"):
		check_near(hs[0].result.amount, 8.4375, EPS, "Swift Wind vs Water dummy = 7.5 x 1.5 x 0.75")
	check_near(water.health, 60.0 - 5.0 - 11.25 - 8.4375, EPS, "water dummy health")
	# Head: the weak-point box centred 1.78 m up.
	hs = _shoot(w, bolts, Vector3(4, 1.78, 0), Vector3.FORWARD, E.FIRE, 10.0)
	if check_one(hs, earth, "head shot"):
		check(hs[0].shape >= 0 and earth.is_weak_point_shape(hs[0].shape) and not hs[0].grazed, "struck the Head shape")
		check(is_equal_approx(hs[0].result.amount, 30.0) and hs[0].result.crit == Damage.WEAK_POINT_MULTIPLIER, "head hit x2: Fire 10 on Earth = 30 (%f)" % hs[0].result.amount)
		check(earth.last_weak_point, "enemy saw a weak-point hit")
	hs = _shoot(w, bolts, Vector3(4, 0.8, 0), Vector3.FORWARD, E.FIRE, 10.0)
	if check_one(hs, earth, "body shot"):
		check(is_equal_approx(hs[0].result.amount, 15.0) and not earth.damage_target.weak_point, "body shot = 15 (weak point reset)")
	# Overkill.
	hs = _shoot(w, bolts, eye, Vector3.FORWARD, E.ARCANE, 1000.0)
	if check_one(hs, water, "1000 Arcane"):
		check(water.health == 0.0 and water.dead, "overkill clamps at 0")
		check_near(water.damage_taken, 60.0, EPS, "damage_taken excludes overkill")
	check(water.flash > 0.0, "hit flash")
	water.tick(Enemy.FLASH_TIME)
	check(water.flash == 0.0, "flash ends after %.2f s" % Enemy.FLASH_TIME)
	w.free()

func check_one(hs: Array[SpellBolts.Hit], who: Enemy, what: String) -> bool:
	var good := hs.size() == 1 and hs[0].collider == who and hs[0].result != null
	check(good, "%s hits %s once (%s)" % [what, who.name, hs.map(func(h: SpellBolts.Hit) -> String: return str(h.collider))])
	return good

func test_bolts_graze_enemies() -> void:
	var w := _world(Vector3(0, 0, -1800))
	var dummy := _dummy(w, "earth_training_dummy", Vector3(0, 0, -5))
	var bolts := _bolts(w)
	# Body half-width 0.35: a ray 0.05 m beside it grazes with the 0.1 m sphere.
	var hs := _shoot(w, bolts, Vector3(0.40, 0.8, 0), Vector3.FORWARD, E.FIRE, 10.0)
	if check_one(hs, dummy, "0.05 m graze"):
		check(hs[0].grazed, "flagged as a graze")
		check_near(hs[0].point.x - w.global_position.x, 0.35, 0.02, "graze point on the body's side")
		check(is_equal_approx(hs[0].result.amount, 15.0), "graze resolves like a hit")
	check(_shoot(w, bolts, Vector3(0.40, 0.8, 0), Vector3.FORWARD, E.FIRE, 10.0, 0.0).is_empty(), "graze radius 0: miss")
	check(_shoot(w, bolts, Vector3(0.50, 0.8, 0), Vector3.FORWARD, E.FIRE, 10.0).is_empty(), "0.15 m beside: miss")
	hs = _shoot(w, bolts, Vector3(0, 0.8, 0), Vector3.FORWARD, E.FIRE, 10.0)
	check(hs.size() == 1 and not hs[0].grazed, "a direct hit is a ray hit")
	# A wall in front of the dummy blocks a graze.
	_box(w, Vector3(0.0, 1.0, -2.0), Vector3(0.3, 1.0, 0.05))
	hs = _shoot(w, bolts, Vector3(0.25, 0.8, 0), Vector3.FORWARD, E.FIRE, 10.0)
	check(hs.size() == 1 and not (hs[0].collider is Enemy), "never grazes through a wall (%s)" % [hs.map(func(h: SpellBolts.Hit) -> String: return str(h.collider))])
	w.free()

func test_damage_numbers() -> void:
	for pair in [[15.0, "15"], [11.25, "11.3"], [7.5, "7.5"], [4.999, "5"], [0.0, "0"], [-3.0, "0"], [8.4375, "8.4"]]:
		check(DamageNumbers.format(pair[0]) == pair[1], "format(%s) = %s (got %s)" % [pair[0], pair[1], DamageNumbers.format(pair[0])])
	var dn := DamageNumbers.new()
	dn.auto_tick = false
	dn.draw_labels = false
	var t := ElementTable.load_default()
	var target := Damage.Target.new(E.EARTH)
	var strong := Damage.resolve_hit(10.0, E.FIRE, target)
	var weak := Damage.resolve_hit(10.0, E.AIR, target)
	var plain := Damage.resolve_hit(10.0, E.ARCANE, target)
	target.weak_point = true
	var crit := Damage.resolve_hit(10.0, E.FIRE, target)
	var n0 := dn.add(Vector3(1, 2, 3), strong, E.FIRE)
	var n1 := dn.add(Vector3.ZERO, weak, E.AIR)
	var n2 := dn.add(Vector3.ZERO, plain, E.ARCANE)
	var n3 := dn.add(Vector3.ZERO, crit, E.FIRE)
	check(n0.color == t.color(E.FIRE) and n1.color == t.color(E.AIR), "element colours")
	check(n0.scale == DamageNumbers.STRONG_SCALE and n1.scale == DamageNumbers.WEAK_SCALE and n2.scale == 1.0 and n3.scale == DamageNumbers.CRIT_SCALE, "strong / weak / plain / crit scales")
	check(n0.callout == "Super Effective!" and n0.callout_color == Color(1, 0.8, 0) and n1.callout == "Not Very Effective..."
		and n1.callout_color == Color(0.5, 0.5, 0.5) and n2.callout == "" and n3.callout == "Super Effective!", "Magewar's effectiveness callouts + colours")
	check(n0.drift_x != n1.drift_x and n1.drift_x != n2.drift_x, "stacked numbers drift apart")
	check(DamageNumbers.position_of(n0) == Vector3(1, 2, 3) and DamageNumbers.alpha_of(n0) == 1.0, "starts at the impact, opaque")
	dn.tick(0.5)
	var rise := DamageNumbers.position_of(n0).y - 2.0
	check_near(rise, DamageNumbers.RISE * 0.75, EPS, "ease-out rise at half life")
	check(DamageNumbers.alpha_of(n0) == 1.0, "opaque until %.1f" % DamageNumbers.FADE_START)
	dn.tick(0.3)
	check_near(DamageNumbers.alpha_of(n0), 0.5, EPS, "half faded at 0.8 s")
	dn.tick(0.25)
	check(dn.numbers.is_empty(), "gone after %.1f s" % DamageNumbers.LIFETIME)
	for i in 70:
		dn.add(Vector3(i, 0, 0), plain, E.ARCANE)
	check(dn.numbers.size() == DamageNumbers.MAX and dn.numbers[0].world.x == 6.0, "capped at 64, oldest dropped")
	dn.free()
	# Labels: a Label3D per number in the element colour, freed when it expires.
	var w := _world(Vector3(1800, 0, 0))
	var dl := DamageNumbers.new()
	dl.auto_tick = false
	w.add_child(dl)
	var n := dl.add(w.global_position + Vector3(0, 1, 0), crit, E.FIRE)
	check(n.label != null and n.label.text == "30" and n.label.modulate.is_equal_approx(t.color(E.FIRE)) and n.label.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Label3D \"30\" in Fire's colour, billboarded")
	check(n.callout_label != null and n.callout_label.text == "Super Effective!" and n.callout_label.get_parent() == n.label, "callout label under the number")
	dl.tick(0.5)
	check(n.label.global_position.is_equal_approx(DamageNumbers.position_of(n)), "label follows the number")
	dl.tick(0.6)
	check(dl.numbers.is_empty() and n.label == null, "label dropped")
	w.free()

func test_midden_markers_spawn_dummies() -> void:
	var w := _world(Vector3(1800, 0, 1800))
	var level: Node3D = (load(LEVEL_SCENE) as PackedScene).instantiate()
	w.add_child(level)
	var parent := Node3D.new()
	w.add_child(parent)
	var skipped: Array = []
	var got := Enemy.spawn_at_markers(level, parent, EnemyTable.load_default(), skipped)
	check(got.size() == 4 and skipped.is_empty(), "2 dummies + the Gnawer + the Heap spawned, none skipped (steps 12/13) (%d, %s)" % [got.size(), skipped])
	var kinds := got.map(func(e: Enemy) -> String: return "heap" if e is Heap else ("gnawer" if e is Gnawer else "dummy"))
	check(kinds.count("gnawer") == 1 and kinds.count("heap") == 1 and kinds.count("dummy") == 2, "the rusher spawns as a Gnawer, the tank as a Heap, the dummies as plain Enemies (%s)" % [kinds])
	var markers := level.get_node("EnemySpawns")
	for e in got:
		var m := markers.get_node(NodePath(String(e.name))) as Node3D
		check(m != null and e.global_transform.is_equal_approx(m.global_transform), "%s at its marker" % e.name)
		check(e.collision_layer == 1 << (Enemy.ENEMY_LAYER - 1) and e.is_in_group(Enemy.GROUP) and e.health == e.def.max_health and e.health == (150.0 if e is Heap else (30.0 if e is Gnawer else 60.0)), "%s: enemy layer, in 'enemies', full HP (60; Gnawer 30; Heap 150)" % e.name)
		check(e.head_shape != null and e.body_shape.position.y == e.def.size.y * 0.5, "%s stands on its feet with a head" % e.name)
	check(ProjectSettings.get_setting("layer_names/3d_physics/layer_3") == "enemy", "physics layer 3 is named enemy")
	w.free()
