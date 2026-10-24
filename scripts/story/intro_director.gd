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

var main: Node
var player: Player
var flags: StoryFlags
var here := ""


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
