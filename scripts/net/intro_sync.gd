class_name IntroSync
extends Node
## Step 117: co-op intro sync. The host owns the intro: every story-flag change (beats,
## gates, gifts) goes out as one "intro" message, and a late joiner gets the whole state
## when the roster changes. Clients mirror the flags (gates, markers, menu locks follow),
## get Bob's kit / Joe's wand / the crystal when the host's party has them, and see a
## recap card. Clients never skip a cinematic (Cinematic: "The host can skip"); a client
## that joins mid-cinematic gets a wait card instead.

const KIND := "intro"

var session: NetSession
var flags: StoryFlags
var player: Player
var host := false
var sent := 0
var received := 0
var last_card := ""
var _dirty := false


func setup(s: NetSession, f: StoryFlags, p: Player, is_host: bool) -> void:
	session = s
	flags = f
	player = p
	host = is_host
	name = "IntroSync"
	if host:
		f.changed.connect(func(_fl: String, _v: int): _dirty = true)
		s.roster_changed.connect(push)
	else:
		s.message.connect(_on_message)


func _process(_dt: float) -> void:
	if _dirty:
		_dirty = false
		push()


## Host: the whole intro state to everyone (cheap: a few dozen flags).
func push() -> void:
	if not host or session == null:
		return
	session.send(KIND, {"flags": flags.to_dict(), "cinematic": Cinematic.playing != null})
	sent += 1


func _on_message(_from: int, kind: String, data: Dictionary) -> void:
	if kind != KIND:
		return
	received += 1
	mirror(data)


## Client: adopt the host's intro flags and hand out what the party already has.
func mirror(data: Dictionary) -> void:
	var was_active := IntroDirector.active(flags)
	var had_beat := IntroDirector.beat(flags)
	flags.from_dict(data.get("flags", {}))
	if IntroDirector.active(flags):
		IntroDirector.live = flags
	if player:
		if flags.has("bob_met"):
			IntroDirector.give_staff(player)
		if flags.has("joe_wand_given") or flags.has(IntroDirector.DONE):
			IntroDirector.give_wand(player)
	var b := IntroDirector.beat(flags)
	if flags.has(IntroDirector.DONE):
		last_card = (
			"Prologue complete" if was_active or had_beat != "" else "Recap: the prologue is done. Welcome to Elyria."
		)
	elif bool(data.get("cinematic", false)):
		last_card = "The host is watching a cutscene... (the host can skip)"
	elif b != had_beat:
		last_card = "Recap: %s" % IntroDirector.OBJECTIVES.get(b, b)
	_card(last_card)


func _card(text: String) -> void:
	if text.is_empty():
		return
	var hud := get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud and hud.has_method("show_hint"):
		hud.show_hint(text)
	print("[intro-sync] " + text)
