extends TestCase
## 0.9.3: falling off a level skips the downed window and comes back at the last spawn.
## Gold stays. A partner is a different player, so this check is per body.


func test_host_rejects_a_far_claim() -> void:
	var level := Node3D.new()
	level.name = "Level"
	var start := Marker3D.new()
	start.name = "PlayerStart"
	level.add_child(start)
	runner_tree.root.add_child(level)
	start.global_position = Vector3(0, 0, 12)
	var near := Vector3(1, 0, 12)
	check(KillPlane.host_dest(level, near, -8.0).distance_to(near) < 0.01, "a claim on the start stays")
	var far := Vector3(40, 1, 40)
	check(KillPlane.host_dest(level, far, -8.0).distance_to(start.global_position) < 0.01, "a far claim is the start")
	var hole := Vector3(0, -40, 12)
	check(KillPlane.host_dest(level, hole, -8.0).distance_to(start.global_position) < 0.01, "a claim in the void is the start")
	level.free()


func test_line_and_floor() -> void:
	check(is_equal_approx(KillPlane.line_for(0.0), -8.0), "eight metres under the floor")
	check(KillPlane.below(-9.0, -8.0) and not KillPlane.below(-2.0, -8.0), "the bowl is not the void")
	check(is_nan(KillPlane.lowest_top(null)), "no level, no floor")


func test_fall_respawns_and_keeps_gold() -> void:
	var level := Node3D.new()
	level.name = "Level"
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)
	level.add_child(body)
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(level)
	runner_tree.root.add_child(p)
	p.spawn(Vector3(2, 0, 3), 0.4)
	p.inventory.gold = 77
	p.global_position = Vector3(9, -30, 1)
	check(KillPlane.tick(p), "the fall is caught")
	check(p.void_falls == 1, "counted")
	check(p.inventory.gold == 77, "gold kept")
	check(p.alive() and not p.downed, "back up, no downed window")
	check(p.global_position.distance_to(Vector3(2, 0, 3)) < 0.5, "back at the last spawn")
	p.global_position = Vector3(2, 0, 3)
	check(not KillPlane.tick(p), "standing on the floor is fine")
	p.free()
	level.free()


func test_waystone_becomes_the_spawn() -> void:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var stone := Waystone.new("town_gate", FastTravel.new())
	runner_tree.root.add_child(p)
	runner_tree.root.add_child(stone)
	p.spawn(Vector3.ZERO, 0.0)
	stone.global_position = Vector3(4, 0, 4)
	p.global_position = Vector3(4, 0, 5)
	stone.player = p
	check(stone.check_attune(), "first touch attunes")
	check(p.spawn_feet.distance_to(stone.global_position) < 2.0, "the stone is the way back")
	check(not stone.check_attune(), "already attuned")
	check(p.spawn_feet.distance_to(stone.global_position) < 2.0, "standing there still remembers it")
	p.free()
	stone.free()
