class_name IntroLandfill
extends RefCounted
## Helpers extracted from scripts/story/intro_director.gd so that file stays under the line limit.
## Behavior is unchanged; the original type keeps the same methods.


static func _dress_landfill(h: IntroDirector) -> void:
	h.main.call("_ensure_dialogue")
	if not (h.main.dialogue as DialogueRunner).ended.is_connected(h._on_dialogue_ended):
		(h.main.dialogue as DialogueRunner).ended.connect(h._on_dialogue_ended)
	var b := h.current()
	if b == "filth":
		_arm_filth(h)
		return
	if not b in ["combat", "crafting", "light_dark"]:
		return
	var sp := spawner(h)
	if sp and sp.trigger_radius > 0.0:
		h._saved_trigger = sp.trigger_radius  # the Filth's mound stays quiet until beat 11
		sp.trigger_radius = 0.0
	for w in h.WALLS:
		if not h.flags.has(String(h.WALLS[w][1])):
			h.walls[w] = _wall(h, w, float(h.WALLS[w][0]))
	var st := station(h)
	if st:
		st.global_position = h.spot("joe_bench", h.CAMP)
	if not h.flags.has("joe_wand_given"):
		h._spawn("Crazy Joe", h.spot("joe_camp", h.JOE_CAMP), -120.0)
	if not GameEvents.bus().crafting_completed.is_connected(h._on_crafted):
		GameEvents.bus().crafting_completed.connect(h._on_crafted)
	match b:
		"combat":
			_start_yard(h)
		"crafting":
			_drop_part(h, h.at(Vector3(0, 0, 10.5)))
		"light_dark":
			_make_shrines(h)
	_queue_toasts(h, b)


static func spawner(h: IntroDirector) -> EnemySpawner:
	return h.main.get_node_or_null("Enemies") as EnemySpawner


static func station(h: IntroDirector) -> AssemblyStation:
	for c in h.main.get_children():
		if c is AssemblyStation:
			return c
	return null


static func wall_up(h: IntroDirector, w: String) -> bool:
	return h.walls.has(w) and is_instance_valid(h.walls[w])


static func _wall(h: IntroDirector, n: String, z: float) -> StaticBody3D:
	return IntroWall.make(h.main, n, z)


static func _drop_wall(h: IntroDirector, w: String) -> void:
	if wall_up(h, w):
		(h.walls[w] as Node).queue_free()
	h.walls.erase(w)


static func _start_yard(h: IntroDirector) -> void:
	var sp := spawner(h)
	var d := sp.table.find("gnawer") if sp else null
	if d == null:
		return
	for at in h.YARD_GNAWERS:
		var e := Enemy.create(d, Transform3D(Basis(), h.base + at))
		e.name = "YardGnawer%d" % (h.yard.size() + 1)
		sp.add_child(e)
		sp.call("_adopt", e)
		e.died.connect(func(dead: Enemy, _el: ElementTable.Element): _on_yard_kill(h, dead))
		h.yard.append(e)
	h._hint("Objective: Clear the Gnawers (0/%d)" % h.yard.size())


static func _on_yard_kill(h: IntroDirector, e: Enemy) -> void:
	h.yard_kills += 1
	h._hint("Objective: Clear the Gnawers (%d/%d)" % [h.yard_kills, h.YARD_GNAWERS.size()])
	if h.yard_kills < h.YARD_GNAWERS.size() or h.current() != "combat":
		return
	h.flags.set_flag("gnawers_cleared")
	_drop_wall(h, "YardWall")
	_drop_part(h, e.global_position)
	h.advance("crafting")
	_queue_toasts(h, "crafting")


## The guaranteed first parts (beat 8): a Basic salvage kit around the last kill, Interact to pick up.
static func _drop_part(h: IntroDirector, at: Vector3) -> void:
	h.part_pickups.clear()
	var i := 0
	for id in h.TUTORIAL_KIT:
		var part := WieldablePart.load_part(id)
		if part == null:
			continue
		var d := LootDrop.new()
		d.kind = LootDrop.Kind.PART
		d.item = part.duplicate()
		d.rarity_id = "basic"
		d.rolled_rarity_id = "basic"
		d.element = part.element
		var off := Vector3(cos(i * TAU / h.TUTORIAL_KIT.size()), 0, sin(i * TAU / h.TUTORIAL_KIT.size())) * 0.9
		var pk := LootPickup.create(d, Vector3(at.x, at.y + 0.4, at.z) + off)
		h.main.add_child(pk)
		h.part_pickups.append(pk)
		i += 1
	next_pickup(h)


## The next kit piece still lying around (also kept in `part_pickup`).
static func next_pickup(h: IntroDirector) -> LootPickup:
	h.part_pickup = null
	for pk in h.part_pickups:
		if h.part_pickup == null and is_instance_valid(pk) and pk.is_inside_tree():
			h.part_pickup = pk
	return h.part_pickup


static func _on_crafted(h: IntroDirector, _p: Player, _w: WieldableInstance) -> void:
	if h.flags.has("crafted_once"):
		return
	h.flags.set_flag("crafted_once")
	_drop_wall(h, "JunkWall")
	if h.current() == "crafting":
		h.advance("light_dark")
		_make_shrines(h)
		_queue_toasts(h, "light_dark")


static func _make_shrines(h: IntroDirector) -> void:
	if not h.shrines.is_empty():
		return
	for spec in [
		["Light shrine", h.spot("light_shrine", h.LIGHT_SHRINE)], ["Dark shrine", h.spot("dark_shrine", h.DARK_SHRINE)]
	]:
		var n := Npc.new(String(spec[0]))
		n.name = String(spec[0]).replace(" ", "")
		n.player = h.player
		h.main.add_child(n)
		n.global_position = spec[1]
		n.talked.connect(h.touch_shrine)
		h.shrines[spec[0]] = n
	if not h.flags.has("light_learned"):
		ScavengerPose.lay(h._spawn("Wounded scavenger", h.spot("light_shrine", h.LIGHT_SHRINE), 0.0))


## Beat 10: either order. Light heals the scavenger; Dark forces one Gnawer conversion.
static func touch_shrine(h: IntroDirector, which: String) -> void:
	if which == "Light shrine" and not h.flags.has("light_learned"):
		h.flags.set_flag("light_learned")
		MagicEffects.light_heals += 1
		h.player.health.heal(h.player.health.max_value())
		ScavengerPose.stand(h.cast.get("Wounded scavenger") as Npc)
		h._hint("Light washes over the scavenger. He stands. (Light heals allies; enemies take a little less.)")
	elif which == "Dark shrine" and not h.flags.has("dark_learned"):
		_dark_lesson(h)
	if h.flags.has("light_learned") and h.flags.has("dark_learned") and h.current() == "light_dark":
		_drop_wall(h, "ArenaWall")
		var sp := spawner(h)
		if sp and h._saved_trigger > 0.0:
			sp.trigger_radius = h._saved_trigger
		h.advance("filth")
		_arm_filth(h)


static func _dark_lesson(h: IntroDirector) -> void:
	var sp := spawner(h)
	var d := sp.table.find("gnawer") if sp else null
	if d:
		h.dark_gnawer = Enemy.create(
			d, Transform3D(Basis(), h.spot("dark_shrine", h.DARK_SHRINE) + Vector3(1.5, 0, -1.0))
		)
		h.dark_gnawer.name = "ShrineGnawer"
		sp.add_child(h.dark_gnawer)
		sp.call("_adopt", h.dark_gnawer)
		if not h.flags.has("tutorial_force_convert"):
			h.flags.set_flag("tutorial_force_convert")  # once per character
			MagicEffects.force_convert = true
		MagicEffects.try_corrupt(h.dark_gnawer, 0.0)
	h.flags.set_flag("dark_learned")
	h._hint("The Gnawer's eyes go dark: it fights for you now. (Normally ~1%. Dark parts raise it.)")


static func _queue_toasts(h: IntroDirector, b: String) -> void:
	for t in h.TOASTS.get(b, []):
		h._toasts.append(String(t))


static func _tick_toasts(h: IntroDirector, dt: float) -> void:
	h._toast_left -= dt
	if h._toasts.is_empty() or h._toast_left > 0.0 or Cinematic.playing != null:
		return
	h._hint(h._toasts.pop_front())
	h._toast_left = h.TOAST_SECONDS


static func _arm_filth(h: IntroDirector) -> void:
	var bus := GameEvents.bus()
	if not bus.wave_started.is_connected(h._on_wave):
		bus.wave_started.connect(h._on_wave)
	if not h.flags.changed.is_connected(h._on_flag):
		h.flags.changed.connect(h._on_flag)


static func _on_wave(h: IntroDirector, _i: int, id: String) -> void:
	if id != Filth.WAVE_ID or h.current() != "filth" or h.flags.has("filth_revealed"):
		return
	h.flags.set_flag("filth_revealed")
	var sp := spawner(h)
	var c: Vector3 = sp.trigger_center if sp else Vector3.ZERO
	h.cinematic = (
		h
		. play_cinematic(
			"filth_reveal",
			[
				{
					"from": c + Vector3(0, 2, 10),
					"to": c + Vector3(0, 1.5, 7),
					"look": c + Vector3(0, 1, 0),
					"s": 2.0,
					"text": "The arena walls grind up out of the trash."
				},
				{
					"from": c + Vector3(-3, 1, 6),
					"to": c + Vector3(-1, 0.8, 5),
					"look": c + Vector3(0, 3, -2),
					"s": 3.0,
					"text": "THE FILTH"
				},
			]
		)
	)


static func _on_flag(h: IntroDirector, flag: String, _v: int) -> void:
	if flag == "filth_defeated" and h.current() == "filth":
		h.advance("return_to_bob")
		h._hint("The north road is open. The Breach is past the pit; Bob still wants Joe's trash.")


static func _play_crystal(h: IntroDirector) -> void:
	var bob := h.main.get_node_or_null("Npc_Bob") as Node3D
	var at: Vector3 = bob.global_position if bob else h.player.global_position
	var gem := RitualFX.crystal(at + Vector3(0, 1.4, 0.4))  # step 133 (FX F7)
	h.main.add_child(gem)
	h.cinematic = (
		h
		. play_cinematic(
			"crystal",
			[
				{
					"from": at + Vector3(2, 1.8, 2),
					"to": at + Vector3(1, 1.6, 1.5),
					"look": at + Vector3(0, 1.2, 0),
					"s": 3.0,
					"text": "Bob turns Joe's trash in his hands. It hums. It glows. It becomes a crystal."
				},
			],
			h.complete
		)
	)
	h.cinematic.finished.connect(func(_i, _s): gem.queue_free())
