extends TestCase
## OW5a: instanced interiors. Entering the Mage Association loads it at Interiors.DEPTH
## and lands the party inside its town exit; leaving through either exit lands outside
## at the linked world marker, clear of the door trigger, and frees the interior.


func test_links_resolve() -> void:
	for id in Interiors.LINKS:
		var lvl := (load(GameFlow.level_scene(id)) as PackedScene).instantiate()
		for to in Interiors.LINKS[id]["exits"]:
			var found := false
			for e in lvl.get_node("Exits").get_children():
				found = found or String(e.get_meta(&"to", "")) == to
			check(found, "%s has an exit to %s" % [id, to])
			var link: Array = Interiors.LINKS[id]["exits"][to]
			var out := (load(GameFlow.level_scene(link[0])) as PackedScene).instantiate()
			check(out.has_node(NodePath("Exits/" + link[1])), "%s has %s" % link)
			out.free()
		lvl.free()


func test_enter_and_leave() -> void:
	var root := Node3D.new()
	runner_tree.root.add_child(root)
	var i := Interiors.new()
	root.add_child(i)
	i.add_doors()
	var door := i.get_node("Door_mage_association") as Node3D
	check(door.position.distance_to(Vector3(0, 0, -17)) < 0.01, "front door at the town marker")
	var p := Node3D.new()
	p.add_to_group(Player.GROUP)
	root.add_child(p)
	var fades := [0]
	i.fade.connect(func(_s: float) -> void: fades[0] += 1)
	var land: Vector3 = await i.enter("mage_association")
	check(i.current == "mage_association" and i.interior != null, "interior loaded")
	check(absf(land.y - Interiors.DEPTH) < 5.0, "landing below the world (%s)" % land)
	check(p.global_position.distance_to(land) < 1.0, "player moved inside")
	check(i.interior.get_node_or_null("WorldEnvironment") == null, "world sky kept")
	var out := i.leave("midden")
	check(i.current == "", "left")
	check(out.y > -100.0, "back above ground (%s)" % out)
	check(
		out.distance_to(Vector3(0, 0, 17.5)) < Interiors.INSET + 0.1,
		"back door lands at the Landfill road"
	)
	await i.enter("mage_association")
	out = i.leave("town_square")
	check(
		out.distance_to(door.position) >= InteriorDoor.RADIUS, "landing clear of the door trigger"
	)
	check(fades[0] == 4, "a fade per transition (%d)" % fades[0])
	root.free()


func test_fade_and_slow_load_overlay() -> void:
	var i := Interiors.new()
	runner_tree.root.add_child(i)
	var f := InteriorFade.new()
	f.interiors = i
	runner_tree.root.add_child(f)
	i.fade.emit(Interiors.FADE)
	for n in 5:
		await runner_tree.process_frame
	check(f.rect.color.a > 0.0, "fade dips to black (%.2f)" % f.rect.color.a)
	i.slow_load.emit("mage_association")
	check(f.screen != null and f.screen.manual, "slow load shows the overlay")
	var s := f.screen
	i.entered.emit("mage_association")
	check(f.screen == null and s.progress >= 1.0, "overlay closes on entry")
	await runner_tree.create_timer(0.6).timeout
	await runner_tree.process_frame
	check(not is_instance_valid(s), "overlay freed after its fade-out")
	check(
		runner_tree.current_scene == null or runner_tree.current_scene.name != "", "no scene change"
	)
	f.free()
	i.free()
