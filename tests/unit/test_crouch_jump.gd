extends TestCase
## 0.8.3 #23: crouching in the air tucks the capsule up so the feet clear a higher
## ledge. Letting go stands only when the standing capsule fits. A slide-jump still
## stands up. Co-op poses carry the crouch bit onto the remote hull.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _world() -> Node3D:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	return w


func _box(parent: Node, center: Vector3, half: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.position = center
	parent.add_child(b)
	return b


func _player(w: Node3D, at: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(at, 0.0)
	return p


func test_air_tuck_raises_feet_and_release_needs_room() -> void:
	var w := _world()
	_box(w, Vector3(0, -0.5, 0), Vector3(20, 0.5, 20))
	var p := _player(w, Vector3(0, 2.5, 0))
	await runner_tree.physics_frame
	var top := p.global_position.y + p.capsule_height()
	p.tick(PlayerInput.hold([&"crouch"]), DT)
	check(p.air_tucked() and p.crouched, "crouch in the air tucks")
	check_near(p.capsule_height(), 0.7, 1e-4, "crouch capsule")
	check(p.feet().y > 3.2, "feet rose (%.2f)" % p.feet().y)
	check_near(p.feet().y + p.capsule_height(), top, 0.05, "the head stays put")
	var tucked := p.feet().y
	p.tick(PlayerInput.hold([]), DT)
	check(not p.air_tucked() and not p.crouched, "open air: uncrouch drops the feet")
	check(p.feet().y < tucked - 0.7, "feet came back down (%.2f -> %.2f)" % [tucked, p.feet().y])
	p.spawn(Vector3(0, 2.5, 0), 0.0)
	p.velocity = Vector3.ZERO
	p.tick(PlayerInput.hold([&"crouch"]), DT)
	check(p.air_tucked(), "tucked again")
	var feet := p.feet()
	# Below the snap distance, overlapping the standing capsule the release would grow into.
	_box(w, feet + Vector3(0, -1.15, 0), Vector3(0.6, 0.25, 0.6))
	await runner_tree.physics_frame
	p.tick(PlayerInput.hold([]), DT)
	check(p.air_tucked() and p.crouched, "no headroom / legroom: stay tucked")
	check_near(p.feet().y, feet.y, 0.05, "feet were not dropped into the slab")
	w.free()


func test_tuck_lands_on_a_ledge_a_standing_jump_misses() -> void:
	var w := _world()
	_box(w, Vector3(0, -0.5, 0), Vector3(30, 0.5, 30))
	# Top at 1.40 m. Standing apex is ~1.07 m.
	_box(w, Vector3(0, 0.7, -2.6), Vector3(1.2, 0.7, 2.2))
	_box(w, Vector3(8, 0.7, -2.6), Vector3(1.2, 0.7, 2.2))
	var p := _player(w, Vector3.ZERO)
	await runner_tree.physics_frame
	for i in 20:
		p.tick(PlayerInput.hold([&"forward", &"sprint"]), DT)
	p.tick(PlayerInput.hold([&"forward", &"sprint"], [&"jump"]), DT)
	var landed := false
	for i in 90:
		p.tick(PlayerInput.hold([&"forward", &"sprint", &"crouch"]), DT)
		if p.on_ground() and p.feet().y > 1.2:
			landed = true
			break
	check(landed, "tucked jump lands on the 1.4 m ledge (feet %.2f)" % p.feet().y)
	var q := _player(w, Vector3(8, 0, 0))
	for i in 20:
		q.tick(PlayerInput.hold([&"forward", &"sprint"]), DT)
	q.tick(PlayerInput.hold([&"forward", &"sprint"], [&"jump"]), DT)
	var stood_on := false
	for i in 90:
		q.tick(PlayerInput.hold([&"forward", &"sprint"]), DT)
		if q.on_ground() and q.feet().y > 1.2:
			stood_on = true
	check(not stood_on and q.feet().y < 0.2, "without the tuck the same jump stays on the floor (%.2f)" % q.feet().y)
	w.free()


func test_remote_hull_follows_the_crouch_bit() -> void:
	var w := _world()
	var rp := RemotePlayer.new()
	w.add_child(rp)
	rp.apply_pose({"p": Vector3(0, 2, 0), "cr": 1, "y": 0.2})
	check(rp.crouched, "remote crouched")
	check_near(rp._hit_shape.height, 0.7, 1e-4, "remote hull tucked")
	check_near(rp.eye_position().y, 2.6, 1e-3, "remote eye at crouch height")
	rp.apply_pose({"p": Vector3(0, 2, 0), "cr": 0})
	check(not rp.crouched and absf(rp._hit_shape.height - 1.8) < 1e-4, "remote stands")
	check_near(rp.eye_position().y, 3.5, 1e-3, "remote eye standing")
	w.free()
