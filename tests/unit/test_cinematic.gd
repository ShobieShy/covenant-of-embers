extends TestCase
## Step 110 done check: a cinematic moves its camera through the shots, locks the player,
## blocks saving and the pause menu, ends by itself or on skip (finished fires either way),
## and a co-op client may not skip.


func _player() -> Player:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	return p


func test_plays_and_skips() -> void:
	var p := _player()
	var shots := [
		{"from": Vector3(0, 2, 5), "to": Vector3(0, 2, 3), "look": Vector3.ZERO, "s": 0.2, "text": "One"},
		{"from": Vector3(3, 2, 0), "look": Vector3.ZERO, "s": 0.2, "text": "Two"},
	]
	var got := []
	var c := Cinematic.make("t", shots, p)
	c.finished.connect(func(i, s): got.append([i, s]))
	runner_tree.root.add_child(c)
	check(Cinematic.playing == c and p.ui_open and c.camera.current, "plays, player locked, its camera live")
	check(c.caption.text == "One", "first caption")
	c._process(0.25)
	check(c.shot == 1 and c.caption.text == "Two", "next shot")
	c._process(0.25)
	check(got == [["t", false]] and Cinematic.playing == null and not p.ui_open, "ends by itself, control back")
	var d := Cinematic.make("u", shots, p)
	d.finished.connect(func(i, s): got.append([i, s]))
	runner_tree.root.add_child(d)
	check(d.skip() and got[1] == ["u", true] and Cinematic.playing == null, "skip still finishes")
	var e := Cinematic.make("v", shots, p)
	e.can_skip = false  # a co-op client
	runner_tree.root.add_child(e)
	check(not e.skip() and Cinematic.playing == e, "client can't skip")
	e._end(false)
	await runner_tree.process_frame
	p.free()


func test_no_save_or_pause_mid_cinematic() -> void:
	GameFlow.dry_run = true
	GameFlow.level_id = "midden"
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(0, 0, -7000)
	runner_tree.root.add_child(g)
	var c := Cinematic.make("w", [{"from": Vector3(0, 2, 2), "look": Vector3.ZERO, "s": 5.0}], g.get_node("Player"))
	g.add_child(c)
	check(g.save_game() == ERR_BUSY, "no save during a cinematic")
	g.pause_menu.open()
	check(not g.pause_menu.visible and not runner_tree.paused, "no pause menu during a cinematic")
	c.skip()
	g.free()
	GameFlow.dry_run = false
