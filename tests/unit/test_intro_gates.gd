extends TestCase
## Step 156 done check: FlagGate soft-blocks drop on their flag; IntroDirector.spot() reads
## Level/Anchors markers and falls back to the greybox constants.


func test_gate_blocks_until_flag() -> void:
	var g := FlagGate.new()
	g.size = Vector3(4, 3, 0.5)
	g.reason = "Bob said to stick to the path."
	runner_tree.root.add_child(g)
	var f := StoryFlags.new()
	g.bind(f)
	check(not g.is_open() and g.visible and g.collision_layer == 1, "gate up before tutorial_done")
	check(g.label.text.begins_with("Bob said"), "gate shows its reason")
	f.set_flag("tutorial_done")
	check(g.is_open() and not g.visible and g.collision_layer == 0, "gate drops at tutorial_done")
	g.queue_free()


func test_spot_uses_anchor_marker() -> void:
	var main := Node3D.new()
	var lvl := Node3D.new()
	lvl.name = "Level"
	main.add_child(lvl)
	var anchors := Node3D.new()
	anchors.name = "Anchors"
	lvl.add_child(anchors)
	var m := Marker3D.new()
	m.name = "dais"
	m.position = Vector3(40, 2, -30)
	anchors.add_child(m)
	runner_tree.root.add_child(main)
	var d := IntroDirector.new()
	d.main = main
	check(d.spot("dais", Vector3.ZERO).is_equal_approx(Vector3(40, 2, -30)), "spot reads Anchors marker")
	check(d.spot("elder", IntroDirector.ELDER_SPOT) == IntroDirector.ELDER_SPOT, "spot falls back to constant")
	d.free()
	main.queue_free()
