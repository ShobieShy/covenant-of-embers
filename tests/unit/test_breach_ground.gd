extends TestCase
## L5b: the ground outside the Breach (no box pads, Interiors.CELL_SKIP) is Terrain3D only, so
## its Dynamic collision must follow the player. Before L5b a player leaving the Breach rooms
## fell through the world on the way to the crater gate.

const FILE := "user://test_breach_ground_save.json"
const STASH := "user://test_breach_ground_stash.json"


func _frames(n: int) -> void:
	for i in n:
		await runner_tree.physics_frame


func _ray_hits(p: Player, x: float, z: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 50, z), Vector3(x, -50, z))
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and absf((hit["position"] as Vector3).y + 0.02) < 0.5


func test_breach_exit_to_gate_has_ground() -> void:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	Stash.shared_path = STASH
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	GameFlow.open_world = true
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	runner_tree.root.add_child(g)
	var p := g.get_node("Player") as Player
	var ow := g.get_node("OpenWorld") as OpenWorld
	var n := 0
	while (ow.travel.busy or n < 120) and n < 3600:
		await _frames(1)
		n += 1
	ow.interiors.leave()
	await _frames(30)
	await g._world_travel(ow, "breach")
	await _frames(120)
	check(ow.interiors.current == "breach_rooms", "in the Breach rooms (%s)" % ow.interiors.current)
	var land: Vector3 = ow.interiors.leave()
	check(ow.interiors.current == "", "left the rooms")
	await _frames(90)
	check(p.global_position.y > -1.0, "standing outside the Breach exit %s" % p.global_position)
	check(_ray_hits(p, land.x, land.z), "ground under the Breach exit %s" % land)
	var gate: Vector3 = ow.find_children("Door_labyrinth", "", true, false)[0].global_position
	var stop := gate + (land - gate).normalized() * 3.0  # short of the door: it would enter
	for i in 7:  # the path from the exit to the crater gate, walked in steps
		var at := land.lerp(stop, i / 6.0)
		p.global_position = Vector3(at.x, at.y + 0.5, at.z)
		p.velocity = Vector3.ZERO
		await _frames(20)
		check(_ray_hits(p, at.x, at.z), "ground at %.0f,%.0f" % [at.x, at.z])
		check(p.global_position.y > at.y - 1.0, "not falling at %.0f,%.0f" % [at.x, at.z])
	check(_ray_hits(p, gate.x, gate.z), "ground under the crater gate %s" % gate)
	g.queue_free()
	for i in 10:
		await runner_tree.process_frame
	GameFlow.open_world = false
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	Stash.shared_path = Stash.PATH
	for f in [FILE, STASH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
