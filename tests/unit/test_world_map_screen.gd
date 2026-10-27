extends TestCase
## OW7: fog of war, map pins and the open-world map screen.


func test_fog_reveal_and_save() -> void:
	var f := WorldFog.new()
	check(f.cols == 72 and f.rows == 48, "fog grid from world/map.json (%dx%d)" % [f.cols, f.rows])
	check(not f.is_revealed(0, 0), "starts fogged")
	var n := f.reveal(0, 0)
	check(n > 0 and f.is_revealed(0, 0), "reveals around the player (%d cells)" % n)
	check(not f.is_revealed(200, 0), "far stays fogged")
	check(f.reveal(0, 0) == 0, "revealing again adds nothing")
	var g := WorldFog.new()
	g.from_save(f.to_save())
	check(g.revealed_count() == f.revealed_count(), "round-trips through the save")
	var h := WorldFog.new()
	h.reveal(500, 0)
	h.merge(f)
	check(h.is_revealed(0, 0) and h.is_revealed(500, 0), "partner fog merges")
	var k := WorldFog.new()
	k.from_save(Marshalls.raw_to_base64(PackedByteArray([1, 2, 3])))
	k.from_save("")
	check(k.revealed_count() == 0, "wrong-size or missing fog (old saves) is ignored")
	check(f.reveal(-99999, 0) == 0, "outside the world is a no-op")


func test_pins() -> void:
	var p := MapPins.new()
	for i in MapPins.MAX:
		p.add(i * 100.0, 0.0)
	check(p.pins.size() == MapPins.MAX, "pins placed")
	check(not p.add(1, 1), "capped at %d" % MapPins.MAX)
	check(p.remove_near(102, 0) and p.pins.size() == MapPins.MAX - 1, "removes the nearest")
	check(not p.remove_near(150, 0), "nothing near")
	var q := MapPins.new()
	q.from_save(p.to_save())
	check(q.pins.size() == p.pins.size(), "round-trips")
	q.from_save("junk")
	check(q.pins.is_empty(), "bad data is dropped")


func test_screen() -> void:
	LoadingScreen.dry_run = true
	var t := WorldTravel.new()
	t.fast_travel = FastTravel.new()
	t.fast_travel.flags.set_flag(FastTravel.CRYSTAL)
	t.fast_travel.flags.set_flag(FastTravel.TUTORIAL_DONE)
	runner_tree.root.add_child(t)
	var m := WorldMapScreen.new()
	m.travel = t
	m.regions = WorldMap.new()
	m.size = Vector2(1280, 720)
	runner_tree.root.add_child(m)
	m.open()
	check(m.tex != null, "world map texture (tools/gen_world_map.py)")
	check(m.visible, "opens")
	var w := Vector3(123, 0, -45)
	var back := m.screen_to_world(m.world_to_screen(w))
	check(back.distance_to(w) < 0.01, "screen <-> world round-trips")
	var s := m.world_to_screen(w)
	m.zoom_at(s, 2.0)
	check(m.world_to_screen(w).distance_to(s) < 0.01, "zoom keeps the point under the cursor")
	var at := m.world_to_screen(t.point_world("landfill"))
	check(m.waystone_at(at) == "", "unattuned waystones are not clickable")
	t.fast_travel.attune("landfill")
	var asked := []
	m.travel_requested.connect(func(p: String) -> void: asked.append(p))
	check(m.click(at) and asked == ["landfill"], "clicking an attuned waystone travels")
	check(not m.visible, "and closes the map")
	m.open()
	var here := m.world_to_screen(Vector3(300, 0, 0))
	m.right_click(here)
	check(m.pins.pins.size() == 1, "right click places a pin")
	m.right_click(here)
	check(m.pins.pins.is_empty(), "and removes it")
	await runner_tree.process_frame  # one draw pass without errors
	for i in 30:
		if not t.busy:
			break
		await runner_tree.process_frame
	LoadingScreen.dry_run = false
	m.free()
	t.free()
