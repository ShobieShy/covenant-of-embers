extends SceneTree
## QA-5 (worktree only): drives a real game (main.tscn, open world, --skip-intro) through the
## Labyrinth: crater gate -> floors 1-4 (kill all, stairs trigger) -> floor 5 King -> chest,
## waystone, rest shrine, stairs up. Prints [qa] lines; exit code = number of failed checks.
## godot --headless --fixed-fps 60 --path . -s tools/qa_lab_run.gd -- --skip-intro [--shots DIR]

var main: Node
var fails := 0
var shots := ""


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print("[qa] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for _i in n:
		await physics_frame


func shot(name: String) -> void:
	if shots == "":
		return
	await frames(20)
	await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [shots, name]
	root.get_texture().get_image().save_png(p)
	print("[qa] shot ", p)


func pickups() -> Array:
	return main.find_children("*", "LootPickup", true, false)


func enemies() -> Array:
	var sp := main.get_node_or_null("LabyrinthEnemies")
	if sp == null:
		return []
	return sp.find_children("*", "Enemy", true, false).filter(func(e): return e.alive())


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--shots")
	if i >= 0:
		shots = a[i + 1]
		DirAccess.make_dir_recursive_absolute(shots)
	var si := a.find("--scale")
	if si >= 0:
		Engine.time_scale = float(a[si + 1])
		print("[qa] time_scale ", Engine.time_scale)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var ow: OpenWorld = null
	var t := 0
	while t < 3600:
		ow = main.get_node_or_null("OpenWorld") as OpenWorld
		if ow and not ow.travel.busy and t > 120:
			break
		await frames(1)
		t += 1
	check(ow != null, "open world up (%d frames)" % t)
	if ow == null:
		quit(99)
		return
	var player := main.get_node("Player") as Player
	var it := ow.interiors
	var st: LabyrinthState = main.get("labyrinth")
	check(it.labyrinth == st, "interiors uses main's save block")
	check(main.get_node_or_null("LootDropper") != null, "LootDropper exists in the open world")
	if it.current != "":
		print("[qa] starting inside ", it.current, "; leaving")
		it.leave()
		await frames(180)
	# Crater entry, by walking the player onto the gate door (as a player would).
	var gate := it.link_world(Interiors.LINKS["labyrinth"]["front"])
	print("[qa] crater gate at ", gate)
	var doors := ow.find_children("*", "InteriorDoor", true, false).filter(
		func(d): return String(d.interior) == "labyrinth")
	print("[qa] labyrinth doors: ", doors.map(func(d): return "%s@%s" % [d.name, d.global_position]))
	if not doors.is_empty():
		player.global_position = (doors[0] as Node3D).global_position + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
	print("[qa] before door: busy=%s current=%s" % [it.busy, it.current])
	await frames(120)
	print("[qa] after door: busy=%s current=%s pos=%s" % [it.busy, it.current, player.global_position])
	if it.current != "labyrinth":
		print("[qa] door did not take us in; entering by call")
		check(false, "crater door trigger enters the Labyrinth")
		var r = await it.enter("labyrinth")
		print("[qa] enter() -> ", r, " busy=", it.busy)
	else:
		check(true, "crater door trigger enters the Labyrinth")
	await frames(30)
	check(it.current == "labyrinth" and it.floor_no == 1, "floor 1 from the crater (floor_no=%d)" % it.floor_no)
	var prev_pickups := 0
	for n in range(1, 6):
		await frames(30)
		var fl := it.lab_floor
		check(fl != null and it.floor_no == n and st.current == n, "on floor %d (st.current=%d deepest=%d)" % [n, st.current, st.deepest])
		if fl == null:
			break
		var pd := player.global_position.distance_to(fl.start_pos())
		check(pd < 3.0, "player at floor %d start (%.1f m)" % [n, pd])
		var es := enemies()
		var shr := fl.find_children("*", "RestShrine", true, false)
		var sd := fl.get_node_or_null("StairsDown")
		var su := fl.get_node_or_null("StairsUp")
		print("[qa] floor %d: rooms=%d enemies=%d shrines=%d down=%s up=%s ids=%s" % [n, fl.rooms.size(), es.size(), shr.size(), sd != null, su != null, ",".join(es.map(func(e): return e.def.id))])
		check(shr.size() == 1, "floor %d has one rest shrine" % n)
		check(es.size() > 0, "floor %d has enemies" % n)
		for e in es:
			check(e.level() == ActLoot.item_level(n), "enemy %s lvl %d == band %d" % [e.def.id, e.level(), ActLoot.item_level(n)]) if e == es[0] else null
		await shot("floor%d_start" % n)
		var olds := pickups()
		var near_old := olds.filter(func(p): return p.global_position.distance_to(fl.start_pos()) < 200.0 and p.global_position.y < -1000.0).size()
		print("[qa] floor %d: %d pickups from earlier floors sit inside this floor's space" % [n, near_old])
		check(n == 1 or near_old == 0, "no stale loot from earlier floors on floor %d" % n)
		var before := olds.size()
		var king := false
		for e in es:
			if String(e.def.id) == "goblin_king":
				king = true
				print("[qa] king found")
			e.apply_damage(1.0e6, ElementTable.Element.FIRE)
			await frames(2)
		await frames(90)
		var left := enemies()
		check(left.is_empty(), "floor %d all enemies dead (left %d)" % [n, left.size()])
		var pk := pickups()
		var newp := pk.slice(before)
		var rar := {}
		var lv := {}
		var els := {}
		var nobeam := 0
		for p in newp:
			if p.drop:
				rar[p.drop.rarity_id] = int(rar.get(p.drop.rarity_id, 0)) + 1
				els[p.drop.element] = int(els.get(p.drop.element, 0)) + 1
				var il = null
				if p.drop.item:
					for k in ["item_level", "level", "ilvl"]:
						if p.drop.item.get(k) != null:
							il = p.drop.item.get(k)
							break
				lv[str(il)] = int(lv.get(str(il), 0)) + 1
				if p.beam == null or not p.beam.visible:
					nobeam += 1
		print("[qa] floor %d loot: pickups +%d rarity=%s level=%s element=%s nobeam=%d" % [n, newp.size(), rar, lv, els, nobeam])
		check(newp.size() > 0, "floor %d kills dropped loot" % n)
		await shot("floor%d_cleared" % n)
		# rest shrine
		if not shr.is_empty():
			player.health.value = 1.0
			var saves := []
			it.rested.connect(func(at): saves.append(at), CONNECT_ONE_SHOT)
			(shr[0] as RestShrine).rest(player)
			await frames(5)
			check(is_equal_approx(player.health.value, player.health.max_value()) and saves.size() == 1, "floor %d rest heals + saves" % n)
		if n == 5:
			check(king, "floor 5 has the Goblin King")
			await frames(60)
			print("[qa] labyrinth bosses: ", st.bosses)
			check(st.bosses.size() >= 1, "King recorded defeated")
			var ch := fl.get_node_or_null("BossChest") as VaultChest
			check(ch != null, "boss chest present")
			if ch:
				print("[qa] boss chest rarity=", ch.floor_rarity, " at ", ch.global_position)
				check(ch.floor_rarity == "unique", "first clear chest is unique")
			check(fl.find_children("Waystone_*", "", true, false).size() > 0, "waystone appears after the King")
			check(sd == null, "no stairs down on the boss floor")
			await shot("floor5_after_king")
			# stairs up -> Breach
			if su:
				player.global_position = (su as Node3D).global_position + Vector3(0, 0.5, 0)
				await frames(120)
				check(it.current != "labyrinth", "stairs up leave to the Breach (current=%s)" % it.current)
			break
		check(sd != null, "floor %d has stairs down" % n)
		if sd == null:
			break
		player.global_position = (sd as Node3D).global_position + Vector3(0, 0.5, 0)
		var w := 0
		while it.floor_no == n and w < 600:
			await frames(1)
			w += 1
		check(it.floor_no == n + 1, "stairs down floor %d -> %d in %d frames" % [n, it.floor_no, w])
		check(st.cleared.has(n), "floor %d marked cleared" % n)
		var stale := pickups().filter(func(p): return p.global_position.y < -100.0 or p.global_position.y > 1000.0).size()
		print("[qa] pickups total %d after leaving floor %d" % [pickups().size(), n])
	print("[qa] state ", st.to_dict())
	print("[qa] DONE fails=%d" % fails)
	quit(fails)
