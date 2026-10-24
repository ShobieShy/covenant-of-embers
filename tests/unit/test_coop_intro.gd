extends TestCase
## Step 117 done check (loopback): the client follows the host's beats, a late joiner gets
## the kit and a recap card, only the host skips, and the character records intro_done.

var _port := 28200 + randi_range(0, 300) * 2


func _wait(cond: Callable, frames := 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


func _pair() -> Dictionary:
	_port += 1
	var w := Node.new()
	runner_tree.root.add_child(w)
	var h := NetSession.new()
	var c := NetSession.new()
	w.add_child(h)
	w.add_child(c)
	check(h.host(NetTransport.make("enet"), _port, {"name": "H"}), "host")
	check(c.join(NetTransport.make("enet"), "127.0.0.1:%d" % _port, {"name": "C"}), "join")
	check(await _wait(func(): return h.roster.size() == 2 and c.state == NetSession.State.LOBBY), "lobby")
	return {"w": w, "h": h, "c": c}


func _player() -> Player:
	var p := Player.new()
	p.input_enabled = false
	return p


func test_client_follows_beats_and_late_join() -> void:
	var hf := StoryFlags.new()
	IntroDirector.start(hf)
	IntroDirector.reach(hf, "back_door")
	hf.set_flag("bob_met")
	var d := await _pair()
	var hs := IntroSync.new()
	var cs := IntroSync.new()
	var cp := _player()
	var cf := StoryFlags.new()
	(d["w"] as Node).add_child(hs)
	(d["w"] as Node).add_child(cs)
	hs.setup(d["h"], hf, null, true)
	cs.setup(d["c"], cf, cp, false)
	hs.push()  # what the roster change does for a late joiner
	check(await _wait(func(): return cs.received > 0), "client hears the host")
	check(IntroDirector.beat(cf) == "back_door", "client mirrors the beat")
	check(cp.loadout.wieldable(Loadout.Slot.STAFF) != null, "late joiner gets Bob's kit")
	check(cs.last_card.begins_with("Recap:"), "recap card")
	var n := cs.received
	IntroDirector.reach(hf, "combat")
	hf.set_flag("joe_wand_given")
	check(await _wait(func(): return cs.received > n), "beat change pushed")
	check(IntroDirector.beat(cf) == "combat", "client follows")
	check(cp.loadout.wieldable(Loadout.Slot.WAND) != null, "Joe's wand too")
	n = cs.received
	IntroDirector.finish(hf)
	check(await _wait(func(): return cs.received > n), "finish pushed")
	check(cf.has(IntroDirector.DONE) and cs.last_card == "Prologue complete", "end card")
	(d["c"] as NetSession).leave()
	(d["h"] as NetSession).leave()
	(d["w"] as Node).queue_free()
	cp.free()
	IntroDirector.live = null


func test_only_host_skips_and_character_records_done() -> void:
	var c := Cinematic.make("t", [{"from": Vector3.ZERO, "to": Vector3.ONE, "look": Vector3.FORWARD, "s": 1.0}], null)
	check(c.can_skip != Coop.is_client(), "skip follows host role")
	c.free()
	var p := _player()
	var path := CharacterSave.PREFIX + "intro_sync_test.json"
	check(CharacterSave.write(p, path, true) == OK, "write")
	var q := _player()
	check(bool(CharacterSave.load_into(q, path).get("intro_done", false)), "intro_done recorded")
	q.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	p.free()
