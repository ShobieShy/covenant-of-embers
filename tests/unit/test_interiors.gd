extends TestCase
## OW5a: instanced interiors. Entering the Mage Association loads it at Interiors.DEPTH
## and lands the party inside its town exit; leaving through either exit lands outside
## at the linked world marker, clear of the door trigger, and frees the interior.


func test_links_resolve() -> void:
	for id in Interiors.LINKS:
		if String(Interiors.LINKS[id]["scene"]) == "":
			continue  # Labyrinth floors are built (test_labyrinth_floor.gd)
		var lvl := (
			(load(GameFlow.level_scene(Interiors.LINKS[id]["scene"])) as PackedScene).instantiate()
		)
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
	await runner_tree.process_frame  # earlier tests' queued frees (players) land first
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
	check(
		p.global_position.distance_to(land) < 1.0,
		"player moved inside (%s vs %s)" % [p.global_position, land]
	)
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


func test_breach_rooms() -> void:
	var root := Node3D.new()
	runner_tree.root.add_child(root)
	var i := Interiors.new()
	root.add_child(i)
	i.add_doors()
	var door := i.get_node("Door_breach_rooms") as Node3D
	check(
		door.position.distance_to(Vector3(1099.5, 0, 11)) < 0.01,
		"portal at the complex entrance (%s)" % door.position
	)
	var p := Node3D.new()
	p.add_to_group(Player.GROUP)
	root.add_child(p)
	var land: Vector3 = await i.enter("breach_rooms")
	check(i.current == "breach_rooms", "rooms entered")
	check(absf(land.y - Interiors.DEPTH) < 5.0, "rooms below the world (%s)" % land)
	check(i.interior.get_node_or_null("Terrain") == null, "crater stays in the world")
	check(i.interior.has_node("Boxes/vault_door"), "rooms keep their boxes")
	check(i.breach != null and i.breach.encounters.size() > 0, "Breach logic runs the rooms")
	var out := i.leave("midden")
	check(
		out.y > -100.0 and out.distance_to(door.position) >= InteriorDoor.RADIUS,
		"back out in the crater, clear of the portal (%s)" % out
	)
	check(i.breach == null, "logic dropped")
	root.free()


func test_interior_nav_cached_and_fresh() -> void:
	for id in Interiors.LINKS:
		if String(Interiors.LINKS[id]["scene"]) == "":
			continue
		check(ResourceLoader.exists(Interiors.nav_cache(id)), "%s nav cache present" % id)
		var ps := load(GameFlow.level_scene(Interiors.LINKS[id]["scene"])) as PackedScene
		var n := ps.instantiate() as Node3D
		Interiors.prepare(n, id)
		var nav := n.get_node_or_null("Navigation") as LevelNavigation
		check(nav != null and not nav.bake_on_ready, "%s uses the cache" % id)
		var cached := nav.navigation_mesh.get_polygon_count()
		runner_tree.root.add_child(n)
		check(nav.bakes == 0, "%s did not bake on entry" % id)
		var fresh := nav.bake_now()
		check(
			fresh == cached,
			"%s cache fresh (%d vs %d): rerun tools/bake_interior_nav.gd" % [id, cached, fresh]
		)
		n.free()


func test_arrival_and_respawn_fade_in() -> void:  # 0.3.1 P1
	var t := WorldTravel.new()
	var f := InteriorFade.new()
	f.travel = t
	runner_tree.root.add_child(f)
	f.rect.color.a = 1.0
	t.arrived.emit("x")
	check(f.rect.color.a == 0.0, "arrival fades in (instant headless)")
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.position = Vector3(0, 900, 4000)
	runner_tree.root.add_child(p)
	check(p.respawned.is_connected(f._on_respawned), "a new player's respawn is watched")
	f.rect.color.a = 1.0
	p.respawned.emit(p)
	check(f.rect.color.a == 0.0, "respawn fades in")
	p.free()
	f.free()
	t.free()
