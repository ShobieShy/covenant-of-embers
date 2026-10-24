extends TestCase
## Step 22 done check: a kill spawns its drops as LootPickups with the right rarity colour.
##  - killing a Gnawer/Heap through Enemy.apply_damage (→ EventBus.enemy_killed) spawns
##    exactly the drops DropRoller.roll_enemy gives on the same peer rng, around the corpse,
##    each tinted LootDrop.rarity_color() (gem, beam, light, label) with describe() as text;
##  - beam height grows with the tier; pickups sit on the pickup physics layer;
##  - training dummies never drop; one death = one roll (hitting the corpse again doesn't);
##  - per-peer rng streams are deterministic and differ between peers.

const E := ElementTable.Element

func _world() -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(500, 0, 500)
	runner_tree.root.add_child(w)
	return w

func _enemy(id: String, at: Vector3, world: Node3D) -> Enemy:
	var d := EnemyTable.load_default().find(id)
	check(d != null, "enemy def " + id)
	var e := Enemy.create(d, Transform3D(Basis.IDENTITY, at))
	e.process_mode = Node.PROCESS_MODE_DISABLED   # no AI ticks: only the death matters
	world.add_child(e)
	return e

func _dropper(world: Node3D, peer := 1) -> LootDropper:
	var dr := LootDropper.new()
	dr.peer_id = peer
	dr.seed_base = "test_drops"
	world.add_child(dr)
	return dr

func test_kill_spawns_coloured_drops() -> void:
	var w := _world()
	var dr := _dropper(w)
	var replay := LootDropper.make_peer_rng("test_drops", 1)
	var rt := RarityTable.load_default()
	var tiers_seen := {}
	for k in 30:
		var id := "heap" if k % 3 == 0 else "gnawer"
		var at := Vector3(k * 3.0, 0, 0)
		var e := _enemy(id, at, w)
		var expect := DropRoller.roll_enemy(replay, e.def, 0.0)
		var before := w.get_children().filter(func(n: Node) -> bool: return n is LootPickup).size()
		check(e.apply_damage(100000.0, E.FIRE), "%s dies" % id)
		e.apply_damage(100000.0, E.FIRE)   # hitting the corpse: no second roll
		var pickups: Array = w.get_children().filter(func(n: Node) -> bool: return n is LootPickup)
		var new_ones := pickups.slice(before)
		check(new_ones.size() == expect.size(), "kill %d: %d pickups, expected %d" % [k, new_ones.size(), expect.size()])
		for i in mini(new_ones.size(), expect.size()):
			var p: LootPickup = new_ones[i]
			var x: LootDrop = expect[i]
			check(p.drop.rarity_id == x.rarity_id and p.drop.kind == x.kind, "kill %d drop %d same roll" % [k, i])
			var c := rt.color(x.rarity_id)
			check(p.color.is_equal_approx(c), "pickup colour = rarity colour")
			check((p.gem.material_override as StandardMaterial3D).albedo_color.is_equal_approx(c), "gem tint")
			var bc := (p.beam.material_override as StandardMaterial3D).albedo_color
			check(Color(bc, 1.0).is_equal_approx(c), "beam tint")
			check(p.light.light_color.is_equal_approx(c), "light tint")
			check(p.label.text == x.describe(), "label '%s'" % p.label.text)
			check_near(p.beam_height(), LootPickup.BEAM_BASE + LootPickup.BEAM_PER_TIER * Rarity.parse(x.rarity_id), 1e-6, "beam height")
			check(p.collision_layer == 1 << (LootPickup.PICKUP_LAYER - 1), "pickup layer")
			check(p.is_in_group(LootPickup.GROUP), "group")
			check(p.position.distance_to(at) <= LootDropper.SCATTER + 0.1, "near the corpse")
			tiers_seen[x.rarity_id] = true
		e.queue_free()
	check(dr.kills_seen == 30 and dr.kills_skipped == 0, "30 kills seen (%d)" % dr.kills_seen)
	check(tiers_seen.size() >= 3, "several rarities seen: %s" % [tiers_seen.keys()])
	print("    30 kills: %d pickups, tiers %s" % [dr.spawned, tiers_seen.keys()])
	w.queue_free()

func test_dummies_never_drop() -> void:
	var w := _world()
	var dr := _dropper(w)
	for id in ["earth_training_dummy", "water_training_dummy"]:
		for k in 5:
			var e := _enemy(id, Vector3(k, 0, 0), w)
			e.apply_damage(100000.0, E.WATER)
			e.queue_free()
	check(dr.spawned == 0, "dummies dropped %d" % dr.spawned)
	check(dr.kills_skipped == 10, "10 skipped (%d)" % dr.kills_skipped)
	check(not LootDropper.drops_for("earth_training_dummy") and LootDropper.drops_for("gnawer"), "drops_for")
	w.queue_free()

func test_peer_streams() -> void:
	var a := LootDropper.make_peer_rng("s", 1)
	var b := LootDropper.make_peer_rng("s", 1)
	var c := LootDropper.make_peer_rng("s", 2)
	var same := true
	var differ := false
	for i in 20:
		var x := a.randi()
		same = same and x == b.randi()
		differ = differ or x != c.randi()
	check(same, "same peer → same stream")
	check(differ, "different peers → different streams")

func test_beam_grows_with_tier() -> void:
	var prev := 0.0
	for t in Rarity.COUNT:
		var d := LootDrop.new()
		d.rarity_id = Rarity.IDS[t]
		var p := LootPickup.create(d, Vector3.ZERO)
		check(p.beam_height() > prev, "tier %d beam taller" % t)
		prev = p.beam_height()
		p.free()
