extends TestCase
## 0.3.1 P2: the Labyrinth stairs take a HOLD_S Interact hold, not a walk-on.


func test_hold_interact_to_use() -> void:
	var s := LabyrinthStairs.new()
	runner_tree.root.add_child(s)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	p.global_position = Vector3(0, 900, 4000)
	var got: Array = []
	s.used.connect(func(dir: int) -> void: got.append(dir))
	check(s.prompt.text == "Stairs down", "the title while nobody is on them")
	s._on_body(p)
	s.tick(1.0)
	check(got.is_empty(), "standing on the stairs does not take them")
	check(s.prompt.text.begins_with("E: go down"), "the prompt shows on the stairs")
	p.interact_held = true
	s.tick(0.3)
	check(got.is_empty() and s.hold > 0.25, "a short hold fills the bar")
	s.tick(0.2)
	check(got == [LabyrinthStairs.DOWN], "a 0.5 s hold takes the stairs")
	s.tick(1.0)
	check(got.size() == 1, "a long hold fires once")
	p.interact_held = false
	s.tick(0.1)
	p.interact_held = true
	s.tick(0.2)
	p.interact_held = false
	s.tick(0.1)
	check(s.hold == 0.0 and got.size() == 1, "letting go resets the hold")
	s._off_body(p)
	check(s.prompt.text == "Stairs down", "off the stairs: the title again")
	p.free()
	s.free()
