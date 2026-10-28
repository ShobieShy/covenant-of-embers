extends TestCase
## L4: co-op Labyrinth floors (LabyrinthSync): the joiner plays the host's floor from the
## host's state (its own block untouched), only the host's stairs descend, and they need
## the whole party nearby or the 10 s vote.


class FakeSession:
	extends Node
	signal message(from: int, kind: String, data: Dictionary)
	signal roster_changed
	var sent: Array = []
	var peer: FakeSession

	func send(kind: String, data: Dictionary, _to := 0, _reliable := true) -> void:
		sent.append([kind, data])
		if peer:
			peer.message.emit(1, kind, data.duplicate(true))


func _pair() -> Dictionary:
	var hs := FakeSession.new()
	var js := FakeSession.new()
	hs.peer = js
	var hi := Interiors.new()
	var ji := Interiors.new()
	for n in [hs, js, hi, ji]:
		runner_tree.root.add_child(n)
	hi.labyrinth = LabyrinthState.fresh(1234)
	ji.labyrinth = LabyrinthState.fresh(99)
	var h := LabyrinthSync.new()
	var j := LabyrinthSync.new()
	runner_tree.root.add_child(h)
	runner_tree.root.add_child(j)
	h.setup(hs, hi, true)
	j.setup(js, ji, false)
	var me := Node3D.new()
	me.add_to_group(Player.GROUP)
	runner_tree.root.add_child(me)
	return {"hs": hs, "js": js, "hi": hi, "ji": ji, "h": h, "j": j, "me": me}


func _free(d: Dictionary) -> void:
	for k in ["h", "j", "hi", "ji", "hs", "js", "me"]:
		if is_instance_valid(d[k]):
			d[k].free()


func test_joiner_plays_the_hosts_floor() -> void:
	var d := _pair()
	var hi: Interiors = d["hi"]
	var ji: Interiors = d["ji"]
	var own: LabyrinthState = ji.labyrinth
	await hi.enter("labyrinth")
	check(d["h"].pushes == 1 and d["hs"].sent[0][0] == "lab", "the host announces floor 1")
	check(ji.labyrinth != own and ji.labyrinth.save_seed == 1234, "joiner uses the host's state")
	check(ji.floor_no == 1, "joiner's next floor is the host's")
	await ji.enter("labyrinth")
	check(ji.lab_floor.layout == hi.lab_floor.layout, "same seed, same floor layout on both peers")
	await hi.descend()
	for _f in 3:
		await runner_tree.process_frame
	await runner_tree.process_frame
	while ji.busy:
		await runner_tree.process_frame
	check(ji.floor_no == 2 and d["j"].follows == 1, "joiner followed the host down")
	check(own.save_seed == 99 and own.deepest == 0, "the joiner's own block is untouched")
	d["j"].free()
	check(ji.labyrinth == own and not ji.follow_only, "own block back when the sync ends")
	_free(d)


func test_joiner_stairs_do_nothing() -> void:
	var d := _pair()
	var hi: Interiors = d["hi"]
	var ji: Interiors = d["ji"]
	await hi.enter("labyrinth")
	await ji.enter("labyrinth")
	ji._on_stairs(LabyrinthStairs.DOWN)
	await runner_tree.process_frame
	check(ji.floor_no == 1 and not ji.busy, "a joiner's stairs wait for the host")
	_free(d)


func test_stairs_wait_for_the_party_or_the_vote() -> void:
	var d := _pair()
	var hi: Interiors = d["hi"]
	var h: LabyrinthSync = d["h"]
	await hi.enter("labyrinth")
	var sd := h.stairs_pos()
	check(sd != Vector3.INF, "floor 1 has stairs down")
	var mate := Node3D.new()
	mate.add_to_group(&"coop_avatars")
	runner_tree.root.add_child(mate)
	d["me"].global_position = sd
	mate.global_position = sd + Vector3(40, 0, 0)
	hi._on_stairs(LabyrinthStairs.DOWN)
	check(hi.floor_no == 1 and h.vote_left > 9.9, "a straggler: the vote countdown starts")
	check(d["hs"].sent.back()[0] == "lab_vote", "the party is told")
	h.tick(5.0)
	check(hi.floor_no == 1 and not hi.busy, "still waiting at 5 s")
	h.tick(5.1)
	while hi.busy:
		await runner_tree.process_frame
	check(hi.floor_no == 2 and h.vote_left < 0.0, "vote over: the party goes down")
	sd = h.stairs_pos()
	d["me"].global_position = sd
	mate.global_position = sd + Vector3(2, 0, 0)
	hi._on_stairs(LabyrinthStairs.DOWN)
	while hi.busy:
		await runner_tree.process_frame
	check(hi.floor_no == 3, "everyone at the stairs: straight down")
	mate.free()
	_free(d)


func test_roster_change_pushes() -> void:
	var d := _pair()
	await d["hi"].enter("labyrinth")
	var n: int = d["h"].pushes
	d["hs"].roster_changed.emit()
	check(d["h"].pushes == n + 1, "a new partner gets the floor")
	_free(d)
