class_name IntroDirector
extends Node
## The linear intro + tutorial (BUILD_PLAN steps 109-118, docs/INTRO_PLAN.md). The story
## flag FLAG holds the current beat (index + 1) so the beat survives travel and saves;
## DONE ends the intro. Beats only move forward. One director lives in the game scene while
## the intro runs; it owns this level's intro dressing and reports the objective + target
## (HUD markers and the playtest bot use those).

signal beat_changed(id: String)

const FLAG := "intro_beat"
const DONE := "intro_done"
const BEATS: PackedStringArray = [
	"summoning",
	"appraisal",
	"expulsion",
	"grant",
	"welcome",
	"new_home",
	"back_door",
	"combat",
	"crafting",
	"light_dark",
	"filth",
	"return_to_bob",
	"crystal",
]
## The level each beat plays in.
const LEVEL := {
	"summoning": "mage_association",
	"appraisal": "mage_association",
	"expulsion": "mage_association",
	"grant": "mage_association",
	"welcome": "town_square",
	"new_home": "old_oak",
	"back_door": "mage_association",
	"combat": "midden",
	"crafting": "midden",
	"light_dark": "midden",
	"filth": "midden",
	"return_to_bob": "old_oak",
	"crystal": "old_oak",
}
const OBJECTIVES := {
	"summoning": "Watch the summoning",
	"appraisal": "Choose who you are",
	"expulsion": "Listen to Crazy Joe",
	"grant": "Collect your grant from the Clerk",
	"welcome": "Find the Old Oak",
	"new_home": "Rest on the moss bed",
	"back_door": "Reach the Landfill through the Association's back door",
	"combat": "Defeat the Gnawers",
	"crafting": "Fit the salvaged parts at the Assembly Station",
	"light_dark": "Touch the Light and Dark shrines",
	"filth": "Defeat the Filth",
	"return_to_bob": "Return to Bob at the Old Oak",
	"crystal": "Talk to Bob",
}
## Flags a finished (or skipped) intro leaves behind.
const END_FLAGS: PackedStringArray = [
	"joe_met",
	"identity_chosen",
	"joe_expelled",
	"permit_given",
	"home_unlocked",
	"bob_arrived",
	"bob_met",
	"landfill_route_open",
	"rusty_dagger",
	"crafted_once",
	"light_learned",
	"dark_learned",
	"filth_defeated",
	"tutorial_done",
	"fast_travel_crystal",
]

## Step 111: where the Association's intro cast stands (the hall's dais is at z -10).
const DAIS_SPOT := Vector3(0.0, 0.3, -7.5)
const ELDER_SPOT := Vector3(-3.0, 0.3, -11.0)
const CLERK_SPOT := Vector3(6.0, 0.0, 9.0)
const SUMMONED_SPOTS: Array[Vector3] = [Vector3(-2.0, 0.3, -8.0), Vector3(2.0, 0.3, -8.0), Vector3(-1.0, 0.3, -9.0)]
const BACK_DOOR := Vector3(0.0, 0.0, -13.5)
const GRANT_GOLD := 50

## Step 112: intro-only gate rules, level -> gate target -> [flag that opens it, locked text].
const GATE_RULES := {
	"mage_association":
	{
		"town_square": ["permit_given", "The Clerk has your papers. Speak to the Clerk first."],
		"midden": ["landfill_route_open", "Staff only. By order of the Elders."],
	},
	"town_square":
	{"midden": ["filth_defeated", 'Bored Guard: "Barrier edge. Summoned don\'t go out there without say-so."']},
	"midden":
	{
		"breach": ["tutorial_done", "The Breach is sealed. Bob wants you back first."],
		"town_square":
		["filth_defeated", "The barrier gate is barred from this side. Deal with whatever lurks here first."],
	},
}
## Next gate to take from a level towards another (the intro's map: Association - Town - Oak,
## the Landfill off the Association's back door, and its barrier gate back to town).
const ROUTE := {
	"mage_association": {"town_square": "town_square", "old_oak": "town_square", "midden": "midden"},
	"town_square": {"mage_association": "mage_association", "old_oak": "old_oak", "midden": "mage_association"},
	"old_oak": {"town_square": "town_square", "mage_association": "town_square", "midden": "town_square"},
	"midden": {"town_square": "town_square", "old_oak": "town_square", "mage_association": "town_square"},
}
## Menus the intro holds back: feature -> [flag that unlocks it, why].
const LOCKS := {
	"inventory": ["bob_met", "Your pack is empty. (Unlocks once Bob kits you out.)"],
	"skills": ["bob_met", "You don't know any skills yet. (Unlocks after meeting Bob.)"],
	"save": ["bob_met", "Saving unlocks at the Old Oak. (Leaving still keeps your place.)"],
	"map": ["fast_travel_crystal", "The waystone is dormant. Its light is out."],
}

static var live: StoryFlags  ## the running intro's flags (menus check them)

var marker: Label3D
var main: Node
var player: Player
var flags: StoryFlags
var here := ""
var cast := {}  ## speaker -> Npc this director spawned
var creator: CanvasLayer
var cinematic: Cinematic


## Why `feature` is locked right now ("" when it is open or no intro runs).
static func lock_text(feature: String) -> String:
	if not active(live) or not LOCKS.has(feature) or live.has(LOCKS[feature][0]):
		return ""
	return String(LOCKS[feature][1])


## True (with a HUD hint) when the intro still holds `feature` back.
static func refuse(n: Node, feature: String) -> bool:
	var why := lock_text(feature)
	if why.is_empty():
		return false
	var hud := n.get_tree().get_first_node_in_group(&"hud") if n.is_inside_tree() else null
	if hud:
		hud.show_hint(why)
	print("[intro] locked: " + feature)
	return true


static func active(f: StoryFlags) -> bool:
	return f != null and f.has(FLAG) and not f.has(DONE)


static func index_of(id: String) -> int:
	return BEATS.find(id)


## The current beat id ("" when no intro runs).
static func beat(f: StoryFlags) -> String:
	if not active(f):
		return ""
	return BEATS[clampi(f.value(FLAG) - 1, 0, BEATS.size() - 1)]


static func start(f: StoryFlags) -> void:
	f.clear(DONE)
	f.set_flag(FLAG, 1)


## Moves to `id` if it is ahead of the current beat; false otherwise (beats never go back).
static func reach(f: StoryFlags, id: String) -> bool:
	var i := index_of(id)
	if not active(f) or i < 0 or i + 1 <= f.value(FLAG):
		return false
	f.set_flag(FLAG, i + 1)
	return true


## Ends the intro: the world opens.
static func finish(f: StoryFlags) -> void:
	for fl in END_FLAGS:
		f.set_flag(fl)
	f.set_flag(FLAG, BEATS.size())
	f.set_flag(DONE)


## Step 118 / --skip-intro: the intro's end state - flags plus Bob's and Joe's gifts.
static func apply_skip(f: StoryFlags, p: Player) -> void:
	finish(f)
	if p:
		give_starter_weapons(p)


static func give_starter_weapons(p: Player) -> void:
	give_staff(p)
	give_wand(p)


## Bob's gift (Q18).
static func give_staff(p: Player) -> void:
	if p.loadout.wieldable(Loadout.Slot.STAFF) == null:
		p.equip(WieldableInstance.load_base("apprentice_fire_staff"))


## Joe's gift at his Landfill camp (Q21).
static func give_wand(p: Player) -> void:
	if p.loadout.wieldable(Loadout.Slot.WAND) == null:
		p.equip(WieldableInstance.load_base("swift_wind_wand"))


## A fresh intro character starts empty-handed: Bob hands over the staff (Q18).
static func strip_weapons(p: Player) -> void:
	for s in [Loadout.Slot.STAFF, Loadout.Slot.WAND]:
		p.loadout.unequip(s)


func setup(m: Node, p: Player, f: StoryFlags, level: String) -> void:
	main = m
	player = p
	flags = f
	here = level
	name = "IntroDirector"
	live = f
	_apply_gate_rules()
	_make_marker()
	beat_changed.connect(func(_b: String): _on_beat())
	print("[intro] beat %s in %s" % [current(), here])
	if main.get("dialogue"):
		(main.dialogue as DialogueRunner).ended.connect(_on_dialogue_ended)
	if here == "mage_association":
		_dress_association()
	elif here == "old_oak":
		_dress_oak()
	elif here == "midden":
		if current() == "back_door":
			advance("combat")  # step 114: through the back door, into the Landfill
		_dress_landfill()


func current() -> String:
	return beat(flags)


func objective() -> String:
	return OBJECTIVES.get(current(), "")


## True when the current beat plays in this level.
func beat_here() -> bool:
	return LEVEL.get(current(), "") == here


func advance(id: String) -> bool:
	if not reach(flags, id):
		return false
	print("[intro] -> %s" % id)
	beat_changed.emit(id)
	return true


## Step 156: a beat / cinematic marker from the level's Anchors (TOML [[anchor]]), so
## redesigned maps move the intro without code changes; `fallback` = the greybox spot.
func spot(id: String, fallback: Vector3) -> Vector3:
	var n := main.get_node_or_null(NodePath("Level/Anchors/" + id)) as Node3D if main else null
	return n.global_position if n else fallback


## Step 110: plays a cinematic here; `done` runs when it ends or is skipped (flags apply).
func play_cinematic(cid: String, shots: Array, done: Callable = Callable()) -> Cinematic:
	var c := Cinematic.make(cid, shots, player)
	if done.is_valid():
		c.finished.connect(func(_i: String, _s: bool): done.call())
	main.add_child(c)
	return c


# --- Step 111: beats 1-4 in the Mage Association -------------------------------------------


func _dress_association() -> void:
	main.call("_ensure_dialogue")
	if not (main.dialogue as DialogueRunner).ended.is_connected(_on_dialogue_ended):
		(main.dialogue as DialogueRunner).ended.connect(_on_dialogue_ended)
	_spawn("Elder", spot("elder", ELDER_SPOT), 0.0)
	_spawn("Clerk", spot("clerk", CLERK_SPOT), 180.0)
	var others := Array(Archetype.IDS).filter(func(a: String) -> bool: return a != player.archetype)
	for i in mini(3, others.size()):
		_spawn("Summoned " + Archetype.label(others[i]), SUMMONED_SPOTS[i], 0.0)
	if flags.has("joe_expelled"):
		_hide_joe()
	match current():
		"summoning":
			player.global_position = spot("dais", DAIS_SPOT)
			_play_summoning()
		"appraisal":
			open_creator()
		"expulsion":
			_joe_explains()


func _spawn(speaker: String, at: Vector3, yaw_deg: float) -> Npc:
	var n := Npc.new(speaker)
	n.name = "Npc_" + speaker.replace(" ", "_")
	n.player = player
	main.add_child(n)
	n.global_position = at
	n.rotation_degrees.y = yaw_deg
	n.talked.connect(Callable(main, "_on_npc_talked"))
	main.npcs.append(n)
	cast[speaker] = n
	return n


func joe() -> Npc:
	for n in main.npcs:
		if is_instance_valid(n) and n.speaker == "Crazy Joe":
			return n
	return null


func _hide_joe() -> void:
	var j := joe()
	if j:
		j.visible = false
		j.process_mode = Node.PROCESS_MODE_DISABLED
		j.position.y -= 50.0


func _play_summoning() -> void:
	var dais := Vector3(0, 1.2, -10)
	var circle := RitualFX.summoning_circle(spot("dais", DAIS_SPOT))  # step 133 (FX F7)
	main.add_child(circle)
	cinematic = play_cinematic(
		"summoning",
		[
			{
				"from": Vector3(0, 6, 8),
				"to": Vector3(0, 4, -2),
				"look": dais,
				"s": 3.0,
				"text": "The Mage Association, Eldoria. Crazy Joe's forbidden ritual."
			},
			{
				"from": Vector3(-6, 2, -6),
				"to": Vector3(-3, 2, -5),
				"look": spot("dais", DAIS_SPOT) + Vector3(0, 1, 0),
				"s": 3.0,
				"text": "The circle cracks the marble. Four strangers stand in the smoke."
			},
			{
				"from": Vector3(3, 1.8, -5),
				"to": Vector3(1.5, 1.7, -6),
				"look": Vector3(0, 1.6, -10),
				"s": 2.5,
				"text": 'Crazy Joe: "Ah! The ritual worked! You\'re actually here!"'
			},
		],
		_after_summoning
	)
	cinematic.finished.connect(func(_i, _s): circle.queue_free())


func _after_summoning() -> void:
	flags.set_flag("joe_met")
	advance("appraisal")
	open_creator()


## Beat 2: the appraisal crystal's readout is the character creator.
func open_creator() -> void:
	if creator:
		return
	var pre := {"archetype": player.archetype, "name": player.character_name, "color": player.character_color}
	creator = CharacterCreator.overlay(pre)
	main.add_child(creator)
	CharacterCreator.of(creator).confirmed.connect(choose_identity)
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[intro] appraisal: character creator open")


func choose_identity(idn: Dictionary) -> void:
	player.set_character(String(idn.get("archetype", "")), String(idn.get("name", "")), idn.get("color", null))
	print("[character] %s the %s (appraisal)" % [player.character_name, Archetype.label(player.archetype)])
	if creator:
		creator.queue_free()
		creator = null
	player.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flags.set_flag("identity_chosen")
	advance("expulsion")
	_joe_explains()


func _joe_explains() -> void:
	if not main.call("talk_to", "Crazy Joe"):
		_play_expulsion()


func _play_expulsion() -> void:
	var j := joe()
	var from := j.global_position if j else Vector3(0, 0.3, -10)
	cinematic = play_cinematic(
		"expulsion",
		[
			{
				"from": spot("elder", ELDER_SPOT) + Vector3(2, 1.8, 3),
				"to": spot("elder", ELDER_SPOT) + Vector3(1, 1.7, 2),
				"look": spot("elder", ELDER_SPOT) + Vector3(0, 1.5, 0),
				"s": 2.5,
				"text": 'Elder: "Joseph. You were warned."'
			},
			{
				"from": from + Vector3(3, 2, 3),
				"to": spot("back_door", BACK_DOOR) + Vector3(3, 2, 3),
				"look": spot("back_door", BACK_DOOR) + Vector3(0, 1, 0),
				"s": 3.0,
				"text": "Crazy Joe is marched out through the back door. It slams behind him."
			},
		],
		_after_expulsion
	)
	if j:
		var tw := j.create_tween()
		tw.tween_property(j, "global_position", spot("back_door", BACK_DOOR), 3.0)


func _after_expulsion() -> void:
	flags.set_flag("joe_expelled")
	_hide_joe()
	advance("grant")
	_hint("Speak to the Clerk by the front door")


## Beat 4 ends when the Clerk's grant dialogue does.
func _on_dialogue_ended(id: String) -> void:
	match id:
		"joe_landfill":
			give_wand(player)
			_hint("Crazy Joe's wind wand: swap with 2 / the mouse wheel")
		"joe_expulsion":
			if current() == "expulsion":
				_play_expulsion()
		"clerk_grant":
			give_grant()
		"bob_intro":
			give_kit()
		"bob_after_filth":
			if current() == "crystal":
				_play_crystal()


func give_grant() -> void:
	flags.set_flag("permit_given")
	if current() != "grant":
		return
	player.inventory.add_gold(GRANT_GOLD)
	advance("welcome")
	_hint("+%d gold, residency permit. Find the Old Oak (through the Town Square)" % GRANT_GOLD)


func _hint(text: String) -> void:
	var hud := main.get_node_or_null("Hud")
	if hud and hud.has_method("show_hint"):
		hud.show_hint(text)
	print("[intro] " + text)


# --- Step 112: gates, objective marker ------------------------------------------------------


func _exit_tree() -> void:
	if live == flags:
		live = null


func _apply_gate_rules() -> void:
	var rules: Dictionary = GATE_RULES.get(here, {})
	for g in main.get("gates"):
		if rules.has(g.target):
			g.requires = String(rules[g.target][0])
			g.locked_text = String(rules[g.target][1])
			g.flags = flags


func gate_to(target: String) -> LevelGate:
	for g in main.get("gates"):
		if g.target == target:
			return g
	return null


## Where the objective marker points: the beat's NPC / spot here, or the next gate on the way.
func target_point() -> Variant:
	var b := current()
	if b.is_empty():
		return null
	var dest := String(LEVEL.get(b, here))
	if dest != here:
		var g := gate_to(String(ROUTE.get(here, {}).get(dest, "")))
		return g.global_position if g else null
	var n: Node3D = null
	match b:
		"expulsion":
			n = joe()
		"grant":
			n = cast.get("Clerk")
		"welcome":
			n = gate_to("town_square") if here == "mage_association" else gate_to("old_oak")
		"new_home", "return_to_bob", "crystal":
			n = target_oak()
		"back_door":
			n = gate_to("midden")
		"crafting":
			n = station()
		"light_dark":
			n = shrines.get("Dark shrine" if flags.has("light_learned") else "Light shrine")
	return n.global_position if n else null


func _make_marker() -> void:
	marker = Label3D.new()
	marker.name = "ObjectiveMarker"
	marker.text = "v"
	marker.font_size = 96
	marker.outline_size = 16
	marker.modulate = Color(1.0, 0.8, 0.2)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = true
	marker.pixel_size = 0.0006
	marker.visible = false
	add_child(marker)


func _process(dt: float) -> void:
	_tick_toasts(dt)
	if marker == null:
		return
	var at: Variant = target_point()
	marker.visible = at != null and Cinematic.playing == null
	if at != null:
		var bob := 0.15 * sin(Time.get_ticks_msec() * 0.004)
		marker.global_position = (at as Vector3) + Vector3(0, 3.0 + bob, 0)


func _on_beat() -> void:
	_apply_gate_rules()
	var o := objective()
	if not o.is_empty():
		_hint("Objective: " + o)


# --- Step 113: beat 6, the Old Oak's first night and Bob's kit ----------------------------

var bed: Npc


func _dress_oak() -> void:
	main.call("_ensure_dialogue")
	if not (main.dialogue as DialogueRunner).ended.is_connected(_on_dialogue_ended):
		(main.dialogue as DialogueRunner).ended.connect(_on_dialogue_ended)
	if current() == "welcome":
		flags.set_flag("home_unlocked")
		advance("new_home")
	if current() == "return_to_bob":
		advance("crystal")  # step 116: home again - Bob's waiting
	if current() == "new_home" and not flags.has(MentorArrival.FLAG):
		bed = Npc.new("Moss bed")
		bed.name = "MossBed"
		bed.player = player
		main.add_child(bed)
		bed.global_position = player.spawn_feet + Vector3(-2.5, 0, -4)
		bed.talked.connect(func(_s: String): rest())
	elif current() == "new_home":
		_bob_talks()


func target_oak() -> Node3D:
	match current():
		"new_home":
			return bed if bed and not flags.has(MentorArrival.FLAG) else main.get_node_or_null("Npc_Bob")
		"return_to_bob", "crystal":
			return main.get_node_or_null("Npc_Bob")
	return null


## The moss bed: night falls, "That night...", then Bob's vortex.
func rest() -> bool:
	if current() != "new_home" or flags.has(MentorArrival.FLAG) or cinematic:
		return false
	set_night()
	if bed:
		bed.queue_free()
		bed = null
	var hud := main.get_node_or_null("Hud")
	if hud:
		hud.show_banner("That night...")
	var at := player.spawn_feet + Vector3(0, 0, -3)
	main.add_child(MentorArrival.vortex(at))
	cinematic = play_cinematic(
		"bob_arrives",
		[
			{
				"from": at + Vector3(0, 2.5, 6),
				"to": at + Vector3(0, 2, 4),
				"look": at + Vector3(0, 1.2, 0),
				"s": 3.0,
				"text": "That night, a surge of mana. A vortex tears open inside the Old Oak."
			},
			{
				"from": at + Vector3(2.5, 1.7, 2),
				"to": at + Vector3(1.5, 1.7, 1.5),
				"look": at + Vector3(0, 1.6, 0),
				"s": 3.0,
				"text": "A tall figure steps through - silver-streaked beard, eyes like embers."
			},
		],
		_bob_arrives
	)
	print("[intro] rest: night falls")
	return true


func set_night() -> void:
	var lvl := main.get_node_or_null("Level")
	if lvl == null:
		return
	var anchor := Vector3(0, 0.3, 0)
	if player:
		anchor = player.global_position
	NightPreset.apply(lvl, anchor)


func _bob_arrives() -> void:
	cinematic = null
	MentorArrival.play(flags, player, null, null)
	main.call("spawn_bob", player)
	_bob_talks()


func _bob_talks() -> void:
	if not flags.has("bob_met"):
		main.call("talk_to", "Bob")


## Bob's kit (Q18): the staff, a mana potion (MentorArrival), the rusty dagger keepsake, the
## bark map, and the Landfill route through the Association's back door.
func give_kit() -> void:
	if not active(flags) or flags.has("rusty_dagger"):
		return
	give_staff(player)
	flags.set_flag("rusty_dagger")
	flags.set_flag("bark_map")
	flags.set_flag("landfill_route_open")
	if main.get_node_or_null("DaggerGlow") == null:
		main.add_child(DaggerGlow.make(player))
	advance("back_door")
	_hint("Bob's kit: Apprentice Fire Staff, Mana Potion, rusty dagger (glows near danger), bark map")


# --- Step 115: beats 8-10, the Landfill lessons ------------------------------------------

const YARD_GNAWERS: Array[Vector3] = [Vector3(-8, 0, 10.5), Vector3(8, 0, 10.5), Vector3(-4, 0, 10)]
const CAMP := Vector3(5.0, 0.0, 7.0)  ## Joe's dump camp: his bench (the Assembly Station)
const JOE_CAMP := Vector3(7.0, 0.0, 7.5)
const LIGHT_SHRINE := Vector3(-5.0, 0.0, 4.0)
const DARK_SHRINE := Vector3(5.0, 0.0, 4.0)
const TUTORIAL_PART := "basic_fire_head"
## Step 118: one head can't make a staff, so the yard drops a full salvage kit.
const TUTORIAL_KIT: PackedStringArray = ["basic_fire_head", "basic_exterior", "basic_interior", "basic_handle"]
## Soft walls across the Landfill: name -> [z, flag that drops it].
const WALLS := {
	"YardWall": [9.0, "gnawers_cleared"],
	"JunkWall": [5.5, "crafted_once"],
	"ArenaWall": [2.5, "dark_learned"],
}
const TOASTS := {
	"combat":
	[
		"Cast: left mouse",
		"Dash: Shift (dodges bites)",
		"Mana: watch the blue bar; Q drinks Bob's potion",
		"Two weapons? 1 / 2 or the mouse wheel swaps",
	],
	"crafting":
	[
		"Pick up the parts (E), then E at Joe's bench",
		"Fit the parts to your staff; the card shows the change",
	],
	"light_dark":
	[
		"Light heals allies and hits enemies a little softer",
		"Dark sometimes turns an enemy to your side",
	],
}
const TOAST_SECONDS := 4.0

var yard: Array[Enemy] = []
var yard_kills := 0
var walls := {}  ## name -> StaticBody3D
var shrines := {}  ## speaker -> Npc
var dark_gnawer: Enemy
var part_pickup: LootPickup  ## the kit piece still on the ground nearest the start (or null)
var part_pickups: Array[LootPickup] = []
var _saved_trigger := -1.0
var _toasts: Array[String] = []
var _toast_left := 0.0


func _dress_landfill() -> void:
	main.call("_ensure_dialogue")
	if not (main.dialogue as DialogueRunner).ended.is_connected(_on_dialogue_ended):
		(main.dialogue as DialogueRunner).ended.connect(_on_dialogue_ended)
	var b := current()
	if b == "filth":
		_arm_filth()
		return
	if not b in ["combat", "crafting", "light_dark"]:
		return
	var sp := spawner()
	if sp and sp.trigger_radius > 0.0:
		_saved_trigger = sp.trigger_radius  # the Filth's mound stays quiet until beat 11
		sp.trigger_radius = 0.0
	for w in WALLS:
		if not flags.has(String(WALLS[w][1])):
			walls[w] = _wall(w, float(WALLS[w][0]))
	var st := station()
	if st:
		st.global_position = spot("joe_bench", CAMP)
	if not flags.has("joe_wand_given"):
		_spawn("Crazy Joe", spot("joe_camp", JOE_CAMP), -120.0)
	if not GameEvents.bus().crafting_completed.is_connected(_on_crafted):
		GameEvents.bus().crafting_completed.connect(_on_crafted)
	match b:
		"combat":
			_start_yard()
		"crafting":
			_drop_part(Vector3(0, 0, 10.5))
		"light_dark":
			_make_shrines()
	_queue_toasts(b)


func spawner() -> EnemySpawner:
	return main.get_node_or_null("Enemies") as EnemySpawner


func station() -> AssemblyStation:
	for c in main.get_children():
		if c is AssemblyStation:
			return c
	return null


func wall_up(w: String) -> bool:
	return walls.has(w) and is_instance_valid(walls[w])


func _wall(n: String, z: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(29.0, 4.0, 0.6)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(29.0, 1.2, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.28, 0.2)
	bm.material = mat
	mesh.mesh = bm
	mesh.position.y = -1.4
	body.add_child(mesh)
	main.add_child(body)
	body.global_position = Vector3(0.0, 2.0, z)
	return body


func _drop_wall(w: String) -> void:
	if wall_up(w):
		(walls[w] as Node).queue_free()
	walls.erase(w)


func _start_yard() -> void:
	var sp := spawner()
	var d := sp.table.find("gnawer") if sp else null
	if d == null:
		return
	for at in YARD_GNAWERS:
		var e := Enemy.create(d, Transform3D(Basis(), at))
		e.name = "YardGnawer%d" % (yard.size() + 1)
		sp.add_child(e)
		sp.call("_adopt", e)
		e.died.connect(func(dead: Enemy, _el: ElementTable.Element): _on_yard_kill(dead))
		yard.append(e)
	_hint("Objective: Clear the Gnawers (0/%d)" % yard.size())


func _on_yard_kill(e: Enemy) -> void:
	yard_kills += 1
	_hint("Objective: Clear the Gnawers (%d/%d)" % [yard_kills, YARD_GNAWERS.size()])
	if yard_kills < YARD_GNAWERS.size() or current() != "combat":
		return
	flags.set_flag("gnawers_cleared")
	_drop_wall("YardWall")
	_drop_part(e.global_position)
	advance("crafting")
	_queue_toasts("crafting")


## The guaranteed first parts (beat 8): a Basic salvage kit around the last kill, Interact to pick up.
func _drop_part(at: Vector3) -> void:
	part_pickups.clear()
	var i := 0
	for id in TUTORIAL_KIT:
		var part := WieldablePart.load_part(id)
		if part == null:
			continue
		var d := LootDrop.new()
		d.kind = LootDrop.Kind.PART
		d.item = part.duplicate()
		d.rarity_id = "basic"
		d.rolled_rarity_id = "basic"
		d.element = part.element
		var off := Vector3(cos(i * TAU / TUTORIAL_KIT.size()), 0, sin(i * TAU / TUTORIAL_KIT.size())) * 0.9
		var pk := LootPickup.create(d, Vector3(at.x, 0.4, at.z) + off)
		main.add_child(pk)
		part_pickups.append(pk)
		i += 1
	next_pickup()


## The next kit piece still lying around (also kept in `part_pickup`).
func next_pickup() -> LootPickup:
	part_pickup = null
	for pk in part_pickups:
		if part_pickup == null and is_instance_valid(pk) and pk.is_inside_tree():
			part_pickup = pk
	return part_pickup


func _on_crafted(_p: Player, _w: WieldableInstance) -> void:
	if flags.has("crafted_once"):
		return
	flags.set_flag("crafted_once")
	_drop_wall("JunkWall")
	if current() == "crafting":
		advance("light_dark")
		_make_shrines()
		_queue_toasts("light_dark")


func _make_shrines() -> void:
	if not shrines.is_empty():
		return
	for spec in [["Light shrine", spot("light_shrine", LIGHT_SHRINE)], ["Dark shrine", spot("dark_shrine", DARK_SHRINE)]]:
		var n := Npc.new(String(spec[0]))
		n.name = String(spec[0]).replace(" ", "")
		n.player = player
		main.add_child(n)
		n.global_position = spec[1]
		n.talked.connect(touch_shrine)
		shrines[spec[0]] = n
	if not flags.has("light_learned"):
		var s := _spawn("Wounded scavenger", spot("light_shrine", LIGHT_SHRINE) + Vector3(-1.5, 0, 0.5), 90.0)
		s.rotation_degrees.z = 70.0  # slumped against the heap


## Beat 10: either order. Light heals the scavenger; Dark forces one Gnawer conversion.
func touch_shrine(which: String) -> void:
	if which == "Light shrine" and not flags.has("light_learned"):
		flags.set_flag("light_learned")
		MagicEffects.light_heals += 1
		player.health.heal(player.health.max_value())
		var s: Npc = cast.get("Wounded scavenger")
		if s:
			s.rotation_degrees.z = 0.0
		_hint("Light washes over the scavenger. He stands. (Light heals allies; enemies take a little less.)")
	elif which == "Dark shrine" and not flags.has("dark_learned"):
		_dark_lesson()
	if flags.has("light_learned") and flags.has("dark_learned") and current() == "light_dark":
		_drop_wall("ArenaWall")
		var sp := spawner()
		if sp and _saved_trigger > 0.0:
			sp.trigger_radius = _saved_trigger
		advance("filth")
		_arm_filth()


func _dark_lesson() -> void:
	var sp := spawner()
	var d := sp.table.find("gnawer") if sp else null
	if d:
		dark_gnawer = Enemy.create(d, Transform3D(Basis(), spot("dark_shrine", DARK_SHRINE) + Vector3(1.5, 0, -1.0)))
		dark_gnawer.name = "ShrineGnawer"
		sp.add_child(dark_gnawer)
		sp.call("_adopt", dark_gnawer)
		if not flags.has("tutorial_force_convert"):
			flags.set_flag("tutorial_force_convert")  # once per character
			MagicEffects.force_convert = true
		MagicEffects.try_corrupt(dark_gnawer, 0.0)
	flags.set_flag("dark_learned")
	_hint("The Gnawer's eyes go dark: it fights for you now. (Normally ~1%. Dark parts raise it.)")


func _queue_toasts(b: String) -> void:
	for t in TOASTS.get(b, []):
		_toasts.append(String(t))


func _tick_toasts(dt: float) -> void:
	_toast_left -= dt
	if _toasts.is_empty() or _toast_left > 0.0 or Cinematic.playing != null:
		return
	_hint(_toasts.pop_front())
	_toast_left = TOAST_SECONDS


# --- Step 116: beats 11-13, the Filth, home, the crystal ----------------------------------

const END_CARD := "Prologue complete"


func _arm_filth() -> void:
	var bus := GameEvents.bus()
	if not bus.wave_started.is_connected(_on_wave):
		bus.wave_started.connect(_on_wave)
	if not flags.changed.is_connected(_on_flag):
		flags.changed.connect(_on_flag)


func _on_wave(_i: int, id: String) -> void:
	if id != Filth.WAVE_ID or current() != "filth" or flags.has("filth_revealed"):
		return
	flags.set_flag("filth_revealed")
	var sp := spawner()
	var c: Vector3 = sp.trigger_center if sp else Vector3.ZERO
	cinematic = play_cinematic(
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


func _on_flag(flag: String, _v: int) -> void:
	if flag == "filth_defeated" and current() == "filth":
		advance("return_to_bob")
		_hint("The barrier gate is open. Bring Joe's trash to Bob at the Old Oak")


func _play_crystal() -> void:
	var bob := main.get_node_or_null("Npc_Bob") as Node3D
	var at: Vector3 = bob.global_position if bob else player.global_position
	var gem := RitualFX.crystal(at + Vector3(0, 1.4, 0.4))  # step 133 (FX F7)
	main.add_child(gem)
	cinematic = play_cinematic(
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
		complete
	)
	cinematic.finished.connect(func(_i, _s): gem.queue_free())


## Beat 13 end: every gate and menu opens, the waystone wakes, "Prologue complete".
func complete() -> void:
	if flags.has(DONE):
		return
	finish(flags)
	_apply_gate_rules()
	for g in main.get("gates"):
		g.requires = ""
	if marker:
		marker.visible = false
		marker.queue_free()
		marker = null
	var hud := main.get_node_or_null("Hud")
	if hud and hud.has_method("show_banner"):
		hud.show_banner(END_CARD)
	print("[intro] " + END_CARD)
	beat_changed.emit("done")
