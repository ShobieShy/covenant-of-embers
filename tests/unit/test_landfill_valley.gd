extends TestCase
## The Landfill is a closed valley. South to north: entry dump, compactor, deeper rot,
## the Filth bowl, then an empty road into the Breach. The Filth is the last fight.

const SCENE := "res://scenes/levels/midden.tscn"


func _level() -> Node3D:
	var level: Node3D = (load(SCENE) as PackedScene).instantiate()
	runner_tree.root.add_child(level)
	return level


func _ray(level: Node3D, a: Vector3, b: Vector3) -> Dictionary:
	return level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))


func test_areas_run_south_to_north_and_the_filth_is_last() -> void:
	var level := _level()
	check(level.get_node_or_null("Terrain") == null, "closed level, no terrain")
	check(String(level.get_meta("level_name", "")) == "The Landfill", "keeps its name")
	var start := (level.get_node("PlayerStart") as Node3D).position
	var compactor := (level.get_node("Boxes/compactor") as Node3D).position
	var mound := (level.get_node("Boxes/midden_mound") as Node3D).position
	var ledge := (level.get_node("Boxes/scrap_ledge") as Node3D).position
	var basin := (level.get_node("Boxes/basin_ramp") as Node3D).position
	var bowl := (level.get_node("Boxes/bowl_floor") as Node3D).position
	var road := (level.get_node("Boxes/road_floor") as Node3D).position
	check(start.z > compactor.z, "entry is south of the compactor")
	check(compactor.z > mound.z, "compactor is south of the rot mound")
	check(mound.z > ledge.z, "the rot mound is south of the scrap climb")
	check(ledge.z > basin.z, "the scrap climb is south of the drop into the bowl")
	check(basin.z > bowl.z and bowl.z > road.z, "the bowl is south of the north road")
	var waves := level.get_node("Waves")
	var trigger := waves.get_meta("trigger_center") as Vector3
	var filth := waves.get_child(waves.get_child_count() - 1)
	check(String(filth.name) == "the_filth", "the Filth wave is last")
	var filth_at := String((filth.get_meta("enemies") as Array)[0]["at"])
	var spawn := (level.get_node("WaveSpawns/" + filth_at) as Node3D).position
	check(spawn.z < trigger.z and trigger.z < basin.z, "the bowl trigger is north of the rot")
	var northmost := spawn.z
	for m in level.get_node("WaveSpawns").get_children():
		northmost = minf(northmost, (m as Node3D).position.z)
	for m in level.get_node("EnemySpawns").get_children():
		northmost = minf(northmost, (m as Node3D).position.z)
	check(is_equal_approx(northmost, spawn.z), "no enemy stands north of the Filth")
	var gate := (level.get_node("Exits/to_breach") as Node3D).position
	var town := (level.get_node("Exits/to_town") as Node3D).position
	check(gate.z < spawn.z - 8.0, "the Breach road is past the Filth (%.1f vs %.1f)" % [gate.z, spawn.z])
	check(town.z > start.z, "town is back at the south lip")
	check(start.distance_to(gate) > 8.0, "the Breach road is not the arrival spot")
	var rule := LevelFlow.rule("midden", "breach")
	var intro: Array = IntroDirector.GATE_RULES["midden"]["breach"]
	check(rule[0] == "filth_defeated" and String(intro[0]) == "filth_defeated", "beating the Filth opens the Breach")
	level.free()


func test_walk_from_the_entry_to_the_breach_road() -> void:
	var level := _level()
	var route := [
		Vector3(0, 6, 20),
		Vector3(0, 6, 12.5),
		Vector3(0, 6, 8),
		Vector3(2, 6, 4),
		Vector3(-4.5, 6, -6),
		Vector3(-4.5, 6, -12),
		Vector3(-4.5, 6, -17),
		Vector3(3, 4, -22),
		Vector3(3, 4, -30),
		Vector3(0, 4, -40),
		Vector3(0, 4, -55),
	]
	var prev_y := 2.0
	var saw_bowl := false
	for p in route:
		var hit := _ray(level, p, p + Vector3(0, -12, 0))
		check(not hit.is_empty(), "floor under %s" % p)
		if hit.is_empty():
			continue
		var y: float = (hit["position"] as Vector3).y
		check((hit["normal"] as Vector3).y > 0.7, "walkable at %s" % p)
		check(absf(y - prev_y) < 2.2, "no cliff at %s (%.2f -> %.2f)" % [p, prev_y, y])
		if p.z < -28.0:
			saw_bowl = saw_bowl or y < -1.0
		prev_y = y
	check(saw_bowl, "the bowl is sunken")
	var exit := (level.get_node("Exits/to_breach") as Node3D).position
	var end := _ray(level, exit + Vector3(0, 4, 0), exit + Vector3(0, -6, 0))
	check(not end.is_empty() and absf((end["position"] as Vector3).y - exit.y) < 0.05, "the gate stands on the road")
	var side := _ray(level, Vector3(0, 1.2, -36), Vector3(18, 1.2, -36))
	check(not side.is_empty(), "the bowl's east side is a trash wall")
	level.free()


func test_scavenger_lies_on_open_ground_by_the_light_shrine() -> void:
	var level := _level()
	var lay := IntroDirector.LIGHT_SHRINE + ScavengerPose.BESIDE
	var hit := _ray(level, lay + Vector3(0, 3, 0), lay + Vector3(0, -2, 0))
	check(not hit.is_empty() and (hit["collider"] as Node).name == "ground", "he lies on the trench floor")
	if not hit.is_empty():
		check(absf((hit["position"] as Vector3).y) < 0.05, "that floor is the upper trench, not the bowl")
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, lay + Vector3(0, 0.7, 0))
	var blocked := level.get_world_3d().direct_space_state.intersect_shape(q)
	check(blocked.is_empty(), "open ground east of the Light shrine (%s)" % blocked.size())
	check(lay.z > (level.get_node("Boxes/midden_mound") as Node3D).position.z, "still in the rot, south of the mound")
	level.free()
