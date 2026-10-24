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

var main: Node
var player: Player
var flags: StoryFlags
var here := ""
var cast := {}  ## speaker -> Npc this director spawned
var creator: CanvasLayer
var cinematic: Cinematic


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
	if p.loadout.wieldable(Loadout.Slot.STAFF) == null:
		p.equip(WieldableInstance.load_base("apprentice_fire_staff"))
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
	print("[intro] beat %s in %s" % [current(), here])
	if main.get("dialogue"):
		(main.dialogue as DialogueRunner).ended.connect(_on_dialogue_ended)
	if here == "mage_association":
		_dress_association()


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
	_spawn("Elder", ELDER_SPOT, 0.0)
	_spawn("Clerk", CLERK_SPOT, 180.0)
	var others := Array(Archetype.IDS).filter(func(a: String) -> bool: return a != player.archetype)
	for i in mini(3, others.size()):
		_spawn("Summoned " + Archetype.label(others[i]), SUMMONED_SPOTS[i], 0.0)
	if flags.has("joe_expelled"):
		_hide_joe()
	for g in main.gates:
		if g.target == "town_square":
			g.requires = "permit_given"
			g.locked_text = "The Clerk has your papers. Speak to the Clerk first."
			g.flags = flags
	match current():
		"summoning":
			player.global_position = DAIS_SPOT
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
				"look": DAIS_SPOT + Vector3(0, 1, 0),
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
				"from": ELDER_SPOT + Vector3(2, 1.8, 3),
				"to": ELDER_SPOT + Vector3(1, 1.7, 2),
				"look": ELDER_SPOT + Vector3(0, 1.5, 0),
				"s": 2.5,
				"text": 'Elder: "Joseph. You were warned."'
			},
			{
				"from": from + Vector3(3, 2, 3),
				"to": BACK_DOOR + Vector3(3, 2, 3),
				"look": BACK_DOOR + Vector3(0, 1, 0),
				"s": 3.0,
				"text": "Crazy Joe is marched out through the back door. It slams behind him."
			},
		],
		_after_expulsion
	)
	if j:
		var tw := j.create_tween()
		tw.tween_property(j, "global_position", BACK_DOOR, 3.0)


func _after_expulsion() -> void:
	flags.set_flag("joe_expelled")
	_hide_joe()
	advance("grant")
	_hint("Speak to the Clerk by the front door")


## Beat 4 ends when the Clerk's grant dialogue does.
func _on_dialogue_ended(id: String) -> void:
	match id:
		"joe_expulsion":
			if current() == "expulsion":
				_play_expulsion()
		"clerk_grant":
			give_grant()


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
