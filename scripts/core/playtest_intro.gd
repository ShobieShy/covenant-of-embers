class_name PlaytestIntro
extends RefCounted
## Helpers extracted from scripts/core/playtest_bot.gd so that file stays under the line limit.
## Behavior is unchanged; the original type keeps the same methods.


static func _intro_director(h: PlaytestBot) -> IntroDirector:
	return h.main.get_node_or_null("IntroDirector") as IntroDirector


static func _intro_tick(h: PlaytestBot) -> void:
	var d := _intro_director(h)
	if d == null and IntroDirector.active(h.main.get(&"story_flags")):
		return  # the director is created once the party has landed
	if d == null or not IntroDirector.active(d.flags):
		h.note("prologue done: %d beat(s) %s" % [h.intro_beats.size(), ",".join(h.intro_beats)])
		if h.intro_beats.size() < IntroDirector.BEATS.size():
			h._finish(false, "prologue skipped beats (%s)" % ",".join(h.intro_beats))
		else:
			h._goto("midden_walk")
		return
	var b := d.current()
	if b != h._intro_beat:
		h._intro_beat = b
		if not h.intro_beats.has(b):
			h.intro_beats.append(b)
		h.t = 0.0
		h.note("intro beat %s (%d/%d) in %s" % [b, h.intro_beats.size(), IntroDirector.BEATS.size(), d.here])
	h._talk_cd -= h.get_physics_process_delta_time()
	if h.t > 240.0:  # a stalled beat fails fast with where the bot was and what it aimed at
		h._finish(
			false,
			"intro beat %s stalled in %s: feet %s, target %s" % [b, d.here, h.player.global_position, d.target_point()]
		)
		return
	_intro_shot(h, b)
	if _intro_ui(h, d):
		return
	if d.here == IntroDirector.LEVEL.get(b, d.here) and b in ["combat", "filth"] and _intro_fight(h, d, b):
		return
	if b == "crafting" and d.here == "midden" and _intro_craft(h, d):
		return
	if _arena_held(h, d):
		return
	_intro_interact(h, d)


## With --shots: one screenshot per beat 1 s in, and one 0.7 s into every cinematic (before the skip).
static func _intro_shot(h: PlaytestBot, b: String) -> void:
	var sh := h.main.get_node_or_null("Screenshots") as Screenshots
	if sh == null:
		return
	var dt := h.get_physics_process_delta_time()
	if Cinematic.playing and h._cine_t < 0.7 and h._cine_t + dt >= 0.7:
		sh.take("cine_" + b)
	elif h.t >= 1.0 and h.t - dt < 1.0:
		sh.take("beat_" + b)


## Cinematics (watch 1 s, skip), the appraisal, dialogue (first choice). True while busy.
static func _intro_ui(h: PlaytestBot, d: IntroDirector) -> bool:
	if Cinematic.playing:
		h._cine_t += h.get_physics_process_delta_time()
		if h._cine_t > 1.0:
			Cinematic.playing.skip()
		return true
	h._cine_t = 0.0
	if d.creator:
		d.choose_identity(
			{"archetype": h.player.archetype, "name": h.player.character_name, "color": h.player.character_color}
		)
		return true
	var dlg: DialogueRunner = h.main.get(&"dialogue")
	if dlg and dlg.active:
		if h._talk_cd <= 0.0:
			h._talk_cd = 0.3
			if dlg.awaiting_choice():
				dlg.choose(0)
			else:
				dlg.advance()
		return true
	return false


static func _intro_fight(h: PlaytestBot, d: IntroDirector, b: String) -> bool:
	var e := h.nearest_enemy(true)
	if e:
		h.fight(e)
		return true
	if b != "filth":
		return false
	for q in h.get_tree().get_nodes_in_group(QuestPickup.GROUP):  # Joe's trash, after the kill
		h.walk_to((q as Node3D).global_position)
		return true
	var sp := d.spawner()
	if sp:
		h.walk_to(sp.trigger_center)
	return true


## A wave gnawer corrupted into an ally stays in its wave; once it turns back it keeps the
## arena walls up after the Filth dies (return_to_bob stalled inside the ring). Clear it.
static func _arena_held(h: PlaytestBot, d: IntroDirector) -> bool:
	var sp := d.spawner()
	var lock := sp.get_node_or_null(^"ArenaLock") as ArenaLock if sp else null
	if lock == null or not lock.raised():
		return false
	var e := h.nearest_enemy(true)
	if e:
		h.fight(e)
	return true


static func _intro_craft(h: PlaytestBot, d: IntroDirector) -> bool:
	if _visit_joe(h, d):
		return true
	var pk := d.next_pickup()
	if pk:
		if pk.global_position.distance_to(h.player.eye_position()) < 2.5:
			h.look_at_point(pk.global_position + Vector3(0, LootPickup.GEM_SIZE * 0.5, 0))
			h._input = PlayerInput.hold([], ["interact"] if h._tick % 2 == 0 else [])
		else:
			h.walk_to(pk.global_position)
		return true
	var st := d.station()
	if st and h._reach(st):
		h._craft(st)
		return true
	return false


## QA r6: Joe's wind wand (joe_landfill, Q21) is optional, so the bot never had a wand and
## fought the King on a dry staff (fight()'s slot_2 swap did nothing; 3 of 4 solo runs timed
## out). Like a player, talk to Joe at his Landfill camp before using his bench.
static func _visit_joe(h: PlaytestBot, d: IntroDirector) -> bool:
	if h.player.loadout.wieldable(Loadout.Slot.WAND) != null or d.flags.has("joe_wand_given"):
		return false
	if not d.flags.has("landfill_route_open"):
		return false
	for n in h.main.find_children("*", "", true, false):
		var j := n as Npc
		if j == null or j.speaker != "Crazy Joe" or not j.is_visible_in_tree() or j.talks >= 3:
			continue
		if j.global_position.distance_to(h.player.global_position) > 60.0:
			continue
		if not h._reach(j):
			h.walk_to(j.global_position)
		elif h._talk_cd <= 0.0:
			h._talk_cd = 1.0
			j.talk()
		return true
	return false


## Walk to the objective marker, then Interact with the NPC / gate there.
static func _intro_interact(h: PlaytestBot, d: IntroDirector) -> void:
	var at: Variant = d.target_point()
	if at == null:
		return
	if h.flat_distance(at) > 1.8:
		h.walk_to(at)
		return
	if h._talk_cd > 0.0:
		return
	h._talk_cd = 1.0
	for n in h.main.find_children("*", "", true, false):
		if (n is Npc or n is LevelGate) and (n as Node3D).global_position.distance_to(at) < 0.6:
			h.look_at_point(Interaction.aim_point(n as Node3D))
			if n is Npc:
				(n as Npc).talk()
			else:
				(n as LevelGate).use()
			return
