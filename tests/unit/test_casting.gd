extends TestCase
## Step 7 done check (port of the archived test_casting.cpp, old step 17): wieldable data,
## spell bolts and casting.
##  - resources/wieldables/*.tres = Magewar's four bases (the assets/magewar .tres copies
##    and data/magic/wieldables.toml, plus the plan's numbers transcribed here); final
##    damage 10 / 17.5 / 7 / 7.5; Magewar's part getters (damage, fire rate >= 0.1,
##    accuracy, Head element); bad defs rejected;
##  - a cast at a wall 20 m away hits at 20.000 m in D/v s +-1 tick for all 4 bases (and a
##    500 m/s bolt stops on a 5 cm wall); bolts fizzle at their range; tracers use the
##    element colour;
##  - the Swift Wind Wand never casts twice within 0.18 s however Fire is spammed (60, 144,
##    30 Hz); semi-auto (holding doesn't repeat); mana refusal costs no cooldown;
##  - the caster's own capsule is never hit (the ray starts inside it), another player's is;
##  - casts start at eye_position(), not the bobbed camera; a hit on a body with a
##    damage_target goes through Damage.resolve_hit (Fire staff vs Earth = 15).
## Scenes are built far from the origin (other tests' leftovers can't get in the way) and
## freed at the end.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const E := ElementTable.Element
const BASES: PackedStringArray = [
	"apprentice_fire_staff", "earthward_battlestaff", "novice_arcane_wand", "swift_wind_wand"
]


## A body that takes bolt hits (stands in for step 11's enemies).
class TargetBody:
	extends StaticBody3D
	var damage_target: Damage.Target
	var taken: Array = []

	func take_hit(h: SpellBolts.Hit) -> void:
		taken.append(h)


func _world(at: Vector3) -> Node3D:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	w.global_position = at
	return w


func _box(parent: Node3D, center: Vector3, half: Vector3, body: StaticBody3D = null) -> StaticBody3D:
	var b := body if body != null else StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.position = center
	parent.add_child(b)
	return b


func _player(parent: Node3D, feet_local: Vector3, yaw := 0.0) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	# Placed before entering the tree: Jolt ray queries only see a body's teleport
	# (spawn() after add_child) after the next physics step, and these tests run inside one.
	p.position = feet_local
	parent.add_child(p)
	p.spawn(parent.global_position + feet_local, yaw)
	return p


func _bolts(parent: Node3D) -> SpellBolts:
	var b := SpellBolts.new()
	b.auto_tick = false
	parent.add_child(b)
	return b


func _def(id: String) -> WieldableDef:
	var d := load("res://resources/wieldables/%s.tres" % id) as WieldableDef
	check(d != null, "%s.tres loads as WieldableDef" % id)
	return d


## Magewar .tres (assets/magewar copy): `key = value` lines of the [resource] section.
func _magewar_tres(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	check(f != null, "open " + path)
	if f == null:
		return out
	for line in f.get_as_text().split("\n"):
		var eq := line.find(" = ")
		if eq > 0 and not line.begins_with("["):
			out[line.substr(0, eq)] = line.substr(eq + 3).strip_edges().trim_prefix('"').trim_suffix('"')
	return out


# --- Data ---------------------------------------------------------------------------


func test_bases_match_magewar_toml_and_plan() -> void:
	# The plan's numbers (damage/mana/cooldown/speed/range), transcribed independently.
	var plan := {
		"apprentice_fire_staff":
		["Apprentice Fire Staff", WieldableDef.Type.STAFF, "basic", E.FIRE, 10.0, 5.0, 0.40, 30.0, 50.0],
		"earthward_battlestaff":
		["Earthward Battlestaff", WieldableDef.Type.STAFF, "uncommon", E.EARTH, 14.0, 6.0, 0.55, 22.0, 45.0],
		"novice_arcane_wand":
		["Novice Arcane Wand", WieldableDef.Type.WAND, "basic", E.ARCANE, 7.0, 3.0, 0.25, 40.0, 35.0],
		"swift_wind_wand": ["Swift Wind Wand", WieldableDef.Type.WAND, "uncommon", E.AIR, 6.0, 2.5, 0.18, 55.0, 40.0],
	}
	var magewar_file := {
		"apprentice_fire_staff": "staffs/starter_fire_staff",
		"earthward_battlestaff": "staffs/earthward_staff",
		"novice_arcane_wand": "wands/starter_arcane_wand",
		"swift_wind_wand": "wands/swift_wind_wand",
	}
	var toml := LevelToml.load_file("res://data/magic/wieldables.toml")
	check(not toml.has("error"), "wieldables.toml parses: %s" % toml.get("error", ""))
	var rows: Array = toml.get("wieldable", [])
	check(rows.size() == 4, "4 bases in the TOML")
	var by_id := {}
	for r in rows:
		by_id[r["id"]] = WieldableDef.from_toml(r)
	for id in BASES:
		var d := _def(id)
		if d == null:
			continue
		check(d.validate().is_empty(), "%s valid: %s" % [id, "; ".join(d.validate())])
		var w: Array = plan[id]
		var got := [
			d.display_name,
			d.type,
			d.base_rarity,
			d.element,
			d.damage,
			d.mana_cost,
			d.cooldown,
			d.projectile_speed,
			d.range_m
		]
		check(d.id == id and got == w, "%s = plan %s (got %s)" % [id, w, got])
		var t: WieldableDef = by_id.get(id)
		check(t != null and t.validate().is_empty(), "%s in the TOML and valid" % id)
		if t != null:
			var tg := [
				t.display_name,
				t.type,
				t.base_rarity,
				t.element,
				t.damage,
				t.mana_cost,
				t.cooldown,
				t.projectile_speed,
				t.range_m
			]
			check(tg == got, "%s .tres = TOML (%s vs %s)" % [id, got, tg])
		# Magewar StaffWieldableItem fields (staff_type, base_rarity and primary_element are
		# Magewar enum ints in the same orders as ours).
		var m := _magewar_tres("res://assets/magewar/resources/items/%s.tres" % magewar_file[id])
		check(m.get("name") == d.display_name, "%s Magewar name %s" % [id, m.get("name")])
		check(int(m.get("staff_type", -1)) == d.type, "%s staff_type" % id)
		check(WieldableDef.RARITY_IDS[int(m.get("base_rarity", 0))] == d.base_rarity, "%s base_rarity" % id)
		check(int(m.get("primary_element", -1)) == d.element, "%s primary_element" % id)
		for pair in [
			["wieldable_damage", d.damage],
			["mana_cost", d.mana_cost],
			["fire_cooldown", d.cooldown],
			["projectile_speed", d.projectile_speed],
			["wieldable_range", d.range_m]
		]:
			check(
				float(m.get(pair[0], -1)) == pair[1], "%s Magewar %s %s vs %s" % [id, pair[0], m.get(pair[0]), pair[1]]
			)
	print("    wieldables: 4 bases = Magewar .tres = wieldables.toml = plan")


func test_final_damage_10_17_5_7_7_5() -> void:
	var want := {
		"apprentice_fire_staff": 10.0, "earthward_battlestaff": 17.5, "novice_arcane_wand": 7.0, "swift_wind_wand": 7.5
	}
	var toml := LevelToml.load_file("res://data/magic/wieldables.toml")
	for r in toml.get("wieldable", []):
		# Rarity straight from the TOML (base x Magewar ItemRarity multiplier).
		var from_toml := float(r["damage"]) * WieldableInstance.rarity_multiplier(str(r["base_rarity"]))
		check_near(from_toml, want[r["id"]], 1e-9, "%s TOML damage x rarity" % r["id"])
	var line := []
	for id in BASES:
		var w := WieldableInstance.load_base(id)
		check(w != null and w.parts.is_empty(), "%s instance" % id)
		if w == null:
			continue
		check_near(w.damage(), want[id], 1e-9, "%s final damage" % id)
		check_near(w.cooldown(), w.def.cooldown, 1e-12, "%s cooldown = base without parts" % id)
		check(w.element() == w.def.element and w.accuracy() == 50.0, "%s element/accuracy 50" % id)
		line.append("%s %.1f" % [id, w.damage()])
	print("    final damage: %s" % ", ".join(line))


func test_part_getters_follow_magewar() -> void:
	var P := WieldablePart.PartType
	var wand := WieldableInstance.load_base("novice_arcane_wand")
	# Magewar uncommon_fire_head: damage 4.5, accuracy 8, Fire.
	wand.parts.append(WieldablePart.make(P.HEAD, 4.5, 1.0, 8.0, E.FIRE))
	wand.parts.append(WieldablePart.make(P.EXTERIOR, 1.0, 0.8, 30.0))  # exterior accuracy ignored
	check_near(wand.damage(), 7.0 + 4.5 + 1.0, 1e-9, "flat bonuses after rarity")
	check_near(wand.cooldown(), 0.25 * 0.8, 1e-12, "exterior x fire rate")
	check(wand.accuracy() == 58.0, "accuracy 50 + head 8 (exterior ignored): %s" % wand.accuracy())
	check(wand.element() == E.FIRE, "Head element overrides Arcane")
	var wind := WieldableInstance.load_base("swift_wind_wand")
	wind.parts.append(WieldablePart.make(P.INTERIOR, 2.0, 0.1))  # interior rate ignored
	check_near(wind.cooldown(), 0.18, 1e-12, "interior fire_rate_modifier ignored")
	wind.parts.append(WieldablePart.make(P.CHARM, 0.0, 0.5, 60.0))
	wind.parts.append(WieldablePart.make(P.HANDLE, 0.0, 1.0, 20.0))
	check_near(wind.cooldown(), WieldableDef.MIN_COOLDOWN, 1e-12, "0.18 x 0.5 = 0.09 -> 0.1 floor")
	check(wind.accuracy() == 100.0, "accuracy clamps at 100")
	check_near(wind.damage(), 6.0 * 1.25 + 2.0, 1e-9, "uncommon 7.5 + 2")
	check(wind.element() == E.AIR, "no Head: base element")
	wind.parts.append(WieldablePart.make(P.HEAD, 0.0, 1.0, 0.0, E.ARCANE))
	check(wind.element() == E.AIR, "Arcane (Magewar NONE) head doesn't override")


func test_bad_defs_rejected() -> void:
	var ok := _def("swift_wind_wand")
	check(ok.validate().is_empty(), "base valid")
	var cases := [
		["id", "Bad Id", "lower_snake_case"],
		["display_name", "", "name is empty"],
		["base_rarity", "epic", "unknown base_rarity"],
		["cooldown", 0.05, "cooldown must be in [0.1"],
		["damage", -1.0, "damage must be in"],
		["projectile_speed", 0.0, "projectile_speed must be in"],
		["range_m", 5000.0, "range must be in"],
		["mana_cost", 101.0, "mana_cost must be in"],
		["element", 9, "unknown element"],
		["type", 2, "unknown type"],
	]
	for c in cases:
		var d := ok.duplicate() as WieldableDef
		d.set(c[0], c[1])
		var errs := " | ".join(d.validate())
		check(errs.contains(c[2]), "%s = %s -> '%s' (got '%s')" % [c[0], c[1], c[2], errs])
	for rid in Rarity.IDS:  # step 15: every Magewar rarity has a multiplier now
		var d := ok.duplicate() as WieldableDef
		d.base_rarity = rid
		check(d.validate().is_empty(), "base_rarity %s accepted" % rid)
	var t := WieldableDef.from_toml(
		{
			"id": "w",
			"name": "W",
			"type": "wand",
			"base_rarity": "basic",
			"element": "wind",
			"damage": 5,
			"mana_cost": 1,
			"cooldown": 0.2,
			"projectile_speed": 40,
			"range": 30
		}
	)
	check(ElementTable.parse("wind") == -1 and t.element == E.ARCANE, "unknown TOML element id doesn't parse")


# --- Bolts --------------------------------------------------------------------------


## Player at `w`'s origin facing north (-Z), a wall whose near face is `front` m north;
## casts on the first tick through Player.tick and runs until the bolt lands.
func _cast_at_wall(def: WieldableDef, front: float, thickness: float) -> Dictionary:
	var w := _world(Vector3(700, 0, -700))
	_box(w, Vector3(0, -0.5, 0), Vector3(80, 0.5, 80))
	var wall := _box(w, Vector3(0, 1.5, -front - thickness * 0.5), Vector3(1, 1.5, thickness * 0.5))
	var p := _player(w, Vector3.ZERO)
	var bolts := _bolts(w)
	p.bolts = bolts
	p.caster.equip(WieldableInstance.of(def))
	var hits: Array = []
	var ticks := 0
	var eye := p.eye_position()
	while hits.is_empty() and ticks < 600:
		p.tick(PlayerInput.hold([], ["action_primary"] if ticks == 0 else []), DT)
		if ticks == 0:
			eye = p.eye_position()
		hits.append_array(bolts.tick(DT))
		ticks += 1
		if bolts.live.is_empty() and hits.is_empty():
			break
	check(p.caster.casts == 1 and bolts.spawned == 1, "%s: one cast" % def.id)
	check(hits.size() == 1, "%s: one hit (%d)" % [def.id, hits.size()])
	var out := {"wall": wall == (hits[0].collider if not hits.is_empty() else null), "eye": eye}
	if not hits.is_empty():
		out["hit"] = hits[0]
		out["wall_z"] = w.global_position.z - front
	w.free()
	return out


func test_bolt_hits_20m_wall_in_time_for_all_bases() -> void:
	for id in BASES:
		var d := _def(id)
		var r := _cast_at_wall(d, 20.0, 1.0)
		if not r.has("hit"):
			continue
		var h: SpellBolts.Hit = r["hit"]
		var t_expect := 20.0 / d.projectile_speed
		var tick_expect := ceili(20.0 / (d.projectile_speed * DT) - 1e-4)
		print(
			(
				"    bolt %-22s %3.0f m/s: hit at %.3f m after %.4f s (tick %d; expected 20.000 m, %.4f s, tick %d)"
				% [id, d.projectile_speed, h.distance, h.time, h.tick, t_expect, tick_expect]
			)
		)
		check(r["wall"], "%s hit the wall" % id)
		check_near(h.distance, 20.0, 0.01, "%s distance" % id)
		check_near(h.time, t_expect, DT, "%s time within 1 tick" % id)
		check(absi(h.tick - tick_expect) <= 1, "%s tick %d vs %d" % [id, h.tick, tick_expect])
		check_near(h.point.z, r["wall_z"], 0.01, "%s on the near face" % id)
		check_near(h.normal.z, 1.0, 1e-3, "%s face normal" % id)
		check(
			h.element == d.element and is_equal_approx(h.damage, WieldableInstance.of(d).damage()),
			"%s element/damage carried" % id
		)
	# 500 m/s (8.3 m per tick) vs a 5 cm wall: a swept ray, no tunnelling.
	var fast := _def("apprentice_fire_staff").duplicate() as WieldableDef
	fast.projectile_speed = 500.0
	fast.range_m = 100.0
	var r2 := _cast_at_wall(fast, 37.3, 0.05)
	if r2.has("hit"):
		var h2: SpellBolts.Hit = r2["hit"]
		print("    bolt 500 m/s vs 5 cm wall: hit at %.3f m after %.4f s (tick %d)" % [h2.distance, h2.time, h2.tick])
		check(
			r2["wall"] and absf(h2.distance - 37.3) <= 0.01 and absf(h2.time - 37.3 / 500.0) <= DT,
			"fast bolt stops on the face"
		)


func test_fizzle_at_range_and_tracer_colour() -> void:
	var w := _world(Vector3(-900, 300, 900))  # nothing to hit up here
	var bolts := _bolts(w)
	var c := Caster.new(WieldableInstance.load_base("novice_arcane_wand"))  # 35 m at 40 m/s
	var o := w.global_position
	check(c.tick(true, true, DT, Caster.Aim.make(o, Vector3.FORWARD), bolts), "cast")
	var ticks := 0
	var hits := 0
	while not bolts.live.is_empty() and ticks < 600:
		hits += bolts.tick(DT).size()
		ticks += 1
	print("    range: arcane wand bolt fizzled after %d ticks (35 m at 40 m/s)" % ticks)
	check(hits == 0 and bolts.fizzled == 1 and bolts.spawned == 1, "fizzled, no hit")
	check(ticks == ceili(35.0 / (40.0 * DT)), "53 ticks (%d)" % ticks)
	# Tracer: Air colour from elements.tres (= Magewar AIR 0.8/0.95/1.0); nothing within 0.6 m.
	var s := SpellBolts.Spawn.new()
	s.origin = o
	s.speed = 40.0
	s.range_m = 35.0
	s.element = E.AIR
	bolts.spawn(s)
	check(bolts.tracer_lines(0.5).is_empty(), "not moved yet: no tracer")
	for i in 3:
		bolts.tick(DT)  # 2 m out
	var lines := bolts.tracer_lines(1.0)
	check(lines.size() == 1, "one tracer")
	if lines.size() == 1:
		var air := ElementTable.load_default().color(E.AIR)
		check(lines[0].color == air and air.is_equal_approx(Color(0.8, 0.95, 1.0)), "Air tracer %s" % lines[0].color)
		check_near(lines[0].a.z, o.z - SpellBolts.SKIP_NEAR, 1e-3, "starts 0.6 m out")
		check_near(lines[0].b.z, o.z - 2.0, 1e-3, "head at 2 m")
		check_near(bolts.tracer_lines(0.5)[0].b.z, o.z - 1.6667, 1e-3, "interpolated head")
	var fire := SpellBolts.Spawn.new()
	fire.origin = o + Vector3(1, 0, 0)
	fire.element = E.FIRE
	bolts.spawn(fire)
	for i in 3:
		bolts.tick(DT)
	var cols := bolts.tracer_lines(1.0).map(func(l: SpellBolts.Line) -> Color: return l.color)
	check(cols.has(ElementTable.load_default().color(E.FIRE)), "Fire tracer colour")
	w.free()


# --- Cooldown -----------------------------------------------------------------------


func _spam(
	w: WieldableInstance, dt: float, seconds: float, press_every: int, hold: bool, repeat: bool
) -> PackedFloat64Array:
	var c := Caster.new(w)
	c.hold_to_repeat = repeat
	var times := PackedFloat64Array()
	var n := roundi(seconds / dt)
	for i in n:
		if c.tick(i % press_every == 0, hold, dt, null, null):
			times.append(i * dt)
	check(c.casts == times.size(), "cast count")
	return times


func test_swift_wind_cooldown_holds_however_spammed() -> void:
	var wind := WieldableInstance.load_base("swift_wind_wand")
	for hz in [60.0, 144.0, 30.0]:
		for every in [1, 2, 3, 7]:
			var times := _spam(wind, 1.0 / hz, 3.0, every, true, false)
			var min_gap := 1e9
			for i in range(1, times.size()):
				min_gap = minf(min_gap, times[i] - times[i - 1])
			check(min_gap >= 0.18 - 1e-6, "%d Hz every %d: min gap %f" % [hz, every, min_gap])
			check(times.size() <= floori(3.0 / 0.18) + 1, "%d Hz every %d: %d casts" % [hz, every, times.size()])
			if hz == 60.0 and every == 1:
				print(
					(
						"    cooldown: swift wind wand spammed every tick at 60 Hz for 3 s -> %d casts, min gap %.4f s (11 ticks)"
						% [times.size(), min_gap]
					)
				)
				check(times.size() == 17 and is_equal_approx(min_gap, 11.0 / 60.0), "every 11 ticks at 60 Hz")
	var staff := _spam(WieldableInstance.load_base("apprentice_fire_staff"), DT, 3.0, 1, true, false)
	check(staff.size() > 1 and is_equal_approx(staff[1] - staff[0], 24.0 / 60.0), "fire staff every 24 ticks")
	# Semi-auto: one press, Fire held for 3 s = one cast; hold_to_repeat re-casts.
	check(_spam(wind, DT, 3.0, 100000, true, false).size() == 1, "holding doesn't repeat")
	check(_spam(wind, DT, 3.0, 100000, true, true).size() == 17, "hold_to_repeat repeats every 11 ticks")
	# Mana refusal (step 8 hook): no cast, no cooldown; the next affordable press casts at once.
	var c := Caster.new(wind)
	var allow := [false]
	c.mana_spender = func(cost: float) -> bool: return allow[0] and cost == 2.5
	check(
		not c.tick(true, true, DT, null, null) and c.mana_refused == 1 and c.cooldown_left == 0.0,
		"mana refused: no cooldown"
	)
	allow[0] = true
	check(c.tick(true, true, DT, null, null) and is_equal_approx(c.cooldown_left, 0.18), "then casts")
	check(not c.tick(true, true, DT, null, null) and c.blocked == 2, "cooldown blocks")
	# Empty hands never cast; a swap keeps the running cooldown.
	c.equip(null)
	check(not c.tick(true, true, DT, null, null), "empty hands")
	c.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	check(c.cooldown_left > 0.0 and not c.tick(true, true, DT, null, null), "swap keeps the cooldown")


# --- Self, aim, damage ---------------------------------------------------------------


func test_self_never_hit_other_player_is() -> void:
	var w := _world(Vector3(-700, 0, 700))
	_box(w, Vector3(0, -0.5, 0), Vector3(40, 0.5, 40))
	var me := _player(w, Vector3.ZERO)
	var other := _player(w, Vector3(2, 0, 0))
	var bolts := _bolts(w)
	var c := Caster.new(WieldableInstance.load_base("swift_wind_wand"))
	var self_hits := 0
	var other_hits := 0
	var casts := 0
	for yi in 24:
		for pi in 7:
			me.set_look(deg_to_rad(yi * 15.0), deg_to_rad(-75.0 + pi * 25.0))
			c.cooldown_left = 0.0
			if c.tick(true, true, DT, me.aim(), bolts):
				casts += 1
			for i in 4:
				for h in bolts.tick(DT):
					if h.collider == me:
						self_hits += 1
					if h.collider == other:
						other_hits += 1
	print(
		(
			"    self: %d casts in all directions from inside the capsule, %d self hits, %d on the other player"
			% [casts, self_hits, other_hits]
		)
	)
	check(casts == 168 and self_hits == 0, "never hits itself (%d)" % self_hits)
	check(other_hits > 0, "hits the other player's capsule")
	# Facing the other player (east): the bolt hits its capsule ~1.7 m out (2 m - radius 0.3;
	# at eye height the ray meets the top hemisphere a little further out).
	me.set_look(-PI / 2.0, 0.0)
	c.cooldown_left = 0.0
	c.tick(true, true, DT, me.aim(), bolts)
	var hs: Array[SpellBolts.Hit] = []
	for i in 4:
		hs.append_array(bolts.tick(DT))
	check(
		hs.size() == 1 and hs[0].collider == other and absf(hs[0].distance - 1.7) < 0.05,
		(
			"east -> other at 1.7 m (%s)"
			% [hs.map(func(h: SpellBolts.Hit) -> String: return "%s %.3f m" % [h.collider, h.distance])]
		)
	)
	w.free()


func test_cast_from_eye_and_hit_resolves_damage() -> void:
	var w := _world(Vector3(900, 0, -900))
	_box(w, Vector3(0, -0.5, 0), Vector3(40, 0.5, 40))
	var target := TargetBody.new()
	target.damage_target = Damage.Target.new(E.EARTH)
	_box(w, Vector3(0, 1.5, -15.5), Vector3(2, 1.5, 0.5), target)
	var p := _player(w, Vector3.ZERO)
	var bolts := _bolts(w)
	p.bolts = bolts
	p.caster.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	var signalled: Array = []
	bolts.bolt_hit.connect(func(h: SpellBolts.Hit) -> void: signalled.append(h))
	# Walk 0.5 s first so the camera bobs: the aim must stay on the plain eye.
	for i in 30:
		p.tick(PlayerInput.hold(["forward"]), DT)
	var cam := p.camera_position()
	var a := p.aim()
	print(
		(
			"    aim: eye %s, camera %s (bob offset %s)"
			% [a.origin - w.global_position, cam - w.global_position, p.camera_offset()]
		)
	)
	check(a.origin.is_equal_approx(p.eye_position()), "aim origin = eye_position()")
	check(a.origin.distance_to(cam) > 1e-3, "camera is bobbed away from the eye")
	check(a.exclude == [p.get_rid()] and a.direction.is_equal_approx(Vector3(0, 0, -1)), "excludes self, looks north")
	p.tick(PlayerInput.hold(["action_primary"], ["action_primary"]), DT)
	for i in 59:  # Fire held: semi-auto, no 2nd cast
		p.tick(PlayerInput.hold(["action_primary"]), DT)
		bolts.tick(DT)
	check(p.caster.casts == 1 and bolts.hits == 1, "one cast, one hit (%d, %d)" % [p.caster.casts, bolts.hits])
	check(target.taken.size() == 1 and signalled.size() == 1, "take_hit + bolt_hit")
	if target.taken.size() == 1:
		var h: SpellBolts.Hit = target.taken[0]
		check(
			h.result != null and is_equal_approx(h.result.amount, 15.0) and h.result.strong(),
			"Fire 10 vs Earth = 15 (Super Effective)"
		)
		print(
			(
				"    hit: %s %.1f at %.3f m -> %.1f (x%.1f)"
				% [ElementTable.id_of(h.element), h.damage, h.distance, h.result.amount, h.result.effectiveness]
			)
		)
	w.free()
